import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/providers/llm/llm_transport.dart';

class FakeLlmTransport implements LlmTransport {
  FakeLlmTransport({required this.response});

  LlmHttpResponse response;
  LlmHttpRequest? lastRequest;
  LlmCancellationToken? lastCancellationToken;

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
}
