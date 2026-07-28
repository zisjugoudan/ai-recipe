import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrModelManifest', () {
    test('parses valid JSON, normalizes hash, and round-trips', () {
      final json = validManifestJson();
      final manifest = OcrModelManifest.fromJson(json);

      expect(manifest.packageId, 'paddleocr-ppocrv5-mobile-zh');
      expect(manifest.platforms, <OcrRuntimePlatform>{
        OcrRuntimePlatform.android,
        OcrRuntimePlatform.ios,
      });
      expect(manifest.languages, <String>['zh-Hans', 'en']);
      expect(manifest.files.first.sha256, 'a' * 64);
      expect(manifest.totalSizeBytes, 30);
      final roundTrip = manifest.toJson();
      expect(roundTrip['schemaVersion'], json['schemaVersion']);
      expect(roundTrip['packageId'], json['packageId']);
      expect(
        OcrModelManifest.fromJson(
          Map<String, Object?>.from(roundTrip),
        ).toJson(),
        roundTrip,
      );
    });

    test('rejects unknown top-level and file fields', () {
      expect(
        () => OcrModelManifest.fromJson(<String, Object?>{
          ...validManifestJson(),
          'unexpected': true,
        }),
        throwsFormatException,
      );
      final json = validManifestJson();
      json['files'] = <Object?>[
        <String, Object?>{
          ...((json['files'] as List).first as Map).cast<String, Object?>(),
          'unexpected': true,
        },
      ];
      expect(() => OcrModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects insecure downloads and unsafe paths', () {
      for (final invalidPath in <String>[
        '../det.onnx',
        'models/../det.onnx',
        r'models\det.onnx',
        '/models/det.onnx',
      ]) {
        expect(
          () => OcrModelFile(
            role: 'detector',
            path: invalidPath,
            downloadUrl: 'https://example.com/det.onnx',
            sha256: '0' * 64,
            sizeBytes: 1,
          ),
          throwsArgumentError,
          reason: invalidPath,
        );
      }
      expect(
        () => OcrModelFile(
          role: 'detector',
          path: 'det.onnx',
          downloadUrl: 'http://example.com/det.onnx',
          sha256: '0' * 64,
          sizeBytes: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid hashes and non-positive file sizes', () {
      expect(
        () => OcrModelFile(
          role: 'detector',
          path: 'det.onnx',
          downloadUrl: 'https://example.com/det.onnx',
          sha256: 'not-a-hash',
          sizeBytes: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => OcrModelFile(
          role: 'detector',
          path: 'det.onnx',
          downloadUrl: 'https://example.com/det.onnx',
          sha256: '0' * 64,
          sizeBytes: 0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate languages, platforms, roles, and paths', () {
      OcrModelFile file(String role, String path) => OcrModelFile(
        role: role,
        path: path,
        downloadUrl: 'https://example.com/$path',
        sha256: '0' * 64,
        sizeBytes: 1,
      );

      expect(
        () => buildManifest(languages: <String>['zh-Hans', 'zh-Hans']),
        throwsArgumentError,
      );
      expect(
        () => buildManifest(
          platforms: <OcrRuntimePlatform>[
            OcrRuntimePlatform.android,
            OcrRuntimePlatform.android,
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => buildManifest(
          files: <OcrModelFile>[
            file('detector', 'det.onnx'),
            file('detector', 'rec.onnx'),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => buildManifest(
          files: <OcrModelFile>[
            file('detector', 'model.onnx'),
            file('recognizer', 'model.onnx'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid platform, engine, and semantic versions', () {
      final invalidPlatform = validManifestJson()
        ..['platforms'] = <String>['windows'];
      expect(
        () => OcrModelManifest.fromJson(invalidPlatform),
        throwsFormatException,
      );
      expect(() => buildManifest(engine: 'tflite'), throwsArgumentError);
      expect(() => buildManifest(version: 'v1'), throwsArgumentError);
      expect(() => buildManifest(minAppVersion: '1'), throwsArgumentError);
    });
  });

  group('OcrModelPackageStatus', () {
    test('validates progress and required state metadata', () {
      expect(
        () => OcrModelPackageStatus(
          packageId: 'ocr-model',
          state: OcrModelInstallState.downloading,
          progress: 1.1,
        ),
        throwsArgumentError,
      );
      expect(
        () => OcrModelPackageStatus(
          packageId: 'ocr-model',
          state: OcrModelInstallState.installed,
          progress: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => OcrModelPackageStatus(
          packageId: 'ocr-model',
          state: OcrModelInstallState.failed,
          progress: 0.5,
        ),
        throwsArgumentError,
      );
    });

    test('accepts installed and failed terminal states', () {
      final installed = OcrModelPackageStatus(
        packageId: 'ocr-model',
        state: OcrModelInstallState.installed,
        progress: 1,
        installedVersion: '1.0.0',
      );
      final failed = OcrModelPackageStatus(
        packageId: 'ocr-model',
        state: OcrModelInstallState.failed,
        progress: 0.5,
        failureCode: 'hash_mismatch',
      );

      expect(installed.installedVersion, '1.0.0');
      expect(failed.failureCode, 'hash_mismatch');
      expect(
        () => OcrModelPackageStatus(
          packageId: 'ocr-model',
          state: OcrModelInstallState.installed,
          progress: 1,
          installedVersion: 'latest',
        ),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> validManifestJson() => <String, Object?>{
  'schemaVersion': 1,
  'packageId': 'paddleocr-ppocrv5-mobile-zh',
  'version': '1.0.0',
  'engine': 'onnxruntime',
  'platforms': <String>['android', 'ios'],
  'languages': <String>['zh-Hans', 'en'],
  'minAppVersion': '0.1.0',
  'license': 'Apache-2.0',
  'files': <Object?>[
    <String, Object?>{
      'role': 'detector',
      'path': 'det.onnx',
      'downloadUrl': 'https://example.com/det.onnx',
      'sha256': 'A' * 64,
      'sizeBytes': 10,
    },
    <String, Object?>{
      'role': 'recognizer',
      'path': 'models/rec.onnx',
      'downloadUrl': 'https://example.com/rec.onnx',
      'sha256': 'b' * 64,
      'sizeBytes': 20,
    },
  ],
};

OcrModelManifest buildManifest({
  String version = '1.0.0',
  String engine = 'onnxruntime',
  Iterable<OcrRuntimePlatform> platforms = const <OcrRuntimePlatform>[
    OcrRuntimePlatform.android,
    OcrRuntimePlatform.ios,
  ],
  Iterable<String> languages = const <String>['zh-Hans', 'en'],
  String minAppVersion = '0.1.0',
  Iterable<OcrModelFile>? files,
}) {
  return OcrModelManifest(
    schemaVersion: 1,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: version,
    engine: engine,
    platforms: platforms,
    languages: languages,
    minAppVersion: minAppVersion,
    license: 'Apache-2.0',
    files:
        files ??
        <OcrModelFile>[
          OcrModelFile(
            role: 'detector',
            path: 'det.onnx',
            downloadUrl: 'https://example.com/det.onnx',
            sha256: '0' * 64,
            sizeBytes: 1,
          ),
        ],
  );
}
