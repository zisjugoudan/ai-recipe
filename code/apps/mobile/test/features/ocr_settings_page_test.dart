import 'package:ai_recipe/domain/access/app_session.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/features/settings/ocr_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_ocr_model_package_service.dart';
import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> pumpPage(
    WidgetTester tester, {
    required FakeOcrModelPackageService service,
    AppSession session = const AppSession.guest(),
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness(localOcrModelPackageService: service);
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: OcrSettingsPage(backend: harness.root.backend, session: session),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets(
    'does not fake a downloadable manifest and explains guest cloud OCR',
    (tester) async {
      final service = FakeOcrModelPackageService();
      await pumpPage(tester, service: service);

      final installButton = tester.widget<FilledButton>(
        find.byKey(const Key('installOcrModelButton')),
      );
      expect(installButton.onPressed, isNull);
      expect(
        find.byKey(const Key('ocrManifestUnavailableMessage')),
        findsOneWidget,
      );
      expect(find.textContaining('游客不能使用平台托管的云 OCR'), findsOneWidget);
      expect(service.recoverCount, 1);
    },
  );

  testWidgets('authenticated user with image upload disabled is not prompted', (
    tester,
  ) async {
    final service = FakeOcrModelPackageService();
    await pumpPage(
      tester,
      service: service,
      session: AppSession.authenticated(
        userId: 'user-1',
        signedInAt: DateTime.utc(2026, 7, 30),
      ),
    );

    expect(find.textContaining('当前未允许上传图片'), findsOneWidget);
    expect(find.textContaining('不会在这里诱导或自动修改'), findsOneWidget);
    expect(find.textContaining('开启图片上传'), findsNothing);
  });

  testWidgets('installed model can be deleted after confirmation', (
    tester,
  ) async {
    final service = FakeOcrModelPackageService(
      status: OcrModelPackageStatus(
        packageId: FakeOcrModelPackageService.packageId,
        state: OcrModelInstallState.installed,
        progress: 1,
        installedVersion: '1.0.0',
      ),
    );
    await pumpPage(tester, service: service);

    expect(find.textContaining('模型已安装 1.0.0'), findsOneWidget);
    await tester.tap(find.byKey(const Key('deleteOcrModelButton')));
    await tester.pumpAndSettle();
    expect(find.text('删除本地 OCR 模型？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteOcrModelButton')));
    await tester.pumpAndSettle();

    expect(service.deleteCount, 1);
    expect(find.textContaining('未安装 · 识别能力未启用'), findsOneWidget);
  });

  testWidgets('load failure exposes retry without claiming OCR is ready', (
    tester,
  ) async {
    final service = FakeOcrModelPackageService()..error = StateError('disk');
    final harness = await pumpPage(tester, service: service);

    expect(find.textContaining('OCR'), findsWidgets);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('模型已安装'), findsNothing);

    service.error = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ocrModelStatus')), findsOneWidget);
    expect(harness.settingsRepository.loadError, isNull);
  });

  testWidgets('multimodal request timeout offers up to 600 seconds', (
    tester,
  ) async {
    final service = FakeOcrModelPackageService();
    await pumpPage(tester, service: service);

    // 慢速本地多模态模型（Ollama/LM Studio 等）识别可能超过 120 秒，
    // 识图引擎设置必须提供更大的超时档位（BUG-008）。
    await tester.tap(find.byKey(const Key('multimodalRequestTimeoutField')));
    await tester.pumpAndSettle();
    expect(find.text('180 秒'), findsOneWidget);
    expect(find.text('300 秒'), findsOneWidget);
    expect(find.text('600 秒'), findsOneWidget);
    expect(find.text('30 秒'), findsOneWidget);
  });
}
