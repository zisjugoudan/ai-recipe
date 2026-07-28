import '../domain/access/app_access_repository.dart';
import '../domain/access/app_capability.dart';
import 'llm_config_repository.dart';

typedef CapabilityReadinessLoader = Future<CapabilityReadiness> Function();

class DeviceAppCapabilityRuntimeRepository
    implements AppCapabilityRuntimeRepository {
  DeviceAppCapabilityRuntimeRepository({
    required LlmConfigRepository llmConfigRepository,
    Map<AppCapability, CapabilityReadinessLoader> readinessLoaders =
        const <AppCapability, CapabilityReadinessLoader>{},
  }) : _llmConfigRepository = llmConfigRepository,
       _readinessLoaders = Map.unmodifiable(readinessLoaders);

  final LlmConfigRepository _llmConfigRepository;
  final Map<AppCapability, CapabilityReadinessLoader> _readinessLoaders;

  @override
  Future<AppCapabilityRuntime> load() async {
    final readiness = <AppCapability, CapabilityReadiness>{
      AppCapability.localRecipeLibrary: CapabilityReadiness.ready,
      AppCapability.publicContentImport: CapabilityReadiness.ready,
      AppCapability.customLlm: await _loadCustomLlmReadiness(),
    };

    for (final capability in AppCapability.values) {
      if (readiness.containsKey(capability)) continue;
      readiness[capability] = await _loadOptionalReadiness(capability);
    }
    return AppCapabilityRuntime(readiness: readiness);
  }

  Future<CapabilityReadiness> _loadCustomLlmReadiness() async {
    final override = _readinessLoaders[AppCapability.customLlm];
    if (override != null) {
      return _safeLoad(override);
    }
    try {
      final config = await _llmConfigRepository.load();
      if (config == null) return CapabilityReadiness.notConfigured;
      final apiKey = await _llmConfigRepository.readApiKey(config.secretRef);
      return apiKey.trim().isEmpty
          ? CapabilityReadiness.notConfigured
          : CapabilityReadiness.ready;
    } catch (_) {
      return CapabilityReadiness.unavailable;
    }
  }

  Future<CapabilityReadiness> _loadOptionalReadiness(
    AppCapability capability,
  ) async {
    final loader = _readinessLoaders[capability];
    if (loader != null) return _safeLoad(loader);
    return switch (capability) {
      AppCapability.localOcr => CapabilityReadiness.notInstalled,
      _ => CapabilityReadiness.unavailable,
    };
  }

  static Future<CapabilityReadiness> _safeLoad(
    CapabilityReadinessLoader loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return CapabilityReadiness.unavailable;
    }
  }
}
