/// 图片识别方式（识图引擎，IMAGE-001）。
///
/// - [auto]：自动——多模态 LLM 就绪优先用多模态，否则回退本地 OCR，再否则纯文本。
/// - [ocr]：仅本地 OCR。
/// - [multimodalLlm]：仅多模态 LLM。
enum ImageRecognitionMode {
  auto,
  ocr,
  multimodalLlm;

  static ImageRecognitionMode fromWireName(String? value) {
    return switch (value) {
      'auto' => ImageRecognitionMode.auto,
      'ocr' => ImageRecognitionMode.ocr,
      'multimodalLlm' => ImageRecognitionMode.multimodalLlm,
      _ => ImageRecognitionMode.auto,
    };
  }

  String get wireName => switch (this) {
    ImageRecognitionMode.auto => 'auto',
    ImageRecognitionMode.ocr => 'ocr',
    ImageRecognitionMode.multimodalLlm => 'multimodalLlm',
  };
}

class LocalAppSettings {
  const LocalAppSettings({
    this.recordRecipeHistory = true,
    this.allowTextUpload = true,
    this.allowImageUpload = false,
    this.allowVideoUpload = false,
    this.imageRecognitionMode = ImageRecognitionMode.auto,
    required this.updatedAt,
  });

  final bool recordRecipeHistory;
  final bool allowTextUpload;
  final bool allowImageUpload;
  final bool allowVideoUpload;

  /// 图片识别方式：自动 / 仅 OCR / 仅多模态 LLM。
  final ImageRecognitionMode imageRecognitionMode;
  final DateTime updatedAt;
}

abstract interface class LocalAppSettingsRepository {
  Future<LocalAppSettings?> load();

  Future<void> save(LocalAppSettings settings);
}
