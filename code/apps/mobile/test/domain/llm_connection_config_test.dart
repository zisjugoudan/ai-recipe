import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LlmConnectionConfig buildConfig(String baseUrl) => LlmConnectionConfig(
    id: 'config-1',
    name: '测试配置',
    providerType: LlmProviderType.openAiCompatible,
    baseUrl: baseUrl,
    secretRef: 'secret-1',
    model: 'test-model',
  );

  test('normalizes trailing slashes and keeps API key out of JSON', () {
    final config = buildConfig(' https://example.com/v1/// ');

    expect(config.baseUrl, 'https://example.com/v1');
    expect(config.toJson().containsKey('apiKey'), isFalse);
    expect(config.toJson()['secretRef'], 'secret-1');
  });

  test('round trips the non-sensitive configuration', () {
    final original = buildConfig('http://192.168.1.2:11434/v1');

    final restored = LlmConnectionConfig.fromJson(original.toJson());

    expect(restored.baseUrl, original.baseUrl);
    expect(restored.providerType, original.providerType);
    expect(restored.requestTimeout, original.requestTimeout);
    expect(restored.usesCleartextHttp, isTrue);
  });

  test('rejects unsupported schemes', () {
    expect(
      () => buildConfig('ftp://example.com/v1'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects embedded credentials', () {
    expect(
      () => buildConfig('https://user:password@example.com/v1'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects query strings and fragments in a base URL', () {
    expect(
      () => buildConfig('https://example.com/v1?token=unsafe'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => buildConfig('https://example.com/v1#fragment'),
      throwsA(isA<FormatException>()),
    );
  });
}
