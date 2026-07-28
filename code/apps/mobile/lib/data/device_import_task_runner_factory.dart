import '../application/backend/import_execution_plan.dart';
import '../application/backend/import_task_runner_factory.dart';
import '../application/importing/asr_enriching_import_content_processor.dart';
import '../application/importing/import_pipeline_contracts.dart';
import '../application/importing/import_task_runner.dart';
import '../application/importing/import_task_use_cases.dart';
import '../application/importing/llm_recipe_generation_processor.dart';
import '../application/importing/ocr_enriching_import_content_processor.dart';
import '../domain/asr/asr_provider.dart';
import '../domain/importing/import_content_adapter.dart';
import '../domain/importing/import_task_repository.dart';
import '../domain/ocr/ocr_provider.dart';
import '../domain/recipe/recipe_repository.dart';
import '../providers/llm/llm_provider_factory.dart';
import 'llm_config_repository.dart';

typedef ImportLlmProcessorBuilder =
    Future<ImportContentProcessor> Function(String? userId);
typedef OcrProviderBuilder = Future<OcrProvider> Function();
typedef AsrProviderBuilder = Future<AsrProvider> Function();

class DeviceImportTaskRunnerFactory implements ImportTaskRunnerFactory {
  DeviceImportTaskRunnerFactory({
    required ImportTaskRepository importTaskRepository,
    required RecipeRepository recipeRepository,
    required ImportContentAdapterRegistry adapterRegistry,
    required LlmConfigRepository llmConfigRepository,
    required LlmProviderFactory llmProviderFactory,
    required RecipeDraftIdGenerator idGenerator,
    required ImportTaskClock clock,
    ImportLlmProcessorBuilder? managedLlmBuilder,
    OcrProviderBuilder? localOcrBuilder,
    OcrProviderBuilder? cloudOcrBuilder,
    AsrProviderBuilder? managedAsrBuilder,
  }) : _importTaskRepository = importTaskRepository,
       _recipeRepository = recipeRepository,
       _adapterRegistry = adapterRegistry,
       _llmConfigRepository = llmConfigRepository,
       _llmProviderFactory = llmProviderFactory,
       _idGenerator = idGenerator,
       _clock = clock,
       _managedLlmBuilder = managedLlmBuilder,
       _localOcrBuilder = localOcrBuilder,
       _cloudOcrBuilder = cloudOcrBuilder,
       _managedAsrBuilder = managedAsrBuilder;

  final ImportTaskRepository _importTaskRepository;
  final RecipeRepository _recipeRepository;
  final ImportContentAdapterRegistry _adapterRegistry;
  final LlmConfigRepository _llmConfigRepository;
  final LlmProviderFactory _llmProviderFactory;
  final RecipeDraftIdGenerator _idGenerator;
  final ImportTaskClock _clock;
  final ImportLlmProcessorBuilder? _managedLlmBuilder;
  final OcrProviderBuilder? _localOcrBuilder;
  final OcrProviderBuilder? _cloudOcrBuilder;
  final AsrProviderBuilder? _managedAsrBuilder;

  @override
  Future<ImportTaskRunner> create(
    ImportExecutionPlan plan, {
    String? userId,
  }) async {
    var processor = await _createLlmProcessor(plan.llm, userId);

    if (plan.asr == ImportAsrRoute.managed) {
      final provider = await _buildAsrProvider(_managedAsrBuilder, '托管 ASR');
      processor = AsrEnrichingImportContentProcessor(
        provider: provider,
        downstream: processor,
      );
    }

    if (plan.ocr != ImportOcrRoute.disabled) {
      final provider = switch (plan.ocr) {
        ImportOcrRoute.local => await _buildOcrProvider(
          _localOcrBuilder,
          '本地 OCR',
        ),
        ImportOcrRoute.cloud => await _buildOcrProvider(
          _cloudOcrBuilder,
          '云 OCR',
        ),
        ImportOcrRoute.disabled => throw StateError('unreachable'),
      };
      processor = OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: processor,
      );
    }

    return ImportTaskRunner(
      repository: _importTaskRepository,
      adapterRegistry: _adapterRegistry,
      processor: processor,
      clock: _clock,
    );
  }

  Future<ImportContentProcessor> _createLlmProcessor(
    ImportLlmRoute route,
    String? userId,
  ) async {
    if (route == ImportLlmRoute.managed) {
      final builder = _managedLlmBuilder;
      if (builder == null) {
        throw const ImportTaskRunnerFactoryException(
          code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
          message: '托管 AI 服务尚未接入。',
        );
      }
      try {
        return await builder(_normalizeUserId(userId));
      } catch (error) {
        if (error is ImportTaskRunnerFactoryException) rethrow;
        throw const ImportTaskRunnerFactoryException(
          code: ImportTaskRunnerFactoryErrorCode.providerUnavailable,
          message: '托管 AI 服务暂时不可用。',
        );
      }
    }

    try {
      final config = await _llmConfigRepository.load();
      if (config == null) {
        throw const ImportTaskRunnerFactoryException(
          code: ImportTaskRunnerFactoryErrorCode.configurationUnavailable,
          message: '请先配置 AI API 地址、模型和密钥。',
        );
      }
      final apiKey = await _llmConfigRepository.readApiKey(config.secretRef);
      if (apiKey.trim().isEmpty) {
        throw const ImportTaskRunnerFactoryException(
          code: ImportTaskRunnerFactoryErrorCode.configurationUnavailable,
          message: '请先配置 AI API 密钥。',
        );
      }
      return LlmRecipeGenerationProcessor(
        provider: _llmProviderFactory.create(config.providerType),
        config: config,
        apiKey: apiKey,
        recipeRepository: _recipeRepository,
        idGenerator: _idGenerator,
        clock: _clock,
        userId: _normalizeUserId(userId),
      );
    } on ImportTaskRunnerFactoryException {
      rethrow;
    } catch (_) {
      throw const ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.configurationUnavailable,
        message: 'AI 服务配置暂时不可用。',
      );
    }
  }

  static Future<OcrProvider> _buildOcrProvider(
    OcrProviderBuilder? builder,
    String routeName,
  ) async {
    if (builder == null) {
      throw ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
        message: '$routeName 尚未安装或接入。',
      );
    }
    try {
      return await builder();
    } catch (_) {
      throw ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.providerUnavailable,
        message: '$routeName 暂时不可用。',
      );
    }
  }

  static Future<AsrProvider> _buildAsrProvider(
    AsrProviderBuilder? builder,
    String routeName,
  ) async {
    if (builder == null) {
      throw ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
        message: '$routeName 尚未接入。',
      );
    }
    try {
      return await builder();
    } catch (_) {
      throw ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.providerUnavailable,
        message: '$routeName 暂时不可用。',
      );
    }
  }

  static String? _normalizeUserId(String? userId) {
    final normalized = userId?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
