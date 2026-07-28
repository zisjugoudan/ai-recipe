enum LlmProviderErrorKind {
  invalidConfiguration,
  unauthorized,
  notFound,
  rateLimited,
  timeout,
  cancelled,
  server,
  invalidResponse,
  network,
  unknown,
}

class LlmProviderException implements Exception {
  const LlmProviderException(this.kind, this.message, {this.statusCode});

  final LlmProviderErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
