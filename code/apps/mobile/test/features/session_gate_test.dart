import 'package:ai_recipe/application/backend/ai_recipe_backend_facade.dart';
import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/access/onboarding_state.dart';
import 'package:ai_recipe/features/session/session_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> pumpGate(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(home: SessionGate(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('first guest sees welcome and completed guest reopens shell', (
    tester,
  ) async {
    final harness = await pumpGate(tester);

    expect(find.byKey(const Key('welcomeGuestButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('welcomeGuestButton')));
    await tester.pumpAndSettle();

    expect(
      harness.onboardingRepository.state,
      const OnboardingState.completed(),
    );
    expect(find.text('首页'), findsWidgets);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: SessionGate(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcomeGuestButton')), findsNothing);
    expect(find.text('首页'), findsWidgets);
  });

  testWidgets('profile return resets onboarding and shows welcome', (
    tester,
  ) async {
    final harness = await pumpGate(tester);
    await tester.tap(find.byKey(const Key('welcomeGuestButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('profileSessionActionButton')),
      300,
    );
    await tester.tap(find.byKey(const Key('profileSessionActionButton')));
    await tester.pumpAndSettle();

    expect(harness.onboardingRepository.state, const OnboardingState.pending());
    expect(harness.sessionRepository.session, const AppSession.guest());
    expect(find.byKey(const Key('welcomeGuestButton')), findsOneWidget);
  });

  testWidgets('authenticated session bypasses pending onboarding', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    harness.sessionRepository.session = AppSession.authenticated(
      userId: 'user-1',
      displayName: '测试用户',
      signedInAt: DateTime.utc(2026, 7, 30),
    );

    await tester.pumpWidget(
      MaterialApp(home: SessionGate(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('welcomeGuestButton')), findsNothing);
    expect(find.text('首页'), findsWidgets);
  });

  test(
    'facade maps onboarding storage errors to stable backend error',
    () async {
      final harness = TestBackendHarness();
      addTearDown(harness.close);
      harness.onboardingRepository.loadError = StateError('private detail');

      await expectLater(
        harness.root.backend.loadOnboardingState(),
        throwsA(
          isA<AiRecipeBackendException>().having(
            (error) => error.code,
            'code',
            AiRecipeBackendErrorCode.storageUnavailable,
          ),
        ),
      );
    },
  );
}
