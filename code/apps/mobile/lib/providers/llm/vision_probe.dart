import 'dart:convert';
import 'dart:typed_data';

import '../../domain/llm/llm_provider_exception.dart';

/// 内置 256×256 标准诊断图（BUG-006，ADR-0028）。
///
/// 白底、黑字 "AI RECIPE 314"、右上角纯红色方块。废弃原先无语义的 1×1 PNG：
/// 只有模型同时识别出文字与红色方块，才能证明图片链路与视觉能力真实有效。
/// 资产文件：`assets/diagnostics/vision_probe_v1.png`（固定 SHA-256，防止被误换）。

/// 标准诊断图资产文件的固定 SHA-256（与 `assets/diagnostics/vision_probe_v1.png` 一致）。
const String visionProbeSha256 =
    '7D6D7AB2E6450C8EB41B53968A121CA2F7201C2E744CD3A4D38BF469EC87902E';

/// 标准诊断图版本标识（与资产文件版本一致）。
const String visionProbeVersion = 'v1';

/// 标准诊断图宽高（像素）。
const int visionProbeWidth = 256;
const int visionProbeHeight = 256;

/// 标准诊断图字节（base64 内嵌，运行时无需 Flutter 资产加载）。
final Uint8List visionProbeBytes = base64Decode(
'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',
);

/// 标准诊断图固定提示词：只要求完成探针，不做菜谱生成。
const String visionProbePrompt =
    '只观察图片并返回 JSON，不要解释：{"text":"图片中读到的英文字母和数字","redSquare":true或false}';

/// 标准诊断图 JSON 断言结果。
class VisionProbeAssertion {
  const VisionProbeAssertion({
    required this.passed,
    this.failureKind,
    this.detail,
  });

  final bool passed;

  /// 失败时的稳定错误分类（`image_not_observed` 或 `invalid_response`）。
  final LlmProviderErrorKind? failureKind;
  final String? detail;
}

/// 解析多模态模型对标准诊断图的响应，两个断言必须同时满足：
/// 文字（规范化后等于 "AI RECIPE 314"）与红色方块（redSquare == true）。
///
/// 允许大小写、空白和常见 OCR 分隔差异；只返回 OK、空文本、通用描述或
/// 无法解析的 JSON 均不能判定图片能力通过。
VisionProbeAssertion assertVisionProbe(String responseBody) {
  final Object? decoded;
  try {
    decoded = jsonDecode(responseBody);
  } on FormatException {
    return const VisionProbeAssertion(
      passed: false,
      failureKind: LlmProviderErrorKind.invalidResponse,
      detail: '响应不是有效 JSON',
    );
  }
  if (decoded is! Map<String, Object?>) {
    return const VisionProbeAssertion(
      passed: false,
      failureKind: LlmProviderErrorKind.invalidResponse,
      detail: '响应不是 JSON 对象',
    );
  }
  final text = decoded['text'];
  final redSquare = decoded['redSquare'];
  final textMatches = text is String && _normalizeProbeText(text) == 'AIRECIPE314';
  final redSquareMatches = redSquare == true;
  if (textMatches && redSquareMatches) {
    return const VisionProbeAssertion(passed: true);
  }
  final List<String> missing = <String>[
    if (!textMatches) '文字「AI RECIPE 314」',
    if (!redSquareMatches) '红色方块',
  ];
  return VisionProbeAssertion(
    passed: false,
    failureKind: LlmProviderErrorKind.imageNotObserved,
    detail: '未识别到：${missing.join('、')}',
  );
}

/// 规范化标准图文字：只保留字母数字并转大写，容忍空白与分隔差异。
String _normalizeProbeText(String value) =>
    value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
