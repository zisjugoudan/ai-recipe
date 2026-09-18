import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/ocr/ocr_model_package.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import 'platform_ocr_runtime_bridge.dart';

class PlatformOcrProvider implements OcrProvider {
  const PlatformOcrProvider({
    required OcrModelPackageService packageService,
    required OcrRuntimeBridge runtimeBridge,
    required String packageId,
  }) : _packageService = packageService,
       _runtimeBridge = runtimeBridge,
       _packageId = packageId;

  final OcrModelPackageService _packageService;
  final OcrRuntimeBridge _runtimeBridge;
  final String _packageId;

  @override
  OcrProviderKind get kind => OcrProviderKind.localPlugin;

  @override
  Future<OcrDocument> recognize(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final package = await _packageService.getActivePackage(_packageId);
    if (package == null) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.modelNotInstalled,
        message: '本地 OCR 模型尚未安装，请先在 OCR 设置中安装模型包。',
      );
    }

    final probe = await _runtimeBridge.probe();
    if (!probe.runtimeAvailable || !probe.recognitionSupported) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.unavailable,
        message: '本地 OCR 识别当前不可用，请检查 OCR 设置后重试。',
      );
    }

    cancellationToken?.throwIfCancelled();
    return _runtimeBridge.recognize(input: input, package: package);
  }
}
