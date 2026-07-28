import 'dart:convert';

import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/providers/llm/gemini_provider.dart';
import 'package:ai_recipe/providers/llm/llm_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_llm_transport.dart';

void main() {
  LlmConnectionConfig config() => LlmConnectionConfig(
    id: 'gemini-1',
    name: 'Gemini',
    providerType: LlmProviderType.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    secretRef: 'secret-gemini',
    model: 'models/gemini-test',
  );

  const request = LlmGenerationRequest(
    messages: <LlmMessage>[
      LlmMessage(role: LlmMessageRole.system, content: 'Return JSON.'),
      LlmMessage(role: LlmMessageRole.user, content: 'Make soup.'),
      LlmMessage(role: LlmMessageRole.assistant, content: 'Draft.'),
    ],
    temperature: 0.1,
  );

  test('builds native generateContent request and joins text parts', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body:
            '{"candidates":[{"content":{"parts":[{"text":"recipe "},{"text":"json"}]}}]}',
      ),
    );

    final result = await GeminiProvider(
      transport,
    ).generate(config: config(), apiKey: 'test-key-not-real', request: request);

    expect(result.text, 'recipe json');
    expect(
      transport.lastRequest!.uri.toString(),
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent',
    );
    expect(
      transport.lastRequest!.headers['x-goog-api-key'],
      'test-key-not-real',
    );
    final body =
        jsonDecode(transport.lastRequest!.body) as Map<String, dynamic>;
    expect(body['systemInstruction'], isA<Map<String, dynamic>>());
    final contents = body['contents'] as List<dynamic>;
    expect(contents.length, 2);
    expect((contents.last as Map<String, dynamic>)['role'], 'model');
  });

  test('does not send x-goog-api-key when key is empty', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}',
      ),
    );

    await GeminiProvider(
      transport,
    ).generate(config: config(), apiKey: '', request: request);

    expect(
      transport.lastRequest!.headers.containsKey('x-goog-api-key'),
      isFalse,
    );
  });

  test('maps Gemini error JSON and invalid success shape', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 429,
        body: '{"error":{"message":"quota reached"}}',
      ),
    );
    final provider = GeminiProvider(transport);

    expect(
      () => provider.generate(config: config(), apiKey: '', request: request),
      throwsA(
        isA<LlmProviderException>().having(
          (error) => error.kind,
          'kind',
          LlmProviderErrorKind.rateLimited,
        ),
      ),
    );

    transport.response = const LlmHttpResponse(
      statusCode: 200,
      body: '{"candidates":[{"content":{"parts":[]}}]}',
    );
    expect(
      () => provider.generate(config: config(), apiKey: '', request: request),
      throwsA(
        isA<LlmProviderException>().having(
          (error) => error.kind,
          'kind',
          LlmProviderErrorKind.invalidResponse,
        ),
      ),
    );
  });
}
