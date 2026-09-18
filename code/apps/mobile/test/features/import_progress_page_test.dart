import 'dart:async';

import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/backend/ai_recipe_backend_facade.dart';
import 'package:ai_recipe/application/backend/import_execution_plan.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/importing/import_image_picker.dart';
import 'package:ai_recipe/features/importing/import_progress_page.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_recipe_generation_dependencies.dart';
import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Widget wrap(
    TestBackendHarness harness,
    String taskId, {
    Future<void> Function()? onOpenManualEditor,
    ImportImagePicker? imagePicker,
    AiRecipeBackendFacade? backend,
    VoidCallback? onDataChanged,
  }) => MaterialApp(
    theme: buildAiRecipeTheme(),
    home: ImportProgressPage(
      key: ValueKey<String>(taskId),
      backend: backend ?? harness.root.backend,
      taskId: taskId,
      onDataChanged: onDataChanged ?? () {},
      onOpenManualEditor: onOpenManualEditor,
      imagePicker: imagePicker,
    ),
  );

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'retryable failed import keeps retry and dismissal without recover',
    (tester) async {
      final harness = await createHarness(tester);
      final source = ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/1',
      );
      final retryable =
          ImportTask.queued(
                id: 'retryable-task',
                source: source,
                now: harness.now,
              )
              .start(harness.now)
              .fail(
                code: ImportTaskErrorCode.networkUnavailable,
                message: '网络不可用',
                canRetry: true,
                now: harness.now,
              );
      harness.importTaskRepository.tasks[retryable.id] = retryable;

      await tester.pumpWidget(wrap(harness, retryable.id));
      await tester.pumpAndSettle();

      expect(find.text('导入失败'), findsWidgets);
      expect(find.textContaining('网络不可用'), findsOneWidget);
      await scrollTo(tester, const Key('retryImportButton'));
      expect(find.byKey(const Key('retryImportButton')), findsOneWidget);
      expect(find.byKey(const Key('recoverImportButton')), findsNothing);
      await scrollTo(tester, const Key('dismissFailedImportButton'));
      expect(find.byKey(const Key('dismissFailedImportButton')), findsOneWidget);
      expect(find.text('结束此导入'), findsOneWidget);
    },
  );
  testWidgets(
    'non-retryable failure hides retry and recover but can be dismissed',
    (tester) async {
      final harness = await createHarness(tester);
      final source = ImportSourceLink.parse('https://v.douyin.com/example/');
      final failed =
          ImportTask.queued(id: 'failed-task', source: source, now: harness.now)
              .start(harness.now)
              .fail(
                code: ImportTaskErrorCode.contentUnavailable,
                message: '内容暂不支持',
                canRetry: false,
                now: harness.now,
              );
      harness.importTaskRepository.tasks[failed.id] = failed;

      await tester.pumpWidget(wrap(harness, failed.id));
      await tester.pumpAndSettle();
      expect(find.textContaining('内容暂不支持'), findsOneWidget);
      expect(find.byKey(const Key('retryImportButton')), findsNothing);
      expect(find.byKey(const Key('recoverImportButton')), findsNothing);
      await scrollTo(tester, const Key('dismissFailedImportButton'));
      expect(find.byKey(const Key('dismissFailedImportButton')), findsOneWidget);
      expect(find.text('结束此导入'), findsOneWidget);

      final cancelled = ImportTask.queued(
        id: 'cancelled-task',
        source: source,
        now: harness.now,
      ).cancel(harness.now);
      harness.importTaskRepository.tasks[cancelled.id] = cancelled;
      await tester.pumpWidget(wrap(harness, cancelled.id));
      await tester.pumpAndSettle();
      await scrollTo(tester, const Key('returnFromCancelledImportButton'));
      expect(
        find.byKey(const Key('returnFromCancelledImportButton')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('dismissFailedImportButton')), findsNothing);
      expect(find.byKey(const Key('retryImportButton')), findsNothing);
      expect(find.byKey(const Key('cancelImportButton')), findsNothing);
    },
  );

  testWidgets(
    'failed dismissal reuses cancellation and disables while submitting',
    (tester) async {
      final harness = await createHarness(tester);
      final backend = _PendingFailedCancellationBackend(harness.now);
      var dataChangedCount = 0;

      await tester.pumpWidget(
        wrap(
          harness,
          backend.failed.id,
          backend: backend,
          imagePicker: _FakeImportImagePicker(),
          onDataChanged: () => dataChangedCount += 1,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('AI 返回菜谱结构无效'), findsOneWidget);
      expect(find.byKey(const Key('pastedTextFallbackButton')), findsOneWidget);
      expect(find.byKey(const Key('manualRecipeFallbackButton')), findsOneWidget);
      await scrollTo(tester, const Key('dismissFailedImportButton'));

      await tester.tap(find.byKey(const Key('dismissFailedImportButton')));
      await tester.pump();

      expect(backend.cancelCallCount, 1);
      expect(backend.cancelledTaskId, backend.failed.id);
      expect(find.text('正在结束…'), findsOneWidget);
      final pendingButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('dismissFailedImportButton')),
      );
      expect(pendingButton.onPressed, isNull);

      backend.cancelResult.complete(backend.cancelled);
      await tester.pumpAndSettle();

      expect(find.text('解析已取消'), findsOneWidget);
      expect(find.byKey(const Key('dismissFailedImportButton')), findsNothing);
      expect(dataChangedCount, 1);
    },
  );
  testWidgets('needs-review import automatically opens the AI draft', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '番茄炒蛋 AI 草稿',
        status: RecipeStatus.draft,
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(name: '番茄', confidence: 0.62),
        ],
        steps: const <RecipeStepInput>[
          RecipeStepInput(description: '快速翻炒', confidence: 0.91),
        ],
      ),
    );
    final source = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/2',
    );
    final task =
        ImportTask.queued(id: 'review-task', source: source, now: harness.now)
            .start(harness.now)
            .advance(
              nextStage: ImportTaskStage.generating,
              nextProgress: 0.9,
              now: harness.now,
            )
            .markNeedsReview(recipeId: recipe.id, now: harness.now);
    harness.importTaskRepository.tasks[task.id] = task;

    await tester.pumpWidget(wrap(harness, task.id));
    await tester.pumpAndSettle();

    expect(find.text('确认草稿'), findsWidgets);
    expect(find.text('发现 1 项低置信度内容'), findsOneWidget);
  });

  testWidgets('failed and cancelled tasks expose all fallback entry points', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final source = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/fallback-actions',
    );
    final failed =
        ImportTask.queued(
          id: 'fallback-actions-task',
          source: source,
          now: harness.now,
        ).fail(
          code: ImportTaskErrorCode.contentUnavailable,
          canRetry: false,
          now: harness.now,
        );
    harness.importTaskRepository.tasks[failed.id] = failed;

    await tester.pumpWidget(wrap(harness, failed.id));
    await tester.pumpAndSettle();

    for (final key in <Key>[
      const Key('pastedTextFallbackButton'),
      const Key('imageFallbackButton'),
      const Key('videoFallbackButton'),
      const Key('manualRecipeFallbackButton'),
    ]) {
      await scrollTo(tester, key);
      expect(find.byKey(key), findsOneWidget);
    }
  });

  testWidgets('empty pasted text keeps the sheet open with validation', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = _failedTask(harness, 'fallback-empty-widget');

    await tester.pumpWidget(wrap(harness, task.id));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('pastedTextFallbackButton'));
    await tester.tap(find.byKey(const Key('pastedTextFallbackButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submitPastedTextFallbackButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('fallbackTextField')), findsOneWidget);
    expect(find.textContaining('请先粘贴'), findsOneWidget);
  });

  testWidgets('provider error preserves pasted text for correction', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = _failedTask(harness, 'fallback-provider-widget');
    const pasted = 'tomato 2, egg 3, stir fry all ingredients';

    await tester.pumpWidget(wrap(harness, task.id));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('pastedTextFallbackButton'));
    await tester.tap(find.byKey(const Key('pastedTextFallbackButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fallbackTextField')), pasted);
    await tester.tap(find.byKey(const Key('submitPastedTextFallbackButton')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('fallbackTextField')),
    );
    expect(field.controller?.text, pasted);
    expect(find.textContaining('请先配置 AI'), findsOneWidget);
  });

  testWidgets('successful pasted text opens AI draft review', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final configRepository = _MemoryLlmConfigRepository(
      config: _testLlmConfig,
      apiKey: 'test-placeholder',
    );
    final provider = FakeLlmProvider((config, apiKey, request, token) async {
      return const LlmGenerationResult(text: validRecipeGenerationJson);
    });
    final harness = TestBackendHarness(
      llmConfigRepository: configRepository,
      llmProviderFactory: _FakeLlmProviderFactory(provider),
    );
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    final task = _failedTask(harness, 'fallback-success-widget');

    await tester.pumpWidget(wrap(harness, task.id));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('pastedTextFallbackButton'));
    await tester.tap(find.byKey(const Key('pastedTextFallbackButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('fallbackTextField')),
      'tomato 2, egg 3, stir fry the eggs then add tomato',
    );
    await tester.tap(find.byKey(const Key('submitPastedTextFallbackButton')));
    await tester.pumpAndSettle();

    expect(provider.callCount, 1);
    expect(find.byKey(const Key('importDraftTitleField')), findsOneWidget);
  });

  testWidgets('cancelling image selection keeps the failed task unchanged', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = _failedTask(harness, 'fallback-image-cancel-widget');
    final picker = _FakeImportImagePicker();

    await tester.pumpWidget(wrap(harness, task.id, imagePicker: picker));
    await tester.pumpAndSettle();
    expect(picker.retrieveCount, 1);

    await scrollTo(tester, const Key('imageFallbackButton'));
    await tester.tap(find.byKey(const Key('imageFallbackButton')));
    await tester.pumpAndSettle();

    expect(picker.pickCount, 1);
    expect(await harness.root.backend.getImportTask(task.id), same(task));
    expect(find.text('图片暂时无法处理，请重新选择。'), findsNothing);
    expect(find.byKey(const Key('recoverImportButton')), findsNothing);
    expect(find.byKey(const Key('dismissFailedImportButton')), findsOneWidget);
  });

  testWidgets('image picker failure shows a stable safe error', (tester) async {
    final harness = await createHarness(tester);
    final task = _failedTask(harness, 'fallback-image-picker-error-widget');
    final picker = _FakeImportImagePicker(
      pickError: const ImportImagePickerException('无法打开系统图片选择器，请稍后重试。'),
    );

    await tester.pumpWidget(wrap(harness, task.id, imagePicker: picker));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('imageFallbackButton'));
    await tester.tap(find.byKey(const Key('imageFallbackButton')));
    await tester.pumpAndSettle();

    expect(picker.pickCount, 1);
    expect(find.text('无法打开系统图片选择器，请稍后重试。'), findsOneWidget);
    expect(await harness.root.backend.getImportTask(task.id), same(task));
    expect(find.byKey(const Key('recoverImportButton')), findsNothing);
    expect(find.byKey(const Key('dismissFailedImportButton')), findsOneWidget);
  });

  testWidgets('lost image recovery failure shows a stable safe error', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final task = _failedTask(harness, 'fallback-image-lost-error-widget');
    final picker = _FakeImportImagePicker(
      lostError: const ImportImagePickerException('无法恢复上次的图片选择结果，请重新选择。'),
    );

    await tester.pumpWidget(wrap(harness, task.id, imagePicker: picker));
    await tester.pumpAndSettle();

    expect(picker.retrieveCount, 1);
    expect(find.text('无法恢复上次的图片选择结果，请重新选择。'), findsOneWidget);
    expect(await harness.root.backend.getImportTask(task.id), same(task));
  });
  testWidgets('image fallback shows a safe local OCR installation error', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    final harness = TestBackendHarness(
      localOcrReadiness: CapabilityReadiness.notInstalled,
    );
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    final task = _failedTask(harness, 'fallback-image-no-ocr-widget');
    const privatePath = r'C:/private/recipes/secret-screenshot.png';
    final picker = _FakeImportImagePicker(
      pickedImage: const PickedImportImage(
        localAssetId: privatePath,
        mimeType: 'image/png',
      ),
    );

    await tester.pumpWidget(wrap(harness, task.id, imagePicker: picker));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('imageFallbackButton'));
    await tester.tap(find.byKey(const Key('imageFallbackButton')));
    await tester.pumpAndSettle();

    expect(find.text('请先在 OCR 设置中安装并启用本地 OCR 模型。'), findsOneWidget);
    expect(find.textContaining(privatePath), findsNothing);
    await scrollTo(tester, const Key('pastedTextFallbackButton'));
    expect(find.byKey(const Key('pastedTextFallbackButton')), findsOneWidget);
    await scrollTo(tester, const Key('manualRecipeFallbackButton'));
    expect(find.byKey(const Key('manualRecipeFallbackButton')), findsOneWidget);
  });

  testWidgets(
    'lost Android image selection is recovered through the same route',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      final harness = TestBackendHarness(
        localOcrReadiness: CapabilityReadiness.notInstalled,
      );
      addTearDown(() async {
        await harness.close();
        await tester.binding.setSurfaceSize(null);
      });
      final task = _failedTask(harness, 'fallback-image-lost-widget');
      const privatePath = r'C:/private/recipes/recovered-secret.png';
      final picker = _FakeImportImagePicker(
        lostImage: const PickedImportImage(
          localAssetId: privatePath,
          mimeType: 'image/png',
        ),
      );

      await tester.pumpWidget(wrap(harness, task.id, imagePicker: picker));
      await tester.pumpAndSettle();

      expect(picker.retrieveCount, 1);
      expect(picker.pickCount, 0);
      expect(find.text('请先在 OCR 设置中安装并启用本地 OCR 模型。'), findsOneWidget);
      expect(find.textContaining(privatePath), findsNothing);
      expect(await harness.root.backend.getImportTask(task.id), same(task));
    },
  );

  testWidgets(
    'host refresh exception does not replace the persisted task result',
    (tester) async {
      final harness = await createHarness(tester);
      final backend = _FailedRunBackend(harness.now);

      await tester.pumpWidget(
        wrap(
          harness,
          backend.queued.id,
          backend: backend,
          onDataChanged: () => throw StateError('host refresh failed'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('\u5bfc\u5165\u5931\u8d25'), findsWidgets);
      expect(
        find.textContaining(
          '\u516c\u5f00\u5185\u5bb9\u6682\u65f6\u4e0d\u53ef\u7528',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '\u89e3\u6790\u6682\u65f6\u65e0\u6cd5\u7ee7\u7eed\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'persisted task failure takes precedence over a page-level run exception',
    (tester) async {
      final harness = await createHarness(tester);
      final backend = _FailedRunBackend(
        harness.now,
        throwAfterPersist: true,
      );

      await tester.pumpWidget(
        wrap(harness, backend.queued.id, backend: backend),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          '\u516c\u5f00\u5185\u5bb9\u6682\u65f6\u4e0d\u53ef\u7528',
        ),
        findsOneWidget,
      );
      expect(find.text('\u5f53\u524d\u64cd\u4f5c\u672a\u5b8c\u6210'), findsNothing);
      expect(find.text('\u5bfc\u5165\u80fd\u529b\u6682\u65f6\u65e0\u6cd5\u786e\u8ba4\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002'), findsNothing);
    },
  );

  testWidgets(
    'late polling snapshot cannot replace a successful cancellation',
    (tester) async {
      final harness = await createHarness(tester);
      final backend = _CancellationRaceBackend(harness.now);

      await tester.pumpWidget(
        wrap(harness, backend.queued.id, backend: backend),
      );
      await tester.pump();
      expect(find.byKey(const Key('cancelImportButton')), findsOneWidget);
      expect(find.text('取消解析'), findsOneWidget);
      expect(find.byKey(const Key('dismissFailedImportButton')), findsNothing);

      await tester.pump(const Duration(milliseconds: 450));
      expect(backend.stalePollStarted.isCompleted, isTrue);

      await tester.tap(find.byKey(const Key('cancelImportButton')));
      await tester.pump();
      expect(find.text('\u89e3\u6790\u5df2\u53d6\u6d88'), findsOneWidget);

      backend.stalePoll.complete(backend.running);
      await tester.pump();
      expect(find.text('\u89e3\u6790\u5df2\u53d6\u6d88'), findsOneWidget);
      expect(find.text('\u6b63\u5728\u89e3\u6790'), findsNothing);

      backend.lateRun.complete(
        ImportTaskRunResult(
          task: backend.lateNeedsReview,
          outcome: ImportTaskRunOutcome.needsReview,
        ),
      );
      await tester.pump();
      expect(find.text('\u89e3\u6790\u5df2\u53d6\u6d88'), findsOneWidget);
    },
  );

  testWidgets(
    'video fallback remains unavailable and manual editor still opens',
    (tester) async {
      final harness = await createHarness(tester);
      final task = _failedTask(harness, 'fallback-media-widget');
      final picker = _FakeImportImagePicker();
      var manualOpenCount = 0;

      await tester.pumpWidget(
        wrap(
          harness,
          task.id,
          imagePicker: picker,
          onOpenManualEditor: () async => manualOpenCount += 1,
        ),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, const Key('videoFallbackButton'));
      await tester.tap(find.byKey(const Key('videoFallbackButton')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('videoFallbackUnavailableDialog')),
        findsOneWidget,
      );
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();

      await scrollTo(tester, const Key('manualRecipeFallbackButton'));
      await tester.tap(find.byKey(const Key('manualRecipeFallbackButton')));
      await tester.pumpAndSettle();
      expect(manualOpenCount, 1);
    },
  );
}

class _PendingFailedCancellationBackend implements AiRecipeBackendFacade {
  _PendingFailedCancellationBackend(DateTime now)
    : failed = ImportTask.queued(
        id: 'failed-dismiss-widget',
        source: ImportSourceLink.parse(
          'https://www.xiaohongshu.com/explore/failed-dismiss-widget',
        ),
        now: now,
      ).start(now).fail(
        code: ImportTaskErrorCode.schemaInvalid,
        message: 'AI 返回菜谱结构无效，无法继续。',
        canRetry: false,
        now: now,
      ) {
    cancelled = failed.cancel(now);
  }

  final ImportTask failed;
  late final ImportTask cancelled;
  final Completer<ImportTask> cancelResult = Completer<ImportTask>();
  var cancelCallCount = 0;
  String? cancelledTaskId;

  @override
  Future<ImportTask> getImportTask(String id) async => failed;

  @override
  Future<ImportTask> cancelImportTask(String id) {
    cancelCallCount += 1;
    cancelledTaskId = id;
    return cancelResult.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
class _FailedRunBackend implements AiRecipeBackendFacade {
  _FailedRunBackend(DateTime now, {this.throwAfterPersist = false})
    : queued = ImportTask.queued(
        id: 'host-refresh-failure-widget',
        source: ImportSourceLink.parse(
          'https://www.xiaohongshu.com/explore/host-refresh-failure-widget',
        ),
        now: now,
      ) {
    failed = queued
        .start(now)
        .fail(
          code: ImportTaskErrorCode.contentUnavailable,
          message: '\u516c\u5f00\u5185\u5bb9\u6682\u65f6\u4e0d\u53ef\u7528',
          canRetry: false,
          now: now,
        );
  }

  final ImportTask queued;
  final bool throwAfterPersist;
  late final ImportTask failed;
  var _currentIsFailed = false;

  @override
  Future<ImportTask> getImportTask(String id) async =>
      _currentIsFailed ? failed : queued;

  @override
  Future<ImportTaskRunResult> runImportTask(
    String id, {
    ImportExecutionPlan? plan,
    ImportCancellationToken? cancellationToken,
  }) async {
    _currentIsFailed = true;
    if (throwAfterPersist) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '\u5bfc\u5165\u80fd\u529b\u6682\u65f6\u65e0\u6cd5\u786e\u8ba4\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
      );
    }
    return ImportTaskRunResult(
      task: failed,
      outcome: ImportTaskRunOutcome.failed,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CancellationRaceBackend implements AiRecipeBackendFacade {
  _CancellationRaceBackend(DateTime now)
    : queued = ImportTask.queued(
        id: 'cancel-race-widget',
        source: ImportSourceLink.parse(
          'https://www.xiaohongshu.com/explore/cancel-race-widget',
        ),
        now: now,
      ) {
    running = queued.start(now);
    cancelled = running.cancel(now);
    lateNeedsReview = running
        .advance(
          nextStage: ImportTaskStage.extracting,
          nextProgress: 0.35,
          now: now,
        )
        .advance(
          nextStage: ImportTaskStage.generating,
          nextProgress: 0.8,
          now: now,
        )
        .markNeedsReview(recipeId: 'late-stale-draft', now: now);
  }

  final ImportTask queued;
  late final ImportTask running;
  late final ImportTask cancelled;
  late final ImportTask lateNeedsReview;
  final Completer<void> stalePollStarted = Completer<void>();
  final Completer<ImportTask> stalePoll = Completer<ImportTask>();
  final Completer<ImportTaskRunResult> lateRun =
      Completer<ImportTaskRunResult>();
  var _readCount = 0;

  @override
  Future<ImportTask> getImportTask(String id) {
    _readCount += 1;
    if (_readCount == 1) return Future<ImportTask>.value(queued);
    if (_readCount == 2) {
      stalePollStarted.complete();
      return stalePoll.future;
    }
    return Future<ImportTask>.value(cancelled);
  }

  @override
  Future<ImportTaskRunResult> runImportTask(
    String id, {
    ImportExecutionPlan? plan,
    ImportCancellationToken? cancellationToken,
  }) => lateRun.future;

  @override
  Future<ImportTask> cancelImportTask(String id) async => cancelled;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

ImportTask _failedTask(TestBackendHarness harness, String id) {
  final queued = ImportTask.queued(
    id: id,
    source: ImportSourceLink.parse('https://www.xiaohongshu.com/explore/$id'),
    now: harness.now,
  );
  final failed = queued.fail(
    code: ImportTaskErrorCode.contentUnavailable,
    canRetry: false,
    now: harness.now,
  );
  harness.importTaskRepository.tasks[id] = failed;
  return failed;
}

final LlmConnectionConfig _testLlmConfig = LlmConnectionConfig(
  id: 'widget-config',
  name: 'Widget provider',
  providerType: LlmProviderType.openAiCompatible,
  baseUrl: 'https://example.com/v1',
  secretRef: 'widget-secret',
  model: 'widget-model',
);

class _MemoryLlmConfigRepository implements LlmConfigRepository {
  _MemoryLlmConfigRepository({this.config, this.apiKey = ''});

  LlmConnectionConfig? config;
  String apiKey;

  @override
  Future<void> clearApiKey(String secretRef) async => apiKey = '';

  @override
  Future<LlmConnectionConfig?> load() async => config;

  @override
  Future<String> readApiKey(String secretRef) async => apiKey;

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    this.config = config;
    if (apiKey != null) this.apiKey = apiKey;
  }
}

class _FakeImportImagePicker implements ImportImagePicker {
  _FakeImportImagePicker({
    this.pickedImage,
    this.lostImage,
    this.pickError,
    this.lostError,
  });

  final PickedImportImage? pickedImage;
  final PickedImportImage? lostImage;
  final Object? pickError;
  final Object? lostError;
  var pickCount = 0;
  var retrieveCount = 0;

  @override
  Future<PickedImportImage?> pickImage() async {
    pickCount += 1;
    if (pickError case final error?) throw error;
    return pickedImage;
  }

  @override
  Future<List<PickedImportImage>> pickMultipleImages() async {
    if (pickError case final error?) throw error;
    final picked = pickedImage;
    return picked == null ? const <PickedImportImage>[] : <PickedImportImage>[picked];
  }

  @override
  Future<PickedImportImage?> retrieveLostImage() async {
    retrieveCount += 1;
    if (lostError case final error?) throw error;
    return lostImage;
  }
}

class _FakeLlmProviderFactory extends LlmProviderFactory {
  _FakeLlmProviderFactory(this.provider);

  final LlmProvider provider;

  @override
  LlmProvider create(LlmProviderType type) => provider;
}
