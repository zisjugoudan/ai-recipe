import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/features/llm_settings/llm_settings_page.dart';
import 'package:ai_recipe/features/profile/profile_page.dart';
import 'package:ai_recipe/features/settings/ocr_settings_page.dart';
import 'package:ai_recipe/features/settings/privacy_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_ocr_model_package_service.dart';
import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> pumpProfile(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness(
      localOcrModelPackageService: FakeOcrModelPackageService(),
    );
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePage(
          backend: harness.root.backend,
          session: const AppSession.guest(),
          onSignedOut: (_) {},
          onOpenTrash: () {},
          onDataChanged: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('opens real LLM settings page', (tester) async {
    await pumpProfile(tester);

    await tester.tap(find.text('LLM API 设置'));
    await tester.pumpAndSettle();

    expect(find.byType(LlmSettingsPage), findsOneWidget);
    expect(find.textContaining('后续页面切片'), findsNothing);
  });

  testWidgets('opens real OCR settings page', (tester) async {
    await pumpProfile(tester);

    await tester.scrollUntilVisible(find.text('OCR 设置'), 250);
    await tester.tap(find.text('OCR 设置'));
    await tester.pumpAndSettle();

    expect(find.byType(OcrSettingsPage), findsOneWidget);
    expect(find.textContaining('后续页面切片'), findsNothing);
  });

  testWidgets('opens real privacy settings page', (tester) async {
    await pumpProfile(tester);

    await tester.scrollUntilVisible(find.text('隐私与上传设置'), 250);
    await tester.tap(find.text('隐私与上传设置'));
    await tester.pumpAndSettle();

    expect(find.byType(PrivacySettingsPage), findsOneWidget);
    expect(find.textContaining('后续页面切片'), findsNothing);
  });
}
