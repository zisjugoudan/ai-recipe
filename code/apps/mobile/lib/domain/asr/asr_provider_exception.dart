enum AsrProviderErrorKind {
  unavailable,
  modelNotInstalled,
  invalidInput,
  unsupportedMedia,
  durationExceeded,
  unauthorized,
  rateLimited,
  networkUnavailable,
  timeout,
  cancelled,
  invalidResponse,
  transcriptionFailed,
  unknown,
}

class AsrProviderException implements Exception {
  const AsrProviderException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final AsrProviderErrorKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AsrProviderException(${kind.name}): $message';
}
