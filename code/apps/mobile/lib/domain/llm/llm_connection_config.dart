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
  }) : baseUrl = normalizeAndValidateBaseUrl(baseUrl) {
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

  bool get usesCleartextHttp => Uri.parse(baseUrl).scheme == 'http';

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'providerType': providerType.wireName,
    'baseUrl': baseUrl,
    'secretRef': secretRef,
    'model': model,
    'requestTimeoutMs': requestTimeout.inMilliseconds,
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
    );
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
