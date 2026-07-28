import '../../domain/llm/llm_cancellation_token.dart';

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
}
