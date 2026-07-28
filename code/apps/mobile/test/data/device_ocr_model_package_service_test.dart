import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_recipe/data/ocr/device_ocr_model_package_service.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package_exception.dart';
import 'package:ai_recipe/providers/ocr/http_ocr_model_download_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late FakeDownloadClient downloads;
  late List<OcrInstalledModelPackage> checkedPackages;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-recipe-ocr-models-');
    downloads = FakeDownloadClient();
    checkedPackages = <OcrInstalledModelPackage>[];
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('downloads verifies and activates a model package', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final service = newService(
      root,
      downloads,
      healthCheck: (package) async {
        checkedPackages.add(package);
        expect(
          await package.fileFor(package.manifest.files.single).exists(),
          isTrue,
        );
      },
    );

    final statuses = <OcrModelPackageStatus>[];
    final status = await service.install(
      manifest(version: '1.0.0', bytes: bytes),
      onStatusChanged: statuses.add,
    );

    expect(status.state, OcrModelInstallState.installed);
    expect(status.installedVersion, '1.0.0');
    expect(status.progress, 1);
    expect(checkedPackages.single.version, '1.0.0');
    expect(
      statuses.map((item) => item.state),
      containsAllInOrder(<OcrModelInstallState>[
        OcrModelInstallState.downloading,
        OcrModelInstallState.verifying,
        OcrModelInstallState.installed,
      ]),
    );

    final active = await service.getActivePackage(
      'paddleocr-ppocrv5-mobile-zh',
    );
    expect(active, isNotNull);
    expect(active!.version, '1.0.0');
  });

  test('rejects untrusted download hosts before downloading', () async {
    final bytes = utf8.encode('fake onnx model');
    final service = newService(
      root,
      downloads,
      trustedHosts: {'trusted.example.test'},
    );

    await expectLater(
      service.install(manifest(version: '1.0.0', bytes: bytes)),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.untrustedDownloadHost,
        ),
      ),
    );
    expect(downloads.openedUrls, isEmpty);
  });

  test('checksum failure does not replace previous active version', () async {
    final firstBytes = utf8.encode('first model');
    downloads.add('https://models.example.test/det.onnx', firstBytes);
    final service = newService(root, downloads);
    await service.install(manifest(version: '1.0.0', bytes: firstBytes));

    final secondBytes = utf8.encode('second model');
    downloads.add('https://models.example.test/det.onnx', secondBytes);
    await expectLater(
      service.install(
        manifest(
          version: '1.1.0',
          bytes: firstBytes,
          sizeBytes: secondBytes.length,
        ),
      ),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.checksumMismatch,
        ),
      ),
    );

    final active = await service.getActivePackage(
      'paddleocr-ppocrv5-mobile-zh',
    );
    expect(active, isNotNull);
    expect(active!.version, '1.0.0');
    final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');
    expect(status.state, OcrModelInstallState.failed);
    expect(status.installedVersion, '1.0.0');
    expect(status.failureCode, OcrModelPackageErrorKind.checksumMismatch.name);
  });

  test(
    'upgrade atomically switches active package without artifacts',
    () async {
      final firstBytes = utf8.encode('first model');
      downloads.add('https://models.example.test/det.onnx', firstBytes);
      final service = newService(root, downloads);
      await service.install(manifest(version: '1.0.0', bytes: firstBytes));

      final secondBytes = utf8.encode('second model');
      downloads.add('https://models.example.test/det.onnx', secondBytes);
      await service.install(manifest(version: '1.1.0', bytes: secondBytes));

      final active = await service.getActivePackage(
        'paddleocr-ppocrv5-mobile-zh',
      );
      expect(active, isNotNull);
      expect(active!.version, '1.1.0');

      final packageRoot = Directory(
        '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh',
      );
      final artifactNames = await packageRoot
          .list()
          .map((entry) => entry.uri.pathSegments.last)
          .where((name) => name.contains('.tmp-') || name.contains('.bak-'))
          .toList();
      expect(artifactNames, isEmpty);
    },
  );

  test('rejects an active manifest that does not match its pointer', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final service = newService(root, downloads);
    await service.install(manifest(version: '1.0.0', bytes: bytes));

    final manifestFile = File(
      '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh/'
      'versions/1.0.0/manifest.json',
    );
    final decoded = Map<String, Object?>.from(
      jsonDecode(await manifestFile.readAsString()) as Map,
    );
    decoded['packageId'] = 'another-package';
    await manifestFile.writeAsString(jsonEncode(decoded));

    expect(
      await service.getActivePackage('paddleocr-ppocrv5-mobile-zh'),
      isNull,
    );
  });

  test(
    'health check failure is stable and does not activate package',
    () async {
      final bytes = utf8.encode('fake onnx model');
      downloads.add('https://models.example.test/det.onnx', bytes);
      final service = newService(
        root,
        downloads,
        healthCheck: (_) async => throw const OcrModelPackageException(
          kind: OcrModelPackageErrorKind.healthCheckFailed,
          message: 'health failed',
        ),
      );

      await expectLater(
        service.install(manifest(version: '1.0.0', bytes: bytes)),
        throwsA(
          isA<OcrModelPackageException>().having(
            (error) => error.kind,
            'kind',
            OcrModelPackageErrorKind.healthCheckFailed,
          ),
        ),
      );
      expect(
        await service.getActivePackage('paddleocr-ppocrv5-mobile-zh'),
        isNull,
      );
    },
  );

  test(
    'ignores state files whose package id does not match directory',
    () async {
      final packageRoot = Directory(
        '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh',
      );
      await packageRoot.create(recursive: true);
      await File('${packageRoot.path}/state.json').writeAsString(
        jsonEncode(<String, Object?>{
          'packageId': 'another-package',
          'state': 'failed',
          'progress': 0,
          'installedVersion': null,
          'failureCode': 'checksumMismatch',
        }),
      );

      final service = newService(root, downloads);
      final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');

      expect(status.packageId, 'paddleocr-ppocrv5-mobile-zh');
      expect(status.state, OcrModelInstallState.notInstalled);
    },
  );

  test('maps transport failures to stable download errors', () async {
    final bytes = utf8.encode('fake onnx model');
    final service = DeviceOcrModelPackageService(
      downloadClient: ThrowingDownloadClient(),
      trustedHosts: const {'models.example.test'},
      currentPlatform: OcrRuntimePlatform.android,
      appVersion: '1.0.0',
      storageRootProvider: () async => root,
      healthCheck: (_) async {},
    );

    await expectLater(
      service.install(manifest(version: '1.0.0', bytes: bytes)),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.downloadFailed,
        ),
      ),
    );
  });

  test(
    'delete removes active package and recovery marks interrupted state failed',
    () async {
      final bytes = utf8.encode('fake onnx model');
      downloads.add('https://models.example.test/det.onnx', bytes);
      final service = newService(root, downloads);
      await service.install(manifest(version: '1.0.0', bytes: bytes));
      await service.delete('paddleocr-ppocrv5-mobile-zh');
      expect(
        await service.getActivePackage('paddleocr-ppocrv5-mobile-zh'),
        isNull,
      );

      final packageRoot = Directory(
        '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh',
      );
      await packageRoot.create(recursive: true);
      await File('${packageRoot.path}/state.json').writeAsString(
        jsonEncode(<String, Object?>{
          'packageId': 'paddleocr-ppocrv5-mobile-zh',
          'state': 'downloading',
          'progress': 0.2,
          'installedVersion': null,
          'failureCode': null,
        }),
      );
      await Directory(
        '${packageRoot.path}/.staging/tmp',
      ).create(recursive: true);

      await service.recoverInterruptedInstallations();
      final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');
      expect(status.state, OcrModelInstallState.failed);
      expect(status.failureCode, OcrModelPackageErrorKind.cancelled.name);
      expect(await Directory('${packageRoot.path}/.staging').exists(), isFalse);
    },
  );
}

DeviceOcrModelPackageService newService(
  Directory root,
  FakeDownloadClient downloads, {
  Set<String> trustedHosts = const {'models.example.test'},
  OcrModelPackageHealthCheck? healthCheck,
}) {
  return DeviceOcrModelPackageService(
    downloadClient: downloads,
    trustedHosts: trustedHosts,
    currentPlatform: OcrRuntimePlatform.android,
    appVersion: '1.0.0',
    storageRootProvider: () async => root,
    healthCheck: healthCheck ?? (_) async {},
  );
}

OcrModelManifest manifest({
  required String version,
  required List<int> bytes,
  int? sizeBytes,
}) {
  return OcrModelManifest(
    schemaVersion: 1,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: version,
    engine: 'onnxruntime',
    platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
    languages: const <String>['zh-Hans', 'en'],
    minAppVersion: '0.1.0',
    license: 'Apache-2.0',
    files: <OcrModelFile>[
      OcrModelFile(
        role: 'detector',
        path: 'det.onnx',
        downloadUrl: 'https://models.example.test/det.onnx',
        sha256: sha256.convert(bytes).toString(),
        sizeBytes: sizeBytes ?? bytes.length,
      ),
    ],
  );
}

class FakeDownloadClient implements OcrModelDownloadClient {
  final Map<String, List<int>> _bytes = <String, List<int>>{};
  final List<String> openedUrls = <String>[];

  void add(String url, List<int> bytes) {
    _bytes[url] = bytes;
  }

  @override
  Future<OcrModelDownloadResponse> open(Uri uri) async {
    openedUrls.add(uri.toString());
    final bytes = _bytes[uri.toString()];
    if (bytes == null) {
      return const OcrModelDownloadResponse(
        statusCode: 404,
        bytes: Stream<List<int>>.empty(),
      );
    }
    return OcrModelDownloadResponse(
      statusCode: 200,
      contentLength: bytes.length,
      bytes: Stream<List<int>>.fromIterable(<List<int>>[bytes]),
    );
  }
}

class ThrowingDownloadClient implements OcrModelDownloadClient {
  @override
  Future<OcrModelDownloadResponse> open(Uri uri) {
    throw const SocketException('offline');
  }
}
