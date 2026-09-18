import '../importing/import_cancellation_token.dart';
import 'ocr_models.dart';

abstract interface class OcrRemoteImageStager {
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  });
}

class StagedOcrImage {
  StagedOcrImage({
    required this.input,
    required this.byteLength,
    required this.width,
    required this.height,
    required Future<void> Function() dispose,
  }) : _dispose = dispose;

  final OcrImageInput input;
  final int byteLength;
  final int width;
  final int height;
  final Future<void> Function() _dispose;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _dispose();
  }
}
