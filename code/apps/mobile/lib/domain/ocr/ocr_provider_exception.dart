enum OcrProviderErrorKind {
  unavailable,
  modelNotInstalled,
  invalidInput,
  unauthorized,
  rateLimited,
  networkUnavailable,
  timeout,
  cancelled,
  invalidResponse,
  inferenceFailed,
  unknown,
}

class OcrProviderException implements Exception {
  const OcrProviderException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final OcrProviderErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'OcrProviderException(${kind.name}): $message';
}
