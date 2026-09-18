import '../../domain/access/app_capability.dart';

enum ImportLlmRoute { custom, managed }

/// 图片识别方式路由（识图引擎，IMAGE-001；融合见 BUG-006/ADR-0028）。
///
/// 图片内容（链接导入配图、本地图片导入）识别为文本的通道：
/// - [disabled]：不识别图片（纯文本/正文路径）。
/// - [ocr]：本地 OCR 模型（只提取文字）。
/// - [multimodal]：多模态 LLM（视觉观察，理解图片整体语义）。
/// - [ocrAndMultimodal]：自动融合——OCR 与多模态独立执行、分别结算，
///   任一路成功都保留，冲突字段由确认页展示（ADR-0028）。
enum ImportImageRecognitionRoute { disabled, ocr, multimodal, ocrAndMultimodal }

enum ImportAsrRoute { disabled, managed }

class ImportExecutionPlan {
  const ImportExecutionPlan({
    this.llm = ImportLlmRoute.custom,
    this.imageRecognition = ImportImageRecognitionRoute.disabled,
    this.asr = ImportAsrRoute.disabled,
  });

  final ImportLlmRoute llm;
  final ImportImageRecognitionRoute imageRecognition;
  final ImportAsrRoute asr;

  Set<AppCapability> get requiredCapabilities => <AppCapability>{
    AppCapability.publicContentImport,
    switch (llm) {
      ImportLlmRoute.custom => AppCapability.customLlm,
      ImportLlmRoute.managed => AppCapability.managedLlm,
    },
    if (imageRecognition == ImportImageRecognitionRoute.ocr ||
        imageRecognition == ImportImageRecognitionRoute.ocrAndMultimodal)
      AppCapability.localOcr,
    if (imageRecognition == ImportImageRecognitionRoute.multimodal ||
        imageRecognition == ImportImageRecognitionRoute.ocrAndMultimodal)
      AppCapability.multimodalLlm,
    if (asr == ImportAsrRoute.managed) AppCapability.managedAsr,
  };
}
