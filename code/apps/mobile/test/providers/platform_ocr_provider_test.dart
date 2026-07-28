import 'dart:io';

import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/providers/ocr/platform_ocr_provider.dart';
import 'package:ai_recipe/providers/ocr/platform_ocr_runtime_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FakePackageService packages;
  late FakeRuntimeBridge runtime;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-recipe-platform-ocr-');
    packages = FakePackageService();
    runtime = FakeRuntimeBridge();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('fails when model package is not installed', () async {
    final provider = PlatformOcrProvider(
      packageService: packages,
      runtimeBridge: runtime,
      packageId: 'paddleocr-ppocrv5-mobile-zh',
    );

    await expectLater(
      provider.recognize(OcrImageInput(localAssetId: 'asset-1', order: 0)),
      throwsA(
        isA<OcrProviderException>().having(
          (error) => error.kind,
          'kind',
          OcrProviderErrorKind.modelNotInstalled,
        ),
      ),
    );
  });

  test(
    'keeps recognition unavailable until native pipeline is supported',
    () async {
      packages.active = packageAt(root);
      runtime.probeResult = const OcrRuntimeProbe(
        runtimeAvailable: true,
        recognitionSupported: false,
      );
      final provider = PlatformOcrProvider(
        packageService: packages,
        runtimeBridge: runtime,
        packageId: packages.active!.packageId,
      );

      await expectLater(
        provider.recognize(OcrImageInput(localAssetId: 'asset-1', order: 0)),
        throwsA(
          isA<OcrProviderException>().having(
            (error) => error.kind,
            'kind',
            OcrProviderErrorKind.unavailable,
          ),
        ),
      );
      expect(runtime.recognizeCalled, isFalse);
    },
  );

  test('delegates to runtime when package and recognition are ready', () async {
    packages.active = packageAt(root);
    runtime.probeResult = const OcrRuntimeProbe(
      runtimeAvailable: true,
      recognitionSupported: true,
    );
    final provider = PlatformOcrProvider(
      packageService: packages,
      runtimeBridge: runtime,
      packageId: packages.active!.packageId,
    );

    final document = await provider.recognize(
      OcrImageInput(localAssetId: 'asset-1', order: 0),
    );

    expect(document.fullText, '?? 2 ?');
    expect(runtime.recognizeCalled, isTrue);
  });
}

class FakePackageService implements OcrModelPackageService {
  OcrInstalledModelPackage? active;

  @override
  Future<void> delete(String packageId) async {}

  @override
  Future<OcrInstalledModelPackage?> getActivePackage(String packageId) async {
    return active?.packageId == packageId ? active : null;
  }

  @override
  Future<OcrModelPackageStatus> getStatus(String packageId) async {
    final installed = active;
    if (installed == null) {
      return OcrModelPackageStatus(
        packageId: packageId,
        state: OcrModelInstallState.notInstalled,
        progress: 0,
      );
    }
    return OcrModelPackageStatus(
      packageId: packageId,
      state: OcrModelInstallState.installed,
      progress: 1,
      installedVersion: installed.version,
    );
  }

  @override
  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> recoverInterruptedInstallations() async {}
}

class FakeRuntimeBridge implements OcrRuntimeBridge {
  OcrRuntimeProbe probeResult = const OcrRuntimeProbe(
    runtimeAvailable: false,
    recognitionSupported: false,
  );
  bool recognizeCalled = false;

  @override
  Future<void> healthCheck(OcrInstalledModelPackage package) async {}

  @override
  Future<OcrRuntimeProbe> probe() async => probeResult;

  @override
  Future<OcrDocument> recognize({
    required OcrImageInput input,
    required OcrInstalledModelPackage package,
  }) async {
    recognizeCalled = true;
    return OcrDocument(
      providerId: 'local-paddleocr',
      modelVersion: package.version,
      language: 'zh-Hans',
      blocks: <OcrTextBlock>[
        OcrTextBlock(text: '?? 2 ?', confidence: 0.9, readingOrder: 0),
      ],
    );
  }
}

OcrInstalledModelPackage packageAt(Directory root) {
  return OcrInstalledModelPackage(
    rootDirectory: root,
    manifest: OcrModelManifest(
      schemaVersion: 1,
      packageId: 'paddleocr-ppocrv5-mobile-zh',
      version: '1.0.0',
      engine: 'onnxruntime',
      platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
      languages: const <String>['zh-Hans'],
      minAppVersion: '0.1.0',
      license: 'Apache-2.0',
      files: <OcrModelFile>[
        OcrModelFile(
          role: 'detector',
          path: 'det.onnx',
          downloadUrl: 'https://models.example.test/det.onnx',
          sha256:
              '0000000000000000000000000000000000000000000000000000000000000000',
          sizeBytes: 1,
        ),
      ],
    ),
  );
}
