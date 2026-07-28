import 'package:ai_recipe/app/ai_recipe_backend_composition_root.dart';
import 'package:ai_recipe/application/access/app_access_use_cases.dart';
import 'package:ai_recipe/application/backend/import_execution_plan.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/asr/asr_models.dart';
import 'package:ai_recipe/domain/asr/asr_provider.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_app_access_dependencies.dart';
import '../support/fake_asr_provider.dart';
import '../support/fake_import_dependencies.dart';
import '../support/fake_ocr_provider.dart';
import '../support/fake_recipe_generation_dependencies.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
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
          isA<AppCapabilityUnavailableException>()
              .having(
                (error) => error.capability,
                'capability',
                AppCapability.customLlm,
              )
              .having(
                (error) => error.reason,
                'reason',
                AppCapabilityReason.providerNotConfigured,
              ),
        ),
      );
      expect(harness.provider.callCount, 0);
      expect(harness.xiaohongshuAdapter.callCount, 0);
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
        ocr: ImportOcrRoute.local,
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
}

class BackendHarness {
  BackendHarness({
    required DateTime now,
    required bool authenticated,
    CapabilityReadiness customLlmReadiness = CapabilityReadiness.ready,
    ImportContent Function(ImportSourceLink source)? xiaohongshuContentBuilder,
    Future<OcrProvider> Function()? localOcrBuilder,
    Future<AsrProvider> Function()? managedAsrBuilder,
  }) {
    recipeRepository = MemoryRecipeLibraryRepository();
    taskRepository = MemoryImportTaskRepository();
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
      authenticated: authenticated,
      customLlmReadiness: customLlmReadiness,
      recipeRepository: recipeRepository,
      taskRepository: taskRepository,
      provider: provider,
      xiaohongshuAdapter: xiaohongshuAdapter,
      localOcrBuilder: localOcrBuilder,
      managedAsrBuilder: managedAsrBuilder,
    );
  }

  late final MemoryRecipeLibraryRepository recipeRepository;
  late final MemoryImportTaskRepository taskRepository;
  late final FakeLlmProvider provider;
  late final FakeImportContentAdapter xiaohongshuAdapter;
  late final AiRecipeBackendCompositionRoot root;

  static AiRecipeBackendCompositionRoot _buildRoot({
    required DateTime now,
    required bool authenticated,
    required CapabilityReadiness customLlmReadiness,
    required MemoryRecipeLibraryRepository recipeRepository,
    required MemoryImportTaskRepository taskRepository,
    required FakeLlmProvider provider,
    required FakeImportContentAdapter xiaohongshuAdapter,
    Future<OcrProvider> Function()? localOcrBuilder,
    Future<AsrProvider> Function()? managedAsrBuilder,
  }) {
    var id = 0;
    final readiness = <AppCapability, CapabilityReadiness>{
      for (final capability in AppCapability.values)
        capability: CapabilityReadiness.ready,
      AppCapability.customLlm: customLlmReadiness,
    };
    final douyin = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (source, token) async => sampleImportContent(source),
    );
    return AiRecipeBackendCompositionRoot.device(
      recipeRepository: recipeRepository,
      recipeCategoryRepository: recipeRepository,
      importTaskRepository: taskRepository,
      sessionRepository: FakeAppSessionRepository(
        session: authenticated
            ? AppSession.authenticated(
                userId: 'user-123',
                displayName: 'Test user',
                signedInAt: now,
              )
            : const AppSession.guest(),
      ),
      llmConfigRepository: MemoryLlmConfigRepository(
        config: testLlmConfig,
        apiKey: 'test-placeholder',
      ),
      capabilityRuntimeRepository: FakeAppCapabilityRuntimeRepository(
        runtime: AppCapabilityRuntime(readiness: readiness),
      ),
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        xiaohongshuAdapter,
        douyin,
      ]),
      llmProviderFactory: FakeLlmProviderFactory(provider),
      localOcrBuilder: localOcrBuilder,
      managedAsrBuilder: managedAsrBuilder,
      idGenerator: () => 'backend-${id += 1}',
      clock: () => now,
    );
  }
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
