import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/ocr/ocr_model_manifest.dart';
import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_model_package_exception.dart';
import '../../providers/ocr/http_ocr_model_download_client.dart';

typedef OcrModelStorageRootProvider = Future<Directory> Function();
typedef OcrModelStorageCapacityProvider =
    Future<int?> Function(Directory directory);

class DeviceOcrModelPackageService implements OcrModelPackageService {
  DeviceOcrModelPackageService({
    required OcrModelDownloadClient downloadClient,
    required Set<String> trustedHosts,
    required OcrRuntimePlatform currentPlatform,
    required String appVersion,
    required OcrModelPackageHealthCheck healthCheck,
    OcrModelStorageRootProvider? storageRootProvider,
    OcrModelStorageCapacityProvider? storageCapacityProvider,
    int minimumFreeSpaceReserveBytes = 64 * 1024 * 1024,
    int retainedInactiveVersions = 1,
    Set<String> allowedFileExtensions = const <String>{
      '.onnx',
      '.txt',
      '.json',
    },
  }) : _downloadClient = downloadClient,
       _trustedHosts = trustedHosts.map((host) => host.toLowerCase()).toSet(),
       _currentPlatform = currentPlatform,
       _appVersion = appVersion,
       _healthCheck = healthCheck,
       _storageRootProvider =
           storageRootProvider ?? _defaultModelStorageRootProvider,
       _storageCapacityProvider = storageCapacityProvider,
       minimumFreeSpaceReserveBytes = _requireNonNegative(
         minimumFreeSpaceReserveBytes,
         'minimumFreeSpaceReserveBytes',
       ),
       retainedInactiveVersions = _requireNonNegative(
         retainedInactiveVersions,
         'retainedInactiveVersions',
       ),
       _allowedFileExtensions = allowedFileExtensions;

  final OcrModelDownloadClient _downloadClient;
  final Set<String> _trustedHosts;
  final OcrRuntimePlatform _currentPlatform;
  final String _appVersion;
  final OcrModelPackageHealthCheck _healthCheck;
  final OcrModelStorageRootProvider _storageRootProvider;
  final OcrModelStorageCapacityProvider? _storageCapacityProvider;
  final int minimumFreeSpaceReserveBytes;
  final int retainedInactiveVersions;
  final Set<String> _allowedFileExtensions;
  final Map<String, Future<void>> _operationTails = <String, Future<void>>{};

  @override
  Future<OcrModelPackageStatus> getStatus(String packageId) async {
    final normalizedId = _normalizePackageId(packageId);
    try {
      final root = await _packageRoot(normalizedId);
      final state = await _readStatus(root, expectedPackageId: normalizedId);
      if (state != null) return state;
      final active = await getActivePackage(normalizedId);
      if (active != null) {
        return OcrModelPackageStatus(
          packageId: normalizedId,
          state: OcrModelInstallState.installed,
          progress: 1,
          installedVersion: active.version,
        );
      }
      return OcrModelPackageStatus(
        packageId: normalizedId,
        state: OcrModelInstallState.notInstalled,
        progress: 0,
      );
    } catch (error) {
      if (error is OcrModelPackageException) rethrow;
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.storageUnavailable,
        message: 'OCR model package status is unavailable.',
      );
    }
  }

  @override
  Future<OcrInstalledModelPackage?> getActivePackage(String packageId) async {
    final normalizedId = _normalizePackageId(packageId);
    final root = await _packageRoot(normalizedId);
    final activeFile = File(p.join(root.path, 'active.json'));
    if (!await activeFile.exists()) return null;
    try {
      final json = jsonDecode(await activeFile.readAsString());
      if (json is! Map || json['version'] is! String) return null;
      final version = OcrModelPackageStatus(
        packageId: normalizedId,
        state: OcrModelInstallState.installed,
        progress: 1,
        installedVersion: json['version'] as String,
      ).installedVersion!;
      final versionRoot = Directory(p.join(root.path, 'versions', version));
      final manifest = await _readManifest(versionRoot);
      if (manifest.packageId != normalizedId || manifest.version != version) {
        return null;
      }
      return OcrInstalledModelPackage(
        manifest: manifest,
        rootDirectory: versionRoot,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    _validateManifest(manifest);
    cancellationToken?.throwIfCancelled();
    return _runExclusive(
      manifest.packageId,
      () => _installUnlocked(
        manifest,
        onStatusChanged: onStatusChanged,
        cancellationToken: cancellationToken,
      ),
    );
  }

  Future<OcrModelPackageStatus> _installUnlocked(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final root = await _packageRoot(manifest.packageId);
    final existing = await getActivePackage(manifest.packageId);
    if (existing?.version == manifest.version) {
      final status = OcrModelPackageStatus(
        packageId: manifest.packageId,
        state: OcrModelInstallState.installed,
        progress: 1,
        installedVersion: manifest.version,
      );
      onStatusChanged?.call(status);
      await _writeStatus(root, status);
      return status;
    }

    final stagingRoot = Directory(
      p.join(
        root.path,
        '.staging',
        '${manifest.version}-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final versionsRoot = Directory(p.join(root.path, 'versions'));
    final versionRoot = Directory(p.join(versionsRoot.path, manifest.version));

    Future<OcrModelPackageStatus> emit(
      OcrModelInstallState state,
      double progress, {
      String? installedVersion,
      String? failureCode,
    }) async {
      final status = OcrModelPackageStatus(
        packageId: manifest.packageId,
        state: state,
        progress: progress.clamp(0, 1).toDouble(),
        installedVersion: installedVersion,
        failureCode: failureCode,
      );
      await _writeStatus(root, status);
      onStatusChanged?.call(status);
      return status;
    }

    var activated = false;
    try {
      await root.create(recursive: true);
      cancellationToken?.throwIfCancelled();
      await _ensureStorageCapacity(root, manifest.totalSizeBytes);
      cancellationToken?.throwIfCancelled();
      await versionsRoot.create(recursive: true);
      if (await versionRoot.exists()) {
        await versionRoot.delete(recursive: true);
      }
      await stagingRoot.create(recursive: true);
      await emit(
        OcrModelInstallState.downloading,
        0,
        installedVersion: existing?.version,
      );

      var downloaded = 0;
      final total = manifest.totalSizeBytes;
      for (final file in manifest.files) {
        cancellationToken?.throwIfCancelled();
        await _downloadFile(
          file,
          stagingRoot,
          cancellationToken: cancellationToken,
          onBytes: (count) async {
            downloaded += count;
            await emit(
              OcrModelInstallState.downloading,
              total == 0 ? 0 : downloaded / total * 0.8,
              installedVersion: existing?.version,
            );
          },
        );
      }

      cancellationToken?.throwIfCancelled();
      await _writeManifest(stagingRoot, manifest);
      await emit(
        OcrModelInstallState.verifying,
        0.9,
        installedVersion: existing?.version,
      );

      cancellationToken?.throwIfCancelled();
      await stagingRoot.rename(versionRoot.path);
      final installed = OcrInstalledModelPackage(
        manifest: manifest,
        rootDirectory: versionRoot,
      );
      cancellationToken?.throwIfCancelled();
      try {
        await _healthCheck(installed);
      } on OcrModelPackageException {
        rethrow;
      } catch (_) {
        throw const OcrModelPackageException(
          kind: OcrModelPackageErrorKind.healthCheckFailed,
          message: 'OCR model package health check failed.',
        );
      }
      cancellationToken?.throwIfCancelled();
      await _writeActive(root, manifest.version);
      activated = true;
      await _pruneInactiveVersionsBestEffort(
        root,
        activeVersion: manifest.version,
      );
      return await emit(
        OcrModelInstallState.installed,
        1,
        installedVersion: manifest.version,
      );
    } catch (error) {
      await _safeDelete(stagingRoot);
      if (activated) {
        final installedStatus = OcrModelPackageStatus(
          packageId: manifest.packageId,
          state: OcrModelInstallState.installed,
          progress: 1,
          installedVersion: manifest.version,
        );
        try {
          await _writeStatus(root, installedStatus);
        } catch (_) {
          // Activation is the commit point. A status persistence failure must
          // not delete or report a valid active package as a failed install.
        }
        return installedStatus;
      }

      final shouldDeleteNewVersion = existing?.version != manifest.version;
      if (shouldDeleteNewVersion) await _safeDelete(versionRoot);
      final mapped = _toPackageException(error);
      await emit(
        OcrModelInstallState.failed,
        0,
        installedVersion: existing?.version,
        failureCode: mapped.kind.name,
      );
      throw mapped;
    }
  }

  @override
  Future<void> delete(String packageId) {
    final normalizedId = _normalizePackageId(packageId);
    return _runExclusive(normalizedId, () async {
      await _safeDelete(await _packageRoot(normalizedId));
    });
  }

  @override
  Future<void> recoverInterruptedInstallations() async {
    final root = await _modelsRoot();
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final packageId = p.basename(entry.path);
      await _runExclusive(
        packageId,
        () => _recoverInterruptedInstallation(entry, packageId),
      );
    }
  }

  Future<void> _recoverInterruptedInstallation(
    Directory packageRoot,
    String packageId,
  ) async {
    await _safeDelete(Directory(p.join(packageRoot.path, '.staging')));
    final status = await _readStatus(packageRoot, expectedPackageId: packageId);
    if (status == null || status.state == OcrModelInstallState.installed) {
      return;
    }
    if (status.state == OcrModelInstallState.downloading ||
        status.state == OcrModelInstallState.verifying) {
      await _writeStatus(
        packageRoot,
        OcrModelPackageStatus(
          packageId: status.packageId,
          state: OcrModelInstallState.failed,
          progress: 0,
          installedVersion:
              status.installedVersion ??
              (await getActivePackage(status.packageId))?.version,
          failureCode: OcrModelPackageErrorKind.cancelled.name,
        ),
      );
    }
  }

  Future<T> _runExclusive<T>(
    String packageId,
    Future<T> Function() action,
  ) async {
    final previous = _operationTails[packageId];
    final gate = Completer<void>();
    final tail = gate.future;
    _operationTails[packageId] = tail;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A previous operation must not poison the package queue.
      }
    }
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_operationTails[packageId], tail)) {
        _operationTails.remove(packageId);
      }
    }
  }

  Future<void> _downloadFile(
    OcrModelFile file,
    Directory stagingRoot, {
    required Future<void> Function(int count) onBytes,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final uri = Uri.parse(file.downloadUrl);
    final response = await _downloadClient.open(uri);
    if (response.statusCode != 200) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.downloadFailed,
        message: 'OCR model file download failed.',
      );
    }
    if (response.contentLength != null &&
        response.contentLength != file.sizeBytes) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.sizeMismatch,
        message: 'OCR model file size does not match manifest.',
      );
    }

    final output = File(
      p.joinAll(<String>[stagingRoot.path, ...file.path.split('/')]),
    );
    await output.parent.create(recursive: true);
    final digestSink = _SingleDigestSink();
    final hashSink = sha256.startChunkedConversion(digestSink);
    final writer = output.openWrite();
    var bytesWritten = 0;
    try {
      await for (final chunk in response.bytes) {
        cancellationToken?.throwIfCancelled();
        bytesWritten += chunk.length;
        if (bytesWritten > file.sizeBytes) {
          throw const OcrModelPackageException(
            kind: OcrModelPackageErrorKind.sizeMismatch,
            message: 'OCR model file is larger than manifest.',
          );
        }
        hashSink.add(chunk);
        writer.add(chunk);
        await onBytes(chunk.length);
      }
    } finally {
      await writer.close();
      hashSink.close();
    }
    cancellationToken?.throwIfCancelled();
    if (bytesWritten != file.sizeBytes) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.sizeMismatch,
        message: 'OCR model file is smaller than manifest.',
      );
    }
    final digest = digestSink.value.toString();
    if (digest != file.sha256) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.checksumMismatch,
        message: 'OCR model file checksum does not match manifest.',
      );
    }
  }

  Future<void> _ensureStorageCapacity(
    Directory packageRoot,
    int packageSizeBytes,
  ) async {
    final capacityProvider = _storageCapacityProvider;
    if (capacityProvider == null) return;
    final availableBytes = await capacityProvider(packageRoot);
    if (availableBytes == null) return;
    if (availableBytes < 0) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.storageUnavailable,
        message: 'OCR model storage capacity is unavailable.',
      );
    }
    final requiredBytes = packageSizeBytes + minimumFreeSpaceReserveBytes;
    if (availableBytes < requiredBytes) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.insufficientStorage,
        message: 'Not enough storage space for the OCR model package.',
      );
    }
  }

  Future<void> _pruneInactiveVersionsBestEffort(
    Directory packageRoot, {
    required String activeVersion,
  }) async {
    try {
      await _pruneInactiveVersions(packageRoot, activeVersion: activeVersion);
    } catch (_) {
      // Version cleanup must never invalidate a successfully activated package.
    }
  }

  Future<void> _pruneInactiveVersions(
    Directory packageRoot, {
    required String activeVersion,
  }) async {
    final versionsRoot = Directory(p.join(packageRoot.path, 'versions'));
    if (!await versionsRoot.exists()) return;
    final versions = <Directory>[];
    await for (final entry in versionsRoot.list(followLinks: false)) {
      if (entry is Directory && _isSemanticVersion(p.basename(entry.path))) {
        versions.add(entry);
      }
    }
    versions.sort((left, right) {
      final leftVersion = p.basename(left.path);
      final rightVersion = p.basename(right.path);
      final comparison = _compareSemver(rightVersion, leftVersion);
      return comparison != 0 ? comparison : rightVersion.compareTo(leftVersion);
    });
    var retainedInactive = 0;
    for (final versionRoot in versions) {
      final version = p.basename(versionRoot.path);
      if (version == activeVersion) continue;
      if (retainedInactive < retainedInactiveVersions) {
        retainedInactive += 1;
        continue;
      }
      await _safeDelete(versionRoot);
    }
  }

  void _validateManifest(OcrModelManifest manifest) {
    if (!manifest.platforms.contains(_currentPlatform)) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.incompatiblePlatform,
        message: 'OCR model package does not support this platform.',
      );
    }
    if (_compareSemver(_appVersion, manifest.minAppVersion) < 0) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.incompatibleAppVersion,
        message: 'OCR model package requires a newer app version.',
      );
    }
    for (final file in manifest.files) {
      final host = Uri.parse(file.downloadUrl).host.toLowerCase();
      if (!_trustedHosts.contains(host)) {
        throw const OcrModelPackageException(
          kind: OcrModelPackageErrorKind.untrustedDownloadHost,
          message: 'OCR model download host is not trusted.',
        );
      }
      final extension = p.extension(file.path).toLowerCase();
      if (!_allowedFileExtensions.contains(extension)) {
        throw const OcrModelPackageException(
          kind: OcrModelPackageErrorKind.unsupportedFileType,
          message: 'OCR model package contains an unsupported file type.',
        );
      }
    }
  }

  Future<Directory> _modelsRoot() async {
    final base = await _storageRootProvider();
    return Directory(p.join(base.path, 'ocr-models'));
  }

  Future<Directory> _packageRoot(String packageId) async {
    return Directory(p.join((await _modelsRoot()).path, packageId));
  }

  Future<void> _writeActive(Directory packageRoot, String version) async {
    await _writeJsonAtomically(
      File(p.join(packageRoot.path, 'active.json')),
      <String, Object>{'version': version},
    );
  }

  Future<void> _writeManifest(
    Directory versionRoot,
    OcrModelManifest manifest,
  ) async {
    await _writeJsonAtomically(
      File(p.join(versionRoot.path, 'manifest.json')),
      manifest.toJson(),
    );
  }

  Future<OcrModelManifest> _readManifest(Directory versionRoot) async {
    final text = await File(
      p.join(versionRoot.path, 'manifest.json'),
    ).readAsString();
    final json = jsonDecode(text);
    if (json is! Map) {
      throw const FormatException('manifest must be an object');
    }
    return OcrModelManifest.fromJson(Map<String, Object?>.from(json));
  }

  Future<void> _writeStatus(
    Directory packageRoot,
    OcrModelPackageStatus status,
  ) async {
    await _writeJsonAtomically(
      File(p.join(packageRoot.path, 'state.json')),
      <String, Object?>{
        'packageId': status.packageId,
        'state': status.state.name,
        'progress': status.progress,
        'installedVersion': status.installedVersion,
        'failureCode': status.failureCode,
      },
    );
  }

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, Object?> value,
  ) async {
    await target.parent.create(recursive: true);
    final nonce = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final temporary = File('${target.path}.tmp-$nonce');
    final backup = File('${target.path}.bak-$nonce');
    await temporary.writeAsString(jsonEncode(value), flush: true);

    try {
      try {
        await temporary.rename(target.path);
        return;
      } on FileSystemException {
        if (!await target.exists()) rethrow;
      }

      await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
      } catch (_) {
        await _safeDelete(target);
        if (await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    } finally {
      await _safeDelete(temporary);
      if (await target.exists()) await _safeDelete(backup);
    }
  }

  Future<OcrModelPackageStatus?> _readStatus(
    Directory packageRoot, {
    required String expectedPackageId,
  }) async {
    final file = File(p.join(packageRoot.path, 'state.json'));
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) return null;
      final stateName = json['state'];
      final packageId = json['packageId'];
      final progress = json['progress'];
      if (stateName is! String ||
          packageId is! String ||
          packageId != expectedPackageId ||
          progress is! num) {
        return null;
      }
      final state = OcrModelInstallState.values.byName(stateName);
      return OcrModelPackageStatus(
        packageId: packageId,
        state: state,
        progress: progress.toDouble(),
        installedVersion: json['installedVersion'] as String?,
        failureCode: json['failureCode'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static OcrModelPackageException _toPackageException(Object error) {
    if (error is OcrModelPackageException) return error;
    if (error is SocketException || error is HttpException) {
      return const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.downloadFailed,
        message: 'OCR model file download failed.',
      );
    }
    if (error is FileSystemException) {
      return const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.storageUnavailable,
        message: 'OCR model storage is unavailable.',
      );
    }
    return const OcrModelPackageException(
      kind: OcrModelPackageErrorKind.unknown,
      message: 'OCR model package installation failed.',
    );
  }

  static String _normalizePackageId(String value) {
    try {
      return OcrModelPackageStatus(
        packageId: value,
        state: OcrModelInstallState.notInstalled,
        progress: 0,
      ).packageId;
    } catch (_) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.invalidPackage,
        message: 'OCR model package id is invalid.',
      );
    }
  }

  static Future<void> _safeDelete(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) {
        await entity.delete(recursive: true);
      }
    } catch (_) {
      // Cleanup best effort only. The next recovery pass will try again.
    }
  }

  static int _requireNonNegative(int value, String name) {
    if (value < 0) {
      throw ArgumentError.value(value, name, 'must not be negative');
    }
    return value;
  }

  static bool _isSemanticVersion(String value) {
    return RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
      r'(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
    ).hasMatch(value);
  }

  static int _compareSemver(String left, String right) {
    List<int> parts(String value) {
      final core = value.split(RegExp(r'[-+]')).first;
      return core.split('.').map(int.parse).toList(growable: false);
    }

    final a = parts(left);
    final b = parts(right);
    for (var i = 0; i < 3; i += 1) {
      final delta = a[i].compareTo(b[i]);
      if (delta != 0) return delta;
    }
    return 0;
  }

  static Future<Directory> _defaultModelStorageRootProvider() async {
    return getApplicationSupportDirectory();
  }
}

class _SingleDigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final result = _value;
    if (result == null) throw StateError('SHA-256 digest is unavailable.');
    return result;
  }

  @override
  void add(Digest data) {
    if (_value != null) throw StateError('SHA-256 digest was already set.');
    _value = data;
  }

  @override
  void close() {}
}
