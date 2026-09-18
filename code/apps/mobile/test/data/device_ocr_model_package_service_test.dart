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

  test('persists and reopens the schema 2 runtime contract', () async {
    final detectorBytes = utf8.encode('fake detector model');
    final recognizerBytes = utf8.encode('fake recognizer model');
    final dictionaryBytes = utf8.encode('盐\n糖\n克\n');
    downloads
      ..add('https://models.example.test/detector.onnx', detectorBytes)
      ..add('https://models.example.test/recognizer.onnx', recognizerBytes)
      ..add('https://models.example.test/dictionary.txt', dictionaryBytes);
    final runtime = PaddleOcrRuntimeConfig(
      detector: PaddleOcrDetectionRuntimeConfig(),
      recognizer: PaddleOcrRecognitionRuntimeConfig(),
    );
    final service = newService(root, downloads);

    await service.install(
      schema2Manifest(
        detectorBytes: detectorBytes,
        recognizerBytes: recognizerBytes,
        dictionaryBytes: dictionaryBytes,
        runtime: runtime,
      ),
    );

    final reopened = newService(root, downloads);
    final active = await reopened.getActivePackage(
      'paddleocr-ppocrv5-mobile-zh',
    );
    expect(active, isNotNull);
    expect(active!.manifest.schemaVersion, 2);
    expect(active.manifest.runtimeConfig!.toJson(), runtime.toJson());

    final manifestFile = File(
      '${active.rootDirectory.path}${Platform.pathSeparator}manifest.json',
    );
    final persisted = Map<String, Object?>.from(
      jsonDecode(await manifestFile.readAsString()) as Map,
    );
    expect(persisted['runtimeConfig'], runtime.toJson());
  });

  test(
    'keeps an activated package when the final status callback fails',
    () async {
      final bytes = utf8.encode('fake onnx model');
      downloads.add('https://models.example.test/det.onnx', bytes);
      final service = newService(root, downloads);

      final status = await service.install(
        manifest(version: '1.0.0', bytes: bytes),
        onStatusChanged: (status) {
          if (status.state == OcrModelInstallState.installed) {
            throw StateError('observer failed after activation');
          }
        },
      );

      expect(status.state, OcrModelInstallState.installed);
      expect(status.installedVersion, '1.0.0');
      final active = await service.getActivePackage(
        'paddleocr-ppocrv5-mobile-zh',
      );
      expect(active?.version, '1.0.0');
      final persistedStatus = await service.getStatus(
        'paddleocr-ppocrv5-mobile-zh',
      );
      expect(persistedStatus.state, OcrModelInstallState.installed);
      expect(persistedStatus.installedVersion, '1.0.0');
    },
  );

  test('serializes concurrent installs for the same model package', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final healthCheckStarted = Completer<void>();
    final releaseHealthCheck = Completer<void>();
    final service = newService(
      root,
      downloads,
      healthCheck: (_) async {
        if (!healthCheckStarted.isCompleted) healthCheckStarted.complete();
        await releaseHealthCheck.future;
      },
    );
    final modelManifest = manifest(version: '1.0.0', bytes: bytes);

    final first = service.install(modelManifest);
    await healthCheckStarted.future;
    final second = service.install(modelManifest);
    releaseHealthCheck.complete();

    final results = await Future.wait(<Future<OcrModelPackageStatus>>[
      first,
      second,
    ]);
    expect(
      results.map((status) => status.state),
      everyElement(OcrModelInstallState.installed),
    );
    expect(downloads.openedUrls, hasLength(1));
  });

  test('continues queued installs after an earlier install fails', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final firstHealthCheckStarted = Completer<void>();
    final releaseFirstHealthCheck = Completer<void>();
    var healthCheckCalls = 0;
    final service = newService(
      root,
      downloads,
      healthCheck: (_) async {
        healthCheckCalls += 1;
        if (healthCheckCalls == 1) {
          firstHealthCheckStarted.complete();
          await releaseFirstHealthCheck.future;
          throw StateError('first health check failed');
        }
      },
    );
    final modelManifest = manifest(version: '1.0.0', bytes: bytes);

    final first = service.install(modelManifest);
    await firstHealthCheckStarted.future;
    final second = service.install(modelManifest);
    releaseFirstHealthCheck.complete();

    await expectLater(
      first,
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.healthCheckFailed,
        ),
      ),
    );
    final result = await second;

    expect(result.state, OcrModelInstallState.installed);
    expect(healthCheckCalls, 2);
    expect(downloads.openedUrls, hasLength(2));
  });

  test('delete waits for an in-flight install of the same package', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final healthCheckStarted = Completer<void>();
    final releaseHealthCheck = Completer<void>();
    final service = newService(
      root,
      downloads,
      healthCheck: (_) async {
        healthCheckStarted.complete();
        await releaseHealthCheck.future;
      },
    );

    final installation = service.install(
      manifest(version: '1.0.0', bytes: bytes),
    );
    await healthCheckStarted.future;
    var deleteCompleted = false;
    final deletion = service
        .delete('paddleocr-ppocrv5-mobile-zh')
        .whenComplete(() => deleteCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(deleteCompleted, isFalse);
    releaseHealthCheck.complete();
    await installation;
    await deletion;
    expect(
      await service.getActivePackage('paddleocr-ppocrv5-mobile-zh'),
      isNull,
    );
  });

  test('recovery waits for an in-flight install of the same package', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final healthCheckStarted = Completer<void>();
    final releaseHealthCheck = Completer<void>();
    final service = newService(
      root,
      downloads,
      healthCheck: (_) async {
        healthCheckStarted.complete();
        await releaseHealthCheck.future;
      },
    );

    final installation = service.install(
      manifest(version: '1.0.0', bytes: bytes),
    );
    await healthCheckStarted.future;
    var recoveryCompleted = false;
    final recovery = service.recoverInterruptedInstallations().whenComplete(
      () => recoveryCompleted = true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(recoveryCompleted, isFalse);
    releaseHealthCheck.complete();
    await installation;
    await recovery;
    final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');
    expect(status.state, OcrModelInstallState.installed);
    expect(status.installedVersion, '1.0.0');
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

  test('cancels an in-flight download and clears staging state', () async {
    final firstChunk = utf8.encode('fake ');
    final secondChunk = utf8.encode('onnx model');
    final bytes = <int>[...firstChunk, ...secondChunk];
    downloads.addChunks('https://models.example.test/det.onnx', <List<int>>[
      firstChunk,
      secondChunk,
    ]);
    final service = newService(root, downloads);
    final token = OcrModelInstallCancellationToken();

    await expectLater(
      service.install(
        manifest(version: '1.0.0', bytes: bytes),
        cancellationToken: token,
        onStatusChanged: (status) {
          if (status.state == OcrModelInstallState.downloading &&
              status.progress > 0) {
            token.cancel();
          }
        },
      ),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.cancelled,
        ),
      ),
    );

    final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');
    expect(status.state, OcrModelInstallState.failed);
    expect(status.failureCode, OcrModelPackageErrorKind.cancelled.name);
    expect(
      await service.getActivePackage('paddleocr-ppocrv5-mobile-zh'),
      isNull,
    );
    final stagingRoot = Directory(
      '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh/.staging',
    );
    final stagingEntries = await stagingRoot.exists()
        ? await stagingRoot.list().toList()
        : <FileSystemEntity>[];
    expect(stagingEntries, isEmpty);
  });

  test('cancelled upgrade preserves the previous active version', () async {
    final firstBytes = utf8.encode('first model');
    downloads.add('https://models.example.test/det.onnx', firstBytes);
    final service = newService(root, downloads);
    await service.install(manifest(version: '1.0.0', bytes: firstBytes));

    final firstChunk = utf8.encode('second ');
    final secondChunk = utf8.encode('model');
    final secondBytes = <int>[...firstChunk, ...secondChunk];
    downloads.addChunks('https://models.example.test/det.onnx', <List<int>>[
      firstChunk,
      secondChunk,
    ]);
    final token = OcrModelInstallCancellationToken();

    await expectLater(
      service.install(
        manifest(version: '2.0.0', bytes: secondBytes),
        cancellationToken: token,
        onStatusChanged: (status) {
          if (status.state == OcrModelInstallState.downloading &&
              status.progress > 0) {
            token.cancel();
          }
        },
      ),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.cancelled,
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
  });

  test('rejects insufficient storage before opening a download', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final service = newService(
      root,
      downloads,
      storageCapacityProvider: (_) async => bytes.length - 1,
      minimumFreeSpaceReserveBytes: 0,
    );

    await expectLater(
      service.install(manifest(version: '1.0.0', bytes: bytes)),
      throwsA(
        isA<OcrModelPackageException>().having(
          (error) => error.kind,
          'kind',
          OcrModelPackageErrorKind.insufficientStorage,
        ),
      ),
    );

    expect(downloads.openedUrls, isEmpty);
    final status = await service.getStatus('paddleocr-ppocrv5-mobile-zh');
    expect(status.state, OcrModelInstallState.failed);
    expect(
      status.failureCode,
      OcrModelPackageErrorKind.insufficientStorage.name,
    );
  });

  test('continues installation when storage capacity is unknown', () async {
    final bytes = utf8.encode('fake onnx model');
    downloads.add('https://models.example.test/det.onnx', bytes);
    final service = newService(
      root,
      downloads,
      storageCapacityProvider: (_) async => null,
    );

    final status = await service.install(
      manifest(version: '1.0.0', bytes: bytes),
    );

    expect(status.state, OcrModelInstallState.installed);
    expect(downloads.openedUrls, hasLength(1));
  });

  test(
    'retains the active and one newest inactive version by default',
    () async {
      final service = newService(root, downloads);
      for (final version in <String>['1.0.0', '2.0.0', '3.0.0']) {
        final bytes = utf8.encode('model $version');
        downloads.add('https://models.example.test/det.onnx', bytes);
        await service.install(manifest(version: version, bytes: bytes));
      }

      final versionsRoot = Directory(
        '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh/versions',
      );
      final versions = await versionsRoot
          .list()
          .where((entry) => entry is Directory)
          .map((entry) => entry.path.split(Platform.pathSeparator).last)
          .toList();

      expect(versions, unorderedEquals(<String>['2.0.0', '3.0.0']));
    },
  );

  test('can prune every inactive model version', () async {
    final service = newService(root, downloads, retainedInactiveVersions: 0);
    for (final version in <String>['1.0.0', '2.0.0']) {
      final bytes = utf8.encode('model $version');
      downloads.add('https://models.example.test/det.onnx', bytes);
      await service.install(manifest(version: version, bytes: bytes));
    }

    final versionsRoot = Directory(
      '${root.path}/ocr-models/paddleocr-ppocrv5-mobile-zh/versions',
    );
    final versions = await versionsRoot
        .list()
        .where((entry) => entry is Directory)
        .map((entry) => entry.path.split(Platform.pathSeparator).last)
        .toList();

    expect(versions, <String>['2.0.0']);
  });

  test('rejects negative storage policy values', () {
    expect(
      () => newService(root, downloads, minimumFreeSpaceReserveBytes: -1),
      throwsArgumentError,
    );
    expect(
      () => newService(root, downloads, retainedInactiveVersions: -1),
      throwsArgumentError,
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
  OcrModelStorageCapacityProvider? storageCapacityProvider,
  int minimumFreeSpaceReserveBytes = 64 * 1024 * 1024,
  int retainedInactiveVersions = 1,
}) {
  return DeviceOcrModelPackageService(
    downloadClient: downloads,
    trustedHosts: trustedHosts,
    currentPlatform: OcrRuntimePlatform.android,
    appVersion: '1.0.0',
    storageRootProvider: () async => root,
    storageCapacityProvider: storageCapacityProvider,
    minimumFreeSpaceReserveBytes: minimumFreeSpaceReserveBytes,
    retainedInactiveVersions: retainedInactiveVersions,
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

OcrModelManifest schema2Manifest({
  required List<int> detectorBytes,
  required List<int> recognizerBytes,
  required List<int> dictionaryBytes,
  required PaddleOcrRuntimeConfig runtime,
}) {
  OcrModelFile file(String role, String path, List<int> bytes) {
    return OcrModelFile(
      role: role,
      path: path,
      downloadUrl: 'https://models.example.test/$path',
      sha256: sha256.convert(bytes).toString(),
      sizeBytes: bytes.length,
    );
  }

  return OcrModelManifest(
    schemaVersion: 2,
    packageId: 'paddleocr-ppocrv5-mobile-zh',
    version: '2.0.0',
    engine: 'onnxruntime',
    platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
    languages: const <String>['zh-Hans', 'en'],
    minAppVersion: '0.1.0',
    license: 'Apache-2.0',
    files: <OcrModelFile>[
      file('detector', 'detector.onnx', detectorBytes),
      file('recognizer', 'recognizer.onnx', recognizerBytes),
      file('dictionary', 'dictionary.txt', dictionaryBytes),
    ],
    runtimeConfig: runtime,
  );
}

class FakeDownloadClient implements OcrModelDownloadClient {
  final Map<String, List<List<int>>> _chunks = <String, List<List<int>>>{};
  final List<String> openedUrls = <String>[];

  void add(String url, List<int> bytes) {
    addChunks(url, <List<int>>[bytes]);
  }

  void addChunks(String url, List<List<int>> chunks) {
    _chunks[url] = chunks;
  }

  @override
  Future<OcrModelDownloadResponse> open(Uri uri) async {
    openedUrls.add(uri.toString());
    final chunks = _chunks[uri.toString()];
    if (chunks == null) {
      return const OcrModelDownloadResponse(
        statusCode: 404,
        bytes: Stream<List<int>>.empty(),
      );
    }
    return OcrModelDownloadResponse(
      statusCode: 200,
      contentLength: chunks.fold<int>(
        0,
        (total, chunk) => total + chunk.length,
      ),
      bytes: Stream<List<int>>.fromIterable(chunks),
    );
  }
}

class ThrowingDownloadClient implements OcrModelDownloadClient {
  @override
  Future<OcrModelDownloadResponse> open(Uri uri) {
    throw const SocketException('offline');
  }
}
