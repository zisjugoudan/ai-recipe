import 'package:ai_recipe/application/access/app_access_use_cases.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_app_access_dependencies.dart';

void main() {
  final signedInAt = DateTime.utc(2026, 7, 28, 10, 30);
  late FakeAppSessionRepository sessions;
  late FakeAppCapabilityRuntimeRepository runtime;
  late AppAccessUseCases useCases;

  setUp(() {
    sessions = FakeAppSessionRepository();
    runtime = FakeAppCapabilityRuntimeRepository();
    useCases = AppAccessUseCases(
      sessionRepository: sessions,
      capabilityRuntimeRepository: runtime,
      clock: () => signedInAt,
    );
  });

  test('loads guest session by default', () async {
    final session = await useCases.loadSession();

    expect(session, const AppSession.guest());
    expect(session.isAuthenticated, isFalse);
  });

  test('continueAsGuest persists guest session', () async {
    sessions.session = AppSession.authenticated(
      userId: 'user-1',
      signedInAt: signedInAt,
    );

    final session = await useCases.continueAsGuest();

    expect(session, const AppSession.guest());
    expect(sessions.session, const AppSession.guest());
    expect(sessions.saveCount, 1);
  });

  test(
    'acceptVerifiedSession normalizes identity and uses injected clock',
    () async {
      final session = await useCases.acceptVerifiedSession(
        const AuthenticatedSessionInput(
          userId: '  stable-user-id  ',
          displayName: '  厨房用户  ',
        ),
      );

      expect(session.kind, AppSessionKind.authenticated);
      expect(session.userId, 'stable-user-id');
      expect(session.displayName, '厨房用户');
      expect(session.signedInAt, signedInAt);
      expect(sessions.session, session);
    },
  );

  test('acceptVerifiedSession rejects empty userId', () async {
    await expectLater(
      useCases.acceptVerifiedSession(
        const AuthenticatedSessionInput(userId: '  '),
      ),
      throwsA(isA<AppAccessValidationException>()),
    );
    expect(sessions.saveCount, 0);
  });

  test('signOut only changes session to guest', () async {
    sessions.session = AppSession.authenticated(
      userId: 'user-1',
      signedInAt: signedInAt,
    );

    final session = await useCases.signOut();

    expect(session, const AppSession.guest());
    expect(sessions.session, const AppSession.guest());
  });

  test(
    'guest can use local capabilities and ready self-hosted providers',
    () async {
      runtime.runtime = AppCapabilityRuntime(
        readiness: const {
          AppCapability.customLlm: CapabilityReadiness.ready,
          AppCapability.localOcr: CapabilityReadiness.ready,
        },
      );

      final snapshot = await useCases.loadCapabilities();

      expect(
        snapshot.decisionFor(AppCapability.localRecipeLibrary).isAvailable,
        isTrue,
      );
      expect(
        snapshot.decisionFor(AppCapability.publicContentImport).isAvailable,
        isTrue,
      );
      expect(snapshot.decisionFor(AppCapability.customLlm).isAvailable, isTrue);
      expect(snapshot.decisionFor(AppCapability.localOcr).isAvailable, isTrue);
    },
  );

  test(
    'guest self-hosted capability reasons reflect runtime readiness',
    () async {
      runtime.runtime = AppCapabilityRuntime(
        readiness: const {
          AppCapability.customLlm: CapabilityReadiness.notConfigured,
          AppCapability.localOcr: CapabilityReadiness.notInstalled,
        },
      );

      final snapshot = await useCases.loadCapabilities();

      expect(
        snapshot.decisionFor(AppCapability.customLlm).reason,
        AppCapabilityReason.providerNotConfigured,
      );
      expect(
        snapshot.decisionFor(AppCapability.localOcr).reason,
        AppCapabilityReason.componentNotInstalled,
      );
    },
  );

  test('guest managed and cloud capabilities always require sign in', () async {
    runtime.runtime = AppCapabilityRuntime(
      readiness: const {
        AppCapability.managedLlm: CapabilityReadiness.ready,
        AppCapability.cloudOcr: CapabilityReadiness.offline,
        AppCapability.managedAsr: CapabilityReadiness.quotaExceeded,
        AppCapability.cloudSync: CapabilityReadiness.ready,
      },
    );

    final snapshot = await useCases.loadCapabilities();

    for (final capability in const [
      AppCapability.managedLlm,
      AppCapability.cloudOcr,
      AppCapability.managedAsr,
      AppCapability.cloudSync,
    ]) {
      final decision = snapshot.decisionFor(capability);
      expect(decision.isAvailable, isFalse, reason: capability.name);
      expect(
        decision.reason,
        AppCapabilityReason.signInRequired,
        reason: capability.name,
      );
    }
  });

  test('authenticated managed capabilities map runtime states', () async {
    sessions.session = AppSession.authenticated(
      userId: 'user-1',
      signedInAt: signedInAt,
    );
    runtime.runtime = AppCapabilityRuntime(
      readiness: const {
        AppCapability.managedLlm: CapabilityReadiness.ready,
        AppCapability.cloudOcr: CapabilityReadiness.offline,
        AppCapability.managedAsr: CapabilityReadiness.quotaExceeded,
        AppCapability.cloudSync: CapabilityReadiness.unavailable,
      },
    );

    final snapshot = await useCases.loadCapabilities();

    expect(snapshot.decisionFor(AppCapability.managedLlm).isAvailable, isTrue);
    expect(
      snapshot.decisionFor(AppCapability.cloudOcr).reason,
      AppCapabilityReason.offline,
    );
    expect(
      snapshot.decisionFor(AppCapability.managedAsr).reason,
      AppCapabilityReason.quotaExceeded,
    );
    expect(
      snapshot.decisionFor(AppCapability.cloudSync).reason,
      AppCapabilityReason.serviceUnavailable,
    );
  });

  test('requireCapability throws stable capability and reason', () async {
    try {
      await useCases.requireCapability(AppCapability.managedLlm);
      fail('Expected AppCapabilityUnavailableException.');
    } on AppCapabilityUnavailableException catch (error) {
      expect(error.capability, AppCapability.managedLlm);
      expect(error.reason, AppCapabilityReason.signInRequired);
      expect(error.toString(), '当前能力不可用。');
    }
  });

  test('unknown session repository error is redacted', () async {
    sessions.loadError = StateError('secret storage implementation detail');

    await expectLater(
      useCases.loadSession(),
      throwsA(
        isA<AppAccessStorageException>().having(
          (error) => error.toString(),
          'message',
          '无法读取或保存应用会话。',
        ),
      ),
    );
  });

  test('unknown runtime repository error is redacted', () async {
    runtime.loadError = StateError('provider internal details');

    await expectLater(
      useCases.loadCapabilities(),
      throwsA(
        isA<AppAccessEvaluationException>().having(
          (error) => error.toString(),
          'message',
          '暂时无法读取应用能力状态。',
        ),
      ),
    );
  });
}
