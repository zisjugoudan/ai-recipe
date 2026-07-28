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

class DeviceOcrModelPackageService implements OcrModelPackageService {
  DeviceOcrModelPackageService({
    required OcrModelDownloadClient downloadClient,
    required Set<String> trustedHosts,
    required OcrRuntimePlatform currentPlatform,
    required String appVersion,
    required OcrModelPackageHealthCheck healthCheck,
    OcrModelStorageRootProvider? storageRootProvider,
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
       _allowedFileExtensions = allowedFileExtensions;

  final OcrModelDownloadClient _downloadClient;
  final Set<String> _trustedHosts;
  final OcrRuntimePlatform _currentPlatform;
  final String _appVersion;
  final OcrModelPackageHealthCheck _healthCheck;
  final OcrModelStorageRootProvider _storageRootProvider;
  final Set<String> _allowedFileExtensions;

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
  }) async {
    _validateManifest(manifest);
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

    try {
      await root.create(recursive: true);
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
        await _downloadFile(
          file,
          stagingRoot,
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

      await _writeManifest(stagingRoot, manifest);
      await emit(
        OcrModelInstallState.verifying,
        0.9,
        installedVersion: existing?.version,
      );

      await stagingRoot.rename(versionRoot.path);
      final installed = OcrInstalledModelPackage(
        manifest: manifest,
        rootDirectory: versionRoot,
      );
      try {
        await _healthCheck(installed);
      } catch (_) {
        throw const OcrModelPackageException(
          kind: OcrModelPackageErrorKind.healthCheckFailed,
          message: 'OCR model package health check failed.',
        );
      }
      await _writeActive(root, manifest.version);
      return emit(
        OcrModelInstallState.installed,
        1,
        installedVersion: manifest.version,
      );
    } catch (error) {
      await _safeDelete(stagingRoot);
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
  Future<void> delete(String packageId) async {
    final normalizedId = _normalizePackageId(packageId);
    await _safeDelete(await _packageRoot(normalizedId));
  }

  @override
  Future<void> recoverInterruptedInstallations() async {
    final root = await _modelsRoot();
    if (!await root.exists()) return;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! Directory) continue;
      final staging = Directory(p.join(entry.path, '.staging'));
      await _safeDelete(staging);
      final packageId = p.basename(entry.path);
      final status = await _readStatus(entry, expectedPackageId: packageId);
      if (status == null || status.state == OcrModelInstallState.installed) {
        continue;
      }
      if (status.state == OcrModelInstallState.downloading ||
          status.state == OcrModelInstallState.verifying) {
        await _writeStatus(
          entry,
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
  }

  Future<void> _downloadFile(
    OcrModelFile file,
    Directory stagingRoot, {
    required Future<void> Function(int count) onBytes,
  }) async {
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
