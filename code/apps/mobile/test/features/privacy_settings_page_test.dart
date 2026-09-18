import 'package:ai_recipe/features/settings/privacy_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(home: PrivacySettingsPage(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('shows safe local defaults and persists switches', (
    tester,
  ) async {
    final harness = await pumpPage(tester);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('recordRecipeHistorySwitch')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('allowTextUploadSwitch')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('allowImageUploadSwitch')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('allowVideoUploadSwitch')),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('allowImageUploadSwitch')));
    await tester.pumpAndSettle();
    expect(harness.settingsRepository.settings!.allowImageUpload, isTrue);
  });

  testWidgets('disabling history clears it and manual clear confirms', (
    tester,
  ) async {
    final harness = await pumpPage(tester);

    await tester.tap(find.byKey(const Key('recordRecipeHistorySwitch')));
    await tester.pumpAndSettle();
    expect(harness.settingsRepository.settings!.recordRecipeHistory, isFalse);
    expect(harness.activityRepository.clearCount, 1);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('clearRecipeHistoryButton')));
    await tester.pumpAndSettle();
    expect(find.text('清空最近浏览？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmClearHistoryButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(harness.activityRepository.clearCount, 2);
    expect(find.textContaining('最近浏览记录已清空'), findsOneWidget);
  });

  testWidgets('shows load error and retries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    harness.settingsRepository.loadError = StateError('disk');
    await tester.pumpWidget(
      MaterialApp(home: PrivacySettingsPage(backend: harness.root.backend)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('隐私设置暂时无法'), findsOneWidget);
    harness.settingsRepository.loadError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recordRecipeHistorySwitch')), findsOneWidget);
  });
}
