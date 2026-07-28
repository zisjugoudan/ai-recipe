import 'dart:async';

import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';

void main() {
  late MemoryImportTaskRepository repository;
  late DateTime now;
  DateTime clock() => now;

  ImportTask addTask({String id = 'task-1', int maxAttempts = 3}) {
    final task = ImportTask.queued(
      id: id,
      source: ImportSourceLink.parse('https://v.douyin.com/$id/'),
      now: now,
      maxAttempts: maxAttempts,
    );
    repository.tasks[id] = task;
    return task;
  }

  ImportTaskRunner runner({
    required FakeImportContentAdapter adapter,
    required FakeImportContentProcessor processor,
  }) {
    return ImportTaskRunner(
      repository: repository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]),
      processor: processor,
      clock: clock,
    );
  }

  setUp(() {
    repository = MemoryImportTaskRepository();
    now = DateTime.utc(2026, 7, 28, 10);
  });

  test(
    'runner drives fetched content through processing into review',
    () async {
      addTask();
      final adapter = FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      );
      final processor = FakeImportContentProcessor((
        content,
        progress,
        _,
      ) async {
        await progress(ImportTaskStage.ocr, 0.5);
        await progress(ImportTaskStage.transcribing, 0.7);
        await progress(ImportTaskStage.generating, 0.85);
        return ImportRecipeDraftResult(recipeId: 'recipe-draft-1');
      });

      final result = await runner(
        adapter: adapter,
        processor: processor,
      ).run('task-1');

      expect(result.outcome, ImportTaskRunOutcome.needsReview);
      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(result.task.stage, ImportTaskStage.review);
      expect(result.task.resultRecipeId, 'recipe-draft-1');
      expect(result.content?.title, 'Sample recipe');
      expect(
        repository.savedTasks.map((task) => task.stage),
        containsAllInOrder(<ImportTaskStage>[
          ImportTaskStage.fetching,
          ImportTaskStage.extracting,
          ImportTaskStage.ocr,
          ImportTaskStage.transcribing,
          ImportTaskStage.generating,
          ImportTaskStage.review,
        ]),
      );
    },
  );

  test(
    'adapter authorization errors map to a non-retryable task failure',
    () async {
      addTask();
      final result = await runner(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (_, _) => throw const ImportContentAdapterException(
            kind: ImportContentAdapterErrorKind.authorizationRequired,
            message: 'Login is required.',
            retryable: false,
          ),
        ),
        processor: FakeImportContentProcessor((_, _, _) {
          throw StateError('processor should not run');
        }),
      ).run('task-1');

      expect(result.outcome, ImportTaskRunOutcome.failed);
      expect(result.task.errorCode, ImportTaskErrorCode.authorizationRequired);
      expect(result.task.retryable, isFalse);
      expect(result.task.nextRetryAt, isNull);
    },
  );

  test('retryable network failures use bounded retry scheduling', () async {
    addTask();
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          message: 'Network unavailable.',
          retryable: true,
        ),
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw StateError('processor should not run');
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.networkUnavailable);
    expect(result.task.retryable, isTrue);
    expect(result.task.nextRetryAt, now.add(const Duration(seconds: 30)));
  });

  test('max attempts disable a requested retry', () async {
    addTask(maxAttempts: 1);
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.timeout,
          message: 'Request timed out.',
          retryable: true,
        ),
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw StateError('processor should not run');
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.timeout);
    expect(result.task.retryable, isFalse);
    expect(result.task.nextRetryAt, isNull);
  });

  test('adapter source mismatch maps to extraction failure', () async {
    addTask();
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) async {
          final wrongSource = ImportSourceLink.parse(
            'https://www.xiaohongshu.com/explore/wrong',
          );
          return sampleImportContent(wrongSource);
        },
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw StateError('processor should not run');
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.extractionFailed);
    expect(result.task.retryable, isFalse);
  });

  test('processor failures preserve stable project error codes', () async {
    addTask();
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'LLM request failed.',
          retryable: true,
        );
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.llmFailed);
    expect(result.task.retryable, isTrue);
  });

  test('invalid processor progress maps to schemaInvalid', () async {
    addTask();
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      ),
      processor: FakeImportContentProcessor((_, progress, _) async {
        await progress(ImportTaskStage.ocr, 0.6);
        await progress(ImportTaskStage.extracting, 0.7);
        return ImportRecipeDraftResult(recipeId: 'unreachable');
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.schemaInvalid);
    expect(result.task.retryable, isFalse);
  });

  test('unknown exceptions do not persist exception details', () async {
    addTask();
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw StateError('secret-cookie=abc'),
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw StateError('processor should not run');
      }),
    ).run('task-1');

    expect(result.task.errorCode, ImportTaskErrorCode.unknown);
    expect(result.task.errorMessage, 'The import failed unexpectedly.');
    expect(result.task.errorMessage, isNot(contains('secret-cookie')));
  });

  test('cancellation during adapter work cancels the task', () async {
    addTask();
    final entered = Completer<void>();
    final token = ImportCancellationToken();
    final runFuture = runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, cancellationToken) async {
          entered.complete();
          await cancellationToken!.whenCancelled;
          cancellationToken.throwIfCancelled();
          throw StateError('unreachable');
        },
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw StateError('processor should not run');
      }),
    ).run('task-1', cancellationToken: token);

    await entered.future;
    token.cancel();
    final result = await runFuture;

    expect(result.outcome, ImportTaskRunOutcome.cancelled);
    expect(result.task.status, ImportTaskStatus.cancelled);
    expect(result.task.errorCode, isNull);
  });
}
