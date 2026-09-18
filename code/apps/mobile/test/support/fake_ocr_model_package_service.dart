import 'package:ai_recipe/domain/ocr/ocr_model_manifest.dart';
import 'package:ai_recipe/domain/ocr/ocr_model_package.dart';

class FakeOcrModelPackageService implements OcrModelPackageService {
  FakeOcrModelPackageService({OcrModelPackageStatus? status})
    : status =
          status ??
          OcrModelPackageStatus(
            packageId: packageId,
            state: OcrModelInstallState.notInstalled,
            progress: 0,
          );

  static const packageId = 'paddleocr-ppocrv5-mobile-zh';
  OcrModelPackageStatus status;
  int recoverCount = 0;
  int deleteCount = 0;
  Object? error;

  @override
  Future<void> delete(String packageId) async {
    if (error case final value?) throw value;
    deleteCount += 1;
    status = OcrModelPackageStatus(
      packageId: packageId,
      state: OcrModelInstallState.notInstalled,
      progress: 0,
    );
  }

  @override
  Future<OcrInstalledModelPackage?> getActivePackage(String packageId) async =>
      null;

  @override
  Future<OcrModelPackageStatus> getStatus(String packageId) async {
    if (error case final value?) throw value;
    return status;
  }

  @override
  Future<OcrModelPackageStatus> install(
    OcrModelManifest manifest, {
    void Function(OcrModelPackageStatus status)? onStatusChanged,
    OcrModelInstallCancellationToken? cancellationToken,
  }) async => status;

  @override
  Future<void> recoverInterruptedInstallations() async {
    if (error case final value?) throw value;
    recoverCount += 1;
  }
}
