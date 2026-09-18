import 'llm_cancellation_token.dart';
import 'llm_connection_config.dart';
import 'llm_diagnostic.dart';
import 'llm_provider.dart';
import 'llm_provider_exception.dart';

/// 一张需要多模态 LLM 识别内容的图片。
///
/// 图片字节由上层获取后传入（本地图直接读文件，远程图经安全暂存下载），
/// Provider 不感知图片来源，只负责编码并发送给多模态服务。
class MultimodalImageInput {
  MultimodalImageInput({
    required List<int> bytes,
    String? mimeType,
    this.width,
    this.height,
    required this.order,
  }) : bytes = List<int>.unmodifiable(bytes),
       mimeType = _optionalTrim(mimeType) {
    if (this.bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
    if (width != null && width! <= 0) {
      throw ArgumentError.value(width, 'width', 'must be greater than zero');
    }
    if (height != null && height! <= 0) {
      throw ArgumentError.value(height, 'height', 'must be greater than zero');
    }
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be non-negative');
    }
  }

  final List<int> bytes;
  final String? mimeType;
  final int? width;
  final int? height;
  final int order;
}

/// 多模态 LLM 识别单张图片的结果。
class MultimodalRecognitionResult {
  const MultimodalRecognitionResult({
    required this.text,
    required this.providerId,
    this.modelVersion,
    this.durationMs,
  });

  /// 模型返回的描述/提取文本（可为空，表示未识别出有用内容）。
  final String text;

  final String providerId;
  final String? modelVersion;
  final int? durationMs;
}

/// 多模态 LLM 契约：识别图片内容（不依赖本地 OCR 模型）。
///
/// 实现同时满足 [LlmProvider]（纯文本生成，用于连接测试），保证多模态
/// 配置可复用现有 LLM 设置用例的保存/测试/清除流程。
abstract class MultimodalLlmProvider extends LlmProvider {
  /// 识别单张图片内容，返回文本。
  Future<MultimodalRecognitionResult> recognizeImage({
    required LlmConnectionConfig config,
    required String apiKey,
    required MultimodalImageInput input,
    required String prompt,
    LlmCancellationToken? cancellationToken,
  });

  /// 校验图片字节可用于多模态请求（体积/类型等）。
  ///
  /// 返回 null 表示通过；返回非空字符串为中文失败原因。
  String? validateImageBytes({required List<int> bytes, String? mimeType});

  /// 分阶段连接诊断（BUG-006，ADR-0028）。
  ///
  /// - [imageProbe] 为 false：基础连接（纯文本最小请求），验证地址/鉴权/模型；
  ///   视觉专用模型拒绝纯文本时由上层识别并标记"文本能力未确认"。
  /// - [imageProbe] 为 true：发送内置 256×256 标准诊断图，验证图片协议与视觉能力。
  ///
  /// 失败信息通过返回的 [LlmDiagnosticReport] 承载（取消抛异常），阶段记录
  /// 不会因失败丢失。
  Future<LlmDiagnosticReport> diagnose({
    required LlmConnectionConfig config,
    required String apiKey,
    required bool imageProbe,
    LlmCancellationToken? cancellationToken,
  });
}

String? _optionalTrim(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
