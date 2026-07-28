import '../../domain/ocr/ocr_model_manifest.dart';
import '../../domain/ocr/ocr_model_package.dart';

class LocalOcrModelUseCases {
  const LocalOcrModelUseCases({required OcrModelPackageService packageService})
    : _packageService = packageService;

  final OcrModelPackageService _packageService;

  Future<OcrModelPackageStatus> getStatus(String packageId) {
    return _packageService.getStatus(packageId);
  }

  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) {
    return _packageService.install(
      manifest,
      onStatusChanged: onStatusChanged,
      cancellationToken: cancellationToken,
    );
  }

  Future<void> delete(String packageId) {
    return _packageService.delete(packageId);
  }

  Future<void> recoverInterruptedInstallations() {
    return _packageService.recoverInterruptedInstallations();
  }
}
