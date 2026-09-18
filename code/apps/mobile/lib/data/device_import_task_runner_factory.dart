import '../application/backend/import_execution_plan.dart';
import '../application/backend/import_task_runner_factory.dart';
import '../application/importing/asr_enriching_import_content_processor.dart';
import '../application/importing/import_pipeline_contracts.dart';
import '../application/importing/import_task_runner.dart';
import '../application/importing/import_task_use_cases.dart';
import '../application/importing/llm_recipe_generation_processor.dart';
import '../application/importing/multimodal_image_enriching_import_content_processor.dart';
import '../application/importing/ocr_enriching_import_content_processor.dart';
import '../application/importing/multi_image_draft_split_processor.dart';
import '../application/importing/vision_fusion_import_content_processor.dart';
import '../domain/asr/asr_provider.dart';
import '../domain/importing/import_cancellation_token.dart';
import '../domain/importing/import_content.dart';
import '../domain/importing/import_content_adapter.dart';
import '../domain/importing/import_task_repository.dart';
import '../domain/llm/llm_connection_config.dart';
import '../domain/ocr/ocr_provider.dart';
import '../domain/ocr/ocr_remote_image_stager.dart';
import '../domain/recipe/recipe_cover_image_storer.dart';
import '../domain/recipe/recipe_repository.dart';
import '../providers/llm/llm_provider_factory.dart';
import '../providers/llm/multimodal_llm_provider_impls.dart';
import '../providers/ocr/secure_remote_ocr_image_stager.dart';
import '../providers/ocr/task_scoped_image_cache.dart';
import 'llm_config_repository.dart';

typedef ImportLlmProcessorBuilder =
    Future<ImportContentProcessor> Function(String? userId);
typedef OcrProviderBuilder = Future<OcrProvider> Function();
typedef AsrProviderBuilder = Future<AsrProvider> Function();

class DeviceImportTaskRunnerFactory implements ImportTaskRunnerFactory {
  DeviceImportTaskRunnerFactory({
    required ImportTaskRepository importTaskRepository,
    required RecipeRepository recipeRepository,
    required ImportRecipeDraftDiscarder discardRecipeDraft,
    required ImportContentAdapterRegistry adapterRegistry,
    required LlmConfigRepository llmConfigRepository,
    required LlmProviderFactory llmProviderFactory,
    required RecipeDraftIdGenerator idGenerator,
    required ImportTaskClock clock,
    ImportLlmProcessorBuilder? managedLlmBuilder,
    OcrProviderBuilder? localOcrBuilder,
    OcrProviderBuilder? cloudOcrBuilder,
    AsrProviderBuilder? managedAsrBuilder,
    RecipeCoverImageStorer? coverImageStorer,
    OcrRemoteImageStager? remoteCoverImageStager,
    LlmConfigRepository? multimodalConfigRepository,
    MultimodalLlmProviderFactory? multimodalProviderFactory,
  }) : _importTaskRepository = importTaskRepository,
       _recipeRepository = recipeRepository,
       _discardRecipeDraft = discardRecipeDraft,
       _adapterRegistry = adapterRegistry,
       _llmConfigRepository = llmConfigRepository,
       _llmProviderFactory = llmProviderFactory,
       _idGenerator = idGenerator,
       _clock = clock,
       _managedLlmBuilder = managedLlmBuilder,
       _localOcrBuilder = localOcrBuilder,
       _cloudOcrBuilder = cloudOcrBuilder,
       _managedAsrBuilder = managedAsrBuilder,
       _coverImageStorer = coverImageStorer,
       _remoteCoverImageStager = remoteCoverImageStager,
       _multimodalConfigRepository = multimodalConfigRepository,
       _multimodalProviderFactory = multimodalProviderFactory;

  final ImportTaskRepository _importTaskRepository;
  final RecipeRepository _recipeRepository;
  final ImportRecipeDraftDiscarder _discardRecipeDraft;
  final ImportContentAdapterRegistry _adapterRegistry;
  final LlmConfigRepository _llmConfigRepository;
  final LlmProviderFactory _llmProviderFactory;
  final RecipeDraftIdGenerator _idGenerator;
  final ImportTaskClock _clock;
  final ImportLlmProcessorBuilder? _managedLlmBuilder;
  final OcrProviderBuilder? _localOcrBuilder;
  final OcrProviderBuilder? _cloudOcrBuilder;
  final AsrProviderBuilder? _managedAsrBuilder;
  final RecipeCoverImageStorer? _coverImageStorer;
  final OcrRemoteImageStager? _remoteCoverImageStager;

  /// 多模态 LLM（识图引擎，IMAGE-001）配置仓库与 Provider 工厂。
  final LlmConfigRepository? _multimodalConfigRepository;
  final MultimodalLlmProviderFactory? _multimodalProviderFactory;

  @override
  Future<ImportTaskRunner> create(
    ImportExecutionPlan plan, {
    String? userId,
  }) async {
    // 任务级图片缓存（P0-1）：识别与封面保存共用同一份下载文件，避免重复
    // 下载同一远程图片。缓存包装底层安全暂存器，处理器链结束后统一释放。
    final imageCache = TaskScopedImageCache(
      _remoteCoverImageStager ?? SecureRemoteOcrImageStager(),
    );

    var processor = await _createLlmProcessor(
      plan.llm,
      userId,
      remoteCoverImageStager: imageCache,
    );

    if (plan.asr == ImportAsrRoute.managed) {
      final provider = await _buildAsrProvider(_managedAsrBuilder, '托管 ASR');
      processor = AsrEnrichingImportContentProcessor(
        provider: provider,
        downstream: processor,
      );
    }

    if (plan.imageRecognition == ImportImageRecognitionRoute.ocr) {
      final provider = await _buildOcrProvider(_localOcrBuilder, '本地 OCR');
      processor = OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: processor,
      );
    } else if (plan.imageRecognition ==
        ImportImageRecognitionRoute.multimodal) {
      // 组装顺序必须为：多模态转录 → 分组判断（多图独立/合成）→ 结构化生成。
      // 先包分组（grouping -> LLM），再包多模态转录（multimodal -> grouping）；
      // 否则分组判断在多模态之前执行，看不到任何转录片段（图组数恒为 0），
      // 永远只会产出单草稿（IMAGE-002 修复）。
      processor = await _wrapMultiImageGrouping(processor);
      processor = await _buildMultimodalProcessor(
        processor,
        imageCache: imageCache,
      );
    } else if (plan.imageRecognition ==
        ImportImageRecognitionRoute.ocrAndMultimodal) {
      // 自动融合（BUG-006，ADR-0028）：OCR 与多模态独立执行、部分成功；
      // 分组判断同样位于转录之后（IMAGE-002）。
      final ocrProvider = await _buildOcrProvider(_localOcrBuilder, '本地 OCR');
      processor = await _wrapMultiImageGrouping(processor);
      processor = await _buildMultimodalProcessor(
        processor,
        fusionOcrProvider: ocrProvider,
        imageCache: imageCache,
      );
    }

    return ImportTaskRunner(
      repository: _importTaskRepository,
      adapterRegistry: _adapterRegistry,
      // 包装处理器链：任务执行结束（成功或失败）后释放任务级图片缓存。
      processor: _releaseCacheAfter(processor, imageCache),
      discardRecipeDraft: _discardRecipeDraft,
      clock: _clock,
    );
  }

  /// 组装多模态 LLM 图片识别处理器：读取独立配置与 API Key，创建 Provider。
  ///
  /// [fusionOcrProvider] 非空时组装 [VisionFusionImportContentProcessor]
  /// （OCR 与多模态独立执行、部分成功，ADR-0028）；否则使用原有的
  /// [MultimodalImageEnrichingImportContentProcessor]（仅多模态一路）。
  Future<ImportContentProcessor> _buildMultimodalProcessor(
    ImportContentProcessor downstream, {
    OcrProvider? fusionOcrProvider,
    TaskScopedImageCache? imageCache,
  }) async {
    final configRepository = _multimodalConfigRepository;
    final providerFactory = _multimodalProviderFactory;
    if (configRepository == null || providerFactory == null) {
      throw const ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
        message: '图片识别 LLM 尚未接入。',
      );
    }
    final LlmConnectionConfig config;
    try {
      final loaded = await configRepository.load();
      if (loaded == null) {
        throw const ImportTaskRunnerFactoryException(
          code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
          message: '请先在识图引擎中配置图片识别 LLM。',
        );
      }
      config = loaded;
    } catch (error) {
      if (error is ImportTaskRunnerFactoryException) rethrow;
      throw const ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.providerUnavailable,
        message: '图片识别 LLM 配置暂时无法读取。',
      );
    }
    final apiKey = await configRepository.readApiKey(config.secretRef);
    if (apiKey.trim().isEmpty) {
      throw const ImportTaskRunnerFactoryException(
        code: ImportTaskRunnerFactoryErrorCode.routeNotBound,
        message: '请先在识图引擎中配置图片识别 LLM 的 API Key。',
      );
    }
    // 识别阶段使用任务级缓存作为暂存器，与封面保存阶段共用下载文件（P0-1）。
    final stager = imageCache ?? _remoteCoverImageStager ?? SecureRemoteOcrImageStager();
    final multimodalProvider = providerFactory.create(config.providerType);
    if (fusionOcrProvider != null) {
      return VisionFusionImportContentProcessor(
        ocrProvider: fusionOcrProvider,
        multimodalProvider: multimodalProvider,
        multimodalConfig: config,
        multimodalApiKey: apiKey,
        stager: stager,
        downstream: downstream,
      );
    }
    return MultimodalImageEnrichingImportContentProcessor(
      provider: multimodalProvider,
      config: config,
      apiKey: apiKey,
      stager: stager,
      downstream: downstream,
    );
  }

  Future<ImportContentProcessor> _createLlmProcessor(
    ImportLlmRoute route,
    String? userId, {
    OcrRemoteImageStager? remoteCoverImageStager,
  }) async {
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
        // 公开内容配图下载到菜谱私有封面目录（IMPORT-006）。封面暂存器优先
        // 使用任务级缓存，与识别阶段共用同一份下载文件（P0-1）。
        coverImageStorer: _coverImageStorer,
        remoteCoverImageStager: remoteCoverImageStager ?? _remoteCoverImageStager,
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

  /// 多图分组包装（IMAGE-002，ADR-0029）。
  ///
  /// 复用菜谱生成 LLM 的配置读取，把 [MultiImageDraftSplitProcessor] 包在
  /// 多模态转录处理器之后：多张图都产出转录文字时，先做一次轻量分组判断，
  /// 再按分组拆分为多个菜谱草稿；单图/纯文本内容直接透传，无额外调用。
  Future<ImportContentProcessor> _wrapMultiImageGrouping(
    ImportContentProcessor downstream,
  ) async {
    try {
      final config = await _llmConfigRepository.load();
      if (config == null) {
        return downstream;
      }
      final apiKey = await _llmConfigRepository.readApiKey(config.secretRef);
      if (apiKey.trim().isEmpty) {
        return downstream;
      }
      return MultiImageDraftSplitProcessor(
        provider: _llmProviderFactory.create(config.providerType),
        config: config,
        apiKey: apiKey,
        downstream: downstream,
      );
    } catch (_) {
      // 分组包装不是硬依赖：配置读取失败时退化为单草稿生成。
      return downstream;
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

  /// 包装处理器链：无论导入成功还是失败，执行结束后统一释放任务级图片缓存。
  static ImportContentProcessor _releaseCacheAfter(
    ImportContentProcessor downstream,
    TaskScopedImageCache cache,
  ) {
    return _CacheReleasingProcessor(downstream, cache);
  }
}

/// 在处理器链执行结束（成功或失败）后释放任务级图片缓存的包装处理器。
class _CacheReleasingProcessor implements ImportContentProcessor {
  _CacheReleasingProcessor(this._downstream, this._cache);

  final ImportContentProcessor _downstream;
  final TaskScopedImageCache _cache;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    try {
      return await _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    } finally {
      await _cache.disposeAll();
    }
  }
}
