import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/importing/import_cancellation_token.dart';
import 'import_http_transport.dart';

typedef ImportHttpClientFactory = http.Client Function();

class HttpImportTransport implements ImportHttpTransport {
  HttpImportTransport({ImportHttpClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? http.Client.new;

  final ImportHttpClientFactory _clientFactory;

  @override
  Future<ImportHttpResponse> get(
    ImportHttpRequest request, {
    ImportCancellationToken? cancellationToken,
  }) async {
    var currentUri = request.uri;
    var redirectCount = 0;
    _validateUri(currentUri, request.allowedHosts);

    while (true) {
      cancellationToken?.throwIfCancelled();
      final client = _clientFactory();
      try {
        final outgoing = http.Request('GET', currentUri)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.addAll(request.headers);
        final response = await _withCancellation(
          client.send(outgoing).timeout(request.timeout),
          cancellationToken,
          onCancel: client.close,
        );

        final responseHeaders = <String, String>{
          for (final entry in response.headers.entries)
            entry.key.toLowerCase(): entry.value,
        };

        if (_isRedirect(response.statusCode)) {
          if (redirectCount >= request.maxRedirects) {
            throw const ImportHttpTransportException(
              kind: ImportHttpTransportErrorKind.tooManyRedirects,
              message: 'The public content request redirected too many times.',
              retryable: false,
            );
          }
          final location = responseHeaders['location']?.trim();
          if (location == null || location.isEmpty) {
            throw const ImportHttpTransportException(
              kind: ImportHttpTransportErrorKind.invalidRedirect,
              message: 'The public content redirect is missing a location.',
              retryable: false,
            );
          }
          final nextUri = currentUri.resolve(location);
          _validateUri(nextUri, request.allowedHosts);
          if (currentUri.scheme.toLowerCase() == 'https' &&
              nextUri.scheme.toLowerCase() != 'https') {
            throw const ImportHttpTransportException(
              kind: ImportHttpTransportErrorKind.invalidRedirect,
              message:
                  'An HTTPS public content request cannot downgrade to HTTP.',
              retryable: false,
            );
          }
          currentUri = nextUri;
          redirectCount += 1;
          continue;
        }

        final contentType = _normalizedContentType(
          responseHeaders['content-type'],
        );
        if (contentType == null ||
            !request.acceptedContentTypes.contains(contentType)) {
          throw const ImportHttpTransportException(
            kind: ImportHttpTransportErrorKind.unsupportedContentType,
            message: 'The public content response type is not supported.',
            retryable: false,
          );
        }

        final declaredLength = response.contentLength;
        if (declaredLength != null &&
            declaredLength > request.maxResponseBytes) {
          throw const ImportHttpTransportException(
            kind: ImportHttpTransportErrorKind.responseTooLarge,
            message: 'The public content response is too large.',
            retryable: false,
          );
        }

        final bytes = await _readResponseBytes(
          response,
          timeout: request.timeout,
          maxResponseBytes: request.maxResponseBytes,
          cancellationToken: cancellationToken,
        );

        return ImportHttpResponse(
          statusCode: response.statusCode,
          headers: Map<String, String>.unmodifiable(responseHeaders),
          body: utf8.decode(bytes, allowMalformed: true),
          resolvedUri: currentUri,
          redirectCount: redirectCount,
        );
      } on ImportOperationCancelledException {
        throw const ImportHttpTransportException(
          kind: ImportHttpTransportErrorKind.cancelled,
          message: 'The public content request was cancelled.',
          retryable: false,
        );
      } on ImportHttpTransportException {
        rethrow;
      } on TimeoutException {
        throw const ImportHttpTransportException(
          kind: ImportHttpTransportErrorKind.timeout,
          message: 'The public content request timed out.',
          retryable: true,
        );
      } on SocketException {
        throw const ImportHttpTransportException(
          kind: ImportHttpTransportErrorKind.network,
          message: 'The public content request could not reach the network.',
          retryable: true,
        );
      } on http.ClientException {
        if (cancellationToken?.isCancelled ?? false) {
          throw const ImportHttpTransportException(
            kind: ImportHttpTransportErrorKind.cancelled,
            message: 'The public content request was cancelled.',
            retryable: false,
          );
        }
        throw const ImportHttpTransportException(
          kind: ImportHttpTransportErrorKind.network,
          message: 'The public content network request failed.',
          retryable: true,
        );
      } finally {
        client.close();
      }
    }
  }

  static Future<List<int>> _readResponseBytes(
    http.StreamedResponse response, {
    required Duration timeout,
    required int maxResponseBytes,
    ImportCancellationToken? cancellationToken,
  }) {
    final completer = Completer<List<int>>();
    final bytes = <int>[];
    StreamSubscription<List<int>>? subscription;

    subscription = response.stream
        .timeout(timeout)
        .listen(
          (chunk) {
            if (completer.isCompleted) return;
            if (bytes.length + chunk.length > maxResponseBytes) {
              completer.completeError(
                const ImportHttpTransportException(
                  kind: ImportHttpTransportErrorKind.responseTooLarge,
                  message: 'The public content response is too large.',
                  retryable: false,
                ),
              );
              unawaited(subscription?.cancel());
              return;
            }
            bytes.addAll(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete(List<int>.unmodifiable(bytes));
            }
          },
          cancelOnError: true,
        );

    cancellationToken?.whenCancelled.then((_) {
      if (completer.isCompleted) return;
      unawaited(subscription?.cancel());
      completer.completeError(const ImportOperationCancelledException());
    });

    return completer.future.whenComplete(() => subscription?.cancel());
  }

  static Future<T> _withCancellation<T>(
    Future<T> future,
    ImportCancellationToken? cancellationToken, {
    required void Function() onCancel,
  }) {
    if (cancellationToken == null) return future;
    return Future.any<T>(<Future<T>>[
      future,
      cancellationToken.whenCancelled.then<T>((_) {
        onCancel();
        throw const ImportOperationCancelledException();
      }),
    ]);
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static String? _normalizedContentType(String? header) {
    if (header == null) return null;
    final value = header.split(';').first.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }

  static void _validateUri(Uri uri, Set<String> allowedHosts) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        !allowedHosts.contains(host)) {
      throw const ImportHttpTransportException(
        kind: ImportHttpTransportErrorKind.invalidRequest,
        message:
            'The public content URL is outside the allowed platform hosts.',
        retryable: false,
      );
    }
  }
}
