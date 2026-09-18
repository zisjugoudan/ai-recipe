import '../domain/ocr/ocr_model_manifest.dart';

/// 本地 OCR 模型下载受信主机白名单。
///
/// 只有出现在这里的下载主机才会被 [DeviceOcrModelPackageService] 接受，
/// 用于防止 Manifest 被篡改后从任意地址下载模型文件。
/// 校验按 `Uri.host` 精确匹配：ModelScope 直链实际主机为 `modelscope.cn`
/// （不带 www），需同时保留两种写法以防后续直链域名变化。
const Set<String> ocrTrustedModelHosts = <String>{
  'modelscope.cn',
  'www.modelscope.cn',
};

/// PP-OCRv5 mobile（中文）模型包正式清单（v1.0.0）。
///
/// 文件来源：RapidAI/RapidOCR 官方模型仓库（ModelScope，Apache-2.0）：
/// - 检测模型 `ch_PP-OCRv5_det_mobile.onnx`（DBNet）
/// - 识别模型 `ch_PP-OCRv5_rec_mobile.onnx`（SVTRv2）
/// - 识别字典 `ppocrv5_dict.txt`（首行全角空格为 blank，18383 项）
///
/// 下载地址、SHA-256 与字节大小均来自真实文件实测（2026-08-04），
/// 安装时按字节数与哈希双重校验，不允许伪造或占位。
final OcrModelManifest ocrPpocrV5MobileZhManifest = OcrModelManifest(
  schemaVersion: 2,
  packageId: 'paddleocr-ppocrv5-mobile-zh',
  version: '1.0.0',
  engine: 'onnxruntime',
  platforms: const <OcrRuntimePlatform>{OcrRuntimePlatform.android},
  languages: const <String>['zh'],
  minAppVersion: '1.0.0',
  license: 'Apache-2.0',
  files: <OcrModelFile>[
    OcrModelFile(
      role: 'detector',
      path: 'models/det.onnx',
      downloadUrl:
          'https://modelscope.cn/models/RapidAI/RapidOCR/resolve/master/'
          'onnx/PP-OCRv5/det/ch_PP-OCRv5_det_mobile.onnx',
      sha256: '4d97c44a20d30a81aad087d6a396b08f786c4635742afc391f6621f5c6ae78ae',
      sizeBytes: 4819576,
    ),
    OcrModelFile(
      role: 'recognizer',
      path: 'models/rec.onnx',
      downloadUrl:
          'https://modelscope.cn/models/RapidAI/RapidOCR/resolve/master/'
          'onnx/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile.onnx',
      sha256: '5825fc7ebf84ae7a412be049820b4d86d77620f204a041697b0494669b1742c5',
      sizeBytes: 16631306,
    ),
    OcrModelFile(
      role: 'dictionary',
      path: 'models/ppocrv5_dict.txt',
      downloadUrl:
          'https://modelscope.cn/models/RapidAI/RapidOCR/resolve/master/'
          'paddle/PP-OCRv5/rec/ch_PP-OCRv5_rec_mobile/ppocrv5_dict.txt',
      sha256: 'd1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b',
      sizeBytes: 74012,
    ),
  ],
  // PP-OCRv5 运行时参数与 RapidOCR 官方默认一致：
  // 检测端 limit_side_len=960、normalize bgr [0.485,0.456,0.406]/[0.229,0.224,0.225]；
  // 识别端输入 [3,48,320]、normalize bgr [0.5,0.5,0.5]、blank 索引 0。
  runtimeConfig: PaddleOcrRuntimeConfig(
    detector: PaddleOcrDetectionRuntimeConfig(),
    recognizer: PaddleOcrRecognitionRuntimeConfig(),
  ),
);
