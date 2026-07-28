import '../application/access/app_access_use_cases.dart';
import '../application/backend/ai_recipe_backend_facade.dart';
import '../application/backend/import_task_runner_factory.dart';
import '../application/recipe/recipe_library_use_cases.dart';
import '../data/device_app_capability_runtime_repository.dart';
import '../data/device_app_session_repository.dart';
import '../data/device_import_task_runner_factory.dart';
import '../data/llm_config_repository.dart';
import '../data/local/app_database.dart';
import '../data/sqlite_import_task_repository.dart';
import '../data/sqlite_recipe_repository.dart';
import '../domain/access/app_access_repository.dart';
import '../domain/importing/import_content_adapter.dart';
import '../domain/importing/import_task_repository.dart';
import '../domain/recipe/recipe_repository.dart';
import '../providers/importing/http_import_transport.dart';
import '../providers/importing/import_http_transport.dart';
import '../providers/importing/public_content_adapters.dart';
import '../providers/llm/llm_provider_factory.dart';

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
    AppSessionRepository? sessionRepository,
    LlmConfigRepository? llmConfigRepository,
    AppCapabilityRuntimeRepository? capabilityRuntimeRepository,
    ImportHttpTransport? importTransport,
    ImportContentAdapterRegistry? adapterRegistry,
    LlmProviderFactory? llmProviderFactory,
    ImportTaskRunnerFactory? runnerFactory,
    ImportLlmProcessorBuilder? managedLlmBuilder,
    OcrProviderBuilder? localOcrBuilder,
    OcrProviderBuilder? cloudOcrBuilder,
    AsrProviderBuilder? managedAsrBuilder,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) {
    final resolvedClock = clock ?? DateTime.now;
    final localIdGenerator = _LocalBackendIdGenerator(resolvedClock);
    final resolvedIdGenerator = idGenerator ?? localIdGenerator.next;

    AppDatabase? ownedDatabase = database;
    final needsSqliteRecipeRepository = recipeRepository == null;
    final needsSqliteCategoryRepository = recipeCategoryRepository == null;
    final needsSqliteImportRepository = importTaskRepository == null;
    if (needsSqliteRecipeRepository ||
        needsSqliteCategoryRepository ||
        needsSqliteImportRepository) {
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
    final resolvedSessionRepository =
        sessionRepository ?? DeviceAppSessionRepository();
    final resolvedLlmConfigRepository =
        llmConfigRepository ?? DeviceLlmConfigRepository();
    final resolvedCapabilityRuntimeRepository =
        capabilityRuntimeRepository ??
        DeviceAppCapabilityRuntimeRepository(
          llmConfigRepository: resolvedLlmConfigRepository,
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

    final resolvedAdapterRegistry =
        adapterRegistry ??
        _buildPublicAdapterRegistry(
          importTransport ?? HttpImportTransport(),
          resolvedClock,
        );
    final resolvedRunnerFactory =
        runnerFactory ??
        DeviceImportTaskRunnerFactory(
          importTaskRepository: resolvedImportTaskRepository,
          recipeRepository: resolvedRecipeRepository,
          adapterRegistry: resolvedAdapterRegistry,
          llmConfigRepository: resolvedLlmConfigRepository,
          llmProviderFactory: llmProviderFactory ?? const LlmProviderFactory(),
          idGenerator: resolvedIdGenerator,
          clock: resolvedClock,
          managedLlmBuilder: managedLlmBuilder,
          localOcrBuilder: localOcrBuilder,
          cloudOcrBuilder: cloudOcrBuilder,
          managedAsrBuilder: managedAsrBuilder,
        );

    final backend = AiRecipeBackendFacade(
      access: access,
      recipes: recipes,
      importTaskRepository: resolvedImportTaskRepository,
      runnerFactory: resolvedRunnerFactory,
      importTaskIdGenerator: resolvedIdGenerator,
      clock: resolvedClock,
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

  static ImportContentAdapterRegistry _buildPublicAdapterRegistry(
    ImportHttpTransport transport,
    DateTime Function() clock,
  ) {
    return ImportContentAdapterRegistry(<ImportContentAdapter>[
      XiaohongshuPublicContentAdapter(transport: transport, clock: clock),
      DouyinPublicContentAdapter(transport: transport, clock: clock),
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
