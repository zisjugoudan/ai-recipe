import 'app_session.dart';

enum AppCapability {
  localRecipeLibrary,
  publicContentImport,
  customLlm,
  localOcr,
  managedLlm,
  cloudOcr,
  managedAsr,
  cloudSync,

  /// 多模态 LLM（识图引擎，IMAGE-001）：独立配置的图片识别 AI。
  multimodalLlm,
}

enum CapabilityReadiness {
  ready,
  notConfigured,
  notInstalled,
  offline,
  quotaExceeded,
  unavailable,
}

enum AppCapabilityReason {
  available,
  signInRequired,
  providerNotConfigured,
  componentNotInstalled,
  offline,
  quotaExceeded,
  serviceUnavailable,
}

class AppCapabilityRuntime {
  AppCapabilityRuntime({
    Map<AppCapability, CapabilityReadiness> readiness =
        const <AppCapability, CapabilityReadiness>{},
  }) : _readiness = Map.unmodifiable(readiness);

  final Map<AppCapability, CapabilityReadiness> _readiness;

  CapabilityReadiness readinessFor(AppCapability capability) {
    return _readiness[capability] ?? CapabilityReadiness.unavailable;
  }
}

class AppCapabilityDecision {
  const AppCapabilityDecision({
    required this.capability,
    required this.isAvailable,
    required this.reason,
  });

  const AppCapabilityDecision.available(AppCapability capability)
    : this(
        capability: capability,
        isAvailable: true,
        reason: AppCapabilityReason.available,
      );

  const AppCapabilityDecision.unavailable(
    AppCapability capability,
    AppCapabilityReason reason,
  ) : this(capability: capability, isAvailable: false, reason: reason);

  final AppCapability capability;
  final bool isAvailable;
  final AppCapabilityReason reason;
}

class AppCapabilitySnapshot {
  AppCapabilitySnapshot({
    required this.session,
    required Map<AppCapability, AppCapabilityDecision> decisions,
  }) : decisions = Map.unmodifiable(decisions);

  final AppSession session;
  final Map<AppCapability, AppCapabilityDecision> decisions;

  AppCapabilityDecision decisionFor(AppCapability capability) {
    final decision = decisions[capability];
    if (decision == null) {
      throw StateError('Capability decision is missing.');
    }
    return decision;
  }
}
