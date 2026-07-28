import 'dart:io';

import 'ocr_model_manifest.dart';

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
  });

  Future<void> delete(String packageId);

  Future<void> recoverInterruptedInstallations();
}

typedef OcrModelPackageHealthCheck =
    Future<void> Function(OcrInstalledModelPackage package);
