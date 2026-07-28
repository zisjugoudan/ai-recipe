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
    final message = first['message'];
    if (message is! Map<String, Object?> || message['content'] is! String) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'OpenAI 兼容响应缺少 message.content',
      );
    }
    return LlmGenerationResult(text: message['content'] as String);
  }

  Uri _endpoint(String baseUrl) {
    if (baseUrl.endsWith('/chat/completions')) return Uri.parse(baseUrl);
    return Uri.parse('$baseUrl/chat/completions');
  }
}
