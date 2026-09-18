import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/access/app_access_use_cases.dart';
import '../application/access/onboarding_use_cases.dart';
import '../application/backend/ai_recipe_backend_facade.dart';
import '../application/backend/import_task_runner_factory.dart';
import '../application/backup/backup_export_use_cases.dart';
import '../application/backup/backup_import_use_cases.dart';
import '../application/cooking/cooking_use_cases.dart';
import '../application/home/home_use_cases.dart';
import '../application/importing/import_recipe_draft_discarder.dart';
import '../application/inventory/inventory_use_cases.dart';
import '../application/inventory/recommendation_executor.dart';
import '../application/ocr/local_ocr_model_use_cases.dart';
import '../application/recipe/recipe_detail_use_cases.dart';
import '../application/recipe/recipe_library_use_cases.dart';
import '../application/settings/llm_settings_use_cases.dart';
import '../application/settings/local_app_settings_use_cases.dart';
import '../data/backup/device_backup_archive_reader.dart';
import '../data/backup/device_backup_archive_writer.dart';
import '../data/backup/device_backup_import_media_writer.dart';
import '../data/backup/sqlite_backup_import_repository.dart';
import '../data/backup/sqlite_backup_snapshot_repository.dart';
import '../data/device_app_capability_runtime_repository.dart';
import '../data/device_app_session_repository.dart';
import '../data/device_import_task_runner_factory.dart';
import '../data/device_onboarding_repository.dart';
import '../data/llm_config_repository.dart';
import '../data/multimodal_llm_config_repository.dart';
import '../data/ocr/device_ocr_model_package_service.dart';
import '../data/recipe_cover_image_stager.dart';
import '../data/local/app_database.dart';
import '../data/sqlite_cooking_repository.dart';
import '../data/sqlite_import_task_repository.dart';
import '../data/sqlite_inventory_repository.dart';
import '../data/sqlite_local_app_settings_repository.dart';
import '../data/sqlite_recipe_activity_repository.dart';
import '../data/sqlite_recipe_repository.dart';
import '../domain/access/app_access_repository.dart';
import '../domain/access/onboarding_state.dart';
import '../domain/access/app_capability.dart';
import '../domain/activity/recipe_activity.dart';
import '../domain/backup/backup_import_repository.dart';
import '../domain/backup/backup_repository.dart';
import '../domain/cooking/cooking_session.dart';
import '../domain/importing/import_content_adapter.dart';
import '../domain/importing/import_task.dart';
import '../domain/importing/import_task_repository.dart';
import '../domain/inventory/inventory_repository.dart';
import '../domain/ocr/ocr_model_manifest.dart';
import '../domain/ocr/ocr_model_package.dart';
import '../domain/ocr/ocr_provider.dart';
import '../domain/ocr/ocr_remote_image_stager.dart';
import '../domain/recipe/recipe_repository.dart';
import '../domain/recipe/recipe_cover_image_storer.dart';
import '../domain/settings/local_app_settings.dart';
import '../providers/importing/webview_content_fetcher.dart';
import '../providers/importing/webview_import_content_adapter.dart';
import '../providers/llm/llm_provider_factory.dart';
import '../providers/llm/multimodal_llm_provider_impls.dart';
import '../providers/ocr/http_ocr_model_download_client.dart';
import '../providers/ocr/platform_ocr_provider.dart';
import '../providers/ocr/platform_ocr_runtime_bridge.dart';
import '../providers/ocr/platform_ocr_storage_capacity_provider.dart';
import '../providers/ocr/remote_staging_ocr_provider.dart';
import '../providers/ocr/secure_remote_ocr_image_stager.dart';

class AiRecipeBackendCompositionRoot {
  AiRecipeBackendCompositionRoot._({
    required this.backend,
    required AppDatabase? database,
  }) : _database = database;

  factory AiRecipeBackendCompositionRoot.device({
    AppDatabase? database,
    RecipeRepository? recipeRepository,
    RecipeCategoryRepository? recipeCategoryRepository,
    ImportTaskRepository? importTaskRepository,
    RecipeActivityRepository? recipeActivityRepository,
    LocalAppSettingsRepository? localAppSettingsRepository,
    CookingRepository? cookingRepository,
    InventoryRepository? inventoryRepository,
    AppSessionRepository? sessionRepository,
    OnboardingRepository? onboardingRepository,
    LlmConfigRepository? llmConfigRepository,
    LlmConfigRepository? multimodalConfigRepository,
    MultimodalLlmProviderFactory? multimodalProviderFactory,
    AppCapabilityRuntimeRepository? capabilityRuntimeRepository,
    ImportContentAdapterRegistry? adapterRegistry,
    BackupSnapshotRepository? backupSnapshotRepository,
    BackupArchiveWriter? backupArchiveWriter,
    Future<String> Function()? backupOutputDirectoryProvider,
    BackupArchiveReader? backupArchiveReader,
    BackupImportPreflightRepository? backupImportPreflightRepository,
    BackupImportCommitRepository? backupImportCommitRepository,
    BackupImportMediaWriter? backupImportMediaWriter,
    Future<String> Function()? backupImportStagingDirectoryProvider,
    WebViewContentFetcher? webViewContentFetcher,
    LlmProviderFactory? llmProviderFactory,
    ImportTaskRunnerFactory? runnerFactory,
    ImportLlmProcessorBuilder? managedLlmBuilder,
    OcrProviderBuilder? localOcrBuilder,
    OcrProviderBuilder? cloudOcrBuilder,
    OcrRemoteImageStager? remoteOcrImageStager,
    RecipeCoverImageStorer? coverImageStorer,
    OcrModelPackageService? localOcrModelPackageService,
    OcrRuntimeBridge? localOcrRuntimeBridge,
    OcrModelDownloadClient? ocrModelDownloadClient,
    OcrModelStorageCapacityProvider? ocrModelStorageCapacityProvider,
    OcrRuntimePlatform? currentOcrPlatform,
    Set<String> trustedOcrModelHosts = const <String>{},
    String localOcrPackageId = 'paddleocr-ppocrv5-mobile-zh',
    String appVersion = '1.0.0',
    AsrProviderBuilder? managedAsrBuilder,
    String Function()? idGenerator,
    DateTime Function()? clock,
    RecommendationExecutor? recommendationExecutor,
  }) {
    final resolvedClock = clock ?? DateTime.now;
    final localIdGenerator = _LocalBackendIdGenerator(resolvedClock);
    final resolvedIdGenerator = idGenerator ?? localIdGenerator.next;

    AppDatabase? ownedDatabase = database;
    final needsSqliteRecipeRepository = recipeRepository == null;
    final needsSqliteCategoryRepository = recipeCategoryRepository == null;
    final needsSqliteImportRepository = importTaskRepository == null;
    final needsSqliteActivityRepository = recipeActivityRepository == null;
    final needsSqliteSettingsRepository = localAppSettingsRepository == null;
    final needsSqliteCookingRepository = cookingRepository == null;
    final needsSqliteInventoryRepository = inventoryRepository == null;
    final needsSqliteBackupSnapshotRepository = backupSnapshotRepository == null;
    final needsSqliteBackupImportRepository =
        backupImportPreflightRepository == null ||
        backupImportCommitRepository == null;
    if (needsSqliteRecipeRepository ||
        needsSqliteCategoryRepository ||
        needsSqliteImportRepository ||
        needsSqliteActivityRepository ||
        needsSqliteSettingsRepository ||
        needsSqliteCookingRepository ||
        needsSqliteInventoryRepository ||
        needsSqliteBackupSnapshotRepository ||
        needsSqliteBackupImportRepository) {
      ownedDatabase ??= AppDatabase();
    }

    final sqliteRecipeRepository =
        needsSqliteRecipeRepository || needsSqliteCategoryRepository
        ? SqliteRecipeRepository(ownedDatabase!)
        : null;
    final resolvedRecipeRepository =
        recipeRepository ?? sqliteRecipeRepository!;
    final resolvedCategoryRepository =
        recipeCategoryRepository ?? sqliteRecipeRepository!;
    final resolvedImportTaskRepository =
        importTaskRepository ?? SqliteImportTaskRepository(ownedDatabase!);
    final resolvedActivityRepository =
        recipeActivityRepository ??
        SqliteRecipeActivityRepository(ownedDatabase!);
    final resolvedSettingsRepository =
        localAppSettingsRepository ??
        SqliteLocalAppSettingsRepository(ownedDatabase!);
    final resolvedCookingRepository =
        cookingRepository ?? SqliteCookingRepository(ownedDatabase!);
    final resolvedInventoryRepository =
        inventoryRepository ?? SqliteInventoryRepository(ownedDatabase!);
    // 备份导出（BACKUP-003）：SQLite 快照 + 设备归档写入器，输出目录
    // 默认应用文档目录下的 backups/（导入/导出共用）。
    final resolvedBackupSnapshotRepository =
        backupSnapshotRepository ??
        SqliteBackupSnapshotRepository(ownedDatabase!);
    final resolvedBackupArchiveWriter =
        backupArchiveWriter ?? DeviceBackupArchiveWriter();
    final resolvedBackupUseCases = BackupExportUseCases(
      snapshotRepository: resolvedBackupSnapshotRepository,
      archiveWriter: resolvedBackupArchiveWriter,
      outputDirectoryProvider:
          backupOutputDirectoryProvider ?? _defaultBackupOutputDirectory,
      clock: resolvedClock,
      appVersion: appVersion,
    );
    // 备份导入（BACKUP-004/005）：ZIP 安全读取 + SQLite 目标仓库 + 媒体
    // 落盘，staging 默认应用文档目录下的 backup-import/（瞬时数据）。
    final resolvedBackupImportUseCases = BackupImportUseCases(
      archiveReader: backupArchiveReader ?? DeviceBackupArchiveReader(),
      preflightRepository:
          backupImportPreflightRepository ??
          SqliteBackupImportRepository(ownedDatabase!),
      commitRepository:
          backupImportCommitRepository ??
          SqliteBackupImportRepository(ownedDatabase!),
      mediaWriter:
          backupImportMediaWriter ?? DeviceBackupImportMediaWriter(),
      exportUseCases: resolvedBackupUseCases,
      stagingDirectoryProvider:
          backupImportStagingDirectoryProvider ??
          _defaultBackupImportStagingDirectory,
      idGenerator: resolvedIdGenerator,
    );
    final resolvedSessionRepository =
        sessionRepository ?? DeviceAppSessionRepository();
    final resolvedOnboardingRepository =
        onboardingRepository ?? DeviceOnboardingRepository();
    final resolvedLlmConfigRepository =
        llmConfigRepository ?? DeviceLlmConfigRepository();
    final resolvedLlmProviderFactory =
        llmProviderFactory ?? const LlmProviderFactory();
    // 图片识别 LLM（识图引擎，IMAGE-001）：独立配置仓库与 Provider 工厂。
    final resolvedMultimodalConfigRepository =
        multimodalConfigRepository ?? DeviceMultimodalLlmConfigRepository();
    final resolvedMultimodalProviderFactory =
        multimodalProviderFactory ?? const MultimodalLlmProviderFactory();
    final resolvedLocalOcrRuntimeBridge =
        localOcrRuntimeBridge ?? PlatformOcrRuntimeBridge();
    final resolvedLocalOcrModelPackageService =
        localOcrModelPackageService ??
        DeviceOcrModelPackageService(
          downloadClient:
              ocrModelDownloadClient ?? HttpOcrModelDownloadClient(),
          trustedHosts: trustedOcrModelHosts,
          currentPlatform: currentOcrPlatform ?? _currentOcrRuntimePlatform(),
          appVersion: appVersion,
          healthCheck: resolvedLocalOcrRuntimeBridge.healthCheck,
          storageCapacityProvider:
              ocrModelStorageCapacityProvider ??
              PlatformOcrStorageCapacityProvider().availableBytes,
        );
    final baseLocalOcrBuilder =
        localOcrBuilder ??
        () async => PlatformOcrProvider(
          packageService: resolvedLocalOcrModelPackageService,
          runtimeBridge: resolvedLocalOcrRuntimeBridge,
          packageId: localOcrPackageId,
        );
    final resolvedRemoteOcrImageStager =
        remoteOcrImageStager ?? SecureRemoteOcrImageStager();
    Future<OcrProvider> resolvedLocalOcrBuilder() async =>
        RemoteStagingOcrProvider(
          inner: await baseLocalOcrBuilder(),
          stager: resolvedRemoteOcrImageStager,
        );
    final resolvedCapabilityRuntimeRepository =
        capabilityRuntimeRepository ??
        DeviceAppCapabilityRuntimeRepository(
          llmConfigRepository: resolvedLlmConfigRepository,
          readinessLoaders: <AppCapability, CapabilityReadinessLoader>{
            AppCapability.localOcr: () async {
              final active = await resolvedLocalOcrModelPackageService
                  .getActivePackage(localOcrPackageId);
              if (active == null) return CapabilityReadiness.notInstalled;
              final probe = await resolvedLocalOcrRuntimeBridge.probe();
              return probe.runtimeAvailable && probe.recognitionSupported
                  ? CapabilityReadiness.ready
                  : CapabilityReadiness.unavailable;
            },
            // 多模态 LLM 就绪 = 已保存配置且已保存 API Key（识图引擎，IMAGE-001）。
            AppCapability.multimodalLlm: () async {
              final config = await resolvedMultimodalConfigRepository.load();
              if (config == null) return CapabilityReadiness.notConfigured;
              final apiKey = await resolvedMultimodalConfigRepository
                  .readApiKey(config.secretRef);
              return apiKey.trim().isEmpty
                  ? CapabilityReadiness.notConfigured
                  : CapabilityReadiness.ready;
            },
          },
        );

    final access = AppAccessUseCases(
      sessionRepository: resolvedSessionRepository,
      capabilityRuntimeRepository: resolvedCapabilityRuntimeRepository,
      clock: resolvedClock,
    );
    final recipes = RecipeLibraryUseCases(
      recipeRepository: resolvedRecipeRepository,
      categoryRepository: resolvedCategoryRepository,
      idGenerator: resolvedIdGenerator,
      clock: resolvedClock,
    );

    final discardRecipeDraft = SafeImportRecipeDraftDiscarder(
      resolvedRecipeRepository,
      coverImageStorer: coverImageStorer ?? DeviceRecipeCoverImageStager(),
    ).discard;
    final resolvedAdapterRegistry =
        adapterRegistry ??
        _buildPublicAdapterRegistry(
          webViewContentFetcher ?? MethodChannelWebViewContentFetcher(),
          resolvedClock,
        );
    final resolvedRunnerFactory =
        runnerFactory ??
        DeviceImportTaskRunnerFactory(
          importTaskRepository: resolvedImportTaskRepository,
          recipeRepository: resolvedRecipeRepository,
          discardRecipeDraft: discardRecipeDraft,
          adapterRegistry: resolvedAdapterRegistry,
          llmConfigRepository: resolvedLlmConfigRepository,
          llmProviderFactory: resolvedLlmProviderFactory,
          idGenerator: resolvedIdGenerator,
          clock: resolvedClock,
          managedLlmBuilder: managedLlmBuilder,
          localOcrBuilder: resolvedLocalOcrBuilder,
          cloudOcrBuilder: cloudOcrBuilder,
          managedAsrBuilder: managedAsrBuilder,
          // 链接导入把公开内容配图下载到菜谱私有封面目录（IMPORT-006）。
          coverImageStorer: coverImageStorer ?? DeviceRecipeCoverImageStager(),
          remoteCoverImageStager: resolvedRemoteOcrImageStager,
          // 多模态 LLM 图片识别（识图引擎，IMAGE-001）。
          multimodalConfigRepository: resolvedMultimodalConfigRepository,
          multimodalProviderFactory: resolvedMultimodalProviderFactory,
        );

    final backend = AiRecipeBackendFacade(
      access: access,
      onboarding: OnboardingUseCases(repository: resolvedOnboardingRepository),
      recipes: recipes,
      llmSettings: LlmSettingsUseCases(
        repository: resolvedLlmConfigRepository,
        providerBuilder: resolvedLlmProviderFactory.create,
        idGenerator: resolvedIdGenerator,
      ),
      // 图片识别 LLM（识图引擎，IMAGE-001）：独立配置，复用同一用例流程。
      multimodalSettings: LlmSettingsUseCases(
        repository: resolvedMultimodalConfigRepository,
        providerBuilder: resolvedMultimodalProviderFactory.create,
        idGenerator: resolvedIdGenerator,
      ),
      multimodalConfigRepository: resolvedMultimodalConfigRepository,
      multimodalProviderFactory: resolvedMultimodalProviderFactory,
      home: HomeUseCases(
        recipes: recipes,
        activityRepository: resolvedActivityRepository,
        importTaskRepository: resolvedImportTaskRepository,
      ),
      recipeDetails: RecipeDetailUseCases(
        recipes: recipes,
        activityRepository: resolvedActivityRepository,
        settingsRepository: resolvedSettingsRepository,
        importTaskRepository: resolvedImportTaskRepository,
        clock: resolvedClock,
      ),
      localSettings: LocalAppSettingsUseCases(
        repository: resolvedSettingsRepository,
        activityRepository: resolvedActivityRepository,
        clock: resolvedClock,
      ),
      cooking: CookingUseCases(
        repository: resolvedCookingRepository,
        recipes: recipes,
        idGenerator: resolvedIdGenerator,
        clock: resolvedClock,
      ),
      inventory: InventoryLibraryUseCases(
        repository: resolvedInventoryRepository,
        idGenerator: resolvedIdGenerator,
        clock: resolvedClock,
      ),
      importTaskRepository: resolvedImportTaskRepository,
      runnerFactory: resolvedRunnerFactory,
      discardRecipeDraft: discardRecipeDraft,
      importTaskIdGenerator: resolvedIdGenerator,
      clock: resolvedClock,
      localOcrModels: LocalOcrModelUseCases(
        packageService: resolvedLocalOcrModelPackageService,
      ),
      localOcrProviderBuilder: resolvedLocalOcrBuilder,
      // 推荐匹配计算：生产默认后台 Isolate；测试注入直算执行器。
      recommendationExecutor:
          recommendationExecutor ?? const IsolateRecommendationExecutor(),
      // 菜谱备份导出（BACKUP-003）。
      backup: resolvedBackupUseCases,
      // 菜谱备份导入（BACKUP-004/005）。
      backupImport: resolvedBackupImportUseCases,
    );

    return AiRecipeBackendCompositionRoot._(
      backend: backend,
      database: ownedDatabase,
    );
  }

  final AiRecipeBackendFacade backend;
  final AppDatabase? _database;
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _database?.close();
  }

  static OcrRuntimePlatform _currentOcrRuntimePlatform() {
    return Platform.isIOS ? OcrRuntimePlatform.ios : OcrRuntimePlatform.android;
  }

  /// 备份文件默认输出目录：应用文档目录下的 backups/（导入/导出共用）。
  static Future<String> _defaultBackupOutputDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, 'backups');
  }

  /// 导入 staging 默认根目录：应用文档目录下的 backup-import/（瞬时数据，
  /// 应用启动时由用例清理遗留会话目录）。
  static Future<String> _defaultBackupImportStagingDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return p.join(documents.path, 'backup-import');
  }

  static ImportContentAdapterRegistry _buildPublicAdapterRegistry(
    WebViewContentFetcher fetcher,
    DateTime Function() clock,
  ) {
    // IMPORT-008：链接导入改用浏览器内核（WebView）抓取，任意网页通用；
    // 小红书/抖音/未知域名分别注册同一抓取实现的适配器实例。
    return ImportContentAdapterRegistry(<ImportContentAdapter>[
      WebViewImportContentAdapter(
        fetcher: fetcher,
        platform: ImportSourcePlatform.xiaohongshu,
        clock: clock,
      ),
      WebViewImportContentAdapter(
        fetcher: fetcher,
        platform: ImportSourcePlatform.douyin,
        clock: clock,
      ),
      WebViewImportContentAdapter(
        fetcher: fetcher,
        platform: ImportSourcePlatform.web,
        clock: clock,
      ),
    ]);
  }
}

class _LocalBackendIdGenerator {
  _LocalBackendIdGenerator(this._clock);

  final DateTime Function() _clock;
  int _counter = 0;

  String next() {
    _counter += 1;
    final timestamp = _clock().toUtc().microsecondsSinceEpoch;
    return 'local-$timestamp-$_counter';
  }
}
