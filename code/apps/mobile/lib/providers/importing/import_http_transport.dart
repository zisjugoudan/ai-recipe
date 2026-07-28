import '../../domain/importing/import_cancellation_token.dart';

enum ImportHttpTransportErrorKind {
  invalidRequest,
  invalidRedirect,
  tooManyRedirects,
  responseTooLarge,
  unsupportedContentType,
  network,
  timeout,
  cancelled,
}

class ImportHttpTransportException implements Exception {
  const ImportHttpTransportException({
    required this.kind,
    required this.message,
    required this.retryable,
  });

  final ImportHttpTransportErrorKind kind;
  final String message;
  final bool retryable;

  @override
  String toString() => 'ImportHttpTransportException(${kind.name}): $message';
}

class ImportHttpRequest {
  ImportHttpRequest({
    required this.uri,
    this.headers = const <String, String>{},
    required Iterable<String> allowedHosts,
    this.timeout = const Duration(seconds: 15),
    this.maxRedirects = 4,
    this.maxResponseBytes = 2 * 1024 * 1024,
    Iterable<String> acceptedContentTypes = const <String>{
      'text/html',
      'application/xhtml+xml',
      'text/plain',
      'application/json',
    },
  }) : allowedHosts = Set<String>.unmodifiable(
         allowedHosts.map((host) => host.trim().toLowerCase()),
       ),
       acceptedContentTypes = Set<String>.unmodifiable(
         acceptedContentTypes.map((type) => type.trim().toLowerCase()),
       ) {
    if (this.allowedHosts.isEmpty || this.allowedHosts.contains('')) {
      throw ArgumentError.value(
        allowedHosts,
        'allowedHosts',
        'must contain non-empty hosts',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (maxRedirects < 0) {
      throw ArgumentError.value(
        maxRedirects,
        'maxRedirects',
        'must be zero or greater',
      );
    }
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must be positive',
      );
    }
    if (this.acceptedContentTypes.isEmpty ||
        this.acceptedContentTypes.contains('')) {
      throw ArgumentError.value(
        acceptedContentTypes,
        'acceptedContentTypes',
        'must contain non-empty content types',
      );
    }
  }

  final Uri uri;
  final Map<String, String> headers;
  final Set<String> allowedHosts;
  final Duration timeout;
  final int maxRedirects;
  final int maxResponseBytes;
  final Set<String> acceptedContentTypes;
}

class ImportHttpResponse {
  const ImportHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.resolvedUri,
    required this.redirectCount,
  });

  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Uri resolvedUri;
  final int redirectCount;
}

abstract interface class ImportHttpTransport {
  Future<ImportHttpResponse> get(
    ImportHttpRequest request, {
    ImportCancellationToken? cancellationToken,
  });
}
