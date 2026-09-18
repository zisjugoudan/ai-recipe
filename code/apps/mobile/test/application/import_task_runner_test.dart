import 'dart:async';

import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/importing/import_task_use_cases.dart';
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

  /// 构造一个已进入待确认、关联旧草稿的任务。
  ImportTask needsReviewTask(String id) {
    final queued = addTask(id: id);
    return queued
        .start(now)
        .advance(
          nextStage: ImportTaskStage.extracting,
          nextProgress: 0.25,
          now: now,
        )
        .advance(
          nextStage: ImportTaskStage.generating,
          nextProgress: 0.9,
          now: now,
        )
        .markNeedsReview(recipeId: 'old-draft-$id', now: now);
  }

  ImportTaskRunner runner({
    required FakeImportContentAdapter adapter,
    required FakeImportContentProcessor processor,
    ImportRecipeDraftDiscarder? discardRecipeDraft,
  }) {
    return ImportTaskRunner(
      repository: repository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]),
      processor: processor,
      discardRecipeDraft: discardRecipeDraft ?? discardImportRecipeDraft,
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

  test('persisted cancellation wins over a late pipeline failure', () async {
    addTask();
    final entered = Completer<void>();
    final release = Completer<void>();
    final runFuture = runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      ),
      processor: FakeImportContentProcessor((_, _, _) async {
        entered.complete();
        await release.future;
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.schemaInvalid,
          message: 'late invalid schema',
          retryable: false,
        );
      }),
    ).run('task-1');

    await entered.future;
    await CancelImportTask(repository: repository, clock: clock)('task-1');
    release.complete();
    final result = await runFuture;

    expect(result.outcome, ImportTaskRunOutcome.cancelled);
    expect(result.task.status, ImportTaskStatus.cancelled);
    expect(result.task.errorCode, isNull);
    expect(repository.tasks['task-1']!.status, ImportTaskStatus.cancelled);
    expect(
      repository.savedTasks.where(
        (task) => task.status == ImportTaskStatus.failed,
      ),
      isEmpty,
    );
  });

  test('persisted cancellation wins over a late generated draft', () async {
    final queued = addTask();
    final entered = Completer<void>();
    final release = Completer<void>();
    final discarded = <({String recipeId, String sourceId})>[];
    final runFuture = runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (source, _) async => sampleImportContent(source),
      ),
      processor: FakeImportContentProcessor((_, _, _) async {
        entered.complete();
        await release.future;
        return ImportRecipeDraftResult(recipeId: 'late-recipe-draft');
      }),
      discardRecipeDraft:
          ({required String recipeId, required String sourceId}) async {
            discarded.add((recipeId: recipeId, sourceId: sourceId));
          },
    ).run(queued.id);

    await entered.future;
    await CancelImportTask(repository: repository, clock: clock)(queued.id);
    release.complete();
    final result = await runFuture;

    expect(result.outcome, ImportTaskRunOutcome.cancelled);
    expect(result.task.status, ImportTaskStatus.cancelled);
    expect(repository.tasks[queued.id]!.status, ImportTaskStatus.cancelled);
    expect(
      repository.savedTasks.where(
        (task) => task.status == ImportTaskStatus.needsReview,
      ),
      isEmpty,
    );
    expect(discarded, <({String recipeId, String sourceId})>[
      (recipeId: 'late-recipe-draft', sourceId: queued.normalizedUrl),
    ]);
  });

  test('fallback content bypasses adapter and reaches review', () async {
    final queued = addTask();
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    repository.tasks[failed.id] = failed;
    final adapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (_, _) => throw StateError('adapter must not run'),
    );
    final processor = FakeImportContentProcessor((content, progress, _) async {
      await progress(ImportTaskStage.generating, 0.9);
      return ImportRecipeDraftResult(recipeId: 'fallback-recipe');
    });
    final content = sampleImportContent(
      ImportSourceLink(
        sourceUrl: failed.sourceUrl,
        normalizedUrl: failed.normalizedUrl,
        platform: failed.sourcePlatform,
      ),
      title: 'Pasted recipe',
    );

    final result = await runner(
      adapter: adapter,
      processor: processor,
    ).runWithContent(failed.id, content);

    expect(adapter.callCount, 0);
    expect(processor.callCount, 1);
    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.resultRecipeId, 'fallback-recipe');
    expect(result.task.attempt, failed.attempt);
  });

  test('fallback source mismatch leaves failed task unchanged', () async {
    final queued = addTask();
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    repository.tasks[failed.id] = failed;
    final wrongContent = sampleImportContent(
      ImportSourceLink.parse('https://www.xiaohongshu.com/explore/wrong'),
    );

    await expectLater(
      runner(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (_, _) => throw StateError('adapter must not run'),
        ),
        processor: FakeImportContentProcessor((_, _, _) {
          throw StateError('processor must not run');
        }),
      ).runWithContent(failed.id, wrongContent),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.invalidPayload,
        ),
      ),
    );
    expect(repository.tasks[failed.id], same(failed));
  });

  test('fallback pipeline errors never schedule automatic retry', () async {
    final queued = addTask();
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    repository.tasks[failed.id] = failed;
    final source = ImportSourceLink(
      sourceUrl: failed.sourceUrl,
      normalizedUrl: failed.normalizedUrl,
      platform: failed.sourcePlatform,
    );

    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw StateError('adapter must not run'),
      ),
      processor: FakeImportContentProcessor((_, _, _) {
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'provider key must stay private',
          retryable: true,
        );
      }),
    ).runWithContent(failed.id, sampleImportContent(source));

    expect(result.outcome, ImportTaskRunOutcome.failed);
    expect(result.task.errorCode, ImportTaskErrorCode.llmFailed);
    expect(result.task.retryable, isFalse);
    expect(result.task.nextRetryAt, isNull);
  });

  test('fallback processing can be cancelled without using adapter', () async {
    final queued = addTask();
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    repository.tasks[failed.id] = failed;
    final source = ImportSourceLink(
      sourceUrl: failed.sourceUrl,
      normalizedUrl: failed.normalizedUrl,
      platform: failed.sourcePlatform,
    );
    final entered = Completer<void>();
    final token = ImportCancellationToken();
    final adapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (_, _) => throw StateError('adapter must not run'),
    );
    final runFuture =
        runner(
          adapter: adapter,
          processor: FakeImportContentProcessor((
            _,
            _,
            cancellationToken,
          ) async {
            entered.complete();
            await cancellationToken!.whenCancelled;
            cancellationToken.throwIfCancelled();
            throw StateError('unreachable');
          }),
        ).runWithContent(
          failed.id,
          sampleImportContent(source),
          cancellationToken: token,
        );

    await entered.future;
    token.cancel();
    final result = await runFuture;

    expect(adapter.callCount, 0);
    expect(result.outcome, ImportTaskRunOutcome.cancelled);
    expect(result.task.status, ImportTaskStatus.cancelled);
  });

  test('fallback runner rejects running tasks', () async {
    final queued = addTask();
    // 运行中的任务不允许再以内容运行（防止并发重复处理）。
    final running = queued.start(now);
    repository.tasks[queued.id] = running;
    final source = ImportSourceLink(
      sourceUrl: running.sourceUrl,
      normalizedUrl: running.normalizedUrl,
      platform: running.sourcePlatform,
    );

    await expectLater(
      runner(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (_, _) => throw StateError('adapter must not run'),
        ),
        processor: FakeImportContentProcessor((_, _, _) {
          throw StateError('processor must not run');
        }),
      ).runWithContent(running.id, sampleImportContent(source)),
      throwsA(isA<ImportTaskTransitionException>()),
    );
  });

  test('fallback runner accepts queued placeholder tasks and runs content', () async {
    // 快速导入"拍照选图/剪贴板"新建的占位任务（queued，IMPORT-009）：
    // 直接用本地内容运行，不经过 adapter 抓取链接。
    final queued = addTask(id: 'task-local-placeholder');
    final source = ImportSourceLink(
      sourceUrl: queued.sourceUrl,
      normalizedUrl: queued.normalizedUrl,
      platform: queued.sourcePlatform,
    );

    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw StateError('adapter must not run'),
      ),
      processor: FakeImportContentProcessor((_, progress, _) async {
        await progress(ImportTaskStage.ocr, 0.5);
        await progress(ImportTaskStage.generating, 0.9);
        return const ImportRecipeDraftResult(recipeId: 'recipe-draft-local');
      }),
    ).runWithContent(queued.id, sampleImportContent(source));

    // 排队占位任务直接处理内容：跳过 fetching，进入 extracting → ocr → generating。
    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(result.task.resultRecipeId, 'recipe-draft-local');
    expect(
      repository.savedTasks.map((task) => task.stage),
      containsAllInOrder(<ImportTaskStage>[
        ImportTaskStage.extracting,
        ImportTaskStage.ocr,
        ImportTaskStage.generating,
        ImportTaskStage.review,
      ]),
    );
  });

  test('regenerate replaces the reviewed draft and discards the old one',
      () async {
    final task = needsReviewTask('task-regen');
    repository.tasks[task.id] = task;
    final discarded = <String>[];
    final result = await runner(
      adapter: FakeImportContentAdapter(
        platform: ImportSourcePlatform.douyin,
        handler: (_, _) => throw StateError('adapter must not run'),
      ),
      processor: FakeImportContentProcessor((_, _, _) async {
        return ImportRecipeDraftResult(recipeId: 'recipe-draft-2');
      }),
      discardRecipeDraft: ({required recipeId, required sourceId}) async {
        discarded.add(recipeId);
      },
    ).regenerateWithContent(
      task.id,
      sampleImportContent(ImportSourceLink.parse(task.normalizedUrl)),
    );

    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(result.task.stage, ImportTaskStage.review);
    expect(result.task.resultRecipeId, 'recipe-draft-2');
    expect(result.task.localVersion, greaterThan(task.localVersion));
    expect(discarded, contains('old-draft-task-regen'));
  });

  test('regenerate rejects tasks that are not awaiting review', () async {
    final queued = addTask(id: 'task-queued');
    await expectLater(
      runner(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (_, _) => throw StateError('adapter must not run'),
        ),
        processor: FakeImportContentProcessor((_, _, _) {
          throw StateError('processor must not run');
        }),
      ).regenerateWithContent(
        queued.id,
        sampleImportContent(ImportSourceLink.parse(queued.normalizedUrl)),
      ),
      throwsA(isA<ImportTaskTransitionException>()),
    );
  });

  test('regenerate keeps the reviewed draft when generation fails', () async {
    final task = needsReviewTask('task-regen-fail');
    repository.tasks[task.id] = task;
    final discarded = <String>[];
    await expectLater(
      runner(
        adapter: FakeImportContentAdapter(
          platform: ImportSourcePlatform.douyin,
          handler: (_, _) => throw StateError('adapter must not run'),
        ),
        processor: FakeImportContentProcessor((_, _, _) {
          throw const ImportPipelineException(
            code: ImportTaskErrorCode.schemaInvalid,
            message: 'Schema invalid.',
            retryable: false,
          );
        }),
        discardRecipeDraft: ({required recipeId, required sourceId}) async {
          discarded.add(recipeId);
        },
      ).regenerateWithContent(
        task.id,
        sampleImportContent(ImportSourceLink.parse(task.normalizedUrl)),
      ),
      throwsA(isA<ImportPipelineException>()),
    );
    final latest = await repository.getTaskById(task.id);
    expect(latest!.status, ImportTaskStatus.needsReview);
    expect(latest.resultRecipeId, 'old-draft-task-regen-fail');
    expect(discarded, isEmpty);
  });
}
