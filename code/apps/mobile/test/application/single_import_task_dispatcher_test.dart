import 'dart:async';

import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/importing/single_import_task_dispatcher.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';

void main() {
  late MemoryImportTaskRepository repository;
  late DateTime now;
  DateTime clock() => now;

  void addTask(String id, DateTime createdAt) {
    repository.tasks[id] = ImportTask.queued(
      id: id,
      source: ImportSourceLink.parse('https://v.douyin.com/$id/'),
      now: createdAt,
    );
  }

  SingleImportTaskDispatcher dispatcher({
    required FakeImportContentAdapter adapter,
  }) {
    final processor = FakeImportContentProcessor((content, progress, _) async {
      await progress(ImportTaskStage.generating, 0.9);
      return ImportRecipeDraftResult(recipeId: 'recipe-${content.title}');
    });
    final runner = ImportTaskRunner(
      repository: repository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]),
      processor: processor,
      discardRecipeDraft: discardImportRecipeDraft,
      clock: clock,
    );
    return SingleImportTaskDispatcher(repository: repository, runner: runner);
  }

  setUp(() {
    repository = MemoryImportTaskRepository();
    now = DateTime.utc(2026, 7, 28, 10);
  });

  test(
    'dispatcher runs queued tasks oldest first and continues after failure',
    () async {
      addTask('newer', now);
      addTask('oldest', now.subtract(const Duration(minutes: 2)));
      addTask('middle-fail', now.subtract(const Duration(minutes: 1)));
      final calls = <String>[];
      final report = await dispatcher(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (source, _) async {
            final id = Uri.parse(
              source.normalizedUrl,
            ).pathSegments.lastWhere((segment) => segment.isNotEmpty);
            calls.add(id);
            if (id == 'middle-fail') {
              throw const ImportContentAdapterException(
                kind: ImportContentAdapterErrorKind.contentUnavailable,
                message: 'Content is unavailable.',
                retryable: false,
              );
            }
            return sampleImportContent(source, title: id);
          },
        ),
      ).dispatchPending();

      expect(calls, <String>['oldest', 'middle-fail', 'newer']);
      expect(report.processedCount, 3);
      expect(
        report.results.map((result) => result.outcome),
        <ImportTaskRunOutcome>[
          ImportTaskRunOutcome.needsReview,
          ImportTaskRunOutcome.failed,
          ImportTaskRunOutcome.needsReview,
        ],
      );
    },
  );

  test('dispatcher rejects concurrent batches', () async {
    addTask('only', now);
    final entered = Completer<void>();
    final release = Completer<void>();
    final target = dispatcher(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async {
          entered.complete();
          await release.future;
          return sampleImportContent(source);
        },
      ),
    );

    final first = target.dispatchPending();
    await entered.future;
    await expectLater(
      target.dispatchPending(),
      throwsA(isA<ImportDispatcherBusyException>()),
    );
    release.complete();
    final report = await first;

    expect(report.processedCount, 1);
    expect(target.isDispatching, isFalse);
  });

  test(
    'batch cancellation cancels current task and leaves later tasks queued',
    () async {
      addTask('first', now);
      addTask('second', now.add(const Duration(minutes: 1)));
      final entered = Completer<void>();
      final token = ImportCancellationToken();
      final target = dispatcher(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (source, cancellationToken) async {
            entered.complete();
            await cancellationToken!.whenCancelled;
            cancellationToken.throwIfCancelled();
            throw StateError('unreachable');
          },
        ),
      );

      final dispatch = target.dispatchPending(cancellationToken: token);
      await entered.future;
      token.cancel();
      final report = await dispatch;

      expect(report.cancelled, isTrue);
      expect(report.processedCount, 1);
      expect(repository.tasks['first']!.status, ImportTaskStatus.cancelled);
      expect(repository.tasks['second']!.status, ImportTaskStatus.queued);
    },
  );

  test('limit bounds the number of claimed tasks', () async {
    addTask('first', now);
    addTask('second', now.add(const Duration(minutes: 1)));
    final report = await dispatcher(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      ),
    ).dispatchPending(limit: 1);

    expect(report.processedCount, 1);
    expect(repository.tasks['first']!.status, ImportTaskStatus.needsReview);
    expect(repository.tasks['second']!.status, ImportTaskStatus.queued);
  });
}
