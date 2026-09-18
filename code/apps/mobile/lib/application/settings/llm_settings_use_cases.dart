import '../../data/llm_config_repository.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_models.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/llm_provider_type.dart';
import '../importing/recipe_generation_prompt.dart';

typedef LlmSettingsIdGenerator = String Function();
typedef LlmSettingsProviderBuilder = LlmProvider Function(LlmProviderType type);

enum LlmSettingsErrorCode {
  invalidInput,
  storageUnavailable,
  unauthorized,
  notFound,
  rateLimited,
  timeout,
  cancelled,
  serverUnavailable,
  invalidResponse,
  networkUnavailable,
  operationFailed,
}

class LlmSettingsException implements Exception {
  const LlmSettingsException({required this.code, required this.message});

  final LlmSettingsErrorCode code;
  final String message;

  @override
  String toString() => 'LlmSettingsException(${code.name}): $message';
}

class LlmSettingsSnapshot {
  const LlmSettingsSnapshot({
    required this.configuration,
    required this.hasStoredApiKey,
  });

  final LlmConnectionConfig? configuration;
  final bool hasStoredApiKey;
}

/// 「测试结构化生成」结果（BUG-008 诊断辅助）：记录耗时、生成文本与
/// 实际生效的推理模式，用于判断"最终结构化生成超时"是 LLM 服务本身慢、
/// 深度思考开关（PERF-001）还是别处问题。
class LlmStructuredGenerationResult {
  const LlmStructuredGenerationResult({
    required this.elapsedMs,
    required this.text,
    this.reasoningMode,
  });

  /// 从发出请求到拿到完整响应的耗时（毫秒）。
  final int elapsedMs;
  final String text;

  /// 本次测试实际生效的推理模式（fast/deep）。null 表示交给 Provider 默认
  /// 策略；deep 时实际导入会发送 `reasoning_effort: high` 等深度思考参数，
  /// 生成耗时可能成倍增长——测试与导入必须用同一模式对比。
  final LlmReasoningMode? reasoningMode;
}

class LlmSettingsInput {
  const LlmSettingsInput({
    this.id,
    required this.name,
    required this.providerType,
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.requestTimeout = const Duration(seconds: 120),
  });

  final String? id;
  final String name;
  final LlmProviderType providerType;
  final String baseUrl;
  final String model;

  /// `null` 或空白表示继续使用已保存的密钥，不会回填明文。
  final String? apiKey;
  final Duration requestTimeout;
}

class LlmSettingsUseCases {
  const LlmSettingsUseCases({
    required LlmConfigRepository repository,
    required LlmSettingsProviderBuilder providerBuilder,
    required LlmSettingsIdGenerator idGenerator,
  }) : _repository = repository,
       _providerBuilder = providerBuilder,
       _idGenerator = idGenerator;

  final LlmConfigRepository _repository;
  final LlmSettingsProviderBuilder _providerBuilder;
  final LlmSettingsIdGenerator _idGenerator;

  Future<LlmSettingsSnapshot> loadConfiguration() async {
    try {
      final configuration = await _repository.load();
      if (configuration == null) {
        return const LlmSettingsSnapshot(
          configuration: null,
          hasStoredApiKey: false,
        );
      }
      final apiKey = await _repository.readApiKey(configuration.secretRef);
      return LlmSettingsSnapshot(
        configuration: configuration,
        hasStoredApiKey: apiKey.trim().isNotEmpty,
      );
    } on FormatException {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: '已保存的 LLM 配置无法读取，请重新配置。',
      );
    } on LlmSettingsException {
      rethrow;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: 'LLM 配置暂时无法读取，请稍后重试。',
      );
    }
  }

  Future<LlmSettingsSnapshot> saveConfiguration(LlmSettingsInput input) async {
    final existing = await _loadStoredConfiguration();
    final configuration = _buildConfiguration(input, existing: existing);
    final normalizedKey = _normalizedOptionalKey(input.apiKey);
    try {
      await _repository.save(configuration, apiKey: normalizedKey);
      final hasStoredApiKey = normalizedKey != null
          ? normalizedKey.isNotEmpty
          : await _hasStoredApiKey(configuration.secretRef);
      return LlmSettingsSnapshot(
        configuration: configuration,
        hasStoredApiKey: hasStoredApiKey,
      );
    } on LlmSettingsException {
      rethrow;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: 'LLM 配置暂时无法保存，请稍后重试。',
      );
    }
  }

  Future<void> testConnection(
    LlmSettingsInput input, {
    LlmCancellationToken? cancellationToken,
  }) async {
    final existing = await _loadStoredConfiguration();
    final configuration = _buildConfiguration(input, existing: existing);
    final apiKey = await _resolveApiKey(input, existing);

    try {
      await _providerBuilder(configuration.providerType).testConnection(
        config: configuration,
        apiKey: apiKey,
        cancellationToken: cancellationToken,
      );
    } on LlmProviderException catch (error) {
      throw _mapProviderException(error);
    } on LlmSettingsException {
      rethrow;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.operationFailed,
        message: '连接测试失败，请检查配置后重试。',
      );
    }
  }

  /// 「测试结构化生成」：输入任意文本，走与真实导入完全相同的结构化生成
  /// prompt 与 JSON Schema，返回耗时与生成文本（BUG-008 诊断辅助）。
  ///
  /// 用于确认"最终结构化生成超时"到底是 LLM 服务本身响应慢，
  /// 还是图片/文本预处理等其他环节引入的延迟。
  Future<LlmStructuredGenerationResult> testStructuredGeneration(
    LlmSettingsInput input, {
    required String sourceText,
    LlmCancellationToken? cancellationToken,
  }) async {
    final normalizedSource = sourceText.trim();
    if (normalizedSource.isEmpty) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.invalidInput,
        message: '请输入要测试结构化的文本。',
      );
    }
    final existing = await _loadStoredConfiguration();
    final configuration = _buildConfiguration(input, existing: existing);
    final apiKey = await _resolveApiKey(input, existing);

    // 复用真实结构化生成链路：把用户文本作为正文片段，走同一 prompt 与 Schema。
    // 推理模式必须与实际导入一致（跟随已保存配置），否则深度思考配置
    // （PERF-001）会让测试显示 fast 的假快，掩盖实际导入的慢。
    final content = ImportContent(
      source: ImportSourceLink(
        sourceUrl: 'https://llm-test.local/structured',
        normalizedUrl: 'https://llm-test.local/structured',
        platform: ImportSourcePlatform.web,
      ),
      resolvedUrl: 'https://llm-test.local/structured',
      contentType: ImportContentType.article,
      capturedAt: DateTime.now().toUtc(),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: normalizedSource,
          order: 0,
        ),
      ],
    );
    final prompt = const RecipeGenerationPromptBuilder().build(
      content,
      reasoningMode: existing?.reasoningMode,
    );

    final startedAt = DateTime.now();
    try {
      final result = await _providerBuilder(
        configuration.providerType,
      ).generate(
        config: configuration,
        apiKey: apiKey,
        request: prompt.request,
        cancellationToken: cancellationToken,
      );
      return LlmStructuredGenerationResult(
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        text: result.text,
        // 回传实际生效的推理模式，便于页面诊断"测试快、导入慢"是否源于深度思考。
        reasoningMode: prompt.request.reasoningMode,
      );
    } on LlmProviderException catch (error) {
      throw _mapProviderException(error);
    } on LlmSettingsException {
      rethrow;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.operationFailed,
        message: '结构化生成测试失败，请检查配置后重试。',
      );
    }
  }

  Future<LlmSettingsSnapshot> clearStoredApiKey() async {
    final existing = await _loadStoredConfiguration();
    if (existing == null) {
      return const LlmSettingsSnapshot(
        configuration: null,
        hasStoredApiKey: false,
      );
    }
    try {
      await _repository.clearApiKey(existing.secretRef);
      return LlmSettingsSnapshot(
        configuration: existing,
        hasStoredApiKey: false,
      );
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: 'API Key 暂时无法清除，请稍后重试。',
      );
    }
  }

  /// 解析本次连接/生成测试实际使用的 API Key：优先表单新输入，
  /// 否则回退到已保存密钥。
  Future<String> _resolveApiKey(
    LlmSettingsInput input,
    LlmConnectionConfig? existing,
  ) async {
    final enteredKey = _normalizedOptionalKey(input.apiKey);
    String apiKey = enteredKey ?? '';
    if (apiKey.isEmpty && existing != null) {
      try {
        apiKey = await _repository.readApiKey(existing.secretRef);
      } catch (_) {
        throw const LlmSettingsException(
          code: LlmSettingsErrorCode.storageUnavailable,
          message: '已保存的 API Key 暂时无法读取，请重新输入。',
        );
      }
    }
    return apiKey;
  }

  Future<LlmConnectionConfig?> _loadStoredConfiguration() async {
    try {
      return await _repository.load();
    } on FormatException {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: '已保存的 LLM 配置无法读取，请重新配置。',
      );
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: 'LLM 配置暂时无法读取，请稍后重试。',
      );
    }
  }

  LlmConnectionConfig _buildConfiguration(
    LlmSettingsInput input, {
    required LlmConnectionConfig? existing,
  }) {
    try {
      final requestedId = input.id?.trim();
      final id = requestedId != null && requestedId.isNotEmpty
          ? requestedId
          : existing?.id ?? _nextId();
      final secretRef = existing != null && existing.id == id
          ? existing.secretRef
          : 'llm-api-key-$id';
      return LlmConnectionConfig(
        id: id,
        name: input.name.trim(),
        providerType: input.providerType,
        baseUrl: input.baseUrl,
        secretRef: secretRef,
        model: input.model.trim(),
        requestTimeout: input.requestTimeout,
        // 推理模式无设置页入口（PERF-001）：必须继承已保存配置的值，
        // 否则测试/保存会静默退化为 fast，与实际导入（跟随存储配置）不一致，
        // 导致"测试 30 秒、实际 120 秒超时"的假象。
        reasoningMode: existing?.reasoningMode ?? LlmReasoningMode.fast,
      );
    } on LlmSettingsException {
      rethrow;
    } on FormatException catch (error) {
      throw LlmSettingsException(
        code: LlmSettingsErrorCode.invalidInput,
        message: error.message.toString(),
      );
    } on ArgumentError catch (error) {
      throw LlmSettingsException(
        code: LlmSettingsErrorCode.invalidInput,
        message: error.message.toString(),
      );
    }
  }

  String _nextId() {
    try {
      final id = _idGenerator().trim();
      if (id.isEmpty) throw const FormatException('配置 ID 不能为空');
      return id;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.operationFailed,
        message: '暂时无法创建 LLM 配置，请稍后重试。',
      );
    }
  }

  Future<bool> _hasStoredApiKey(String secretRef) async {
    try {
      return (await _repository.readApiKey(secretRef)).trim().isNotEmpty;
    } catch (_) {
      throw const LlmSettingsException(
        code: LlmSettingsErrorCode.storageUnavailable,
        message: 'API Key 状态暂时无法读取，请稍后重试。',
      );
    }
  }

  static String? _normalizedOptionalKey(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static LlmSettingsException _mapProviderException(
    LlmProviderException error,
  ) {
    final code = switch (error.kind) {
      LlmProviderErrorKind.invalidConfiguration ||
      LlmProviderErrorKind.badRequest ||
      LlmProviderErrorKind.methodNotAllowed ||
      LlmProviderErrorKind.payloadTooLarge ||
      LlmProviderErrorKind.unsupportedMediaType =>
        LlmSettingsErrorCode.invalidInput,
      LlmProviderErrorKind.unauthorized => LlmSettingsErrorCode.unauthorized,
      LlmProviderErrorKind.notFound => LlmSettingsErrorCode.notFound,
      LlmProviderErrorKind.rateLimited => LlmSettingsErrorCode.rateLimited,
      LlmProviderErrorKind.timeout ||
      LlmProviderErrorKind.providerGatewayTimeout ||
      LlmProviderErrorKind.firstByteDeadline ||
      LlmProviderErrorKind.bodyIdleDeadline ||
      LlmProviderErrorKind.streamNotTerminated =>
        LlmSettingsErrorCode.timeout,
      LlmProviderErrorKind.cancelled => LlmSettingsErrorCode.cancelled,
      LlmProviderErrorKind.server ||
      LlmProviderErrorKind.modelBusy => LlmSettingsErrorCode.serverUnavailable,
      LlmProviderErrorKind.invalidResponse ||
      LlmProviderErrorKind.imageNotObserved ||
      LlmProviderErrorKind.textCapabilityUnconfirmed =>
        LlmSettingsErrorCode.invalidResponse,
      LlmProviderErrorKind.network => LlmSettingsErrorCode.networkUnavailable,
      LlmProviderErrorKind.unknown => LlmSettingsErrorCode.operationFailed,
    };
    final message = switch (code) {
      LlmSettingsErrorCode.invalidInput => 'LLM 配置或请求参数无效，请检查地址、协议和模型。',
      LlmSettingsErrorCode.unauthorized => '身份验证失败，请检查 API Key。',
      LlmSettingsErrorCode.notFound => '没有找到对应的模型或接口地址。',
      LlmSettingsErrorCode.rateLimited => '请求过于频繁或额度不足，请稍后重试。',
      LlmSettingsErrorCode.timeout => '连接测试超时，请检查网络和服务状态。',
      LlmSettingsErrorCode.cancelled => '连接测试已取消。',
      LlmSettingsErrorCode.serverUnavailable => 'LLM 服务暂时不可用，请稍后重试。',
      LlmSettingsErrorCode.invalidResponse => 'LLM 服务返回了无法识别的响应。',
      LlmSettingsErrorCode.networkUnavailable => '无法连接 LLM 服务，请检查网络和 API 地址。',
      _ => '连接测试失败，请稍后重试。',
    };
    return LlmSettingsException(code: code, message: message);
  }
}
