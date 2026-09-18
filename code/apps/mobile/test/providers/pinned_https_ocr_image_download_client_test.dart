import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/providers/ocr/ocr_remote_image_download_client.dart';
import 'package:ai_recipe/providers/ocr/pinned_https_ocr_image_download_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File destination;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-recipe-ocr-download-');
    destination = File('${root.path}${Platform.pathSeparator}image.tmp');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'downloads a Content-Length response through the pinned address',
    () async {
      final harness = _Harness(<String>[
        _response(
          headers: const <String>[
            'Content-Type: image/png',
            'Content-Length: 4',
          ],
          body: 'DATA',
        ),
      ]);

      final result = await harness.client.download(
        Uri.parse('https://images.example.test/dish.png'),
        destination,
      );

      expect(result.mimeType, 'image/png');
      expect(result.byteLength, 4);
      expect(await destination.readAsString(), 'DATA');
      expect(harness.addresses.single.address, '8.8.8.8');
      expect(
        harness.connections.single.requestText,
        contains('Host: images.example.test'),
      );
      expect(
        harness.connections.single.requestText,
        contains('Accept-Encoding: identity'),
      );
    },
  );

  test('downloads a chunked response', () async {
    final harness = _Harness(<String>[
      _response(
        headers: const <String>[
          'Content-Type: image/webp',
          'Transfer-Encoding: chunked',
        ],
        body: '4\r\nDATA\r\n0\r\n\r\n',
      ),
    ]);

    final result = await harness.client.download(
      Uri.parse('https://images.example.test/dish.webp'),
      destination,
    );

    expect(result.mimeType, 'image/webp');
    expect(await destination.readAsString(), 'DATA');
  });

  test('revalidates DNS on every redirect hop', () async {
    final harness = _Harness(<String>[
      _response(
        status: '302 Found',
        headers: const <String>['Location: https://cdn.example.test/final.jpg'],
      ),
      _response(
        headers: const <String>[
          'Content-Type: image/jpeg',
          'Content-Length: 2',
        ],
        body: 'OK',
      ),
    ]);

    await harness.client.download(
      Uri.parse('https://images.example.test/start'),
      destination,
    );

    expect(harness.resolvedHosts, <String>[
      'images.example.test',
      'cdn.example.test',
    ]);
    expect(harness.connections, hasLength(2));
  });

  test('rejects a redirect that downgrades to HTTP', () async {
    final harness = _Harness(<String>[
      _response(
        status: '301 Moved Permanently',
        headers: const <String>['Location: http://example.test/final.png'],
      ),
    ]);

    await expectLater(
      harness.client.download(
        Uri.parse('https://images.example.test/start'),
        destination,
      ),
      throwsA(_invalidInput),
    );
  });

  test('rejects a redirect to a private literal address', () async {
    final harness = _Harness(<String>[
      _response(
        status: '307 Temporary Redirect',
        headers: const <String>['Location: https://127.0.0.1/final.png'],
      ),
    ]);

    await expectLater(
      harness.client.download(
        Uri.parse('https://images.example.test/start'),
        destination,
      ),
      throwsA(_invalidInput),
    );
  });

  test('rejects oversized Content-Length before writing body', () async {
    final harness = _Harness(<String>[
      _response(
        headers: const <String>['Content-Type: image/png', 'Content-Length: 5'],
        body: '12345',
      ),
    ], maxBytes: 4);

    await expectLater(
      harness.client.download(
        Uri.parse('https://images.example.test/a.png'),
        destination,
      ),
      throwsA(_invalidInput),
    );
  });

  for (final sample in <({String name, String response})>[
    (
      name: 'unsupported MIME',
      response: _response(
        headers: const <String>['Content-Type: text/html', 'Content-Length: 2'],
        body: 'OK',
      ),
    ),
    (
      name: 'duplicate Content-Length',
      response: _response(
        headers: const <String>[
          'Content-Type: image/png',
          'Content-Length: 2',
          'Content-Length: 2',
        ],
        body: 'OK',
      ),
    ),
    (
      name: 'Content-Length with chunked encoding',
      response: _response(
        headers: const <String>[
          'Content-Type: image/png',
          'Content-Length: 2',
          'Transfer-Encoding: chunked',
        ],
        body: '2\r\nOK\r\n0\r\n\r\n',
      ),
    ),
  ]) {
    test('rejects ${sample.name}', () async {
      final harness = _Harness(<String>[sample.response]);
      await expectLater(
        harness.client.download(
          Uri.parse('https://images.example.test/a.png'),
          destination,
        ),
        throwsA(_invalidResponse),
      );
    });
  }

  test('rejects an oversized response header', () async {
    final harness = _Harness(<String>[
      _response(
        headers: <String>[
          'Content-Type: image/png',
          'X-Large: ${'a' * 100}',
          'Content-Length: 2',
        ],
        body: 'OK',
      ),
    ], maxResponseHeaderBytes: 64);

    await expectLater(
      harness.client.download(
        Uri.parse('https://images.example.test/a.png'),
        destination,
      ),
      throwsA(_invalidResponse),
    );
  });

  test('destroys the active connection when cancelled', () async {
    final controller = StreamController<List<int>>();
    final connection = _FakeConnection(
      controller.stream,
      onDestroy: controller.close,
    );
    final token = ImportCancellationToken();
    final client = PinnedHttpsOcrImageDownloadClient(
      hostResolver: (_) async => <InternetAddress>[InternetAddress('8.8.8.8')],
      connector:
          ({
            required uri,
            required address,
            required connectionTimeout,
            required tlsTimeout,
            cancellationToken,
          }) async => connection,
    );

    final future = client.download(
      Uri.parse('https://images.example.test/a.png'),
      destination,
      cancellationToken: token,
    );
    await Future<void>.delayed(Duration.zero);
    token.cancel();

    await expectLater(
      future,
      throwsA(isA<ImportOperationCancelledException>()),
    );
    expect(connection.destroyed, isTrue);
  });

  test('prefers IPv4 when DNS lists IPv6 addresses first', () async {
    // 真机实测：部分 CDN 的 IPv6 边缘节点会对非浏览器客户端返回 403，
    // 客户端应优先连接 IPv4 节点。
    final harness = _Harness(
      <String>[
        _response(
          headers: const <String>[
            'Content-Type: image/png',
            'Content-Length: 4',
          ],
          body: 'DATA',
        ),
      ],
      hostResolver: (_) async => <InternetAddress>[
        InternetAddress('2408:8756:2cf6:f014:41::'),
        InternetAddress('8.8.8.8'),
      ],
    );

    final result = await harness.client.download(
      Uri.parse('https://images.example.test/dish.png'),
      destination,
    );

    expect(result.byteLength, 4);
    expect(harness.addresses.single.address, '8.8.8.8');
  });

  test('tries the next resolved address when one is rejected with 403', () async {
    final harness = _Harness(
      <String>[
        _response(
          status: '403 Forbidden',
          headers: const <String>['Content-Type: text/plain'],
          body: 'Forbidden',
        ),
        _response(
          headers: const <String>[
            'Content-Type: image/png',
            'Content-Length: 4',
          ],
          body: 'DATA',
        ),
      ],
      hostResolver: (_) async => <InternetAddress>[
        InternetAddress('192.0.2.1'),
        InternetAddress('192.0.2.2'),
      ],
    );

    final result = await harness.client.download(
      Uri.parse('https://images.example.test/dish.png'),
      destination,
    );

    expect(result.byteLength, 4);
    expect(harness.addresses.map((item) => item.address), <String>[
      '192.0.2.1',
      '192.0.2.2',
    ]);
  });

  test('does not expose the source URL in mapped failures', () async {
    const secretUrl =
        'https://private-name.example.test/secret/path.png?token=value';
    final client = PinnedHttpsOcrImageDownloadClient(
      hostResolver: (_) async => throw const SocketException('resolver failed'),
    );

    try {
      await client.download(Uri.parse(secretUrl), destination);
      fail('Expected a provider exception.');
    } on OcrProviderException catch (error) {
      expect(error.toString(), isNot(contains('private-name')));
      expect(error.toString(), isNot(contains('secret/path')));
      expect(error.toString(), isNot(contains('token=value')));
    }
  });
}

class _Harness {
  _Harness(
    List<String> responses, {
    int maxBytes = 16 * 1024 * 1024,
    int maxResponseHeaderBytes = 32 * 1024,
    OcrHostResolver? hostResolver,
  }) : _responses = List<String>.of(responses) {
    client = PinnedHttpsOcrImageDownloadClient(
      maxBytes: maxBytes,
      maxResponseHeaderBytes: maxResponseHeaderBytes,
      hostResolver:
          hostResolver ??
          (host) async {
            resolvedHosts.add(host);
            return <InternetAddress>[InternetAddress('8.8.8.8')];
          },
      connector:
          ({
            required uri,
            required address,
            required connectionTimeout,
            required tlsTimeout,
            cancellationToken,
          }) async {
            addresses.add(address);
            final response = _responses.removeAt(0);
            final connection = _FakeConnection(
              Stream<List<int>>.fromIterable(<List<int>>[
                ascii.encode(response),
              ]),
            );
            connections.add(connection);
            return connection;
          },
    );
  }

  final List<String> _responses;
  final List<String> resolvedHosts = <String>[];
  final List<InternetAddress> addresses = <InternetAddress>[];
  final List<_FakeConnection> connections = <_FakeConnection>[];
  late final PinnedHttpsOcrImageDownloadClient client;
}

class _FakeConnection implements OcrPinnedHttpsConnection {
  _FakeConnection(this.incoming, {this.onDestroy});

  @override
  final Stream<List<int>> incoming;
  final FutureOr<void> Function()? onDestroy;
  final List<int> request = <int>[];
  bool destroyed = false;

  String get requestText => ascii.decode(request);

  @override
  void add(List<int> bytes) => request.addAll(bytes);

  @override
  Future<void> close() async {}

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    final result = onDestroy?.call();
    if (result is Future<void>) unawaited(result);
  }

  @override
  Future<void> flush() async {}
}

String _response({
  String status = '200 OK',
  List<String> headers = const <String>[],
  String body = '',
}) {
  return <String>['HTTP/1.1 $status', ...headers, '', body].join('\r\n');
}

final Matcher _invalidInput = isA<OcrProviderException>().having(
  (error) => error.kind,
  'kind',
  OcrProviderErrorKind.invalidInput,
);
final Matcher _invalidResponse = isA<OcrProviderException>().having(
  (error) => error.kind,
  'kind',
  OcrProviderErrorKind.invalidResponse,
);
