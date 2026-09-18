import 'llm_models.dart';
import 'llm_provider_type.dart';

class LlmConnectionConfig {
  LlmConnectionConfig({
    required this.id,
    required this.name,
    required this.providerType,
    required String baseUrl,
    required this.secretRef,
    required this.model,
    this.requestTimeout = const Duration(seconds: 120),
    // 深度思考开关（PERF-002，ADR-0031）：默认快速；旧配置缺失时回退 fast。
    LlmReasoningMode reasoningMode = LlmReasoningMode.fast,
  }) : baseUrl = normalizeAndValidateBaseUrl(baseUrl),
       reasoningMode = reasoningMode {
    if (id.trim().isEmpty) throw const FormatException('配置 ID 不能为空');
    if (name.trim().isEmpty) throw const FormatException('配置名称不能为空');
    if (secretRef.trim().isEmpty) throw const FormatException('密钥引用不能为空');
    if (model.trim().isEmpty) throw const FormatException('模型不能为空');
    if (requestTimeout <= Duration.zero) {
      throw const FormatException('请求超时必须大于 0');
    }
  }

  final String id;
  final String name;
  final LlmProviderType providerType;
  final String baseUrl;
  final String secretRef;
  final String model;
  final Duration requestTimeout;

  /// 推理深度：fast=快速（默认）/ deep=深度思考。最终结构化生成跟随该值。
  final LlmReasoningMode reasoningMode;

  bool get usesCleartextHttp => Uri.parse(baseUrl).scheme == 'http';

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'providerType': providerType.wireName,
    'baseUrl': baseUrl,
    'secretRef': secretRef,
    'model': model,
    'requestTimeoutMs': requestTimeout.inMilliseconds,
    'reasoningMode': reasoningMode.name,
  };

  factory LlmConnectionConfig.fromJson(Map<String, Object?> json) {
    return LlmConnectionConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      providerType: LlmProviderType.fromWireName(
        json['providerType'] as String,
      ),
      baseUrl: json['baseUrl'] as String,
      secretRef: json['secretRef'] as String,
      model: json['model'] as String,
      requestTimeout: Duration(milliseconds: json['requestTimeoutMs'] as int),
      reasoningMode: _parseReasoningMode(json['reasoningMode']),
    );
  }

  /// 兼容旧配置：字段缺失或取值非法时回退 fast。
  static LlmReasoningMode _parseReasoningMode(Object? value) {
    if (value is String) {
      for (final mode in LlmReasoningMode.values) {
        if (mode.name == value) return mode;
      }
    }
    return LlmReasoningMode.fast;
  }

  static String normalizeAndValidateBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('API 地址必须是完整的 HTTP 或 HTTPS URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('API 地址只支持 HTTP 或 HTTPS');
    }
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('API 地址不能包含用户名或密码');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw const FormatException('API Base URL 不能包含查询参数或片段');
    }

    var normalized = uri.toString();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
