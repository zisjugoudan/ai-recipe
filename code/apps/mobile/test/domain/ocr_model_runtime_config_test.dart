import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaddleOcrRuntimeConfig', () {
    test('uses the official PP-OCRv5 mobile preprocessing defaults', () {
      final runtime = runtimeConfig();

      expect(runtime.type, 'paddleocr-ppocrv5');
      expect(runtime.detector.resizeLongSide, 960);
      expect(
        runtime.detector.normalization.colorOrder,
        PaddleOcrColorOrder.bgr,
      );
      expect(runtime.detector.normalization.scale, closeTo(1 / 255, 1e-12));
      expect(runtime.detector.normalization.mean, <double>[
        0.485,
        0.456,
        0.406,
      ]);
      expect(runtime.detector.normalization.standardDeviation, <double>[
        0.229,
        0.224,
        0.225,
      ]);
      expect(runtime.detector.pixelThreshold, 0.3);
      expect(runtime.detector.boxThreshold, 0.6);
      expect(runtime.detector.maxCandidates, 1000);
      expect(runtime.detector.unclipRatio, 1.5);
      expect(runtime.recognizer.imageShape, <int>[3, 48, 320]);
      expect(runtime.recognizer.blankIndex, 0);
      expect(runtime.recognizer.useSpaceCharacter, isFalse);
      expect(runtime.requiredFileRoles, <String>{
        'detector',
        'recognizer',
        'dictionary',
      });
    });

    test('round-trips strict runtime JSON', () {
      final runtime = runtimeConfig();
      final json = runtime.toJson();

      expect(PaddleOcrRuntimeConfig.fromJson(json).toJson(), json);
      expect(
        () => PaddleOcrRuntimeConfig.fromJson(<String, Object?>{
          ...json,
          'unexpected': true,
        }),
        throwsFormatException,
      );
    });

    test('rejects unsafe dimensions, thresholds, and role collisions', () {
      expect(
        () => PaddleOcrDetectionRuntimeConfig(resizeLongSide: 16),
        throwsArgumentError,
      );
      expect(
        () => PaddleOcrDetectionRuntimeConfig(pixelThreshold: 1.1),
        throwsArgumentError,
      );
      expect(
        () => PaddleOcrRecognitionRuntimeConfig(
          imageShape: const <int>[1, 48, 320],
        ),
        throwsArgumentError,
      );
      expect(
        () => PaddleOcrRuntimeConfig(
          detector: PaddleOcrDetectionRuntimeConfig(modelRole: 'detector'),
          recognizer: PaddleOcrRecognitionRuntimeConfig(
            dictionaryRole: 'detector',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('OcrModelManifest schema 2', () {
    test('requires runtime config and all declared runtime roles', () {
      expect(
        () => manifest(schemaVersion: 2, runtime: null),
        throwsArgumentError,
      );
      expect(
        () => manifest(
          schemaVersion: 2,
          runtime: runtimeConfig(),
          files: modelFiles().where((file) => file.role != 'dictionary'),
        ),
        throwsArgumentError,
      );
    });

    test('requires ONNX model files and a TXT dictionary', () {
      expect(
        () => manifest(
          schemaVersion: 2,
          runtime: runtimeConfig(),
          files: modelFiles(recognizerPath: 'models/recognizer.json'),
        ),
        throwsArgumentError,
      );
      expect(
        () => manifest(
          schemaVersion: 2,
          runtime: runtimeConfig(),
          files: modelFiles(dictionaryPath: 'models/dictionary.json'),
        ),
        throwsArgumentError,
      );
    });

    test('round-trips schema 2 without changing schema 1', () {
      final schema2 = manifest(schemaVersion: 2, runtime: runtimeConfig());
      final schema2Json = schema2.toJson();

      expect(schema2Json['runtimeConfig'], isA<Map<String, Object>>());
      expect(OcrModelManifest.fromJson(schema2Json).toJson(), schema2Json);

      final schema1 = manifest(schemaVersion: 1, runtime: null);
      expect(schema1.toJson().containsKey('runtimeConfig'), isFalse);
    });
  });
}

PaddleOcrRuntimeConfig runtimeConfig() => PaddleOcrRuntimeConfig(
  detector: PaddleOcrDetectionRuntimeConfig(),
  recognizer: PaddleOcrRecognitionRuntimeConfig(),
);

OcrModelManifest manifest({
  required int schemaVersion,
  required PaddleOcrRuntimeConfig? runtime,
  Iterable<OcrModelFile>? files,
}) {
  return OcrModelManifest(
    schemaVersion: schemaVersion,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: '1.0.0',
    engine: 'onnxruntime',
    platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
    languages: const <String>['zh-Hans'],
    minAppVersion: '1.0.0',
    license: 'Apache-2.0',
    files: files ?? modelFiles(),
    runtimeConfig: runtime,
  );
}

List<OcrModelFile> modelFiles({
  String detectorPath = 'models/detector.onnx',
  String recognizerPath = 'models/recognizer.onnx',
  String dictionaryPath = 'models/dictionary.txt',
}) {
  OcrModelFile file(String role, String path) => OcrModelFile(
    role: role,
    path: path,
    downloadUrl: 'https://models.example.test/$path',
    sha256: '0' * 64,
    sizeBytes: 1,
  );

  return <OcrModelFile>[
    file('detector', detectorPath),
    file('recognizer', recognizerPath),
    file('dictionary', dictionaryPath),
  ];
}
