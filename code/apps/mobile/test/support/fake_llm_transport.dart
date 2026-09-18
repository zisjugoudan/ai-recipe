import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/providers/llm/llm_transport.dart';

class FakeLlmTransport implements LlmTransport {
  FakeLlmTransport({required this.response});

  LlmHttpResponse response;
  LlmHttpRequest? lastRequest;
  LlmCancellationToken? lastCancellationToken;
  LlmDiagnosticReport Function()? diagnosticReport;

  @override
  Future<LlmHttpResponse> send(
    LlmHttpRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    lastRequest = request;
    lastCancellationToken = cancellationToken;
    return response;
  }

  @override
  Future<LlmDiagnosticReport> sendDiagnostic(
    LlmDiagnosticRequest request, {
    LlmCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return diagnosticReport != null
        ? diagnosticReport!()
        : const LlmDiagnosticReport(
            records: [],
            totalElapsedMs: 0,
            succeeded: true,
          );
  }
}
