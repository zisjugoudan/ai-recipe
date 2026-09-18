import 'dart:io';

import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/providers/ocr/platform_ocr_runtime_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai_recipe/local_ocr_test');
  late PlatformOcrRuntimeBridge bridge;
  late Directory root;

  setUp(() async {
    bridge = PlatformOcrRuntimeBridge(channel: channel);
    root = await Directory.systemTemp.createTemp('ai-recipe-ocr-bridge-');
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('probe parses runtime readiness', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'probe');
          return <String, Object?>{
            'runtimeAvailable': true,
            'recognitionSupported': false,
            'runtimeVersion': 'test-runtime',
          };
        });

    final probe = await bridge.probe();
    expect(probe.runtimeAvailable, isTrue);
    expect(probe.recognitionSupported, isFalse);
    expect(probe.runtimeVersion, 'test-runtime');
  });

  test('healthCheck sends model directory and manifest only', () async {
    late Map<Object?, Object?> args;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'healthCheck');
          args = Map<Object?, Object?>.from(
            call.arguments as Map<Object?, Object?>,
          );
          return null;
        });

    final package = packageAt(root);
    await bridge.healthCheck(package);

    expect(args['modelDirectory'], root.absolute.path);
    expect(args['manifest'], isA<Map<Object?, Object?>>());
    expect(args.keys, unorderedEquals(<Object?>['modelDirectory', 'manifest']));
  });

  test('healthCheck forwards the complete schema 2 runtime contract', () async {
    late Map<Object?, Object?> manifest;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          manifest = Map<Object?, Object?>.from(
            (call.arguments as Map<Object?, Object?>)['manifest']
                as Map<Object?, Object?>,
          );
          return null;
        });

    final package = packageAtV2(root);
    await bridge.healthCheck(package);

    expect(manifest['schemaVersion'], 2);
    expect(manifest['runtimeConfig'], package.manifest.runtimeConfig!.toJson());
  });

  test('recognize parses strict OCR document', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'recognize');
          return <String, Object?>{
            'providerId': 'local-paddleocr',
            'modelVersion': '1.0.0',
            'language': 'zh-Hans',
            'durationMs': 12,
            'blocks': <Object?>[
              <String, Object?>{
                'text': '?? 2 ?',
                'confidence': 0.91,
                'readingOrder': 0,
                'polygon': <Object?>[
                  <String, Object?>{'x': 0.1, 'y': 0.1},
                  <String, Object?>{'x': 0.9, 'y': 0.1},
                  <String, Object?>{'x': 0.9, 'y': 0.2},
                  <String, Object?>{'x': 0.1, 'y': 0.2},
                ],
              },
            ],
          };
        });

    final document = await bridge.recognize(
      input: OcrImageInput(localAssetId: 'asset-1', order: 0),
      package: packageAt(root),
    );

    expect(document.providerId, 'local-paddleocr');
    expect(document.blocks.single.text, '?? 2 ?');
    expect(document.averageConfidence, closeTo(0.91, 0.001));
  });

  test('maps platform errors without leaking details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'inference_not_implemented',
            message:
                '  native stack trace should not appear but stable text is fine  ',
          );
        });

    await expectLater(
      bridge.recognize(
        input: OcrImageInput(localAssetId: 'asset-1', order: 0),
        package: packageAt(root),
      ),
      throwsA(
        isA<OcrProviderException>().having(
          (error) => error.kind,
          'kind',
          OcrProviderErrorKind.unavailable,
        ),
      ),
    );
  });

  test('maps image input failures to stable provider errors', () async {
    const cases = <String, OcrProviderErrorKind>{
      'image_too_large': OcrProviderErrorKind.invalidInput,
      'image_permission_denied': OcrProviderErrorKind.invalidInput,
      'image_source_unavailable': OcrProviderErrorKind.unavailable,
    };

    for (final entry in cases.entries) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: entry.key,
              message: 'native path and stack details must not escape',
            );
          });

      await expectLater(
        bridge.recognize(
          input: OcrImageInput(localAssetId: 'asset-1', order: 0),
          package: packageAt(root),
        ),
        throwsA(
          isA<OcrProviderException>()
              .having((error) => error.kind, 'kind', entry.value)
              .having(
                (error) => error.message,
                'message',
                isNot(contains('native path')),
              ),
        ),
        reason: entry.key,
      );
    }
  });

  test('rejects malformed text geometry', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'providerId': 'local-paddleocr',
            'modelVersion': '1.0.0',
            'language': 'zh-Hans',
            'blocks': <Object?>[
              <String, Object?>{
                'text': 'bad',
                'confidence': 1.5,
                'readingOrder': 0,
              },
            ],
          };
        });

    await expectLater(
      bridge.recognize(
        input: OcrImageInput(localAssetId: 'asset-1', order: 0),
        package: packageAt(root),
      ),
      throwsA(
        isA<OcrProviderException>().having(
          (error) => error.kind,
          'kind',
          OcrProviderErrorKind.invalidResponse,
        ),
      ),
    );
  });
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

OcrInstalledModelPackage packageAtV2(Directory root) {
  return OcrInstalledModelPackage(
    rootDirectory: root,
    manifest: OcrModelManifest(
      schemaVersion: 2,
      packageId: 'paddleocr-ppocrv5-mobile-zh',
      version: '2.0.0',
      engine: 'onnxruntime',
      platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
      languages: const <String>['zh-Hans'],
      minAppVersion: '0.1.0',
      license: 'Apache-2.0',
      files: <OcrModelFile>[
        modelFile('detector', 'detector.onnx'),
        modelFile('recognizer', 'recognizer.onnx'),
        modelFile('dictionary', 'dictionary.txt'),
      ],
      runtimeConfig: PaddleOcrRuntimeConfig(
        detector: PaddleOcrDetectionRuntimeConfig(),
        recognizer: PaddleOcrRecognitionRuntimeConfig(),
      ),
    ),
  );
}

OcrModelFile modelFile(String role, String path) {
  return OcrModelFile(
    role: role,
    path: path,
    downloadUrl: 'https://models.example.test/$path',
    sha256: '0' * 64,
    sizeBytes: 1,
  );
}
