import 'dart:convert';

import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_models.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import 'llm_response_helpers.dart';
import 'llm_transport.dart';

class OpenAiCompatibleProvider extends LlmProvider {
  const OpenAiCompatibleProvider(this.transport);

  final LlmTransport transport;

  @override
  LlmReasoningCapability get reasoningCapability => const LlmReasoningCapability(
    supportsReasoningControl: true,
    supportedModes: <LlmReasoningMode>{
      LlmReasoningMode.fast,
      LlmReasoningMode.deep,
    },
    defaultMode: LlmReasoningMode.fast,
  );

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) async {
    if (request.messages.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidConfiguration,
        '消息不能为空',
      );
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final payload = <String, Object?>{
      'model': config.model,
      'messages': request.messages
          .map(
            (message) => <String, String>{
              'role': message.role.name,
              'content': message.content,
            },
          )
          .toList(growable: false),
      if (request.temperature != null) 'temperature': request.temperature,
      // 推理深度映射：request 优先，其次跟随用户配置；仅 deep 时发送
      // reasoning_effort，避免向不支持的服务发送未知字段（《解决方案.md》）。
      if (_reasoningEffort(config, request) case final effort?)
        'reasoning_effort': effort,
    };

    final response = await transport.send(
      LlmHttpRequest(
        uri: _endpoint(config.baseUrl),
        headers: headers,
        body: jsonEncode(payload),
        timeout: config.requestTimeout,
      ),
      cancellationToken: cancellationToken,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throwForStatus(response.statusCode, response.body);
    }

    final decoded = decodeJsonObject(response.body);
    final choices = decoded['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应缺少 choices',
      );
    }
    final first = choices.first;
    if (first is! Map<String, Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应中的 choice 无效',
      );
    }
    if (first['finish_reason'] == 'length') {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应因长度限制被截断',
      );
    }
    final message = first['message'];
    if (message is! Map<String, Object?> || message['content'] is! String) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应缺少 message.content',
      );
    }
    final content = (message['content'] as String).trim();
    if (content.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应内容为空',
      );
    }
    return LlmGenerationResult(text: content);
  }

  Uri _endpoint(String baseUrl) {
    if (baseUrl.endsWith('/chat/completions')) return Uri.parse(baseUrl);
    return Uri.parse('$baseUrl/chat/completions');
  }

  /// 计算 OpenAI-compatible 的 `reasoning_effort` 值。
  ///
  /// 仅当最终模式为 deep 时返回 `high`；fast 或未指定返回 null（不发送字段）。
  /// request 的 [LlmGenerationRequest.reasoningMode] 优先，其次跟随
  /// [LlmConnectionConfig.reasoningMode]，避免向不支持的服务发送未知参数。
  static String? _reasoningEffort(
    LlmConnectionConfig config,
    LlmGenerationRequest request,
  ) {
    final mode = request.reasoningMode ?? config.reasoningMode;
    return mode == LlmReasoningMode.deep ? 'high' : null;
  }
}
