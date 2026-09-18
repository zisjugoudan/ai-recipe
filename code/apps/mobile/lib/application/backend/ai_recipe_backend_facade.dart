import 'dart:io';

import '../../domain/access/app_capability.dart';
import '../../domain/access/app_session.dart';
import '../../domain/access/onboarding_state.dart';
import '../../domain/cooking/cooking_session.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../domain/settings/local_app_settings.dart';
import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_fallback_input.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_diagnostic.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/llm_provider_type.dart';
import '../../domain/llm/multimodal_llm_provider.dart';
import '../../domain/ocr/ocr_model_manifest.dart';
import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_model_package_exception.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/recipe/recipe.dart';
import '../../data/recipe_cover_image_stager.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../domain/backup/backup_errors.dart';
import '../../domain/backup/backup_import_plan.dart';
import '../access/app_access_use_cases.dart';
import '../access/onboarding_use_cases.dart';
import '../backup/backup_export_use_cases.dart';
import '../backup/backup_import_use_cases.dart';
import '../cooking/cooking_use_cases.dart';
import '../home/home_use_cases.dart';
import '../importing/import_fallback_content_factory.dart';
import '../importing/import_pipeline_contracts.dart';
import '../importing/import_task_runner.dart';
import '../inventory/inventory_use_cases.dart';
import '../inventory/recommendation_executor.dart';
import '../../domain/importing/import_content.dart';
import '../importing/import_task_use_cases.dart';
import '../importing/single_import_task_dispatcher.dart';
import '../ocr/local_ocr_model_use_cases.dart';
import '../recipe/recipe_detail_use_cases.dart';
import '../recipe/recipe_library_commands.dart';
import '../recipe/recipe_library_use_cases.dart';
import '../settings/llm_settings_use_cases.dart';
import '../settings/local_app_settings_use_cases.dart';
import '../../data/llm_config_repository.dart';
import '../../providers/llm/multimodal_llm_provider_impls.dart';
import '../../providers/llm/vision_probe.dart';
import 'import_execution_plan.dart';
import 'import_task_runner_factory.dart';

enum AiRecipeBackendErrorCode {
  invalidInput,
  importTaskNotFound,
  importDraftNotFound,
  invalidTaskState,
  providerRouteUnavailable,
  storageUnavailable,
  insufficientStorage,
  operationCancelled,
  operationFailed,
  componentNotInstalled,
  componentInstallationFailed,
  componentIncompatible,
  recipeNotFound,
  categoryNotFound,
  authenticationFailed,
  rateLimited,
  timeout,
  networkUnavailable,
  providerUnavailable,
  invalidProviderResponse,
  cookingSessionNotFound,
  cookingTimerNotFound,
  backupFailed,
  backupCancelled,
}

class AiRecipeBackendException implements Exception {
  const AiRecipeBackendException({required this.code, required this.message});

  final AiRecipeBackendErrorCode code;
  final String message;

  @override
  String toString() => 'AiRecipeBackendException(${code.name}): $message';
}

class ImportDraftConfirmation {
  const ImportDraftConfirmation({required this.task, required this.recipe});

  final ImportTask task;
  final Recipe recipe;
}

/// 扣减确认中的单项消耗（FRIDGE-003）：目标批次 + 消耗数量。
class InventoryConsumptionItem {
  const InventoryConsumptionItem({
    required this.batchId,
    required this.delta,
    this.relatedRecipeId,
  });

  final String batchId;
  final double delta;
  final String? relatedRecipeId;
}

/// 本地图片/文本任务在创建时使用的占位来源 URL。
///
/// 这类任务的内容由 [AiRecipeBackendFacade.runImportWithLocalImage] /
/// [AiRecipeBackendFacade.runImportWithText] 提供，不能走公开链接抓取；
/// [AiRecipeBackendFacade.runImportTask] 遇到占位任务会拒绝并引导重新创建。
const String localImageCapturePlaceholderUrl = 'https://local-image/capture';
const String localTextCapturePlaceholderUrl = 'https://local-text/capture';

class AiRecipeBackendFacade {
  AiRecipeBackendFacade({
    required this.access,
    required this.onboarding,
    required this.recipes,
    required this.llmSettings,
    required this.home,
    required this.recipeDetails,
    required this.localSettings,
    required this.cooking,
    required ImportTaskRepository importTaskRepository,
    required ImportTaskRunnerFactory runnerFactory,
    required ImportRecipeDraftDiscarder discardRecipeDraft,
    required ImportTaskIdGenerator importTaskIdGenerator,
    required ImportTaskClock clock,
    this.inventory,
    this.localOcrModels,
    this.localOcrProviderBuilder,
    this.coverImageStager,
    this.multimodalSettings,
    this.multimodalConfigRepository,
    this.multimodalProviderFactory,
    this.recommendationExecutor = const IsolateRecommendationExecutor(),
    this.backup,
    this.backupImport,
  }) : _importTaskRepository = importTaskRepository,
       _runnerFactory = runnerFactory,
       _discardRecipeDraft = discardRecipeDraft,
       _importTaskIdGenerator = importTaskIdGenerator,
       _clock = clock;

  final AppAccessUseCases access;
  final OnboardingUseCases onboarding;
  final RecipeLibraryUseCases recipes;
  final LlmSettingsUseCases llmSettings;

  /// 图片识别 LLM（识图引擎，IMAGE-001）独立配置用例。
  final LlmSettingsUseCases? multimodalSettings;

  /// 图片识别 LLM 配置仓库与 Provider 工厂（"测试识图"直接识别本地图片用）。
  final LlmConfigRepository? multimodalConfigRepository;
  final MultimodalLlmProviderFactory? multimodalProviderFactory;
  final HomeUseCases home;
  final RecipeDetailUseCases recipeDetails;
  final LocalAppSettingsUseCases localSettings;
  final CookingUseCases cooking;
  final ImportTaskRepository _importTaskRepository;
  final ImportTaskRunnerFactory _runnerFactory;
  final ImportRecipeDraftDiscarder _discardRecipeDraft;
  final ImportTaskIdGenerator _importTaskIdGenerator;
  final ImportTaskClock _clock;

  /// 当前进程内正在实时执行的导入任务 ID 集合。
  ///
  /// 用于让"恢复遗留任务"跳过仍在后台实时运行的导入任务，避免把
  /// "解析中按返回后继续后台执行"的任务误判为中断而置为失败。
  final Set<String> _inFlightTaskIds = <String>{};
  final InventoryLibraryUseCases? inventory;
  final LocalOcrModelUseCases? localOcrModels;
  final DeviceRecipeCoverImageStager? coverImageStager;

  /// 推荐匹配计算执行器（解决方案.md 第六节：生产用后台 Isolate，
  /// 测试注入直算版本避免 FakeAsync 下 Isolate 挂起）。
  final RecommendationExecutor recommendationExecutor;

  /// 菜谱备份导出用例（BACKUP-003）。为 null 时备份功能不可用。
  final BackupExportUseCases? backup;

  /// 菜谱备份导入用例（BACKUP-004/005）。为 null 时导入功能不可用。
  final BackupImportUseCases? backupImport;

  /// 构建本地 OCR Provider 的工厂（OCR 设置页"测试 OCR"直接识别本地图片用）。
  final Future<OcrProvider> Function()? localOcrProviderBuilder;

  Future<AppSession> loadSession() => _accessOperation(access.loadSession);

  Future<OnboardingState> loadOnboardingState() =>
      _onboardingOperation(onboarding.load);

  Future<OnboardingState> completeOnboarding() =>
      _onboardingOperation(onboarding.complete);

  Future<OnboardingState> resetOnboarding() =>
      _onboardingOperation(onboarding.reset);

  Future<AppSession> returnToWelcome() async {
    await resetOnboarding();
    return signOut();
  }

  Future<AppSession> continueAsGuest() =>
      _accessOperation(access.continueAsGuest);

  Future<AppSession> acceptVerifiedSession(AuthenticatedSessionInput input) =>
      _accessOperation(() => access.acceptVerifiedSession(input));

  Future<AppSession> signOut() => _accessOperation(access.signOut);

  Future<AppCapabilitySnapshot> loadCapabilities() =>
      _accessOperation(access.loadCapabilities);

  Future<LlmSettingsSnapshot> loadLlmSettings() =>
      _llmSettingsOperation(llmSettings.loadConfiguration);

  Future<LlmSettingsSnapshot> saveLlmSettings(LlmSettingsInput input) =>
      _llmSettingsOperation(() => llmSettings.saveConfiguration(input));

  Future<void> testLlmConnection(
    LlmSettingsInput input, {
    LlmCancellationToken? cancellationToken,
  }) => _llmSettingsOperation(
    () =>
        llmSettings.testConnection(input, cancellationToken: cancellationToken),
  );

  /// 「测试结构化生成」（BUG-008 诊断辅助）：输入文本走真实结构化生成链路，
  /// 返回耗时与生成文本，用于判断"最终结构化生成超时"是否由 LLM 服务本身引起。
  Future<LlmStructuredGenerationResult> testLlmStructuredGeneration(
    LlmSettingsInput input, {
    required String sourceText,
    LlmCancellationToken? cancellationToken,
  }) => _llmSettingsOperation(
    () => llmSettings.testStructuredGeneration(
      input,
      sourceText: sourceText,
      cancellationToken: cancellationToken,
    ),
  );

  Future<LlmSettingsSnapshot> clearLlmApiKey() =>
      _llmSettingsOperation(llmSettings.clearStoredApiKey);

  // ---- 图片识别 LLM（识图引擎，IMAGE-001，独立配置）----

  Future<LlmSettingsSnapshot> loadMultimodalSettings() {
    final settings = _requireMultimodalSettings();
    return _llmSettingsOperation(settings.loadConfiguration);
  }

  Future<LlmSettingsSnapshot> saveMultimodalSettings(LlmSettingsInput input) {
    final settings = _requireMultimodalSettings();
    return _llmSettingsOperation(() => settings.saveConfiguration(input));
  }

  /// 检查基础连接（BUG-006）：只验证地址、鉴权与模型存在性，不以图片能力
  /// 为前提，也不再把等待完整响应包装成"链接超时"。
  ///
  /// 视觉专用模型明确拒绝纯文本（HTTP 400/422 且错误提示涉及图片）时返回
  /// [MultimodalDiagnosticOutcome.textCapabilityUnconfirmed] = true，表示
  /// "服务与鉴权已通过，文本能力未确认"，而不是连接失败。
  Future<MultimodalDiagnosticOutcome> checkMultimodalBaseConnection(
    LlmSettingsInput input, {
    LlmCancellationToken? cancellationToken,
  }) async {
    final configRepository = multimodalConfigRepository;
    final providerFactory = multimodalProviderFactory;
    if (configRepository == null || providerFactory == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '图片识别 LLM 尚未接入。',
      );
    }
    final (config, apiKey) = await _buildMultimodalDiagnosticContext(
      input,
      configRepository,
    );
    final provider = providerFactory.create(config.providerType);
    var report = await provider.diagnose(
      config: config,
      apiKey: apiKey,
      imageProbe: false,
      cancellationToken: cancellationToken,
    );
    // 视觉专用模型可能拒绝纯文本：400/422 且提示涉及图片时，判定为
    // "服务与鉴权已通过，文本能力未确认"，不显示为连接失败。
    if (!report.succeeded &&
        report.failureKind == LlmProviderErrorKind.badRequest &&
        _looksLikeTextRejectedByVisionModel(report.responseBody)) {
      report = _withTextCapabilityUnconfirmed(report);
    }
    return MultimodalDiagnosticOutcome(
      report: report,
      providerId: providerTypeId(config.providerType),
      modelVersion: config.model,
      textCapabilityUnconfirmed: report.succeeded &&
          report.failureKind == null &&
          !report.records.every(
            (record) => record.messageKey != 'text_capability_unconfirmed',
          ),
    );
  }

  /// 检查图片能力（BUG-006）：发送内置 256×256 标准诊断图，只有文字
  /// "AI RECIPE 314" 与红色方块两个断言同时通过才算通过。
  Future<MultimodalDiagnosticOutcome> checkMultimodalImageCapability(
    LlmSettingsInput input, {
    LlmCancellationToken? cancellationToken,
  }) async {
    final configRepository = multimodalConfigRepository;
    final providerFactory = multimodalProviderFactory;
    if (configRepository == null || providerFactory == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '图片识别 LLM 尚未接入。',
      );
    }
    final (config, apiKey) = await _buildMultimodalDiagnosticContext(
      input,
      configRepository,
    );
    final provider = providerFactory.create(config.providerType);
    final report = await provider.diagnose(
      config: config,
      apiKey: apiKey,
      imageProbe: true,
      cancellationToken: cancellationToken,
    );
    if (!report.succeeded) {
      return MultimodalDiagnosticOutcome(
        report: report,
        providerId: providerTypeId(config.providerType),
        modelVersion: config.model,
        imageProbePassed: false,
      );
    }
    // 正文完整后做标准图断言；断言失败停在第 image_assertion 阶段。
    final assertion = assertVisionProbe(report.responseBody ?? '');
    if (!assertion.passed) {
      final failedReport = _withImageAssertion(report, assertion);
      return MultimodalDiagnosticOutcome(
        report: failedReport,
        providerId: providerTypeId(config.providerType),
        modelVersion: config.model,
        imageProbePassed: false,
        assertionDetail: assertion.detail,
      );
    }
    return MultimodalDiagnosticOutcome(
      report: report,
      providerId: providerTypeId(config.providerType),
      modelVersion: config.model,
      imageProbePassed: true,
    );
  }

  /// 组装诊断上下文：表单当前输入为准构造配置，并解析已存 Key。
  Future<(LlmConnectionConfig, String)> _buildMultimodalDiagnosticContext(
    LlmSettingsInput input,
    LlmConfigRepository configRepository,
  ) async {
    // 已保存的配置只用于复用 ID / 密钥引用并读取已存 Key；地址、模型、超时
    // 一律以表单当前输入为准。否则"改了模型再测试"仍会命中旧配置，出现
    // 旧模型不支持图片输入而一直等待的假"超时"。
    final saved = await _loadMultimodalConfigSafely(configRepository);
    final config = LlmConnectionConfig(
      id:
          saved?.id ??
          (input.id?.trim().isNotEmpty == true
              ? input.id!.trim()
              : 'multimodal-test'),
      name: input.name.trim().isEmpty ? '图片识别 LLM' : input.name.trim(),
      providerType: input.providerType,
      baseUrl: input.baseUrl,
      secretRef: saved?.secretRef ?? 'multimodal-test-${input.id ?? 'new'}',
      model: input.model.trim(),
      requestTimeout: input.requestTimeout,
    );
    String apiKey = input.apiKey?.trim() ?? '';
    if (apiKey.isEmpty && saved != null) {
      try {
        apiKey = await configRepository.readApiKey(saved.secretRef);
      } catch (_) {
        // 已存 Key 读取失败时按未填 Key 处理，让 Provider 明确报鉴权错误。
        apiKey = '';
      }
    }
    return (config, apiKey);
  }

  /// 视觉专用模型拒绝纯文本的保守识别：错误正文包含图片相关关键词。
  static bool _looksLikeTextRejectedByVisionModel(String? body) {
    final normalized = (body ?? '').toLowerCase();
    const keywords = <String>[
      'image_url',
      'image',
      'picture',
      'vision',
      'multimodal',
      '视觉',
      '图片',
    ];
    return keywords.any(normalized.contains);
  }

  /// 把基础连接"文本能力未确认"合并进报告：原失败阶段保留为 warning，
  /// 报告整体标记为通过（服务与鉴权可用，仅文本能力未验证）。
  static LlmDiagnosticReport _withTextCapabilityUnconfirmed(
    LlmDiagnosticReport report,
  ) {
    final records = report.records.map((record) {
      if (record.result != LlmDiagnosticStageResult.failed) return record;
      return LlmDiagnosticStageRecord(
        stage: record.stage,
        result: LlmDiagnosticStageResult.warning,
        elapsedMs: record.elapsedMs,
        httpStatus: record.httpStatus,
        providerErrorCode: record.providerErrorCode,
        messageKey: 'text_capability_unconfirmed',
        nextAction: '直接使用"检查图片能力"验证图片输入',
      );
    }).toList(growable: false);
    return LlmDiagnosticReport(
      records: records,
      totalElapsedMs: report.totalElapsedMs,
      succeeded: true,
      failureKind: null,
      responseBody: report.responseBody,
    );
  }

  /// 把标准图断言失败合并进报告（追加 image_assertion 失败阶段）。
  static LlmDiagnosticReport _withImageAssertion(
    LlmDiagnosticReport report,
    VisionProbeAssertion assertion,
  ) {
    final records = report.records.toList(growable: false)
      ..add(
        LlmDiagnosticStageRecord(
          stage: LlmDiagnosticStage.imageAssertion,
          result: LlmDiagnosticStageResult.failed,
          elapsedMs: report.totalElapsedMs,
          messageKey: 'image_not_observed',
          nextAction: assertion.detail ?? '检查图片字段与视觉模型能力',
        ),
      );
    return LlmDiagnosticReport(
      records: records,
      totalElapsedMs: report.totalElapsedMs,
      succeeded: false,
      failureKind: LlmProviderErrorKind.imageNotObserved,
      responseBody: report.responseBody,
    );
  }

  static String providerTypeId(LlmProviderType type) => switch (type) {
    LlmProviderType.openAiCompatible => 'multimodal-openai-compatible',
    LlmProviderType.gemini => 'multimodal-gemini',
  };

  Future<LlmConnectionConfig?> _loadMultimodalConfigSafely(
    LlmConfigRepository repository,
  ) async {
    try {
      return await repository.load();
    } catch (_) {
      return null;
    }
  }

  Future<LlmSettingsSnapshot> clearMultimodalApiKey() {
    final settings = _requireMultimodalSettings();
    return _llmSettingsOperation(settings.clearStoredApiKey);
  }

  LlmSettingsUseCases _requireMultimodalSettings() {
    final settings = multimodalSettings;
    if (settings == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '图片识别 LLM 尚未接入。',
      );
    }
    return settings;
  }

  /// 测试识图：选择一张本地图片 → 多模态 LLM 识别 → 返回文本与耗时。
  ///
  /// 与"测试连接"（纯文本连通性）不同，这里真正发送图片，验证视觉能力。
  Future<MultimodalRecognitionResult> testMultimodalImage(String localPath) async {
    final configRepository = multimodalConfigRepository;
    final providerFactory = multimodalProviderFactory;
    if (configRepository == null || providerFactory == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '图片识别 LLM 尚未接入。',
      );
    }
    final LlmConnectionConfig config;
    try {
      final loaded = await configRepository.load();
      if (loaded == null) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.providerRouteUnavailable,
          message: '请先在识图引擎中配置图片识别 LLM。',
        );
      }
      config = loaded;
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '图片识别 LLM 配置暂时无法读取，请稍后重试。',
      );
    }
    final apiKey = await configRepository.readApiKey(config.secretRef);
    if (apiKey.trim().isEmpty) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '请先保存图片识别 LLM 的 API Key。',
      );
    }
    final List<int> bytes;
    try {
      bytes = await File(localPath).readAsBytes();
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '无法读取所选图片，请重新选择。',
      );
    }
    try {
      final provider = providerFactory.create(config.providerType);
      final validationError = provider.validateImageBytes(bytes: bytes);
      if (validationError != null) {
        throw AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.invalidInput,
          message: validationError,
        );
      }
      return await provider.recognizeImage(
        config: config,
        apiKey: apiKey,
        input: MultimodalImageInput(bytes: bytes, order: 0),
        prompt: '请识别这张测试图片的内容，输出图片中的文字以及图片的大致描述。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } on LlmProviderException catch (error) {
      throw AiRecipeBackendException(
        code: _mapMultimodalProviderError(error),
        message: error.message,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '多模态识图暂时失败，请稍后重试。',
      );
    }
  }

  /// 把多模态 LLM Provider 错误映射为 Facade 稳定错误码。
  static AiRecipeBackendErrorCode _mapMultimodalProviderError(
    LlmProviderException error,
  ) {
    return switch (error.kind) {
      LlmProviderErrorKind.invalidConfiguration ||
      LlmProviderErrorKind.badRequest ||
      LlmProviderErrorKind.payloadTooLarge ||
      LlmProviderErrorKind.unsupportedMediaType =>
        AiRecipeBackendErrorCode.invalidInput,
      LlmProviderErrorKind.unauthorized =>
        AiRecipeBackendErrorCode.authenticationFailed,
      LlmProviderErrorKind.notFound ||
      LlmProviderErrorKind.methodNotAllowed =>
        AiRecipeBackendErrorCode.providerUnavailable,
      LlmProviderErrorKind.rateLimited => AiRecipeBackendErrorCode.rateLimited,
      LlmProviderErrorKind.timeout ||
      LlmProviderErrorKind.providerGatewayTimeout ||
      LlmProviderErrorKind.firstByteDeadline ||
      LlmProviderErrorKind.bodyIdleDeadline ||
      LlmProviderErrorKind.streamNotTerminated =>
        AiRecipeBackendErrorCode.timeout,
      LlmProviderErrorKind.cancelled =>
        AiRecipeBackendErrorCode.operationCancelled,
      LlmProviderErrorKind.server ||
      LlmProviderErrorKind.modelBusy =>
        AiRecipeBackendErrorCode.providerUnavailable,
      LlmProviderErrorKind.invalidResponse ||
      LlmProviderErrorKind.imageNotObserved ||
      LlmProviderErrorKind.textCapabilityUnconfirmed =>
        AiRecipeBackendErrorCode.invalidProviderResponse,
      LlmProviderErrorKind.network =>
        AiRecipeBackendErrorCode.networkUnavailable,
      LlmProviderErrorKind.unknown => AiRecipeBackendErrorCode.operationFailed,
    };
  }

  Future<Recipe> createRecipe(
    RecipeDraftInput input, {
    String? userId,
    String? sourceId,
  }) => _recipeOperation(
    () => recipes.createRecipe(input, userId: userId, sourceId: sourceId),
  );

  Future<Recipe> updateRecipe(String id, RecipeDraftInput input) =>
      _recipeOperation(() => recipes.updateRecipe(id, input));

  /// 只更新菜谱指定步骤的时长（COOK-001：烹饪模式自定义计时同步到菜谱）。
  Future<Recipe> updateRecipeStepDuration(
    String recipeId,
    String stepId,
    int durationSeconds,
  ) => _recipeOperation(
    () => recipes.updateRecipeStepDuration(recipeId, stepId, durationSeconds),
  );

  /// 把来源图片（系统相册返回的临时路径）复制到菜谱私有封面目录。
  ///
  /// [containerId] 用于区分菜谱（编辑已有菜谱用其 ID，新建用临时 ID）；
  /// 返回复制后的本地绝对路径列表，供 [RecipeDraftInput.images] 使用。
  Future<List<String>> stageCoverImages(
    String containerId,
    List<String> sourcePaths,
  ) async {
    try {
      final stager =
          coverImageStager ?? DeviceRecipeCoverImageStager();
      final staged = <String>[];
      for (final entry in sourcePaths.indexed) {
        staged.add(
          await stager.copyIn(
            sourcePath: entry.$2,
            containerId: containerId,
            index: entry.$1,
          ),
        );
      }
      return staged;
    } on RecipeCoverImageException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '图片暂时无法保存到本机，请稍后重试。',
      );
    }
  }

  /// 删除菜谱私有封面目录中的单个图片文件（best-effort）。
  Future<void> deleteCoverImage(String imagePath) async {
    try {
      final stager =
          coverImageStager ?? DeviceRecipeCoverImageStager();
      await stager.deleteFile(imagePath);
    } catch (_) {
      // best-effort：清理失败不阻断主流程。
    }
  }

  Future<Recipe> getRecipe(String id, {bool includeDeleted = false}) =>
      _recipeOperation(
        () => recipes.getRecipe(id, includeDeleted: includeDeleted),
      );

  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) => _recipeOperation(
    () => recipes.listRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      deletionFilter: deletionFilter,
    ),
  );

  /// 菜谱列表摘要分页（解决方案.md：列表页不再读取完整聚合）。
  Future<RecipeSummaryPage> listRecipeSummaries({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
    RecipeSort sort = RecipeSort.updated,
    int limit = 40,
    RecipeCursor? after,
  }) => _recipeOperation(
    () => recipes.listRecipeSummaries(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      deletionFilter: deletionFilter,
      sort: sort,
      limit: limit,
      after: after,
    ),
  );

  /// 回收站菜谱轻量列表（单条 SQL，避免 N+1 全量加载卡顿）。
  Future<List<TrashRecipeSummary>> listTrashSummaries() => _recipeOperation(
    () => recipes.listTrashSummaries(),
  );

  /// 列表筛选条件下的菜谱总数（列表页头"共 N 道菜谱"）。
  Future<int> countRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
  }) => _recipeOperation(
    () => recipes.countRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
    ),
  );

  /// 各分类下的活跃菜谱数量（首页分类卡片）。
  Future<Map<String, int>> countRecipesByCategory() =>
      _recipeOperation(() => recipes.countRecipesByCategory());

  /// 按 id 批量读取摘要（首页"最近浏览"等小列表用）。
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids) =>
      _recipeOperation(() => recipes.getRecipeSummariesByIds(ids));

  /// 推荐专用轻量批量读取（只含主记录 + 食材，不含步骤/图片/分类）。
  Future<List<Recipe>> listRecipesForRecommendation({
    RecipeStatus? status,
  }) => _recipeOperation(
    () => recipes.listRecipesForRecommendation(status: status),
  );

  Future<Recipe> copyRecipe(String id, {String? title}) =>
      _recipeOperation(() => recipes.copyRecipe(id, title: title));

  Future<Recipe> setRecipeFavorite(String id, bool favorite) =>
      _recipeOperation(() => recipes.setRecipeFavorite(id, favorite));

  // ---- 冰箱库存（FRIDGE-002）----

  Future<List<InventoryBatch>> listInventoryBatches() {
    return _inventoryOperation(() => _requireInventory().loadAvailableBatches());
  }

  Future<InventorySummary> loadInventorySummary() {
    return _inventoryOperation(() => _requireInventory().loadSummary());
  }

  Future<List<AggregatedInventoryItem>> loadAggregatedInventory() {
    return _inventoryOperation(() => _requireInventory().loadAggregated());
  }

  /// 渐进式录入（ADR-0022）：输入库存食材名称，返回解析出的基础食材
  /// 与可选规格候选，供录入页展示可跳过的规格选择。
  InventoryNameSuggestion suggestInventorySpec(String name) {
    return _requireInventory().suggestIngredientSpec(name);
  }

  /// 食材名称是否已被本地词典识别（草稿确认页“种类待确认”轻量标识）。
  bool isIngredientNameKnown(String name) {
    return _requireInventory().isIngredientNameKnown(name);
  }

  Future<InventoryBatch> createInventoryBatch(InventoryBatchInput input) {
    return _inventoryOperation(() => _requireInventory().createBatch(input));
  }

  Future<InventoryBatch> updateInventoryBatch(
    String id,
    InventoryBatchInput input,
  ) {
    return _inventoryOperation(() => _requireInventory().updateBatch(id, input));
  }

  Future<InventoryBatch> useUpInventoryBatch(String id) {
    return _inventoryOperation(() => _requireInventory().useUpBatch(id));
  }

  Future<InventoryBatch> discardInventoryBatch(String id) {
    return _inventoryOperation(() => _requireInventory().discardBatch(id));
  }

  /// 移动批次到其他分区（长按拖动跨区用）。
  Future<InventoryBatch> moveInventoryBatchToZone(
    String id,
    InventoryZone zone,
  ) {
    return _inventoryOperation(
      () => _requireInventory().moveBatchToZone(id, zone),
    );
  }

  /// 更新批次在分区内的排序权重（长按拖动排序用）。
  Future<InventoryBatch> reorderInventoryBatch(String id, int sortOrder) {
    return _inventoryOperation(
      () => _requireInventory().reorderBatch(id, sortOrder),
    );
  }

  Future<void> deleteInventoryBatch(String id) {
    return _inventoryOperation(() => _requireInventory().deleteBatch(id));
  }

  // ---- 按库存推荐本地菜谱（RECO-001）----

  /// 只读取本地正式菜谱（published、未删除），按已选食材做确定性离线匹配。
  ///
  /// [strictSelected] 为 true 时只使用用户选中的食材（ADR-0021 开关）；
  /// [confirmedBases] 为本推荐会话中用户已确认“视为可用”的基础食材 ID
  /// （ADR-0022：仅本次使用，不改库存、不写全局词典）。
  Future<List<RecipeRecommendation>> recommendRecipesFromInventory(
    Set<String> selectedNames, {
    bool strictSelected = false,
    Set<String> confirmedBases = const <String>{},
  }) async {
    final useCases = _requireInventory();
    try {
      // 1. 库存批次（一次查询）。
      final batches = await useCases.loadAvailableBatches();
      // 2. 推荐专用轻量数据（一次查询主记录 + 一次批量食材，不含步骤/图片/分类）。
      final recipes = await this.recipes.listRecipesForRecommendation(
        status: RecipeStatus.published,
      );
      // 3. 纯匹配计算移到后台 Isolate（或测试注入的直算执行器），
      //    避免阻塞 UI 主线程（解决方案.md 第六节）。
      return recommendationExecutor.compute(
        selectedNames: selectedNames,
        recipes: recipes,
        batches: batches,
        now: _clock(),
        strictSelected: strictSelected,
        confirmedBases: confirmedBases,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '推荐暂时无法计算，请稍后重试。',
      );
    }
  }

  // ---- 下厨后库存扣减确认（FRIDGE-003）----

  /// 用户确认后的预计消耗列表：逐项扣减并记录 InventoryChange；
  /// 数量未知或库存不足的批次会整体失败并保持原库存不变。
  Future<void> confirmInventoryConsumption(
    List<InventoryConsumptionItem> items,
  ) async {
    final useCases = _requireInventory();
    try {
      for (final item in items) {
        await useCases.consumeBatch(
          item.batchId,
          item.delta,
          relatedRecipeId: item.relatedRecipeId,
        );
      }
    } on StateError catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '库存暂时无法更新，请稍后重试。',
      );
    }
  }

  InventoryLibraryUseCases _requireInventory() {
    final useCases = inventory;
    if (useCases == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '冰箱库存功能当前不可用。',
      );
    }
    return useCases;
  }

  // ---- 菜谱备份导出（BACKUP-003）----

  /// 备份前预估：数据规模与空间占用（不计算媒体哈希，只读文件大小）。
  Future<BackupEstimate> estimateBackup() {
    final useCases = _requireBackup();
    return _backupOperation(useCases.estimate);
  }

  /// 创建全量备份归档，返回最终文件路径与统计。
  ///
  /// [cancellationToken] 可随时取消（快照、校验、组装阶段即时响应；
  /// 归档写入与复核阶段完成后统一清理并抛取消）。
  Future<BackupExportResult> createFullBackup({
    BackupCancellationToken? cancellationToken,
    void Function(BackupExportProgress)? onProgress,
  }) {
    final useCases = _requireBackup();
    return _backupOperation(
      () => useCases.createFullBackup(
        token: cancellationToken,
        onProgress: onProgress,
      ),
    );
  }

  BackupExportUseCases _requireBackup() {
    final useCases = backup;
    if (useCases == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '备份功能当前不可用。',
      );
    }
    return useCases;
  }

  /// 把备份管线错误映射为 Facade 稳定错误码。
  Future<T> _backupOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on BackupOperationCancelledException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.backupCancelled,
        message: '备份操作已取消。',
      );
    } on BackupException catch (error) {
      throw AiRecipeBackendException(
        code: error.retryable
            ? AiRecipeBackendErrorCode.storageUnavailable
            : AiRecipeBackendErrorCode.backupFailed,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '备份暂时无法完成，请稍后重试。',
      );
    }
  }

  // ---- 菜谱备份导入（BACKUP-004 合并 / BACKUP-005 替换）----

  /// 预检备份：解压并安全校验 → 只读分析当前库 → 生成导入计划。
  ///
  /// 成功后 [BackupImportPreviewResult.sessionId] 用于后续执行；
  /// 用户确认前不修改当前库（架构 10）。
  Future<BackupImportPreviewResult> previewBackupImport({
    required String sourcePath,
    BackupCancellationToken? cancellationToken,
    void Function(BackupImportProgress)? onProgress,
  }) {
    final useCases = _requireBackupImport();
    return _backupOperation(
      () => useCases.previewImport(
        sourcePath: sourcePath,
        token: cancellationToken,
        onProgress: onProgress,
      ),
    );
  }

  /// 修改单个冲突的解决方式（纯函数，返回新计划）。
  BackupImportPlan resolveImportConflict(
    BackupImportPlan plan,
    int index,
    BackupConflictResolution resolution,
  ) {
    return _requireBackupImport().resolveConflict(plan, index, resolution);
  }

  /// 把同一解决方式应用到全部冲突（纯函数，返回新计划）。
  BackupImportPlan resolveAllImportConflicts(
    BackupImportPlan plan,
    BackupConflictResolution resolution,
  ) {
    return _requireBackupImport().resolveAllConflicts(plan, resolution);
  }

  /// 放弃预检会话（用户返回或切换文件），清理 staging。
  Future<void> discardImportPreview(String sessionId) {
    return _backupOperation(
      () => _requireBackupImport().discardPreview(sessionId),
    );
  }

  /// 按已确认的计划执行导入（合并写入或替换恢复）。
  ///
  /// [onProgress] 与导出一致，逐阶段回报；取消、失败均清理 staging，
  /// 替换模式失败时尽力从回滚备份恢复并保留回滚备份文件。
  Future<BackupImportResult> executeBackupImport({
    required String sessionId,
    required BackupImportPlan plan,
    BackupCancellationToken? cancellationToken,
    void Function(BackupImportProgress)? onProgress,
  }) {
    final useCases = _requireBackupImport();
    return _backupOperation(
      () => useCases.executeImport(
        sessionId: sessionId,
        plan: plan,
        token: cancellationToken,
        onProgress: onProgress,
      ),
    );
  }

  /// 清理启动时遗留的 staging 会话目录（应用启动时调用），返回删除数量。
  Future<int> cleanupAbandonedImportSessions() {
    return _backupOperation(_requireBackupImport().cleanupAbandonedSessions);
  }

  BackupImportUseCases _requireBackupImport() {
    final useCases = backupImport;
    if (useCases == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '备份导入功能当前不可用。',
      );
    }
    return useCases;
  }

  Future<T> _inventoryOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ArgumentError catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '库存暂时无法读写，请稍后重试。',
      );
    }
  }

  Future<void> softDeleteRecipe(String id) =>
      _recipeOperation(() => recipes.softDeleteRecipe(id));

  /// 批量软删除（开发者工具清空测试数据等）：一次 SQL 一个事务，
  /// 替代逐条 [softDeleteRecipe] 的「全量加载 + 独立事务」。
  Future<void> softDeleteRecipesByIds(Iterable<String> ids) =>
      _recipeOperation(() => recipes.softDeleteRecipesByIds(ids));

  Future<void> restoreRecipe(String id) =>
      _recipeOperation(() => recipes.restoreRecipe(id));

  Future<void> permanentlyDeleteRecipe(String id) =>
      _recipeOperation(() => recipes.permanentlyDeleteRecipe(id));

  Future<void> restoreRecipes(Iterable<String> ids) =>
      _recipeOperation(() => recipes.restoreRecipes(ids));

  Future<void> permanentlyDeleteRecipes(Iterable<String> ids) =>
      _recipeOperation(() => recipes.permanentlyDeleteRecipes(ids));

  Future<int> emptyRecipeTrash() => _recipeOperation(recipes.emptyRecipeTrash);

  Future<RecipeCategory> createCategory(
    RecipeCategoryInput input, {
    String? userId,
  }) => _recipeOperation(() => recipes.createCategory(input, userId: userId));

  Future<RecipeCategory> updateCategory(String id, RecipeCategoryInput input) =>
      _recipeOperation(() => recipes.updateCategory(id, input));

  Future<RecipeCategory> getCategory(
    String id, {
    bool includeDeleted = false,
  }) => _recipeOperation(
    () => recipes.getCategory(id, includeDeleted: includeDeleted),
  );

  Future<List<RecipeCategory>> listCategories({
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) => _recipeOperation(
    () => recipes.listCategories(deletionFilter: deletionFilter),
  );

  Future<void> softDeleteCategory(String id) =>
      _recipeOperation(() => recipes.softDeleteCategory(id));

  Future<void> restoreCategory(String id) =>
      _recipeOperation(() => recipes.restoreCategory(id));

  Future<void> permanentlyDeleteCategory(String id) =>
      _recipeOperation(() => recipes.permanentlyDeleteCategory(id));

  Future<HomeSnapshot> loadHome({
    int recentLimit = 10,
    int favoriteLimit = 10,
  }) => _localBusinessOperation(
    () => home.load(recentLimit: recentLimit, favoriteLimit: favoriteLimit),
  );

  Future<RecipeDetailSnapshot> openRecipeDetail(
    String recipeId, {
    bool recordView = true,
  }) => _localBusinessOperation(
    () => recipeDetails.open(recipeId, recordView: recordView),
  );

  Future<LocalAppSettings> loadLocalSettings() =>
      _localBusinessOperation(localSettings.load);

  Future<LocalAppSettings> saveLocalSettings(LocalAppSettingsInput input) =>
      _localBusinessOperation(() => localSettings.save(input));

  Future<void> clearRecipeHistory() =>
      _localBusinessOperation(localSettings.clearRecipeHistory);

  Future<CookingSession> startOrResumeCooking(String recipeId) =>
      _cookingOperation(() => cooking.startOrResume(recipeId));

  Future<CookingSession> getCookingSession(String sessionId) =>
      _cookingOperation(() => cooking.getSession(sessionId));

  Future<CookingSession> setCookingStep(String sessionId, int stepIndex) =>
      _cookingOperation(() => cooking.setCurrentStep(sessionId, stepIndex));

  Future<CookingSession> addCookingTimer(
    String sessionId, {
    required String label,
    required int durationSeconds,
    bool startImmediately = true,
  }) => _cookingOperation(
    () => cooking.addTimer(
      sessionId,
      label: label,
      durationSeconds: durationSeconds,
      startImmediately: startImmediately,
    ),
  );

  Future<CookingSession> pauseCookingTimer(String sessionId, String timerId) =>
      _cookingOperation(() => cooking.pauseTimer(sessionId, timerId));

  Future<CookingSession> resumeCookingTimer(String sessionId, String timerId) =>
      _cookingOperation(() => cooking.resumeTimer(sessionId, timerId));

  Future<CookingSession> completeCookingTimer(
    String sessionId,
    String timerId,
  ) => _cookingOperation(() => cooking.completeTimer(sessionId, timerId));

  Future<CookingSession> deleteCookingTimer(String sessionId, String timerId) =>
      _cookingOperation(() => cooking.deleteTimer(sessionId, timerId));

  Future<CookingSession> completeCookingSession(String sessionId) =>
      _cookingOperation(() => cooking.completeSession(sessionId));

  Future<void> deleteCookingSession(String sessionId) =>
      _cookingOperation(() => cooking.deleteSession(sessionId));

  Future<OcrModelPackageStatus> getLocalOcrModelStatus(String packageId) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      return await useCases.getStatus(packageId);
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<OcrModelPackageStatus> installLocalOcrModel(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      return await useCases.install(
        manifest,
        onStatusChanged: onStatusChanged,
        cancellationToken: cancellationToken,
      );
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<void> deleteLocalOcrModel(String packageId) async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      await useCases.delete(packageId);
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  Future<void> recoverLocalOcrModelInstallation() async {
    final useCases = _requireLocalOcrModelUseCases();
    try {
      await useCases.recoverInterruptedInstallations();
    } on OcrModelPackageException catch (error) {
      throw _mapOcrModelPackageException(error);
    }
  }

  /// 测试本地 OCR：识别一张本地图片，返回识别文本与耗时（OCR 设置页用）。
  Future<OcrTestResult> testLocalOcrImage(String localPath) async {
    final builder = localOcrProviderBuilder;
    if (builder == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '本地 OCR 未配置，请检查识图引擎设置。',
      );
    }
    await access.requireCapability(AppCapability.localOcr);
    try {
      final provider = await builder();
      final doc = await provider.recognize(
        OcrImageInput(localAssetId: localPath, order: 0),
      );
      return OcrTestResult(
        text: doc.fullText,
        modelVersion: doc.modelVersion,
        language: doc.language,
        blockCount: doc.blocks.length,
        durationMs: doc.durationMs,
        averageConfidence: doc.averageConfidence,
      );
    } on OcrProviderException catch (error) {
      throw AiRecipeBackendException(
        code: _mapOcrProviderError(error),
        message: error.message,
      );
    } on ImportOperationCancelledException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationCancelled,
        message: 'OCR 识别已取消。',
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: 'OCR 识别暂时失败，请稍后重试。',
      );
    }
  }

  /// 把本地 OCR Provider 错误映射为 Facade 稳定错误码。
  static AiRecipeBackendErrorCode _mapOcrProviderError(
    OcrProviderException error,
  ) {
    return switch (error.kind) {
      OcrProviderErrorKind.modelNotInstalled ||
      OcrProviderErrorKind.unavailable ||
      OcrProviderErrorKind.inferenceFailed =>
        AiRecipeBackendErrorCode.providerRouteUnavailable,
      OcrProviderErrorKind.timeout => AiRecipeBackendErrorCode.timeout,
      OcrProviderErrorKind.cancelled => AiRecipeBackendErrorCode.operationCancelled,
      OcrProviderErrorKind.networkUnavailable =>
        AiRecipeBackendErrorCode.networkUnavailable,
      OcrProviderErrorKind.invalidInput ||
      OcrProviderErrorKind.unauthorized ||
      OcrProviderErrorKind.rateLimited ||
      OcrProviderErrorKind.invalidResponse ||
      OcrProviderErrorKind.unknown =>
        AiRecipeBackendErrorCode.operationFailed,
    };
  }

  Future<ImportTask> createImportTask(
    String sourceUrl, {
    int maxAttempts = 3,
  }) async {
    await access.requireCapability(AppCapability.publicContentImport);
    try {
      return await CreateImportTask(
        repository: _importTaskRepository,
        idGenerator: _importTaskIdGenerator,
        clock: _clock,
      )(sourceUrl, maxAttempts: maxAttempts);
    } on ImportTaskInputException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法保存，请稍后重试。',
      );
    }
  }

  /// 创建以本地图片为内容的导入任务（快速导入"拍照选图"，IMPORT-009）。
  ///
  /// 用占位链接创建任务以复用既有任务持久化、取消与重试流程；图片内容随后
  /// 由 [runImportWithLocalImage] 运行（本地 OCR + 自有 LLM）。
  Future<ImportTask> createLocalImageImportTask() async {
    await access.requireCapability(AppCapability.publicContentImport);
    try {
      return await CreateImportTask(
        repository: _importTaskRepository,
        idGenerator: _importTaskIdGenerator,
        clock: _clock,
      )(localImageCapturePlaceholderUrl, maxAttempts: 1);
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法保存，请稍后重试。',
      );
    }
  }

  /// 创建以本地文本为内容的导入任务（快速导入"剪贴板"，输入文本导入）。
  ///
  /// 用占位链接创建任务以复用既有任务持久化、取消与重试流程；文本内容随后
  /// 由 [runImportWithText] 运行（自有 LLM 整理成菜谱）。
  Future<ImportTask> createLocalTextImportTask() async {
    await access.requireCapability(AppCapability.publicContentImport);
    try {
      return await CreateImportTask(
        repository: _importTaskRepository,
        idGenerator: _importTaskIdGenerator,
        clock: _clock,
      )(localTextCapturePlaceholderUrl, maxAttempts: 1);
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法保存，请稍后重试。',
      );
    }
  }

  Future<ImportTask> getImportTask(String id) async {
    final normalizedId = _requireId(id, '导入任务 ID');
    try {
      final task = await _importTaskRepository.getTaskById(normalizedId);
      if (task == null) throw _taskNotFound();
      return task;
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<List<ImportTask>> listImportTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  }) async {
    if (limit != null && limit <= 0) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '任务数量限制必须大于 0。',
      );
    }
    try {
      return await _importTaskRepository.listTasks(
        statuses: statuses,
        includeDeleted: includeDeleted,
        limit: limit,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务列表暂时无法读取，请稍后重试。',
      );
    }
  }

  /// 运行链接导入任务。
  ///
  /// [plan] 为 null 时自动解析：小红书/抖音图文内容需要把图片 OCR 成文字后
  /// 与正文整合再交给 AI，因此本地 OCR 能力就绪时启用 `ocr: local`；OCR
  /// 不可用时回退纯文本路径，避免无图内容被 OCR 安装状态阻塞。
  Future<ImportTaskRunResult> runImportTask(
    String id, {
    ImportExecutionPlan? plan,
    ImportCancellationToken? cancellationToken,
  }) async {
    final taskId = _requireId(id, '导入任务 ID');
    try {
      // 占位来源的图片/文本任务不能走公开链接抓取；只有通过
      // runImportWithLocalImage / runImportWithText 提供内容后才能运行。
      final guardTask = await getImportTask(taskId);
      if (guardTask.sourceUrl == localImageCapturePlaceholderUrl ||
          guardTask.sourceUrl == localTextCapturePlaceholderUrl) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.invalidTaskState,
          message: '该导入需要重新提供图片或正文内容，请重新创建导入。',
        );
      }
      final resolvedPlan = plan ?? await _resolveDefaultPlan();
      await _requirePlanCapabilities(resolvedPlan);
      final session = await access.loadSession();
      final runner = await _runnerFactory.create(
        resolvedPlan,
        userId: session.userId,
      );
      final runResult = await _trackInFlight(
        taskId,
        () => runner.run(taskId, cancellationToken: cancellationToken),
      );
      await _persistImportEvidence(taskId, runResult.content);
      return runResult;
    } on AppCapabilityUnavailableException catch (error) {
      throw _mapImportCapabilityUnavailable(error);
    } on AppAccessStorageException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '应用会话或导入设置暂时无法读取，请稍后重试。',
      );
    } on AppAccessEvaluationException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '导入能力暂时无法确认，请稍后重试。',
      );
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '导入任务暂时无法运行，请稍后重试。',
      );
    }
  }

  Future<ImportTaskRunResult> runImportWithPastedText(
    String id,
    String text, {
    ImportExecutionPlan plan = const ImportExecutionPlan(),
    ImportCancellationToken? cancellationToken,
  }) async {
    final taskId = _requireId(id, '导入任务 ID');
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.failed &&
        task.status != ImportTaskStatus.cancelled) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有失败或已取消的任务可以使用人工降级输入。',
      );
    }
    late final ImportFallbackInput input;
    try {
      input = ImportFallbackInput.pastedText(
        source: ImportSourceLink(
          sourceUrl: task.sourceUrl,
          normalizedUrl: task.normalizedUrl,
          platform: task.sourcePlatform,
        ),
        text: text,
        capturedAt: _clock(),
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '请先粘贴要整理的正文内容。',
      );
    }

    await _requirePlanCapabilities(plan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(plan, userId: session.userId);
      final content = const ImportFallbackContentFactory().build(input);
      final runResult = await _trackInFlight(
        taskId,
        () => runner.runWithContent(
          taskId,
          content,
          cancellationToken: cancellationToken,
        ),
      );
      await _persistImportEvidence(taskId, runResult.content);
      return runResult;
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '粘贴正文与原导入任务不匹配。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '正文暂时无法处理，请稍后重试。',
      );
    }
  }

  Future<ImportTaskRunResult> runImportWithLocalImage(
    String id,
    String localAssetId, {
    String? mimeType,
    ImportCancellationToken? cancellationToken,
  }) async {
    final taskId = _requireId(id, '导入任务 ID');
    final task = await getImportTask(taskId);
    // 允许 queued：快速导入"拍照选图"新建的图片任务以图片内容运行（IMPORT-009）；
    // 既有降级路径仍是失败/已取消任务。
    if (task.status != ImportTaskStatus.failed &&
        task.status != ImportTaskStatus.cancelled &&
        task.status != ImportTaskStatus.queued) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前导入任务状态不允许使用本地图片导入。',
      );
    }

    late final ImportFallbackInput input;
    try {
      input = ImportFallbackInput.localImage(
        source: ImportSourceLink(
          sourceUrl: task.sourceUrl,
          normalizedUrl: task.normalizedUrl,
          platform: task.sourcePlatform,
        ),
        localAssetId: localAssetId,
        mimeType: mimeType,
        capturedAt: _clock(),
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '请选择可处理的本地图片。',
      );
    }

    // 手动选图/拍照导入：本地 OCR 优先，OCR 未安装/不可用时回退多模态
    // 转录（ADR-0029，IMAGE-002）。
    final plan = await _resolveLocalImagePlan();
    if (plan.imageRecognition == ImportImageRecognitionRoute.disabled) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '当前图片识别方式不可用，请检查识图引擎设置后重试。',
      );
    }
    await _requireLocalImageImportCapabilities(plan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(plan, userId: session.userId);
      final content = const ImportFallbackContentFactory().build(input);
      final runResult = await _trackInFlight(
        taskId,
        () => runner.runWithContent(
          taskId,
          content,
          cancellationToken: cancellationToken,
        ),
      );
      await _persistImportEvidence(taskId, runResult.content);
      return runResult;
    } on ImportTaskRunnerFactoryException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '本地 OCR 或自有 AI 服务当前不可用，请检查设置后重试。',
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '图片导入暂时失败，请稍后重试。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '图片导入暂时失败，请稍后重试。',
      );
    }
  }

  /// 以本地文本为内容运行导入（快速导入"剪贴板"，输入文本导入）。
  ///
  /// 允许 queued：快速导入新建的文本任务以文本内容运行；既有降级路径
  /// 仍是失败/已取消任务。
  Future<ImportTaskRunResult> runImportWithText(
    String id,
    String text, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final taskId = _requireId(id, '导入任务 ID');
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.failed &&
        task.status != ImportTaskStatus.cancelled &&
        task.status != ImportTaskStatus.queued) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前导入任务状态不允许使用文本导入。',
      );
    }

    late final ImportFallbackInput input;
    try {
      input = ImportFallbackInput.pastedText(
        source: ImportSourceLink(
          sourceUrl: task.sourceUrl,
          normalizedUrl: task.normalizedUrl,
          platform: task.sourcePlatform,
        ),
        text: text,
        capturedAt: _clock(),
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '请先粘贴要整理的正文内容。',
      );
    }

    const plan = ImportExecutionPlan(llm: ImportLlmRoute.custom);
    await _requirePlanCapabilities(plan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(plan, userId: session.userId);
      final content = const ImportFallbackContentFactory().build(input);
      final runResult = await _trackInFlight(
        taskId,
        () => runner.runWithContent(
          taskId,
          content,
          cancellationToken: cancellationToken,
        ),
      );
      await _persistImportEvidence(taskId, runResult.content);
      return runResult;
    } on ImportTaskRunnerFactoryException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '自有 AI 服务当前不可用，请检查 LLM 设置后重试。',
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '文本导入暂时失败，请稍后重试。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '文本导入暂时失败，请稍后重试。',
      );
    }
  }

  /// 调度待处理导入任务。
  ///
  /// [plan] 为 null 时与 [runImportTask] 一致：本地 OCR 能力就绪则启用
  /// `ocr: local`，保证恢复的图文任务同样会把图片 OCR 与正文整合。
  Future<ImportDispatchReport> dispatchPendingImports({
    ImportExecutionPlan? plan,
    int? limit,
    ImportCancellationToken? cancellationToken,
  }) async {
    final resolvedPlan = plan ?? await _resolveDefaultPlan();
    await _requirePlanCapabilities(resolvedPlan);
    final session = await access.loadSession();
    try {
      final runner = await _runnerFactory.create(
        resolvedPlan,
        userId: session.userId,
      );
      return await SingleImportTaskDispatcher(
        repository: _importTaskRepository,
        runner: runner,
      ).dispatchPending(limit: limit, cancellationToken: cancellationToken);
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ArgumentError {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '任务数量限制必须大于 0。',
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '待处理任务暂时无法调度，请稍后重试。',
      );
    }
  }

  Future<ImportTask> cancelImportTask(String id) async {
    final taskId = _requireId(id, '导入任务 ID');
    final beforeCancellation = await getImportTask(taskId);
    final cancelled = await _changeTask(() async {
      return CancelImportTask(repository: _importTaskRepository, clock: _clock)(
        taskId,
      );
    });

    final recipeId = beforeCancellation.resultRecipeId;
    if (recipeId == null || recipeId.trim().isEmpty) {
      return cancelled;
    }
    try {
      await _discardRecipeDraft(
        recipeId: recipeId,
        sourceId: beforeCancellation.normalizedUrl,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务已取消，但关联草稿暂时无法清理。',
      );
    }
    return cancelled;
  }

  Future<ImportTask> retryImportTask(String id) {
    return _changeTask(() async {
      return RetryImportTask(repository: _importTaskRepository, clock: _clock)(
        _requireId(id, '导入任务 ID'),
      );
    });
  }

  /// 永久删除导入任务（IMPORT-009 任务列表单个/批量删除）。
  ///
  /// 已结束（失败/已取消）任务直接删除；进行中（排队/解析中）与待确认任务
  /// 会先取消（中断后台解析），再清理任务关联的全部草稿（主草稿 + 附加草稿，
  /// 避免遗留孤儿草稿记录），最后永久删除任务记录。
  Future<void> deleteImportTask(String id) async {
    final taskId = _requireId(id, '导入任务 ID');
    try {
      final task = await _importTaskRepository.getTaskById(taskId);
      if (task == null) throw _taskNotFound();
      final needsCancelFirst = task.status != ImportTaskStatus.failed &&
          task.status != ImportTaskStatus.cancelled;
      if (needsCancelFirst) {
        // 进行中/待确认：先取消任务，中断后台解析（取消内部会清理主草稿）。
        await cancelImportTask(taskId);
      }
      // 清理任务关联的全部草稿（主草稿 + 附加草稿），防止遗留孤儿记录；
      // 已结束任务无草稿（allResultRecipeIds 为空），此循环为空操作。
      for (final recipeId in task.allResultRecipeIds) {
        await _discardRecipeDraft(
          recipeId: recipeId,
          sourceId: task.normalizedUrl,
        );
      }
      await _importTaskRepository.permanentlyDeleteTask(taskId);
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法删除，请稍后重试。',
      );
    }
  }

  /// 批量永久删除导入任务，用于任务列表批量删除与一键清空。
  Future<void> deleteImportTasks(Iterable<String> ids) async {
    for (final id in ids.toList(growable: false)) {
      await deleteImportTask(id);
    }
  }

  /// 是否当前进程内正在实时执行的导入任务。
  bool isImportTaskInFlight(String id) => _inFlightTaskIds.contains(id);

  /// 包裹一次导入任务运行：进入时登记为"在途"，结束（含异常）时移除。
  ///
  /// 这样当解析中按返回、任务仍在后台实时执行时，[recoverInterruptedImports]
  /// 能识别出该任务并非"遗留中断任务"，从而跳过它、不把它判为失败。
  Future<T> _trackInFlight<T>(String taskId, Future<T> Function() action) async {
    _inFlightTaskIds.add(taskId);
    try {
      return await action();
    } finally {
      _inFlightTaskIds.remove(taskId);
    }
  }

  Future<List<ImportTask>> recoverInterruptedImports() async {
    try {
      return await RecoverInterruptedImportTasks(
        repository: _importTaskRepository,
        clock: _clock,
        // 快照当前在途任务：仍在后台实时运行的导入任务不做"中断恢复"。
        skipTaskIds: Set<String>.of(_inFlightTaskIds),
      )();
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务恢复失败，请稍后重试。',
      );
    }
  }

  /// 读取导入任务持久化的原始内容依据（无则返回 null）。
  Future<ImportContent?> getImportEvidence(String taskId) async {
    try {
      return await _importTaskRepository.loadImportEvidence(taskId);
    } catch (_) {
      return null;
    }
  }

  /// best-effort 把一次导入产出的原始内容证据持久化到本地，供"原始内容依据"
  /// 面板展示与复制。保存失败不影响导入结果本身。
  Future<void> _persistImportEvidence(
    String taskId,
    ImportContent? content,
  ) async {
    if (content == null) return;
    try {
      await _importTaskRepository.saveImportEvidence(taskId, content);
    } catch (_) {
      // 证据保存失败不应阻断导入流程。
    }
  }

  /// 读取导入任务的菜谱草稿（IMAGE-002 多草稿）。
  ///
  /// [recipeId] 为空时返回任务主草稿（`resultRecipeId`）；指定时校验该草稿
  /// 属于任务的草稿集合（主草稿 + 附加草稿）后再返回。
  Future<Recipe> getImportDraft(String taskId, {String? recipeId}) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview &&
        task.status != ImportTaskStatus.completed) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前导入任务没有可查看的菜谱。',
      );
    }
    if (recipeId == null || recipeId.trim().isEmpty) {
      return _loadDraft(task, includeDeleted: false);
    }
    final normalized = recipeId.trim();
    if (!task.allResultRecipeIds.contains(normalized)) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '该菜谱不属于当前导入任务。',
      );
    }
    return _loadDraftById(task, normalized, includeDeleted: false);
  }

  /// 确认导入任务的菜谱草稿（IMAGE-002 多草稿）。
  ///
  /// - [recipeId] 为空时确认主草稿；指定时确认该草稿（须属于任务草稿集合）。
  /// - [confirmAll] 为 true 时发布任务关联的全部草稿后完成任务。
  /// - 只发布部分草稿时任务保持 `needsReview`，其余草稿可在确认页继续处理；
  ///   最后一个草稿发布后任务自动完成。
  Future<ImportDraftConfirmation> confirmImportDraft(
    String taskId, {
    String? recipeId,
    RecipeDraftInput? editedDraft,
    bool confirmAll = false,
  }) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以保存菜谱。',
      );
    }

    final available = task.allResultRecipeIds;
    if (available.isEmpty) throw _draftNotFound();
    final targets = confirmAll
        ? available
        : <String>[recipeId ?? task.resultRecipeId ?? available.first];

    final published = <Recipe>[];
    for (final id in targets) {
      if (!available.contains(id)) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.invalidTaskState,
          message: '该菜谱不属于当前导入任务。',
        );
      }
      var recipe = await _loadDraftById(task, id, includeDeleted: false);
      if (recipe.status != RecipeStatus.published) {
        // 编辑仅在确认单个草稿时传入（多草稿批量确认不携带编辑内容）。
        final source = (id == task.resultRecipeId && editedDraft != null)
            ? editedDraft
            : _inputFromRecipe(recipe);
        try {
          recipe = await recipes.updateRecipe(
            recipe.id,
            _publishedInput(source),
          );
        } on RecipeNotFoundException {
          throw _draftNotFound();
        } on RecipeLibraryValidationException catch (error) {
          throw AiRecipeBackendException(
            code: AiRecipeBackendErrorCode.invalidInput,
            message: error.message,
          );
        } on RecipeLibraryException {
          throw const AiRecipeBackendException(
            code: AiRecipeBackendErrorCode.storageUnavailable,
            message: '菜谱草稿暂时无法保存，请稍后重试。',
          );
        }
      }
      published.add(recipe);
    }

    // 全部草稿已发布（或批量确认）时完成任务；否则保持 needsReview。
    final allPublished = available.every(
      (id) => published.any((recipe) => recipe.id == id),
    );
    final ImportTask completed;
    if (confirmAll || allPublished) {
      completed = await _changeTask(() async {
        return CompleteImportTask(
          repository: _importTaskRepository,
          clock: _clock,
        )(task.id);
      });
    } else {
      completed = task;
    }
    return ImportDraftConfirmation(task: completed, recipe: published.first);
  }

  /// 使用会话内保存的原文重新生成待确认草稿。
  ///
  /// 只接受 `needsReview` 任务；复用原文重新调用 LLM 生成并安全替换旧草稿。
  /// 失败时任务保持 `needsReview`、旧草稿保留，返回稳定脱敏错误。
  /// 会话原文证据在 App 重启后丢失，页面应据此禁用“重新生成”。
  Future<ImportTask> regenerateImportDraft(
    String taskId, {
    required ImportContent content,
  }) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以重新生成。',
      );
    }
    try {
      final session = await access.loadSession();
      final runner = await _runnerFactory.create(
        const ImportExecutionPlan(),
        userId: session.userId,
      );
      final result = await _trackInFlight(
        taskId,
        () => runner.regenerateWithContent(taskId, content),
      );
      await _persistImportEvidence(taskId, content);
      return result.task;
    } on AppCapabilityUnavailableException catch (error) {
      throw _mapImportCapabilityUnavailable(error);
    } on AppAccessStorageException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '应用会话或导入设置暂时无法读取，请稍后重试。',
      );
    } on ImportTaskRunnerFactoryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: error.message,
      );
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on ImportPipelineException catch (error) {
      throw AiRecipeBackendException(
        code: _mapPipelineCode(error.code),
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '重新生成失败，请稍后重试。',
      );
    }
  }

  Future<ImportTask> discardImportDraft(String taskId) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以放弃草稿。',
      );
    }
    final recipe = await _loadDraft(task, includeDeleted: true);
    if (recipe.deletedAt == null) {
      try {
        await recipes.softDeleteRecipe(recipe.id);
      } on RecipeNotFoundException {
        throw _draftNotFound();
      } on RecipeLibraryException {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.storageUnavailable,
          message: '菜谱草稿暂时无法移入回收站，请稍后重试。',
        );
      }
    }
    return cancelImportTask(task.id);
  }

  /// 从待确认任务中删除指定草稿（IMAGE-002 多草稿管理）。
  ///
  /// - 只接受 `needsReview` 任务；被删草稿必须属于任务的草稿集合。
  /// - 草稿移入回收站（软删除），可在回收站恢复。
  /// - 删除全部草稿时任务进入"已取消"，不保留空任务；只删除部分草稿时
  ///   任务保持 `needsReview`，若删除的是主草稿，剩余草稿中的第一份
  ///   自动提升为主草稿。
  Future<ImportTask> deleteImportDrafts(
    String taskId,
    Set<String> recipeIds,
  ) async {
    final task = await getImportTask(taskId);
    if (task.status != ImportTaskStatus.needsReview) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '只有待确认的导入任务可以删除草稿。',
      );
    }
    final ids = recipeIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return task;
    final available = task.allResultRecipeIds;
    for (final id in ids) {
      if (!available.contains(id)) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.invalidTaskState,
          message: '该菜谱不属于当前导入任务。',
        );
      }
    }

    // 先把被删草稿移入回收站（软删除）；失败时中止并保持任务不变。
    for (final id in ids) {
      try {
        final recipe = await _loadDraftById(task, id, includeDeleted: true);
        if (recipe.deletedAt == null) {
          await recipes.softDeleteRecipe(recipe.id);
        }
      } on RecipeNotFoundException {
        throw _draftNotFound();
      } on RecipeLibraryException {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.storageUnavailable,
          message: '菜谱草稿暂时无法移入回收站，请稍后重试。',
        );
      }
    }

    final remaining = available.where((id) => !ids.contains(id)).toList();
    if (remaining.isEmpty) {
      // 全部草稿已删除：直接取消任务，不保留空任务。
      return _changeTask(() async {
        return CancelImportTask(
          repository: _importTaskRepository,
          clock: _clock,
        )(task.id);
      });
    }
    // 剩余草稿重排：第一份提升为主草稿，其余保持附加。
    return _changeTask(() async {
      return ReassignImportTaskRecipe(
        repository: _importTaskRepository,
        clock: _clock,
      )(
        task.id,
        recipeId: remaining.first,
        additionalRecipeIds: remaining.skip(1).toList(growable: false),
      );
    });
  }

  LocalOcrModelUseCases _requireLocalOcrModelUseCases() {
    final useCases = localOcrModels;
    if (useCases == null) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.componentNotInstalled,
        message: 'Local OCR model management is not available.',
      );
    }
    return useCases;
  }

  static AiRecipeBackendException _mapOcrModelPackageException(
    OcrModelPackageException error,
  ) {
    final code = switch (error.kind) {
      OcrModelPackageErrorKind.incompatiblePlatform ||
      OcrModelPackageErrorKind.incompatibleAppVersion =>
        AiRecipeBackendErrorCode.componentIncompatible,
      OcrModelPackageErrorKind.invalidPackage =>
        AiRecipeBackendErrorCode.invalidInput,
      OcrModelPackageErrorKind.insufficientStorage =>
        AiRecipeBackendErrorCode.insufficientStorage,
      OcrModelPackageErrorKind.cancelled =>
        AiRecipeBackendErrorCode.operationCancelled,
      OcrModelPackageErrorKind.storageUnavailable =>
        AiRecipeBackendErrorCode.storageUnavailable,
      _ => AiRecipeBackendErrorCode.componentInstallationFailed,
    };
    return AiRecipeBackendException(code: code, message: error.message);
  }

  Future<T> _onboardingOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on OnboardingStorageException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: 'Onboarding state is temporarily unavailable.',
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: 'Onboarding state is temporarily unavailable.',
      );
    }
  }

  Future<T> _accessOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AppAccessValidationException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on AppCapabilityUnavailableException {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: 'The requested capability is unavailable.',
      );
    } on AppAccessStorageException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: 'Session data is temporarily unavailable.',
      );
    } on AppAccessEvaluationException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: 'Capabilities could not be evaluated.',
      );
    }
  }

  Future<T> _recipeOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on RecipeNotFoundException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.recipeNotFound,
        message: error.message,
      );
    } on RecipeCategoryNotFoundException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.categoryNotFound,
        message: error.message,
      );
    } on RecipeLibraryValidationException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on RecipeLibraryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: error.message,
      );
    }
  }

  Future<T> _llmSettingsOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on LlmSettingsException catch (error) {
      final code = switch (error.code) {
        LlmSettingsErrorCode.invalidInput =>
          AiRecipeBackendErrorCode.invalidInput,
        LlmSettingsErrorCode.storageUnavailable =>
          AiRecipeBackendErrorCode.storageUnavailable,
        LlmSettingsErrorCode.unauthorized =>
          AiRecipeBackendErrorCode.authenticationFailed,
        LlmSettingsErrorCode.rateLimited =>
          AiRecipeBackendErrorCode.rateLimited,
        LlmSettingsErrorCode.timeout => AiRecipeBackendErrorCode.timeout,
        LlmSettingsErrorCode.cancelled =>
          AiRecipeBackendErrorCode.operationCancelled,
        LlmSettingsErrorCode.networkUnavailable =>
          AiRecipeBackendErrorCode.networkUnavailable,
        LlmSettingsErrorCode.serverUnavailable ||
        LlmSettingsErrorCode.notFound =>
          AiRecipeBackendErrorCode.providerUnavailable,
        LlmSettingsErrorCode.invalidResponse =>
          AiRecipeBackendErrorCode.invalidProviderResponse,
        LlmSettingsErrorCode.operationFailed =>
          AiRecipeBackendErrorCode.operationFailed,
      };
      throw AiRecipeBackendException(code: code, message: error.message);
    }
  }

  static AiRecipeBackendException _mapImportCapabilityUnavailable(
    AppCapabilityUnavailableException error,
  ) {
    if (error.capability == AppCapability.customLlm) {
      final message = switch (error.reason) {
        AppCapabilityReason.providerNotConfigured =>
          '请先在 LLM 设置中配置并保存可用的自有 AI 服务。',
        AppCapabilityReason.serviceUnavailable =>
          '自有 AI 服务配置暂时无法读取，请检查 LLM 设置后重试。',
        AppCapabilityReason.offline => '当前网络不可用，请检查网络与 LLM 设置后重试。',
        _ => '自有 AI 服务当前不可用，请检查 LLM 设置后重试。',
      };
      return AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: message,
      );
    }
    if (error.capability == AppCapability.localOcr) {
      final message = error.reason == AppCapabilityReason.componentNotInstalled
          ? '请先在 OCR 设置中安装并启用本地 OCR 模型。'
          : '本地 OCR 当前不可用，请检查 OCR 设置后重试。';
      return AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: message,
      );
    }
    return const AiRecipeBackendException(
      code: AiRecipeBackendErrorCode.providerRouteUnavailable,
      message: '导入能力当前不可用，请检查相关设置后重试。',
    );
  }

  /// 把重新生成流水线错误码映射为 Facade 稳定错误码。
  static AiRecipeBackendErrorCode _mapPipelineCode(ImportTaskErrorCode code) {
    return switch (code) {
      ImportTaskErrorCode.cancelled => AiRecipeBackendErrorCode.operationCancelled,
      ImportTaskErrorCode.llmFailed ||
      ImportTaskErrorCode.networkUnavailable ||
      ImportTaskErrorCode.timeout => AiRecipeBackendErrorCode.providerRouteUnavailable,
      ImportTaskErrorCode.schemaInvalid ||
      ImportTaskErrorCode.extractionFailed ||
      ImportTaskErrorCode.ocrFailed ||
      ImportTaskErrorCode.asrFailed ||
      ImportTaskErrorCode.invalidUrl ||
      ImportTaskErrorCode.unsupportedPlatform ||
      ImportTaskErrorCode.contentUnavailable ||
      ImportTaskErrorCode.authorizationRequired => AiRecipeBackendErrorCode.invalidInput,
      ImportTaskErrorCode.storageFailure => AiRecipeBackendErrorCode.storageUnavailable,
      ImportTaskErrorCode.interrupted ||
      ImportTaskErrorCode.unknown ||
      ImportTaskErrorCode.fetchFailed => AiRecipeBackendErrorCode.operationFailed,
    };
  }

  /// 解析链接/图片导入的默认执行计划（识图引擎，IMAGE-001；ADR-0029）。
  ///
  /// 链接导入的图片一律走多模态转录（ADR-0029），不再自动启用本地 OCR：
  /// - 多模态配置就绪时优先 [ImportImageRecognitionRoute.multimodal]
  ///   （多图自动分组生成多草稿，IMAGE-002）；
  /// - 用户显式选择"仅 OCR"且本地 OCR 就绪时仍尊重该选择；
  /// - 多模态不可用且未显式选择 OCR 时回退纯文本路径。
  /// 能力快照不可读或设置读取失败时回退纯文本路径，避免无图内容被阻塞。
  Future<ImportExecutionPlan> _resolveDefaultPlan() async {
    try {
      final snapshot = await access.loadCapabilities();
      final ocrReady =
          snapshot.decisions[AppCapability.localOcr]?.isAvailable ?? false;
      final multimodalReady =
          snapshot.decisions[AppCapability.multimodalLlm]?.isAvailable ??
          false;
      final mode = await _imageRecognitionMode();
      final route = switch (mode) {
        ImageRecognitionMode.ocr => ocrReady
            ? ImportImageRecognitionRoute.ocr
            : ImportImageRecognitionRoute.disabled,
        ImageRecognitionMode.multimodalLlm => multimodalReady
            ? ImportImageRecognitionRoute.multimodal
            : ImportImageRecognitionRoute.disabled,
        // 自动（默认）：链接图片一律多模态；未配置时回退本地 OCR（显式仅 OCR
        // 之外的最后兜底）或纯文本。
        ImageRecognitionMode.auto => multimodalReady
            ? ImportImageRecognitionRoute.multimodal
            : ocrReady
            ? ImportImageRecognitionRoute.ocr
            : ImportImageRecognitionRoute.disabled,
      };
      return ImportExecutionPlan(
        llm: ImportLlmRoute.custom,
        imageRecognition: route,
      );
    } catch (_) {
      return const ImportExecutionPlan(llm: ImportLlmRoute.custom);
    }
  }

  /// 解析手动选图/拍照导入的执行计划（ADR-0029 修订，2026-08-07）。
  ///
  /// 与链接导入一致，手动图片默认**多模态转录优先**（视觉理解 + 文字转录，
  /// 直接识别图片内容），多模态未配置/不可用时回退本地 OCR；用户显式选择
  /// 某一路时尊重该选择。
  Future<ImportExecutionPlan> _resolveLocalImagePlan() async {
    try {
      final snapshot = await access.loadCapabilities();
      final ocrReady =
          snapshot.decisions[AppCapability.localOcr]?.isAvailable ?? false;
      final multimodalReady =
          snapshot.decisions[AppCapability.multimodalLlm]?.isAvailable ??
          false;
      final mode = await _imageRecognitionMode();
      final route = switch (mode) {
        ImageRecognitionMode.ocr => ocrReady
            ? ImportImageRecognitionRoute.ocr
            : (multimodalReady
                  ? ImportImageRecognitionRoute.multimodal
                  : ImportImageRecognitionRoute.disabled),
        ImageRecognitionMode.multimodalLlm => multimodalReady
            ? ImportImageRecognitionRoute.multimodal
            : (ocrReady
                  ? ImportImageRecognitionRoute.ocr
                  : ImportImageRecognitionRoute.disabled),
        // 自动（默认）：手动图片一律多模态转录；未配置时回退本地 OCR。
        ImageRecognitionMode.auto => multimodalReady
            ? ImportImageRecognitionRoute.multimodal
            : (ocrReady
                  ? ImportImageRecognitionRoute.ocr
                  : ImportImageRecognitionRoute.disabled),
      };
      return ImportExecutionPlan(
        llm: ImportLlmRoute.custom,
        imageRecognition: route,
      );
    } catch (_) {
      return const ImportExecutionPlan(llm: ImportLlmRoute.custom);
    }
  }

  Future<ImageRecognitionMode> _imageRecognitionMode() async {
    try {
      final settings = await localSettings.load();
      return settings.imageRecognitionMode;
    } catch (_) {
      return ImageRecognitionMode.auto;
    }
  }

  Future<void> _requirePlanCapabilities(ImportExecutionPlan plan) async {
    for (final capability in plan.requiredCapabilities) {
      await access.requireCapability(capability);
    }
  }

  Future<void> _requireLocalImageImportCapabilities(
    ImportExecutionPlan plan,
  ) async {
    try {
      await _requirePlanCapabilities(plan);
    } on AppCapabilityUnavailableException catch (error) {
      if (error.capability == AppCapability.localOcr &&
          error.reason == AppCapabilityReason.componentNotInstalled) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.componentNotInstalled,
          message: '请先在 OCR 设置中安装并启用本地 OCR 模型。',
        );
      }
      if (error.capability == AppCapability.localOcr) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.providerRouteUnavailable,
          message: '本地 OCR 当前不可用，请检查 OCR 设置后重试。',
        );
      }
      if (error.capability == AppCapability.multimodalLlm) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.providerRouteUnavailable,
          message: '图片识别 LLM 当前不可用，请在识图引擎中检查配置后重试。',
        );
      }
      if (error.capability == AppCapability.customLlm) {
        throw const AiRecipeBackendException(
          code: AiRecipeBackendErrorCode.providerRouteUnavailable,
          message: '请先在 LLM 设置中配置可用的自有 AI 服务。',
        );
      }
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.providerRouteUnavailable,
        message: '图片导入设置暂时无法读取，请稍后重试。',
      );
    } on AppAccessStorageException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '图片导入设置暂时无法读取，请稍后重试。',
      );
    } on AppAccessEvaluationException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.operationFailed,
        message: '图片导入能力暂时无法确认，请稍后重试。',
      );
    }
  }

  Future<Recipe> _loadDraft(
    ImportTask task, {
    required bool includeDeleted,
  }) async {
    final recipeId = task.resultRecipeId;
    if (recipeId == null || recipeId.trim().isEmpty) throw _draftNotFound();
    return _loadDraftById(task, recipeId, includeDeleted: includeDeleted);
  }

  /// 按草稿 ID 加载（多草稿任务的附加草稿也用此路径）。
  Future<Recipe> _loadDraftById(
    ImportTask task,
    String recipeId, {
    required bool includeDeleted,
  }) async {
    try {
      return await recipes.getRecipe(recipeId, includeDeleted: includeDeleted);
    } on RecipeNotFoundException {
      throw _draftNotFound();
    } on RecipeLibraryException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '菜谱草稿暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<T> _localBusinessOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on RecipeNotFoundException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.recipeNotFound,
        message: error.message,
      );
    } on RecipeCategoryNotFoundException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.categoryNotFound,
        message: error.message,
      );
    } on RecipeLibraryValidationException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on RecipeLibraryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: error.message,
      );
    } on ArgumentError catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message?.toString() ?? 'Invalid input.',
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: 'Local data is temporarily unavailable.',
      );
    }
  }

  Future<T> _cookingOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on CookingSessionNotFoundException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.cookingSessionNotFound,
        message: 'Cooking session was not found.',
      );
    } on CookingTimerNotFoundException {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.cookingTimerNotFound,
        message: 'Cooking timer was not found.',
      );
    } on CookingValidationException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on RecipeNotFoundException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.recipeNotFound,
        message: error.message,
      );
    } on RecipeLibraryValidationException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: error.message,
      );
    } on RecipeLibraryException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: error.message,
      );
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: 'Cooking data is temporarily unavailable.',
      );
    }
  }

  Future<ImportTask> _changeTask(
    Future<ImportTask> Function() operation,
  ) async {
    try {
      return await operation();
    } on ImportTaskNotFoundException {
      throw _taskNotFound();
    } on ImportTaskTransitionException catch (error) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: error.message,
      );
    } on AiRecipeBackendException {
      rethrow;
    } catch (_) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.storageUnavailable,
        message: '导入任务暂时无法更新，请稍后重试。',
      );
    }
  }

  static RecipeDraftInput _inputFromRecipe(Recipe recipe) {
    return RecipeDraftInput(
      title: recipe.title,
      description: recipe.description,
      coverImage: recipe.coverImage,
      images: recipe.images,
      servings: recipe.servings,
      prepTimeMinutes: recipe.prepTimeMinutes,
      cookTimeMinutes: recipe.cookTimeMinutes,
      totalTimeMinutes: recipe.totalTimeMinutes,
      difficulty: recipe.difficulty,
      notes: recipe.notes,
      favorite: recipe.favorite,
      status: recipe.status,
      ingredients: recipe.ingredients
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
      steps: recipe.steps
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
      categoryIds: recipe.categoryIds,
      tags: recipe.tags,
    );
  }

  static RecipeDraftInput _publishedInput(RecipeDraftInput input) {
    return RecipeDraftInput(
      title: input.title,
      description: input.description,
      coverImage: input.coverImage,
      images: input.images,
      servings: input.servings,
      prepTimeMinutes: input.prepTimeMinutes,
      cookTimeMinutes: input.cookTimeMinutes,
      totalTimeMinutes: input.totalTimeMinutes,
      difficulty: input.difficulty,
      notes: input.notes,
      favorite: input.favorite,
      status: RecipeStatus.published,
      ingredients: input.ingredients,
      steps: input.steps,
      categoryIds: input.categoryIds,
      tags: input.tags,
    );
  }

  static String _requireId(String id, String fieldName) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidInput,
        message: '$fieldName 不能为空。',
      );
    }
    return normalized;
  }

  static AiRecipeBackendException _taskNotFound() {
    return const AiRecipeBackendException(
      code: AiRecipeBackendErrorCode.importTaskNotFound,
      message: '没有找到对应的导入任务。',
    );
  }

  static AiRecipeBackendException _draftNotFound() {
    return const AiRecipeBackendException(
      code: AiRecipeBackendErrorCode.importDraftNotFound,
      message: '没有找到对应的菜谱草稿。',
    );
  }
}
