import 'package:ai_recipe/application/settings/llm_settings_use_cases.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_exception.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryLlmConfigRepository repository;
  late _RecordingLlmProvider provider;
  late LlmSettingsUseCases useCases;

  const existingKey = 'stored-secret-key';
  final existing = LlmConnectionConfig(
    id: 'config-1',
    name: 'Local gateway',
    providerType: LlmProviderType.openAiCompatible,
    baseUrl: 'https://llm.example.com/v1',
    secretRef: 'llm-api-key-config-1',
    model: 'recipe-model',
  );

  LlmSettingsInput input({
    String? id = 'config-1',
    String name = 'Local gateway',
    LlmProviderType providerType = LlmProviderType.openAiCompatible,
    String baseUrl = 'https://llm.example.com/v1',
    String model = 'recipe-model',
    String? apiKey,
  }) => LlmSettingsInput(
    id: id,
    name: name,
    providerType: providerType,
    baseUrl: baseUrl,
    model: model,
    apiKey: apiKey,
  );

  setUp(() {
    repository = _MemoryLlmConfigRepository();
    provider = _RecordingLlmProvider();
    useCases = LlmSettingsUseCases(
      repository: repository,
      providerBuilder: (_) => provider,
      idGenerator: () => 'generated-config',
    );
  });

  test('load exposes key presence without exposing plaintext', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = existingKey;

    final snapshot = await useCases.loadConfiguration();

    expect(snapshot.configuration, same(existing));
    expect(snapshot.hasStoredApiKey, isTrue);
    expect(
      snapshot.configuration!.toJson().values,
      isNot(contains(existingKey)),
    );
  });

  test('load reports no stored key for blank secure-storage value', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = '   ';

    final snapshot = await useCases.loadConfiguration();

    expect(snapshot.hasStoredApiKey, isFalse);
  });

  test('save creates configuration and stores a normalized new key', () async {
    final snapshot = await useCases.saveConfiguration(
      input(id: null, apiKey: '  new-secret  '),
    );

    expect(snapshot.configuration!.id, 'generated-config');
    expect(snapshot.configuration!.secretRef, 'llm-api-key-generated-config');
    expect(snapshot.hasStoredApiKey, isTrue);
    expect(repository.configuration, same(snapshot.configuration));
    expect(repository.keys['llm-api-key-generated-config'], 'new-secret');
  });

  test('save with blank key preserves the previously stored key', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = existingKey;

    final snapshot = await useCases.saveConfiguration(input(apiKey: '  '));

    expect(snapshot.configuration!.secretRef, existing.secretRef);
    expect(snapshot.hasStoredApiKey, isTrue);
    expect(repository.keys[existing.secretRef], existingKey);
    expect(repository.lastSavedApiKey, isNull);
  });

  test('save preserves stored reasoning mode instead of resetting to fast',
      () async {
    // 推理模式无设置页入口（PERF-001）：保存不能把已配置的 deep 静默重置为
    // fast，否则实际导入的深度思考会被悄然关闭。
    repository.configuration = LlmConnectionConfig(
      id: 'config-1',
      name: 'Local gateway',
      providerType: LlmProviderType.openAiCompatible,
      baseUrl: 'https://llm.example.com/v1',
      secretRef: 'llm-api-key-config-1',
      model: 'recipe-model',
      reasoningMode: LlmReasoningMode.deep,
    );

    final snapshot = await useCases.saveConfiguration(input());

    expect(snapshot.configuration!.reasoningMode, LlmReasoningMode.deep);
  });

  test('clearStoredApiKey removes only the secret', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = existingKey;

    final snapshot = await useCases.clearStoredApiKey();

    expect(snapshot.configuration, same(existing));
    expect(snapshot.hasStoredApiKey, isFalse);
    expect(repository.keys.containsKey(existing.secretRef), isFalse);
  });

  test('testConnection prefers the key entered for this attempt', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = existingKey;

    await useCases.testConnection(input(apiKey: '  one-time-key  '));

    expect(provider.lastApiKey, 'one-time-key');
    expect(provider.lastConfig!.secretRef, existing.secretRef);
    expect(repository.readApiKeyCount, 0);
  });

  test('testConnection falls back to the saved key', () async {
    repository.configuration = existing;
    repository.keys[existing.secretRef] = existingKey;

    await useCases.testConnection(input());

    expect(provider.lastApiKey, existingKey);
    expect(repository.readApiKeyCount, 1);
  });

  for (final scenario
      in <({LlmProviderErrorKind kind, LlmSettingsErrorCode code})>[
        (
          kind: LlmProviderErrorKind.unauthorized,
          code: LlmSettingsErrorCode.unauthorized,
        ),
        (
          kind: LlmProviderErrorKind.timeout,
          code: LlmSettingsErrorCode.timeout,
        ),
        (
          kind: LlmProviderErrorKind.network,
          code: LlmSettingsErrorCode.networkUnavailable,
        ),
        (
          kind: LlmProviderErrorKind.rateLimited,
          code: LlmSettingsErrorCode.rateLimited,
        ),
        (
          kind: LlmProviderErrorKind.invalidResponse,
          code: LlmSettingsErrorCode.invalidResponse,
        ),
      ]) {
    test('maps ${scenario.kind.name} provider failures', () async {
      provider.error = LlmProviderException(
        scenario.kind,
        'provider detail with secret-token',
      );

      await expectLater(
        useCases.testConnection(input(apiKey: 'secret-token')),
        throwsA(
          isA<LlmSettingsException>()
              .having((error) => error.code, 'code', scenario.code)
              .having(
                (error) => error.message,
                'redacted message',
                isNot(contains('secret-token')),
              ),
        ),
      );
    });
  }

  test('invalid URL and blank model map to invalidInput', () async {
    await expectLater(
      useCases.saveConfiguration(input(baseUrl: 'not-a-url')),
      throwsA(
        isA<LlmSettingsException>().having(
          (error) => error.code,
          'code',
          LlmSettingsErrorCode.invalidInput,
        ),
      ),
    );
    await expectLater(
      useCases.testConnection(input(model: '   ')),
      throwsA(
        isA<LlmSettingsException>().having(
          (error) => error.code,
          'code',
          LlmSettingsErrorCode.invalidInput,
        ),
      ),
    );
  });

  test(
    'storage errors are mapped without leaking implementation details',
    () async {
      repository.loadError = StateError('disk path and secret-token');

      await expectLater(
        useCases.loadConfiguration(),
        throwsA(
          isA<LlmSettingsException>()
              .having(
                (error) => error.code,
                'code',
                LlmSettingsErrorCode.storageUnavailable,
              )
              .having(
                (error) => error.message,
                'redacted message',
                allOf(
                  isNot(contains('disk path')),
                  isNot(contains('secret-token')),
                ),
              ),
        ),
      );
    },
  );

  group('testStructuredGeneration', () {
    test('generates structured text and reports elapsed time', () async {
      repository.configuration = existing;
      repository.keys[existing.secretRef] = existingKey;

      final result = await useCases.testStructuredGeneration(
        input(),
        sourceText: '红烧肉。五花肉 500 克焯水，锅中放糖炒出糖色…',
      );

      expect(result.elapsedMs, greaterThanOrEqualTo(0));
      expect(result.text, 'OK');
      // 走真实结构化生成 prompt：必须带上系统 prompt 与用户文本。
      expect(provider.lastApiKey, existingKey);
      expect(provider.lastRequest, isNotNull);
      expect(provider.lastRequest!.messages, hasLength(2));
      expect(
        provider.lastRequest!.messages.first.role,
        LlmMessageRole.system,
      );
      expect(
        provider.lastRequest!.messages.last.content,
        contains('红烧肉'),
      );
    });

    test('inherits stored reasoning mode so test matches real import',
        () async {
      // 已保存配置为 deep（PERF-001）：测试必须与实际导入一样走深度思考，
      // 不能静默退化为 fast，否则会掩盖"测试 30 秒、实际 120 秒超时"的差异。
      repository.configuration = LlmConnectionConfig(
        id: 'config-1',
        name: 'Local gateway',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://llm.example.com/v1',
        secretRef: 'llm-api-key-config-1',
        model: 'recipe-model',
        reasoningMode: LlmReasoningMode.deep,
      );
      repository.keys['llm-api-key-config-1'] = existingKey;

      final result = await useCases.testStructuredGeneration(
        input(),
        sourceText: '红烧肉。五花肉 500 克…',
      );

      expect(result.reasoningMode, LlmReasoningMode.deep);
      expect(provider.lastRequest!.reasoningMode, LlmReasoningMode.deep);
    });

    test('rejects blank source text as invalid input', () async {
      await expectLater(
        useCases.testStructuredGeneration(input(), sourceText: '   '),
        throwsA(
          isA<LlmSettingsException>().having(
            (error) => error.code,
            'code',
            LlmSettingsErrorCode.invalidInput,
          ),
        ),
      );
    });

    test('maps provider timeout without leaking secrets', () async {
      repository.configuration = existing;
      repository.keys[existing.secretRef] = existingKey;
      provider.generateError = LlmProviderException(
        LlmProviderErrorKind.timeout,
        'provider detail with secret-token',
      );

      await expectLater(
        useCases.testStructuredGeneration(
          input(apiKey: 'secret-token'),
          sourceText: '红烧肉',
        ),
        throwsA(
          isA<LlmSettingsException>()
              .having(
                (error) => error.code,
                'code',
                LlmSettingsErrorCode.timeout,
              )
              .having(
                (error) => error.message,
                'redacted message',
                isNot(contains('secret-token')),
              ),
        ),
      );
    });
  });
}

class _MemoryLlmConfigRepository implements LlmConfigRepository {
  LlmConnectionConfig? configuration;
  final Map<String, String> keys = <String, String>{};
  Object? loadError;
  Object? saveError;
  Object? readError;
  Object? clearError;
  int readApiKeyCount = 0;
  String? lastSavedApiKey;

  @override
  Future<LlmConnectionConfig?> load() async {
    if (loadError case final error?) throw error;
    return configuration;
  }

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    if (saveError case final error?) throw error;
    configuration = config;
    lastSavedApiKey = apiKey;
    if (apiKey != null) keys[config.secretRef] = apiKey;
  }

  @override
  Future<String> readApiKey(String secretRef) async {
    readApiKeyCount += 1;
    if (readError case final error?) throw error;
    return keys[secretRef] ?? '';
  }

  @override
  Future<void> clearApiKey(String secretRef) async {
    if (clearError case final error?) throw error;
    keys.remove(secretRef);
  }
}

class _RecordingLlmProvider extends LlmProvider {
  _RecordingLlmProvider();

  Object? error;
  Object? generateError;
  String? lastApiKey;
  LlmConnectionConfig? lastConfig;
  LlmGenerationRequest? lastRequest;

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) async {
    lastConfig = config;
    lastApiKey = apiKey;
    lastRequest = request;
    if (generateError case final value?) throw value;
    return const LlmGenerationResult(text: 'OK');
  }

  @override
  Future<void> testConnection({
    required LlmConnectionConfig config,
    required String apiKey,
    LlmCancellationToken? cancellationToken,
  }) async {
    lastConfig = config;
    lastApiKey = apiKey;
    if (error case final value?) throw value;
  }
}
