import 'dart:async';
import 'dart:io';

import 'ocr_model_manifest.dart';
import 'ocr_model_package_exception.dart';

class OcrInstalledModelPackage {
  OcrInstalledModelPackage({
    required this.manifest,
    required Directory rootDirectory,
  }) : rootDirectory = rootDirectory.absolute;

  final OcrModelManifest manifest;
  final Directory rootDirectory;

  String get packageId => manifest.packageId;
  String get version => manifest.version;

  File fileFor(OcrModelFile file) => File('${rootDirectory.path}/${file.path}');
}

abstract interface class OcrModelPackageService {
  Future<OcrModelPackageStatus> getStatus(String packageId);

  Future<OcrInstalledModelPackage?> getActivePackage(String packageId);

  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  });

  Future<void> delete(String packageId);

  Future<void> recoverInterruptedInstallations();
}

typedef OcrModelPackageHealthCheck =
    Future<void> Function(OcrInstalledModelPackage package);

class OcrModelInstallCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const OcrModelPackageException(
        kind: OcrModelPackageErrorKind.cancelled,
        message: 'OCR model package installation was cancelled.',
      );
    }
  }
}
