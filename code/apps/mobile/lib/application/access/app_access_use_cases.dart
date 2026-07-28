import 'package:ai_recipe/domain/access/app_access_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/access/app_session.dart';

typedef AppAccessClock = DateTime Function();

class AuthenticatedSessionInput {
  const AuthenticatedSessionInput({required this.userId, this.displayName});

  final String userId;
  final String? displayName;
}

class AppAccessUseCases {
  const AppAccessUseCases({
    required AppSessionRepository sessionRepository,
    required AppCapabilityRuntimeRepository capabilityRuntimeRepository,
    required AppAccessClock clock,
  }) : _sessionRepository = sessionRepository,
       _capabilityRuntimeRepository = capabilityRuntimeRepository,
       _clock = clock;

  final AppSessionRepository _sessionRepository;
  final AppCapabilityRuntimeRepository _capabilityRuntimeRepository;
  final AppAccessClock _clock;

  Future<AppSession> loadSession() {
    return _loadSession();
  }

  Future<AppSession> continueAsGuest() async {
    const session = AppSession.guest();
    await _saveSession(session);
    return session;
  }

  Future<AppSession> acceptVerifiedSession(
    AuthenticatedSessionInput input,
  ) async {
    final userId = input.userId.trim();
    if (userId.isEmpty) {
      throw const AppAccessValidationException('用户 ID 不能为空。');
    }
    final displayName = input.displayName?.trim();
    final session = AppSession.authenticated(
      userId: userId,
      displayName: displayName == null || displayName.isEmpty
          ? null
          : displayName,
      signedInAt: _clock(),
    );
    await _saveSession(session);
    return session;
  }

  Future<AppSession> signOut() async {
    const session = AppSession.guest();
    await _saveSession(session);
    return session;
  }

  Future<AppCapabilitySnapshot> loadCapabilities() async {
    final session = await _loadSession();
    final runtime = await _loadRuntime();
    final decisions = <AppCapability, AppCapabilityDecision>{};
    for (final capability in AppCapability.values) {
      decisions[capability] = _evaluate(session, runtime, capability);
    }
    return AppCapabilitySnapshot(session: session, decisions: decisions);
  }

  Future<void> requireCapability(AppCapability capability) async {
    final decision = (await loadCapabilities()).decisionFor(capability);
    if (!decision.isAvailable) {
      throw AppCapabilityUnavailableException(
        capability: capability,
        reason: decision.reason,
      );
    }
  }

  Future<AppSession> _loadSession() async {
    try {
      return await _sessionRepository.load();
    } on FormatException {
      throw const AppAccessStorageException();
    } on AppAccessStorageException {
      rethrow;
    } catch (_) {
      throw const AppAccessStorageException();
    }
  }

  Future<void> _saveSession(AppSession session) async {
    try {
      await _sessionRepository.save(session);
    } on AppAccessStorageException {
      rethrow;
    } catch (_) {
      throw const AppAccessStorageException();
    }
  }

  Future<AppCapabilityRuntime> _loadRuntime() async {
    try {
      return await _capabilityRuntimeRepository.load();
    } on AppAccessEvaluationException {
      rethrow;
    } catch (_) {
      throw const AppAccessEvaluationException();
    }
  }

  static AppCapabilityDecision _evaluate(
    AppSession session,
    AppCapabilityRuntime runtime,
    AppCapability capability,
  ) {
    if (capability == AppCapability.localRecipeLibrary ||
        capability == AppCapability.publicContentImport) {
      return AppCapabilityDecision.available(capability);
    }

    if (_requiresSignIn(capability) && !session.isAuthenticated) {
      return AppCapabilityDecision.unavailable(
        capability,
        AppCapabilityReason.signInRequired,
      );
    }

    final readiness = runtime.readinessFor(capability);
    if (readiness == CapabilityReadiness.ready) {
      return AppCapabilityDecision.available(capability);
    }

    return AppCapabilityDecision.unavailable(
      capability,
      _reasonFor(capability, readiness),
    );
  }

  static bool _requiresSignIn(AppCapability capability) {
    return switch (capability) {
      AppCapability.managedLlm ||
      AppCapability.cloudOcr ||
      AppCapability.managedAsr ||
      AppCapability.cloudSync => true,
      _ => false,
    };
  }

  static AppCapabilityReason _reasonFor(
    AppCapability capability,
    CapabilityReadiness readiness,
  ) {
    return switch (readiness) {
      CapabilityReadiness.ready => AppCapabilityReason.available,
      CapabilityReadiness.offline => AppCapabilityReason.offline,
      CapabilityReadiness.quotaExceeded => AppCapabilityReason.quotaExceeded,
      CapabilityReadiness.notConfigured
          when capability == AppCapability.customLlm =>
        AppCapabilityReason.providerNotConfigured,
      CapabilityReadiness.notInstalled
          when capability == AppCapability.localOcr =>
        AppCapabilityReason.componentNotInstalled,
      _ => AppCapabilityReason.serviceUnavailable,
    };
  }
}

class AppAccessValidationException implements Exception {
  const AppAccessValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AppAccessStorageException implements Exception {
  const AppAccessStorageException();

  @override
  String toString() => '无法读取或保存应用会话。';
}

class AppAccessEvaluationException implements Exception {
  const AppAccessEvaluationException();

  @override
  String toString() => '暂时无法读取应用能力状态。';
}

class AppCapabilityUnavailableException implements Exception {
  const AppCapabilityUnavailableException({
    required this.capability,
    required this.reason,
  });

  final AppCapability capability;
  final AppCapabilityReason reason;

  @override
  String toString() => '当前能力不可用。';
}
