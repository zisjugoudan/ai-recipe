import 'package:ai_recipe/app/ai_recipe_backend_composition_root.dart';
import 'package:ai_recipe/application/access/app_access_use_cases.dart';
import 'package:ai_recipe/application/backend/ai_recipe_backend_facade.dart';
import 'package:ai_recipe/application/backend/import_execution_plan.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/asr/asr_models.dart';
import 'package:ai_recipe/domain/asr/asr_provider.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_diagnostic.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/llm/multimodal_llm_provider.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package_exception.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider.dart';
import 'package:ai_recipe/domain/ocr/ocr_remote_image_stager.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_cover_image_storer.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';
import 'package:ai_recipe/providers/llm/multimodal_llm_provider_impls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_app_access_dependencies.dart';
import '../support/fake_asr_provider.dart';
import '../support/fake_import_dependencies.dart';
import '../support/fake_ocr_provider.dart';
import '../support/fake_recipe_generation_dependencies.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  final now = DateTime.utc(2026, 7, 28, 22);

  test(
    'authenticated link import becomes an edited published recipe',
    () async {
      final harness = BackendHarness(now: now, authenticated: true);
      addTearDown(harness.root.close);

      final task = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/facade-flow',
      );
      final runResult = await harness.root.backend.runImportTask(task.id);
      final draft = await harness.root.backend.getImportDraft(task.id);

      expect(runResult.task.status, ImportTaskStatus.needsReview);
      expect(draft.status, RecipeStatus.draft);
      expect(draft.userId, 'user-123');

      final confirmation = await harness.root.backend.confirmImportDraft(
        task.id,
        editedDraft: RecipeDraftInput(
          title: '编辑后的番茄炒蛋',
          description: draft.description,
          servings: draft.servings,
          prepTimeMinutes: draft.prepTimeMinutes,
          cookTimeMinutes: draft.cookTimeMinutes,
          totalTimeMinutes: draft.totalTimeMinutes,
          difficulty: draft.difficulty,
          notes: draft.notes,
          favorite: true,
          status: RecipeStatus.draft,
          ingredients: draft.ingredients
              .map(
                (item) => RecipeIngredientInput(
                  id: item.id,
                  name: item.name,
                  groupName: item.groupName,
                  quantity: item.quantity,
                  unit: item.unit,
                  optional: item.optional,
                  preparation: item.preparation,
                  substitutes: item.substitutes,
                  confidence: item.confidence,
                ),
              )
              .toList(),
          steps: draft.steps
              .map(
                (item) => RecipeStepInput(
                  id: item.id,
                  description: item.description,
                  durationSeconds: item.durationSeconds,
                  temperature: item.temperature,
                  heatLevel: item.heatLevel,
                  cookware: item.cookware,
                  tips: item.tips,
                  mediaUrl: item.mediaUrl,
                  confidence: item.confidence,
                ),
              )
              .toList(),
        ),
      );

      expect(confirmation.task.status, ImportTaskStatus.completed);
      expect(confirmation.recipe.title, '编辑后的番茄炒蛋');
      expect(confirmation.recipe.favorite, isTrue);
      expect(confirmation.recipe.status, RecipeStatus.published);
      expect(confirmation.recipe.localVersion, draft.localVersion + 1);
      expect(harness.provider.callCount, 1);
    },
  );

  test('guest draft stays local and can be discarded', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.douyin.com/video/guest-draft',
    );
    await harness.root.backend.runImportTask(task.id);
    final draft = await harness.root.backend.getImportDraft(task.id);

    expect(draft.userId, isNull);

    final cancelled = await harness.root.backend.discardImportDraft(task.id);
    expect(cancelled.status, ImportTaskStatus.cancelled);
    expect(harness.recipeRepository.recipes[draft.id]!.deletedAt, isNotNull);
    await expectLater(
      harness.root.backend.discardImportDraft(task.id),
      throwsA(isA<Exception>()),
    );
  });

  test('cancelImportTask removes an active generated draft', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final task = await harness.root.backend.createImportTask(
      'https://www.douyin.com/video/cancel-active-draft',
    );
    final result = await harness.root.backend.runImportTask(task.id);
    final recipeId = result.task.resultRecipeId!;

    expect(harness.recipeRepository.recipes, contains(recipeId));
    final cancelled = await harness.root.backend.cancelImportTask(task.id);

    expect(cancelled.status, ImportTaskStatus.cancelled);
    expect(harness.recipeRepository.recipes, isNot(contains(recipeId)));
  });

  test('cancelImportTask never deletes an already published recipe', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final task = await harness.root.backend.createImportTask(
      'https://www.douyin.com/video/cancel-published-recipe',
    );
    final review = await harness.root.backend.runImportTask(task.id);
    final confirmation = await harness.root.backend.confirmImportDraft(task.id);
    harness.taskRepository.tasks[task.id] = review.task;

    final cancelled = await harness.root.backend.cancelImportTask(task.id);

    expect(cancelled.status, ImportTaskStatus.cancelled);
    expect(
      harness.recipeRepository.recipes[confirmation.recipe.id]!.status,
      RecipeStatus.published,
    );
  });

  test('cancelImportTask reports a draft cleanup storage failure', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final task = await harness.root.backend.createImportTask(
      'https://www.douyin.com/video/cancel-cleanup-failure',
    );
    final review = await harness.root.backend.runImportTask(task.id);
    final recipeId = review.task.resultRecipeId!;
    harness.recipeRepository.error = StateError('storage unavailable');

    await expectLater(
      harness.root.backend.cancelImportTask(task.id),
      throwsA(
        isA<AiRecipeBackendException>().having(
          (error) => error.code,
          'code',
          AiRecipeBackendErrorCode.storageUnavailable,
        ),
      ),
    );

    harness.recipeRepository.error = null;
    expect(
      harness.taskRepository.tasks[task.id]!.status,
      ImportTaskStatus.cancelled,
    );
    expect(harness.recipeRepository.recipes, contains(recipeId));
  });

  test(
    'capability denial stops before provider or adapter invocation',
    () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        customLlmReadiness: CapabilityReadiness.notConfigured,
      );
      addTearDown(harness.root.close);

      final task = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/no-provider',
      );

      await expectLater(
        harness.root.backend.runImportTask(task.id),
        throwsA(
          isA<AiRecipeBackendException>()
              .having(
                (error) => error.code,
                'code',
                AiRecipeBackendErrorCode.providerRouteUnavailable,
              )
              .having(
                (error) => error.message,
                'message',
                '\u8bf7\u5148\u5728 LLM \u8bbe\u7f6e\u4e2d\u914d\u7f6e\u5e76\u4fdd\u5b58\u53ef\u7528\u7684\u81ea\u6709 AI \u670d\u52a1\u3002',
              ),
        ),
      );
      expect(harness.provider.callCount, 0);
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(
        harness.taskRepository.tasks[task.id]!.status,
        ImportTaskStatus.queued,
      );
    },
  );

  test(
    'session read failure is mapped before provider or adapter invocation',
    () async {
      final harness = BackendHarness(now: now, authenticated: false);
      addTearDown(harness.root.close);
      final task = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/session-read-failure',
      );
      harness.sessionRepository.loadError = StateError('session unavailable');

      await expectLater(
        harness.root.backend.runImportTask(task.id),
        throwsA(
          isA<AiRecipeBackendException>()
              .having(
                (error) => error.code,
                'code',
                AiRecipeBackendErrorCode.storageUnavailable,
              )
              .having(
                (error) => error.message,
                'message',
                '\u5e94\u7528\u4f1a\u8bdd\u6216\u5bfc\u5165\u8bbe\u7f6e\u6682\u65f6\u65e0\u6cd5\u8bfb\u53d6\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
              ),
        ),
      );
      expect(harness.provider.callCount, 0);
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(
        harness.taskRepository.tasks[task.id]!.status,
        ImportTaskStatus.queued,
      );
    },
  );

  test(
    'capability runtime read failure is mapped before provider or adapter invocation',
    () async {
      final harness = BackendHarness(now: now, authenticated: false);
      addTearDown(harness.root.close);
      final task = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/capability-read-failure',
      );
      harness.capabilityRuntimeRepository.loadError = StateError(
        'capability unavailable',
      );

      await expectLater(
        harness.root.backend.runImportTask(task.id),
        throwsA(
          isA<AiRecipeBackendException>()
              .having(
                (error) => error.code,
                'code',
                AiRecipeBackendErrorCode.operationFailed,
              )
              .having(
                (error) => error.message,
                'message',
                '\u5bfc\u5165\u80fd\u529b\u6682\u65f6\u65e0\u6cd5\u786e\u8ba4\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002',
              ),
        ),
      );
      expect(harness.provider.callCount, 0);
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(
        harness.taskRepository.tasks[task.id]!.status,
        ImportTaskStatus.queued,
      );
    },
  );

  test(
    'confirming an already published draft completes the task without a version bump',
    () async {
      final harness = BackendHarness(now: now, authenticated: true);
      addTearDown(harness.root.close);

      final task = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/idempotent-confirmation',
      );
      await harness.root.backend.runImportTask(task.id);
      final draft = await harness.root.backend.getImportDraft(task.id);

      final published = await harness.root.backend.recipes.updateRecipe(
        draft.id,
        RecipeDraftInput(
          title: draft.title,
          description: draft.description,
          coverImage: draft.coverImage,
          servings: draft.servings,
          prepTimeMinutes: draft.prepTimeMinutes,
          cookTimeMinutes: draft.cookTimeMinutes,
          totalTimeMinutes: draft.totalTimeMinutes,
          difficulty: draft.difficulty,
          notes: draft.notes,
          favorite: draft.favorite,
          status: RecipeStatus.published,
          categoryIds: draft.categoryIds,
          ingredients: draft.ingredients
              .map(
                (item) => RecipeIngredientInput(
                  id: item.id,
                  name: item.name,
                  groupName: item.groupName,
                  quantity: item.quantity,
                  unit: item.unit,
                  optional: item.optional,
                  preparation: item.preparation,
                  substitutes: item.substitutes,
                  confidence: item.confidence,
                ),
              )
              .toList(),
          steps: draft.steps
              .map(
                (item) => RecipeStepInput(
                  id: item.id,
                  description: item.description,
                  durationSeconds: item.durationSeconds,
                  temperature: item.temperature,
                  heatLevel: item.heatLevel,
                  cookware: item.cookware,
                  tips: item.tips,
                  mediaUrl: item.mediaUrl,
                  confidence: item.confidence,
                ),
              )
              .toList(),
        ),
      );

      final confirmation = await harness.root.backend.confirmImportDraft(
        task.id,
      );

      expect(confirmation.task.status, ImportTaskStatus.completed);
      expect(confirmation.recipe.status, RecipeStatus.published);
      expect(confirmation.recipe.localVersion, published.localVersion);
      expect(
        harness.recipeRepository.recipes[draft.id]!.localVersion,
        published.localVersion,
      );
    },
  );

  group('local OCR model management facade', () {
    test('returns model status through the injected service', () async {
      final packageService = FakeOcrModelPackageService(
        status: OcrModelPackageStatus(
          packageId: 'paddleocr-ppocrv5-mobile-zh',
          state: OcrModelInstallState.installed,
          progress: 1,
          installedVersion: '1.0.0',
        ),
      );
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        localOcrModelPackageService: packageService,
      );
      addTearDown(harness.root.close);

      final status = await harness.root.backend.getLocalOcrModelStatus(
        'paddleocr-ppocrv5-mobile-zh',
      );

      expect(packageService.lastStatusPackageId, 'paddleocr-ppocrv5-mobile-zh');
      expect(status.state, OcrModelInstallState.installed);
      expect(status.installedVersion, '1.0.0');
    });

    test(
      'maps incompatible platform errors to componentIncompatible',
      () async {
        final harness = BackendHarness(
          now: now,
          authenticated: false,
          localOcrModelPackageService: FakeOcrModelPackageService(
            getStatusError: const OcrModelPackageException(
              kind: OcrModelPackageErrorKind.incompatiblePlatform,
              message: 'Platform is not supported.',
            ),
          ),
        );
        addTearDown(harness.root.close);

        await expectLater(
          harness.root.backend.getLocalOcrModelStatus(
            'paddleocr-ppocrv5-mobile-zh',
          ),
          throwsA(
            isA<AiRecipeBackendException>().having(
              (error) => error.code,
              'code',
              AiRecipeBackendErrorCode.componentIncompatible,
            ),
          ),
        );
      },
    );

    test(
      'passes the model installation cancellation token to the service',
      () async {
        final packageService = FakeOcrModelPackageService();
        final harness = BackendHarness(
          now: now,
          authenticated: false,
          localOcrModelPackageService: packageService,
        );
        addTearDown(harness.root.close);
        final token = OcrModelInstallCancellationToken();

        await harness.root.backend.installLocalOcrModel(
          sampleOcrModelManifest(),
          cancellationToken: token,
        );

        expect(packageService.lastCancellationToken, same(token));
      },
    );

    test('maps insufficient storage to a stable facade code', () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        localOcrModelPackageService: FakeOcrModelPackageService(
          installError: const OcrModelPackageException(
            kind: OcrModelPackageErrorKind.insufficientStorage,
            message: 'Not enough storage.',
          ),
        ),
      );
      addTearDown(harness.root.close);

      await expectLater(
        harness.root.backend.installLocalOcrModel(sampleOcrModelManifest()),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.insufficientStorage,
          ),
        ),
      );
    });

    test('maps explicit cancellation to a stable facade code', () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        localOcrModelPackageService: FakeOcrModelPackageService(
          installError: const OcrModelPackageException(
            kind: OcrModelPackageErrorKind.cancelled,
            message: 'Installation cancelled.',
          ),
        ),
      );
      addTearDown(harness.root.close);

      await expectLater(
        harness.root.backend.installLocalOcrModel(sampleOcrModelManifest()),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.operationCancelled,
          ),
        ),
      );
    });

    test('maps install failures to componentInstallationFailed', () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        localOcrModelPackageService: FakeOcrModelPackageService(
          installError: const OcrModelPackageException(
            kind: OcrModelPackageErrorKind.checksumMismatch,
            message: 'Model checksum does not match.',
          ),
        ),
      );
      addTearDown(harness.root.close);

      await expectLater(
        harness.root.backend.installLocalOcrModel(sampleOcrModelManifest()),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.componentInstallationFailed,
          ),
        ),
      );
    });
  });

  test('OCR and ASR routes enrich content before recipe generation', () async {
    final ocrProvider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: '图片识别：番茄两个，鸡蛋三个');
    });
    final asrProvider = FakeAsrProvider(
      (input, token) async =>
          sampleAsrTranscript(text: '先炒鸡蛋，再加入番茄翻炒。', startMs: 200, endMs: 4200),
      kind: AsrProviderKind.cloudApi,
    );
    final harness = BackendHarness(
      now: now,
      authenticated: true,
      xiaohongshuContentBuilder: (source) => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.mixed,
        title: '需要 OCR 和 ASR 的菜谱',
        capturedAt: now,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/recipe.jpg',
            order: 0,
          ),
          ImportMediaReference(
            kind: ImportMediaKind.video,
            remoteUrl: 'https://example.com/recipe.mp4',
            mimeType: 'video/mp4',
            durationMs: 5000,
            order: 1,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
          ImportContentWarning.requiresAsr,
          ImportContentWarning.missingText,
        ],
      ),
      localOcrBuilder: () async => ocrProvider,
      managedAsrBuilder: () async => asrProvider,
    );
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/ocr-asr',
    );
    final result = await harness.root.backend.runImportTask(
      task.id,
      plan: const ImportExecutionPlan(
        imageRecognition: ImportImageRecognitionRoute.ocr,
        asr: ImportAsrRoute.managed,
      ),
    );
    expect(
      result.task.status,
      ImportTaskStatus.needsReview,
      reason: '${result.task.errorCode}: ${result.task.errorMessage}',
    );
    final confirmation = await harness.root.backend.confirmImportDraft(task.id);

    expect(ocrProvider.inputs, hasLength(1));
    expect(asrProvider.inputs, hasLength(1));
    expect(harness.provider.callCount, 1);
    expect(confirmation.recipe.status, RecipeStatus.published);
    expect(confirmation.task.status, ImportTaskStatus.completed);
  });

  test('link import auto-enables local OCR when the capability is ready', () async {
    final ocrProvider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: '图片识别：番茄两个，鸡蛋三个');
    });
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      xiaohongshuContentBuilder: (source) => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.mixed,
        title: '图文菜谱',
        capturedAt: now,
        textFragments: <ImportTextFragment>[
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: '把食材准备好。',
            order: 0,
          ),
        ],
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/recipe.jpg',
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
        ],
      ),
      localOcrBuilder: () async => ocrProvider,
    );
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/auto-ocr',
    );
    // 不传 plan：Facade 应自动启用 ocr: local，把图片 OCR 与正文整合后给 AI。
    final result = await harness.root.backend.runImportTask(task.id);

    expect(ocrProvider.inputs, hasLength(1));
    expect(
      result.task.status,
      ImportTaskStatus.needsReview,
      reason: '${result.task.errorCode}: ${result.task.errorMessage}',
    );
    final draft = await harness.root.backend.getImportDraft(task.id);
    expect(draft.title, isNotEmpty);
  });

  test('link import falls back to text-only when OCR is not installed', () async {
    final ocrProvider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: '不会被调用');
    });
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      localOcrReadiness: CapabilityReadiness.notInstalled,
      xiaohongshuContentBuilder: (source) => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.mixed,
        title: '图文菜谱',
        capturedAt: now,
        textFragments: <ImportTextFragment>[
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: '番茄两个，鸡蛋三个，热锅倒油翻炒。',
            order: 0,
          ),
        ],
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/recipe.jpg',
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
        ],
      ),
      localOcrBuilder: () async => ocrProvider,
    );
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/ocr-not-installed',
    );
    final result = await harness.root.backend.runImportTask(task.id);

    // OCR 未就绪时降级为纯文本路径：有文字的图文内容仍可正常生成。
    expect(ocrProvider.inputs, isEmpty);
    expect(
      result.task.status,
      ImportTaskStatus.needsReview,
      reason: '${result.task.errorCode}: ${result.task.errorMessage}',
    );
  });

  test('image-only link import fails with OCR guidance when OCR is missing', () async {
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      localOcrReadiness: CapabilityReadiness.notInstalled,
      xiaohongshuContentBuilder: (source) => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.imageGallery,
        title: '纯图片菜谱',
        capturedAt: now,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/recipe.jpg',
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
          ImportContentWarning.missingText,
        ],
      ),
    );
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/image-only',
    );
    final result = await harness.root.backend.runImportTask(task.id);

    expect(result.task.status, ImportTaskStatus.failed);
    expect(result.task.errorMessage, contains('需要先完成图片文字识别'));
  });

  test('link import downloads remote images into the draft covers', () async {
    final storer = _TestCoverImageStorer();
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      localOcrReadiness: CapabilityReadiness.notInstalled,
      xiaohongshuContentBuilder: (source) => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.mixed,
        title: '带图菜谱',
        capturedAt: now,
        textFragments: <ImportTextFragment>[
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: '番茄两个，鸡蛋三个。',
            order: 0,
          ),
        ],
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/food-1.jpg',
            order: 0,
          ),
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/food-2.jpg',
            order: 1,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
        ],
      ),
      coverImageStorer: storer,
    );
    addTearDown(harness.root.close);

    final task = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/with-covers',
    );
    final result = await harness.root.backend.runImportTask(task.id);

    expect(
      result.task.status,
      ImportTaskStatus.needsReview,
      reason: '${result.task.errorCode}: ${result.task.errorMessage}',
    );
    // 链接导入自动把配图下载到本地并写入草稿封面（IMPORT-006）。
    expect(storer.copied, hasLength(2));
    final draft = await harness.root.backend.getImportDraft(task.id);
    expect(draft.images, hasLength(2));
    expect(draft.coverImage, draft.images.first);
    expect(
      draft.images.every((path) => path.startsWith('/covers/')),
      isTrue,
      reason: '草稿封面必须是本地路径而非远程 URL',
    );
  });

  test('local image fallback falls back to local OCR when multimodal is unavailable',
      () async {
    final ocrProvider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: '番茄两个，鸡蛋三个。先炒鸡蛋，再加入番茄。');
    });
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      localOcrBuilder: () async => ocrProvider,
      // 多模态未配置（默认多模态优先，2026-08-07 决策）→ 回退本地 OCR。
      multimodalLlmReadiness: CapabilityReadiness.notConfigured,
    );
    addTearDown(harness.root.close);
    final queued = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/fallback-local-image',
    );
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    harness.taskRepository.tasks[failed.id] = failed;
    const localAssetId = 'content://media/external/images/media/42';

    final result = await harness.root.backend.runImportWithLocalImage(
      failed.id,
      localAssetId,
      mimeType: 'image/png',
    );

    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(result.task.attempt, failed.attempt);
    expect(harness.xiaohongshuAdapter.callCount, 0);
    expect(ocrProvider.inputs, hasLength(1));
    expect(ocrProvider.inputs.single.localAssetId, localAssetId);
    expect(ocrProvider.inputs.single.mimeType, 'image/png');
    expect(harness.provider.callCount, 1);
  });

  test('local image fallback prefers multimodal transcription when configured',
      () async {
    // 多模态识别需要真实文件字节：创建临时图片文件。
    final tempDir = await Directory.systemTemp.createTemp(
      'multimodal-facade-test',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final imagePath = '${tempDir.path}/capture.png';
    await File(imagePath).writeAsBytes(<int>[1, 2, 3, 4]);

    final vision = _RecordingMultimodalProvider(
      resultText: '番茄两个，鸡蛋三个。先炒鸡蛋，再加入番茄。',
    );
    final harness = BackendHarness(
      now: now,
      authenticated: false,
      // 多模态可用（默认优先）：即使 OCR 可用也不应被调用。
      localOcrBuilder: () async => FakeOcrProvider((input, token) async {
        throw StateError('多模态优先时不应调用本地 OCR');
      }),
      remoteOcrImageStager: _FixedFileOcrImageStager(imagePath),
      multimodalConfigRepository: MemoryLlmConfigRepository(
        config: testLlmConfig,
        apiKey: 'test-placeholder',
      ),
      multimodalProviderFactory: _RecordingMultimodalLlmProviderFactory(
        vision,
      ),
    );
    addTearDown(harness.root.close);
    final queued = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/fallback-local-image-multimodal',
    );
    harness.taskRepository.tasks[queued.id] = queued;
    const localAssetId = 'content://media/external/images/media/44';

    final result = await harness.root.backend.runImportWithLocalImage(
      queued.id,
      localAssetId,
      mimeType: 'image/png',
    );

    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(harness.xiaohongshuAdapter.callCount, 0);
    // 直接用多模态识别图片内容，本地 OCR 未参与。
    expect(vision.inputs, hasLength(1));
    expect(vision.inputs.single.mimeType, 'image/png');
    expect(harness.provider.callCount, 1);
  });

  test(
    'local image fallback rejects a task outside queued, failed or cancelled',
    () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        hasLlmConfig: false,
      );
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-image-invalid-state',
      );
      // 运行中的任务不允许再用本地图片内容运行（防止并发重复处理）。
      final running = queued.start(now);
      harness.taskRepository.tasks[running.id] = running;

      await expectLater(
        harness.root.backend.runImportWithLocalImage(
          running.id,
          'content://media/external/images/media/43',
          mimeType: 'image/jpeg',
        ),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.invalidTaskState,
          ),
        ),
      );

      expect(harness.taskRepository.tasks[running.id], same(running));
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(harness.provider.callCount, 0);
    },
  );

  test(
    'local image fallback rejects empty ids and non-image MIME safely',
    () async {
      final harness = BackendHarness(now: now, authenticated: false);
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-image-invalid-input',
      );
      final failed = queued.fail(
        code: ImportTaskErrorCode.contentUnavailable,
        canRetry: false,
        now: now,
      );
      harness.taskRepository.tasks[failed.id] = failed;

      for (final input in <({String assetId, String? mimeType})>[
        (assetId: '   ', mimeType: 'image/png'),
        (
          assetId: 'content://media/external/video/media/9',
          mimeType: 'video/mp4',
        ),
      ]) {
        await expectLater(
          harness.root.backend.runImportWithLocalImage(
            failed.id,
            input.assetId,
            mimeType: input.mimeType,
          ),
          throwsA(
            isA<AiRecipeBackendException>().having(
              (error) => error.code,
              'code',
              AiRecipeBackendErrorCode.invalidInput,
            ),
          ),
        );
      }

      expect(harness.taskRepository.tasks[failed.id], same(failed));
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(harness.provider.callCount, 0);
    },
  );

  test(
    'local image fallback maps unavailable image routes without exposing its path',
    () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        localOcrReadiness: CapabilityReadiness.notInstalled,
        multimodalLlmReadiness: CapabilityReadiness.notConfigured,
      );
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-image-no-ocr',
      );
      final failed = queued.fail(
        code: ImportTaskErrorCode.contentUnavailable,
        canRetry: false,
        now: now,
      );
      harness.taskRepository.tasks[failed.id] = failed;
      const privatePath = r'C:/private/recipes/api-key-secret.png';

      Object? caught;
      try {
        await harness.root.backend.runImportWithLocalImage(
          failed.id,
          privatePath,
          mimeType: 'image/png',
        );
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<AiRecipeBackendException>());
      final backendError = caught! as AiRecipeBackendException;
      expect(
        backendError.code,
        AiRecipeBackendErrorCode.providerRouteUnavailable,
      );
      expect(
        backendError.message,
        '当前图片识别方式不可用，请检查识图引擎设置后重试。',
      );
      expect(backendError.message, isNot(contains(privatePath)));
      expect(backendError.message, isNot(contains('api-key-secret')));
      expect(harness.taskRepository.tasks[failed.id], same(failed));
      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(harness.provider.callCount, 0);
    },
  );

  test(
    'pasted text fallback reaches review without calling public adapter',
    () async {
      final harness = BackendHarness(now: now, authenticated: false);
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-success',
      );
      final failed = queued.fail(
        code: ImportTaskErrorCode.contentUnavailable,
        canRetry: false,
        now: now,
      );
      harness.taskRepository.tasks[failed.id] = failed;

      final result = await harness.root.backend.runImportWithPastedText(
        failed.id,
        'Tomato 2, egg 3. Stir fry the eggs, then add tomato.',
      );

      expect(harness.xiaohongshuAdapter.callCount, 0);
      expect(harness.provider.callCount, 1);
      expect(result.outcome, ImportTaskRunOutcome.needsReview);
      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(result.task.attempt, failed.attempt);
    },
  );

  test('pasted text fallback maps empty input without changing task', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final queued = await harness.root.backend.createImportTask(
      'https://www.xiaohongshu.com/explore/fallback-empty',
    );
    final failed = queued.fail(
      code: ImportTaskErrorCode.contentUnavailable,
      canRetry: false,
      now: now,
    );
    harness.taskRepository.tasks[failed.id] = failed;

    await expectLater(
      harness.root.backend.runImportWithPastedText(failed.id, '   '),
      throwsA(
        isA<AiRecipeBackendException>().having(
          (error) => error.code,
          'code',
          AiRecipeBackendErrorCode.invalidInput,
        ),
      ),
    );
    expect(harness.taskRepository.tasks[failed.id], same(failed));
  });

  test(
    'pasted text fallback maps missing provider and preserves input task',
    () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        hasLlmConfig: false,
      );
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-provider',
      );
      final failed = queued.fail(
        code: ImportTaskErrorCode.contentUnavailable,
        canRetry: false,
        now: now,
      );
      harness.taskRepository.tasks[failed.id] = failed;
      const pasted = 'private ingredient notes api-key-do-not-log';

      Object? caught;
      try {
        await harness.root.backend.runImportWithPastedText(failed.id, pasted);
      } catch (error) {
        caught = error;
      }

      expect(caught, isA<AiRecipeBackendException>());
      final backendError = caught! as AiRecipeBackendException;
      expect(
        backendError.code,
        AiRecipeBackendErrorCode.providerRouteUnavailable,
      );
      expect(backendError.message, isNot(contains(pasted)));
      expect(backendError.message, isNot(contains('api-key-do-not-log')));
      expect(harness.taskRepository.tasks[failed.id], same(failed));
    },
  );

  test(
    'pasted text fallback rejects queued task before provider routing',
    () async {
      final harness = BackendHarness(
        now: now,
        authenticated: false,
        hasLlmConfig: false,
      );
      addTearDown(harness.root.close);
      final queued = await harness.root.backend.createImportTask(
        'https://www.xiaohongshu.com/explore/fallback-invalid-state',
      );

      await expectLater(
        harness.root.backend.runImportWithPastedText(
          queued.id,
          'Tomato and egg recipe text.',
        ),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.invalidTaskState,
          ),
        ),
      );
      expect(harness.taskRepository.tasks[queued.id], same(queued));
    },
  );

  test('updateRecipeStepDuration persists a custom step duration', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final recipe = await harness.root.backend.createRecipe(
      const RecipeDraftInput(
        title: 'Custom timer recipe',
        status: RecipeStatus.published,
        steps: <RecipeStepInput>[
          RecipeStepInput(description: 'Beat Egg.'),
        ],
      ),
    );

    final updated = await harness.root.backend.updateRecipeStepDuration(
      recipe.id,
      recipe.steps.single.id,
      90,
    );

    expect(updated.steps.single.durationSeconds, 90);
    final reloaded = await harness.root.backend.getRecipe(recipe.id);
    expect(reloaded.steps.single.durationSeconds, 90);
  });

  test('updateRecipeStepDuration maps validation errors safely', () async {
    final harness = BackendHarness(now: now, authenticated: false);
    addTearDown(harness.root.close);
    final recipe = await harness.root.backend.createRecipe(
      const RecipeDraftInput(
        title: 'Custom timer recipe',
        status: RecipeStatus.published,
        steps: <RecipeStepInput>[
          RecipeStepInput(description: 'Step one.'),
        ],
      ),
    );

    await expectLater(
      harness.root.backend.updateRecipeStepDuration(
        recipe.id,
        'foreign-step-private',
        0,
      ),
      throwsA(
        isA<AiRecipeBackendException>().having(
          (error) => error.code,
          'code',
          AiRecipeBackendErrorCode.invalidInput,
        ),
      ),
    );
    expect(harness.recipeRepository.recipes[recipe.id], isNotNull);
  });
}

class BackendHarness {
  BackendHarness({
    required DateTime now,
    required bool authenticated,
    CapabilityReadiness customLlmReadiness = CapabilityReadiness.ready,
    CapabilityReadiness localOcrReadiness = CapabilityReadiness.ready,
    CapabilityReadiness multimodalLlmReadiness = CapabilityReadiness.ready,
    bool hasLlmConfig = true,
    ImportContent Function(ImportSourceLink source)? xiaohongshuContentBuilder,
    Future<OcrProvider> Function()? localOcrBuilder,
    OcrRemoteImageStager? remoteOcrImageStager,
    OcrModelPackageService? localOcrModelPackageService,
    Future<AsrProvider> Function()? managedAsrBuilder,
    RecipeCoverImageStorer? coverImageStorer,
    LlmConfigRepository? multimodalConfigRepository,
    MultimodalLlmProviderFactory? multimodalProviderFactory,
  }) {
    recipeRepository = MemoryRecipeLibraryRepository();
    taskRepository = MemoryImportTaskRepository();
    final readiness = <AppCapability, CapabilityReadiness>{
      for (final capability in AppCapability.values)
        capability: CapabilityReadiness.ready,
      AppCapability.customLlm: customLlmReadiness,
      AppCapability.localOcr: localOcrReadiness,
      AppCapability.multimodalLlm: multimodalLlmReadiness,
    };
    sessionRepository = FakeAppSessionRepository(
      session: authenticated
          ? AppSession.authenticated(
              userId: 'user-123',
              displayName: 'Test user',
              signedInAt: now,
            )
          : const AppSession.guest(),
    );
    capabilityRuntimeRepository = FakeAppCapabilityRuntimeRepository(
      runtime: AppCapabilityRuntime(readiness: readiness),
    );
    provider = FakeLlmProvider((config, apiKey, request, token) async {
      return const LlmGenerationResult(text: validRecipeGenerationJson);
    });
    xiaohongshuAdapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.xiaohongshu,
      handler: (source, token) async =>
          xiaohongshuContentBuilder?.call(source) ??
          sampleImportContent(source),
    );
    root = _buildRoot(
      now: now,
      hasLlmConfig: hasLlmConfig,
      recipeRepository: recipeRepository,
      taskRepository: taskRepository,
      sessionRepository: sessionRepository,
      capabilityRuntimeRepository: capabilityRuntimeRepository,
      provider: provider,
      xiaohongshuAdapter: xiaohongshuAdapter,
      localOcrBuilder: localOcrBuilder,
      remoteOcrImageStager: remoteOcrImageStager,
      localOcrModelPackageService: localOcrModelPackageService,
      managedAsrBuilder: managedAsrBuilder,
      coverImageStorer: coverImageStorer,
      multimodalConfigRepository: multimodalConfigRepository,
      multimodalProviderFactory: multimodalProviderFactory,
    );
  }

  late final MemoryRecipeLibraryRepository recipeRepository;
  late final MemoryImportTaskRepository taskRepository;
  late final FakeAppSessionRepository sessionRepository;
  late final FakeAppCapabilityRuntimeRepository capabilityRuntimeRepository;
  late final FakeLlmProvider provider;
  late final FakeImportContentAdapter xiaohongshuAdapter;
  late final AiRecipeBackendCompositionRoot root;

  static AiRecipeBackendCompositionRoot _buildRoot({
    required DateTime now,
    required bool hasLlmConfig,
    required MemoryRecipeLibraryRepository recipeRepository,
    required MemoryImportTaskRepository taskRepository,
    required FakeAppSessionRepository sessionRepository,
    required FakeAppCapabilityRuntimeRepository capabilityRuntimeRepository,
    required FakeLlmProvider provider,
    required FakeImportContentAdapter xiaohongshuAdapter,
    Future<OcrProvider> Function()? localOcrBuilder,
    OcrRemoteImageStager? remoteOcrImageStager,
    OcrModelPackageService? localOcrModelPackageService,
    Future<AsrProvider> Function()? managedAsrBuilder,
    RecipeCoverImageStorer? coverImageStorer,
    LlmConfigRepository? multimodalConfigRepository,
    MultimodalLlmProviderFactory? multimodalProviderFactory,
  }) {
    var id = 0;
    final douyin = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (source, token) async => sampleImportContent(source),
    );
    return AiRecipeBackendCompositionRoot.device(
      database: AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      ),
      recipeRepository: recipeRepository,
      recipeCategoryRepository: recipeRepository,
      importTaskRepository: taskRepository,
      sessionRepository: sessionRepository,
      llmConfigRepository: MemoryLlmConfigRepository(
        config: hasLlmConfig ? testLlmConfig : null,
        apiKey: hasLlmConfig ? 'test-placeholder' : '',
      ),
      capabilityRuntimeRepository: capabilityRuntimeRepository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        xiaohongshuAdapter,
        douyin,
      ]),
      llmProviderFactory: FakeLlmProviderFactory(provider),
      localOcrBuilder: localOcrBuilder,
      remoteOcrImageStager:
          remoteOcrImageStager ?? const _TestRemoteOcrImageStager(),
      localOcrModelPackageService: localOcrModelPackageService,
      managedAsrBuilder: managedAsrBuilder,
      coverImageStorer: coverImageStorer,
      multimodalConfigRepository: multimodalConfigRepository,
      multimodalProviderFactory: multimodalProviderFactory,
      idGenerator: () => 'backend-${id += 1}',
      clock: () => now,
    );
  }
}

class _TestRemoteOcrImageStager implements OcrRemoteImageStager {
  const _TestRemoteOcrImageStager();

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return StagedOcrImage(
      input: OcrImageInput(
        localAssetId: 'test-staged-${input.order}.img',
        mimeType: input.mimeType,
        width: input.width,
        height: input.height,
        order: input.order,
      ),
      byteLength: 1,
      width: input.width ?? 1,
      height: input.height ?? 1,
      dispose: () async {},
    );
  }
}

/// 可编程多模态 Provider：记录识别输入并返回固定转录文本。
class _RecordingMultimodalProvider extends MultimodalLlmProvider {
  _RecordingMultimodalProvider({this.resultText});

  final String? resultText;
  final List<MultimodalImageInput> inputs = <MultimodalImageInput>[];

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<LlmDiagnosticReport> diagnose({
    required LlmConnectionConfig config,
    required String apiKey,
    required bool imageProbe,
    LlmCancellationToken? cancellationToken,
  }) async {
    return const LlmDiagnosticReport(
      records: [],
      totalElapsedMs: 0,
      succeeded: true,
    );
  }

  @override
  String? validateImageBytes({required List<int> bytes, String? mimeType}) {
    return null;
  }

  @override
  Future<MultimodalRecognitionResult> recognizeImage({
    required LlmConnectionConfig config,
    required String apiKey,
    required MultimodalImageInput input,
    required String prompt,
    LlmCancellationToken? cancellationToken,
  }) async {
    inputs.add(input);
    return MultimodalRecognitionResult(
      text: resultText ?? '画面中有一道菜和几个食材',
      providerId: 'fake-vision',
    );
  }
}

/// 多模态 Provider 工厂：始终返回同一个可编程 Provider。
class _RecordingMultimodalLlmProviderFactory extends MultimodalLlmProviderFactory {
  _RecordingMultimodalLlmProviderFactory(this._provider);

  final _RecordingMultimodalProvider _provider;

  @override
  MultimodalLlmProvider create(LlmProviderType type) => _provider;
}

/// 固定把暂存结果指向真实文件的暂存器（多模态识别需读取真实字节）。
class _FixedFileOcrImageStager implements OcrRemoteImageStager {
  const _FixedFileOcrImageStager(this._localAssetId);

  final String _localAssetId;

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return StagedOcrImage(
      input: OcrImageInput(
        localAssetId: _localAssetId,
        mimeType: input.mimeType,
        width: input.width,
        height: input.height,
        order: input.order,
      ),
      byteLength: 1,
      width: input.width ?? 1,
      height: input.height ?? 1,
      dispose: () async {},
    );
  }
}

class _TestCoverImageStorer implements RecipeCoverImageStorer {
  final List<String> copied = <String>[];

  @override
  Future<String> copyIn({
    required String sourcePath,
    required String containerId,
    required int index,
  }) async {
    copied.add(sourcePath);
    return '/covers/$containerId/$index.jpg';
  }

  @override
  Future<void> deleteFile(String imagePath) async {}

  @override
  Future<void> deleteContainer(String containerId) async {}
}

final LlmConnectionConfig testLlmConfig = LlmConnectionConfig(
  id: 'test-config',
  name: 'Test provider',
  providerType: LlmProviderType.openAiCompatible,
  baseUrl: 'https://example.com/v1',
  secretRef: 'test-secret-ref',
  model: 'test-model',
);

class MemoryLlmConfigRepository implements LlmConfigRepository {
  MemoryLlmConfigRepository({this.config, this.apiKey = ''});

  LlmConnectionConfig? config;
  String apiKey;

  @override
  Future<void> clearApiKey(String secretRef) async {
    apiKey = '';
  }

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

class FakeLlmProviderFactory extends LlmProviderFactory {
  FakeLlmProviderFactory(this.provider);

  final LlmProvider provider;

  @override
  LlmProvider create(LlmProviderType type) => provider;
}

OcrModelManifest sampleOcrModelManifest() {
  return OcrModelManifest(
    schemaVersion: 1,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: '1.0.0',
    engine: 'onnxruntime',
    platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
    languages: const <String>['zh-Hans', 'en'],
    minAppVersion: '0.1.0',
    license: 'Apache-2.0',
    files: <OcrModelFile>[
      OcrModelFile(
        role: 'detector',
        path: 'det.onnx',
        downloadUrl: 'https://models.example.invalid/ocr/det.onnx',
        sha256: '0' * 64,
        sizeBytes: 1,
      ),
    ],
  );
}

class FakeOcrModelPackageService implements OcrModelPackageService {
  FakeOcrModelPackageService({
    OcrModelPackageStatus? status,
    this.activePackage,
    this.getStatusError,
    this.installError,
  }) : status =
           status ??
           OcrModelPackageStatus(
             packageId: 'paddleocr-ppocrv5-mobile-zh',
             state: OcrModelInstallState.notInstalled,
             progress: 0,
           );

  OcrModelPackageStatus status;
  OcrInstalledModelPackage? activePackage;
  Object? getStatusError;
  Object? installError;
  String? lastStatusPackageId;
  OcrModelManifest? lastInstalledManifest;
  OcrModelInstallCancellationToken? lastCancellationToken;
  String? deletedPackageId;
  var recoverCount = 0;

  @override
  Future<OcrModelPackageStatus> getStatus(String packageId) async {
    lastStatusPackageId = packageId;
    if (getStatusError case final error?) throw error;
    return status;
  }

  @override
  Future<OcrInstalledModelPackage?> getActivePackage(String packageId) async {
    return activePackage;
  }

  @override
  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    lastInstalledManifest = manifest;
    lastCancellationToken = cancellationToken;
    if (installError case final error?) throw error;
    onStatusChanged?.call(status);
    return status;
  }

  @override
  Future<void> delete(String packageId) async {
    deletedPackageId = packageId;
  }

  @override
  Future<void> recoverInterruptedInstallations() async {
    recoverCount += 1;
  }
}
