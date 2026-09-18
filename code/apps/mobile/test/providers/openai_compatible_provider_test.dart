import 'dart:convert';

import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/providers/llm/llm_transport.dart';
import 'package:ai_recipe/providers/llm/openai_compatible_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_llm_transport.dart';

void main() {
  LlmConnectionConfig config({String baseUrl = 'https://example.com/v1'}) =>
      LlmConnectionConfig(
        id: 'openai-1',
        name: 'OpenAI compatible',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: baseUrl,
        secretRef: 'secret-openai',
        model: 'recipe-model',
      );

  const request = LlmGenerationRequest(
    messages: <LlmMessage>[
      LlmMessage(role: LlmMessageRole.system, content: 'Return JSON.'),
      LlmMessage(role: LlmMessageRole.user, content: 'Make soup.'),
    ],
    temperature: 0.2,
  );

  test('builds Chat Completions request and parses text', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '{"choices":[{"message":{"content":"recipe json"}}]}',
      ),
    );
    final provider = OpenAiCompatibleProvider(transport);

    final result = await provider.generate(
      config: config(),
      apiKey: 'test-key-not-real',
      request: request,
    );

    expect(result.text, 'recipe json');
    expect(
      transport.lastRequest!.uri.toString(),
      'https://example.com/v1/chat/completions',
    );
    expect(
      transport.lastRequest!.headers['Authorization'],
      'Bearer test-key-not-real',
    );
    final body =
        jsonDecode(transport.lastRequest!.body) as Map<String, dynamic>;
    expect(body['model'], 'recipe-model');
    expect((body['messages'] as List<dynamic>).length, 2);
    expect(body.containsKey('response_format'), isFalse);
  });

  test(
    'preserves a wrapped content string for downstream validation',
    () async {
      const wrapped = '<think>reasoning</think>\n```json\n{}\n```';
      final transport = FakeLlmTransport(
        response: LlmHttpResponse(
          statusCode: 200,
          body: jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'reasoning_content': 'must not be used as the final answer',
                  'content': wrapped,
                },
              },
            ],
          }),
        ),
      );

      final result = await OpenAiCompatibleProvider(
        transport,
      ).generate(config: config(), apiKey: '', request: request);

      expect(result.text, wrapped);
    },
  );
  test('does not send Authorization when key is empty', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '{"choices":[{"message":{"content":"ok"}}]}',
      ),
    );

    await OpenAiCompatibleProvider(
      transport,
    ).generate(config: config(), apiKey: '', request: request);

    expect(
      transport.lastRequest!.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test(
    'accepts a full chat completions endpoint without duplicating it',
    () async {
      final transport = FakeLlmTransport(
        response: const LlmHttpResponse(
          statusCode: 200,
          body: '{"choices":[{"message":{"content":"ok"}}]}',
        ),
      );

      await OpenAiCompatibleProvider(transport).generate(
        config: config(baseUrl: 'https://example.com/v1/chat/completions'),
        apiKey: '',
        request: request,
      );

      expect(
        transport.lastRequest!.uri.toString(),
        'https://example.com/v1/chat/completions',
      );
    },
  );

  for (final testCase in <(int, LlmProviderErrorKind)>[
    (401, LlmProviderErrorKind.unauthorized),
    (403, LlmProviderErrorKind.unauthorized),
    (404, LlmProviderErrorKind.notFound),
    (429, LlmProviderErrorKind.rateLimited),
    (500, LlmProviderErrorKind.server),
  ]) {
    test('maps HTTP ${testCase.$1} to ${testCase.$2.name}', () async {
      final transport = FakeLlmTransport(
        response: LlmHttpResponse(
          statusCode: testCase.$1,
          body: '{"error":{"message":"safe server message"}}',
        ),
      );

      expect(
        () => OpenAiCompatibleProvider(
          transport,
        ).generate(config: config(), apiKey: '', request: request),
        throwsA(
          isA<LlmProviderException>().having(
            (error) => error.kind,
            'kind',
            testCase.$2,
          ),
        ),
      );
    });
  }

  test('maps non-JSON and missing fields to invalidResponse', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '<html>bad</html>',
      ),
    );
    final provider = OpenAiCompatibleProvider(transport);

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

    transport.response = const LlmHttpResponse(statusCode: 200, body: '{}');
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

  test('maps length-truncated content to invalidResponse', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body:
            '{"choices":[{"finish_reason":"length","message":{"content":"{\\\"schemaVersion\\\":1"}}]}',
      ),
    );

    expect(
      () => OpenAiCompatibleProvider(
        transport,
      ).generate(config: config(), apiKey: '', request: request),
      throwsA(
        isA<LlmProviderException>().having(
          (error) => error.kind,
          'kind',
          LlmProviderErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('maps blank message content to invalidResponse', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '{"choices":[{"message":{"content":"   \\n  "}}]}',
      ),
    );

    expect(
      () => OpenAiCompatibleProvider(
        transport,
      ).generate(config: config(), apiKey: '', request: request),
      throwsA(
        isA<LlmProviderException>().having(
          (error) => error.kind,
          'kind',
          LlmProviderErrorKind.invalidResponse,
        ),
      ),
    );
  });
  test('honors a cancellation token before transport starts', () async {
    final transport = FakeLlmTransport(
      response: const LlmHttpResponse(
        statusCode: 200,
        body: '{"choices":[{"message":{"content":"ok"}}]}',
      ),
    );
    final token = LlmCancellationToken()..cancel();

    expect(
      () => OpenAiCompatibleProvider(transport).generate(
        config: config(),
        apiKey: '',
        request: request,
        cancellationToken: token,
      ),
      throwsA(
        isA<LlmProviderException>().having(
          (error) => error.kind,
          'kind',
          LlmProviderErrorKind.cancelled,
        ),
      ),
    );
  });
}
