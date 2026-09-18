import 'package:ai_recipe/app/ai_recipe_backend_composition_root.dart';
import 'package:ai_recipe/application/inventory/recommendation_executor.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/inventory/inventory_repository.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';

import 'fake_app_access_dependencies.dart';
import 'fake_import_dependencies.dart';
import 'fake_inventory_repository.dart';
import 'fake_local_business_repositories.dart';
import 'fake_recipe_library_repository.dart';

class TestBackendHarness {
  TestBackendHarness({
    DateTime? now,
    LlmConfigRepository? llmConfigRepository,
    LlmProviderFactory? llmProviderFactory,
    OcrModelPackageService? localOcrModelPackageService,
    Future<OcrProvider> Function()? localOcrBuilder,
    CapabilityReadiness localOcrReadiness = CapabilityReadiness.ready,
  }) : now = now ?? DateTime.utc(2026, 7, 30) {
    var id = 0;
    root = AiRecipeBackendCompositionRoot.device(
      recipeRepository: recipeRepository,
      recipeCategoryRepository: recipeRepository,
      importTaskRepository: importTaskRepository,
      recipeActivityRepository: activityRepository,
      localAppSettingsRepository: settingsRepository,
      cookingRepository: cookingRepository,
      inventoryRepository: inventoryRepository,
      llmConfigRepository: llmConfigRepository ?? _MemoryLlmConfigRepository(),
      llmProviderFactory: llmProviderFactory,
      localOcrModelPackageService: localOcrModelPackageService,
      localOcrBuilder: localOcrBuilder,
      sessionRepository: sessionRepository,
      onboardingRepository: onboardingRepository,
      capabilityRuntimeRepository: FakeAppCapabilityRuntimeRepository(
        runtime: AppCapabilityRuntime(
          readiness: <AppCapability, CapabilityReadiness>{
            for (final capability in AppCapability.values)
              capability: CapabilityReadiness.ready,
            AppCapability.localOcr: localOcrReadiness,
          },
        ),
      ),
      idGenerator: () => 'widget-${id += 1}',
      clock: () => this.now,
      // 测试运行在 FakeAsync 时区，Isolate 消息无法被 pumpAndSettle 等待，
      // 因此推荐匹配注入直算执行器（生产默认后台 Isolate）。
      recommendationExecutor: const DirectRecommendationExecutor(),
    );
  }

  DateTime now;
  final FakeAppSessionRepository sessionRepository = FakeAppSessionRepository(
    session: const AppSession.guest(),
  );
  final MemoryOnboardingRepository onboardingRepository =
      MemoryOnboardingRepository();
  final MemoryRecipeLibraryRepository recipeRepository =
      MemoryRecipeLibraryRepository();
  final MemoryImportTaskRepository importTaskRepository =
      MemoryImportTaskRepository();
  final MemoryRecipeActivityRepository activityRepository =
      MemoryRecipeActivityRepository();
  final MemoryLocalAppSettingsRepository settingsRepository =
      MemoryLocalAppSettingsRepository();
  final MemoryCookingRepository cookingRepository = MemoryCookingRepository();
  final MemoryInventoryRepository inventoryRepository =
      MemoryInventoryRepository();
  late final AiRecipeBackendCompositionRoot root;

  Future<void> close() => root.close();
}

class _MemoryLlmConfigRepository implements LlmConfigRepository {
  LlmConnectionConfig? config;
  String apiKey = '';

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
