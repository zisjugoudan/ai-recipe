import 'package:ai_recipe/data/device_app_capability_runtime_repository.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceAppCapabilityRuntimeRepository', () {
    test('reports custom LLM not configured without a saved config', () async {
      final runtime = await DeviceAppCapabilityRuntimeRepository(
        llmConfigRepository: MemoryLlmConfigRepository(),
      ).load();

      expect(
        runtime.readinessFor(AppCapability.customLlm),
        CapabilityReadiness.notConfigured,
      );
      expect(
        runtime.readinessFor(AppCapability.localRecipeLibrary),
        CapabilityReadiness.ready,
      );
      expect(
        runtime.readinessFor(AppCapability.publicContentImport),
        CapabilityReadiness.ready,
      );
    });

    test('requires a non-empty API key for custom LLM readiness', () async {
      final repository = MemoryLlmConfigRepository(
        config: testLlmConfig,
        apiKey: '   ',
      );

      final runtime = await DeviceAppCapabilityRuntimeRepository(
        llmConfigRepository: repository,
      ).load();

      expect(
        runtime.readinessFor(AppCapability.customLlm),
        CapabilityReadiness.notConfigured,
      );
    });

    test('reports custom LLM ready when config and key exist', () async {
      final runtime = await DeviceAppCapabilityRuntimeRepository(
        llmConfigRepository: MemoryLlmConfigRepository(
          config: testLlmConfig,
          apiKey: 'test-placeholder',
        ),
      ).load();

      expect(
        runtime.readinessFor(AppCapability.customLlm),
        CapabilityReadiness.ready,
      );
      expect(
        runtime.readinessFor(AppCapability.localOcr),
        CapabilityReadiness.notInstalled,
      );
      expect(
        runtime.readinessFor(AppCapability.managedLlm),
        CapabilityReadiness.unavailable,
      );
    });

    test('maps config read failures to unavailable', () async {
      final runtime = await DeviceAppCapabilityRuntimeRepository(
        llmConfigRepository: MemoryLlmConfigRepository(
          loadError: StateError('private configuration failure'),
        ),
      ).load();

      expect(
        runtime.readinessFor(AppCapability.customLlm),
        CapabilityReadiness.unavailable,
      );
    });

    test('supports injected readiness and contains loader failures', () async {
      final runtime = await DeviceAppCapabilityRuntimeRepository(
        llmConfigRepository: MemoryLlmConfigRepository(),
        readinessLoaders: <AppCapability, CapabilityReadinessLoader>{
          AppCapability.localOcr: () async => CapabilityReadiness.ready,
          AppCapability.cloudOcr: () async {
            throw StateError('provider probe details');
          },
        },
      ).load();

      expect(
        runtime.readinessFor(AppCapability.localOcr),
        CapabilityReadiness.ready,
      );
      expect(
        runtime.readinessFor(AppCapability.cloudOcr),
        CapabilityReadiness.unavailable,
      );
    });
  });
}

final LlmConnectionConfig testLlmConfig = LlmConnectionConfig(
  id: 'test-config',
  name: 'Test provider',
  providerType: LlmProviderType.openAiCompatible,
  baseUrl: 'https://example.com/v1',
  secretRef: 'test-secret-ref',
  model: 'test-model',
);

class MemoryLlmConfigRepository implements LlmConfigRepository {
  MemoryLlmConfigRepository({
    this.config,
    this.apiKey = '',
    this.loadError,
    this.readError,
  });

  LlmConnectionConfig? config;
  String apiKey;
  Object? loadError;
  Object? readError;

  @override
  Future<void> clearApiKey(String secretRef) async {
    apiKey = '';
  }

  @override
  Future<LlmConnectionConfig?> load() async {
    if (loadError case final error?) throw error;
    return config;
  }

  @override
  Future<String> readApiKey(String secretRef) async {
    if (readError case final error?) throw error;
    return apiKey;
  }

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    this.config = config;
    if (apiKey != null) this.apiKey = apiKey;
  }
}
