import 'dart:async';
import 'dart:convert';

import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/providers/importing/http_import_transport.dart';
import 'package:ai_recipe/providers/importing/import_http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const allowedHosts = <String>{'v.douyin.com', 'www.douyin.com'};

  ImportHttpRequest request({
    String url = 'https://v.douyin.com/abc/',
    Duration timeout = const Duration(seconds: 1),
    int maxRedirects = 4,
    int maxResponseBytes = 1024,
  }) => ImportHttpRequest(
    uri: Uri.parse(url),
    allowedHosts: allowedHosts,
    timeout: timeout,
    maxRedirects: maxRedirects,
    maxResponseBytes: maxResponseBytes,
  );

  test('returns a bounded UTF-8 response with normalized headers', () async {
    final requests = <http.BaseRequest>[];
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient((incoming) async {
        requests.add(incoming);
        return _response(
          '<html>ok</html>',
          headers: const <String, String>{
            'Content-Type': 'text/html; charset=utf-8',
            'X-Test': 'value',
          },
        );
      }),
    );

    final response = await transport.get(request());

    expect(response.statusCode, 200);
    expect(response.body, '<html>ok</html>');
    expect(response.resolvedUri, Uri.parse('https://v.douyin.com/abc/'));
    expect(response.redirectCount, 0);
    expect(response.headers['x-test'], 'value');
    expect(requests.single.headers, isNot(contains('authorization')));
    expect(requests.single.headers, isNot(contains('cookie')));
  });

  test('follows an allowed redirect and reports the final URI', () async {
    final visited = <Uri>[];
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient((incoming) async {
        visited.add(incoming.url);
        if (incoming.url.host == 'v.douyin.com') {
          return _response(
            '',
            statusCode: 302,
            headers: const <String, String>{
              'location': 'https://www.douyin.com/video/123',
              'content-type': 'text/html',
            },
          );
        }
        return _response(
          '<html>video</html>',
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }),
    );

    final response = await transport.get(request());

    expect(visited, <Uri>[
      Uri.parse('https://v.douyin.com/abc/'),
      Uri.parse('https://www.douyin.com/video/123'),
    ]);
    expect(response.redirectCount, 1);
    expect(response.resolvedUri, Uri.parse('https://www.douyin.com/video/123'));
  });

  test('rejects a redirect outside the platform host allowlist', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => _response(
          '',
          statusCode: 302,
          headers: const <String, String>{
            'location': 'https://example.com/private',
            'content-type': 'text/html',
          },
        ),
      ),
    );

    await expectLater(
      transport.get(request()),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.invalidRequest,
        ),
      ),
    );
  });

  test('rejects HTTPS to HTTP downgrade redirects', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => _response(
          '',
          statusCode: 302,
          headers: const <String, String>{
            'location': 'http://www.douyin.com/video/123',
            'content-type': 'text/html',
          },
        ),
      ),
    );

    await expectLater(
      transport.get(request()),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.invalidRedirect,
        ),
      ),
    );
  });

  test('enforces the maximum redirect count', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => _response(
          '',
          statusCode: 302,
          headers: const <String, String>{
            'location': 'https://v.douyin.com/next',
            'content-type': 'text/html',
          },
        ),
      ),
    );

    await expectLater(
      transport.get(request(maxRedirects: 1)),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.tooManyRedirects,
        ),
      ),
    );
  });

  test('rejects a declared response length above the limit', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(const <int>[1]),
          200,
          contentLength: 100,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      ),
    );

    await expectLater(
      transport.get(request(maxResponseBytes: 10)),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.responseTooLarge,
        ),
      ),
    );
  });

  test('stops streaming when the actual response exceeds the limit', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.fromIterable(const <List<int>>[
            <int>[1, 2],
            <int>[3, 4],
          ]),
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      ),
    );

    await expectLater(
      transport.get(request(maxResponseBytes: 3)),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.responseTooLarge,
        ),
      ),
    );
  });

  test('rejects unsupported content types before reading the body', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => _response(
          'binary',
          headers: const <String, String>{
            'content-type': 'application/octet-stream',
          },
        ),
      ),
    );

    await expectLater(
      transport.get(request()),
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.unsupportedContentType,
        ),
      ),
    );
  });

  test('cancels while a streamed response is still open', () async {
    final controller = StreamController<List<int>>();
    final token = ImportCancellationToken();
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient(
        (_) async => http.StreamedResponse(
          controller.stream,
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      ),
    );

    final responseFuture = transport.get(request(), cancellationToken: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();

    await expectLater(
      responseFuture,
      throwsA(
        isA<ImportHttpTransportException>().having(
          (error) => error.kind,
          'kind',
          ImportHttpTransportErrorKind.cancelled,
        ),
      ),
    );
    await controller.close();
  });

  test('maps request timeout without exposing transport details', () async {
    final transport = HttpImportTransport(
      clientFactory: () => _HandlerClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return _response(
          'late',
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }),
    );

    await expectLater(
      transport.get(request(timeout: const Duration(milliseconds: 5))),
      throwsA(
        isA<ImportHttpTransportException>()
            .having(
              (error) => error.kind,
              'kind',
              ImportHttpTransportErrorKind.timeout,
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });
}

class _HandlerClient extends http.BaseClient {
  _HandlerClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

http.StreamedResponse _response(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const <String, String>{
    'content-type': 'text/html',
  },
}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    contentLength: bytes.length,
    headers: headers,
  );
}
