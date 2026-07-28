import 'dart:convert';

import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_models.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import 'llm_response_helpers.dart';
import 'llm_transport.dart';

class GeminiProvider extends LlmProvider {
  const GeminiProvider(this.transport);

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

    final systemTexts = request.messages
        .where((message) => message.role == LlmMessageRole.system)
        .map((message) => message.content)
        .toList(growable: false);
    final contentMessages = request.messages
        .where((message) => message.role != LlmMessageRole.system)
        .map(
          (message) => <String, Object>{
            'role': message.role == LlmMessageRole.assistant ? 'model' : 'user',
            'parts': <Map<String, String>>[
              <String, String>{'text': message.content},
            ],
          },
        )
        .toList(growable: false);
    if (contentMessages.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidConfiguration,
        'Gemini 请求至少需要一条非 system 消息',
      );
    }

    final payload = <String, Object?>{
      if (systemTexts.isNotEmpty)
        'systemInstruction': <String, Object>{
          'parts': systemTexts
              .map((text) => <String, String>{'text': text})
              .toList(growable: false),
        },
      'contents': contentMessages,
      if (request.temperature != null)
        'generationConfig': <String, Object?>{
          'temperature': request.temperature,
        },
    };
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.trim().isNotEmpty) {
      headers['x-goog-api-key'] = apiKey.trim();
    }

    final response = await transport.send(
      LlmHttpRequest(
        uri: _endpoint(config.baseUrl, config.model),
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
    final candidates = decoded['candidates'];
    if (candidates is! List<Object?> || candidates.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 响应缺少 candidates',
      );
    }
    final first = candidates.first;
    if (first is! Map<String, Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini candidate 无效',
      );
    }
    final content = first['content'];
    if (content is! Map<String, Object?> ||
        content['parts'] is! List<Object?>) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 响应缺少 content.parts',
      );
    }
    final texts = (content['parts'] as List<Object?>)
        .whereType<Map<String, Object?>>()
        .map((part) => part['text'])
        .whereType<String>()
        .toList(growable: false);
    if (texts.isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        'Gemini 响应没有文本内容',
      );
    }
    return LlmGenerationResult(text: texts.join());
  }

  Uri _endpoint(String baseUrl, String model) {
    if (baseUrl.endsWith(':generateContent')) return Uri.parse(baseUrl);
    final normalizedModel = model.startsWith('models/')
        ? model.substring('models/'.length)
        : model;
    return Uri.parse(
      '$baseUrl/models/${Uri.encodeComponent(normalizedModel)}:generateContent',
    );
  }
}
