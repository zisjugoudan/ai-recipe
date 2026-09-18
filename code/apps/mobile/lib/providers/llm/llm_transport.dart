import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_diagnostic.dart';
import '../../domain/llm/llm_provider_exception.dart';

export '../../domain/llm/llm_diagnostic.dart';

class LlmHttpRequest {
  const LlmHttpRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.timeout,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final Duration timeout;
}

class LlmHttpResponse {
  const LlmHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class LlmTransport {
  Future<LlmHttpResponse> send(
    LlmHttpRequest request, {
    LlmCancellationToken? cancellationToken,
  });

  /// 分阶段连接诊断（BUG-006，ADR-0028）。
  ///
  /// 返回 [LlmDiagnosticReport]；用户取消时抛 [LlmProviderException.cancelled]，
  /// 其余失败（连接失败、无首字节、正文空闲、HTTP 状态等）都通过报告返回，
  /// 不吞掉阶段记录。
  Future<LlmDiagnosticReport> sendDiagnostic(
    LlmDiagnosticRequest request, {
    LlmCancellationToken? cancellationToken,
  });
}
