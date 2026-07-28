import 'dart:io';

import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/providers/importing/import_http_transport.dart';
import 'package:ai_recipe/providers/importing/public_content_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final capturedAt = DateTime.utc(2026, 7, 28, 12);
  String fixture(String name) =>
      File('test/fixtures/importing/$name').readAsStringSync();

  test(
    'Xiaohongshu adapter builds unified content from a public fixture',
    () async {
      final transport = _FakeImportHttpTransport((request) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: fixture('xiaohongshu_public.html'),
          resolvedUri: Uri.parse('https://www.xiaohongshu.com/explore/123'),
          redirectCount: 1,
        );
      });
      final adapter = XiaohongshuPublicContentAdapter(
        transport: transport,
        clock: () => capturedAt,
      );
      final source = ImportSourceLink.parse('https://xhslink.com/a1b2c3');

      final content = await adapter.fetch(source);

      expect(content.source, same(source));
      expect(content.resolvedUrl, 'https://www.xiaohongshu.com/explore/123');
      expect(content.contentType, ImportContentType.mixed);
      expect(content.title, 'Braised Chicken Wings & Potatoes');
      expect(content.authorName, 'Kitchen Notes');
      expect(content.capturedAt, capturedAt);
      expect(
        content.textFragments.map((item) => item.kind),
        <ImportTextFragmentKind>[
          ImportTextFragmentKind.title,
          ImportTextFragmentKind.description,
          ImportTextFragmentKind.caption,
        ],
      );
      expect(content.media, hasLength(2));
      expect(
        content.media.every((item) => item.kind == ImportMediaKind.image),
        isTrue,
      );
      expect(
        content.warnings,
        containsAll(<ImportContentWarning>{
          ImportContentWarning.requiresOcr,
          ImportContentWarning.redirected,
        }),
      );
      expect(
        content.warnings,
        isNot(contains(ImportContentWarning.missingText)),
      );
      expect(transport.lastRequest?.allowedHosts, contains('xhslink.com'));
      expect(
        transport.lastRequest?.allowedHosts,
        contains('www.xiaohongshu.com'),
      );
      expect(transport.lastRequest?.headers.keys, isNot(contains('Cookie')));
      expect(
        transport.lastRequest?.headers.keys,
        isNot(contains('Authorization')),
      );
    },
  );

  test(
    'Douyin adapter exposes video, cover, and ASR/OCR requirements',
    () async {
      final transport = _FakeImportHttpTransport((_) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: fixture('douyin_public.html'),
          resolvedUri: Uri.parse('https://www.douyin.com/video/123456'),
          redirectCount: 0,
        );
      });
      final adapter = DouyinPublicContentAdapter(
        transport: transport,
        clock: () => capturedAt,
      );

      final content = await adapter.fetch(
        ImportSourceLink.parse('https://www.douyin.com/video/123456'),
      );

      expect(content.title, 'Quick Tomato Egg Stir Fry');
      expect(content.authorName, 'Home Cook');
      expect(content.contentType, ImportContentType.mixed);
      expect(
        content.media.where((item) => item.kind == ImportMediaKind.image),
        hasLength(2),
      );
      expect(
        content.media.where((item) => item.kind == ImportMediaKind.video),
        hasLength(2),
      );
      expect(
        content.warnings,
        containsAll(<ImportContentWarning>{
          ImportContentWarning.requiresOcr,
          ImportContentWarning.requiresAsr,
        }),
      );
      expect(
        content.warnings,
        isNot(contains(ImportContentWarning.redirected)),
      );
    },
  );

  test('plain text content remains usable and is marked as partial', () async {
    final transport = _FakeImportHttpTransport((_) async {
      return ImportHttpResponse(
        statusCode: 200,
        headers: const <String, String>{'content-type': 'text/plain'},
        body: 'Slice tofu. Fry until golden.',
        resolvedUri: Uri.parse('https://www.xiaohongshu.com/note/plain'),
        redirectCount: 0,
      );
    });
    final adapter = XiaohongshuPublicContentAdapter(
      transport: transport,
      clock: () => capturedAt,
    );

    final content = await adapter.fetch(
      ImportSourceLink.parse('https://www.xiaohongshu.com/note/plain'),
    );

    expect(content.contentType, ImportContentType.article);
    expect(content.textFragments.single.kind, ImportTextFragmentKind.body);
    expect(content.warnings, contains(ImportContentWarning.missingTitle));
    expect(content.warnings, contains(ImportContentWarning.missingMedia));
    expect(content.warnings, contains(ImportContentWarning.partialContent));
  });

  for (final testCase
      in <({int status, ImportContentAdapterErrorKind kind, bool retryable})>[
        (
          status: 401,
          kind: ImportContentAdapterErrorKind.authorizationRequired,
          retryable: false,
        ),
        (
          status: 403,
          kind: ImportContentAdapterErrorKind.authorizationRequired,
          retryable: false,
        ),
        (
          status: 404,
          kind: ImportContentAdapterErrorKind.contentUnavailable,
          retryable: false,
        ),
        (
          status: 410,
          kind: ImportContentAdapterErrorKind.contentUnavailable,
          retryable: false,
        ),
        (
          status: 408,
          kind: ImportContentAdapterErrorKind.timeout,
          retryable: true,
        ),
        (
          status: 429,
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          retryable: true,
        ),
        (
          status: 503,
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          retryable: true,
        ),
      ]) {
    test('maps HTTP ${testCase.status} to ${testCase.kind.name}', () async {
      final adapter = DouyinPublicContentAdapter(
        transport: _FakeImportHttpTransport((_) async {
          return ImportHttpResponse(
            statusCode: testCase.status,
            headers: const <String, String>{'content-type': 'text/html'},
            body: '<html>private-body-secret</html>',
            resolvedUri: Uri.parse('https://www.douyin.com/video/1'),
            redirectCount: 0,
          );
        }),
      );

      await expectLater(
        adapter.fetch(ImportSourceLink.parse('https://www.douyin.com/video/1')),
        throwsA(
          isA<ImportContentAdapterException>()
              .having((error) => error.kind, 'kind', testCase.kind)
              .having(
                (error) => error.retryable,
                'retryable',
                testCase.retryable,
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('private-body-secret')),
              ),
        ),
      );
    });
  }

  test('detects an explicit login page returned with HTTP 200', () async {
    final adapter = XiaohongshuPublicContentAdapter(
      transport: _FakeImportHttpTransport((_) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: fixture('login_required.html'),
          resolvedUri: Uri.parse('https://www.xiaohongshu.com/explore/login'),
          redirectCount: 0,
        );
      }),
    );

    await expectLater(
      adapter.fetch(
        ImportSourceLink.parse('https://www.xiaohongshu.com/explore/login'),
      ),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.authorizationRequired,
        ),
      ),
    );
  });

  test('detects an explicit unavailable page returned with HTTP 200', () async {
    final adapter = DouyinPublicContentAdapter(
      transport: _FakeImportHttpTransport((_) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: fixture('content_unavailable.html'),
          resolvedUri: Uri.parse('https://www.douyin.com/video/deleted'),
          redirectCount: 0,
        );
      }),
    );

    await expectLater(
      adapter.fetch(
        ImportSourceLink.parse('https://www.douyin.com/video/deleted'),
      ),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.contentUnavailable,
        ),
      ),
    );
  });

  test('maps transport safety failures to invalidPayload', () async {
    final adapter = DouyinPublicContentAdapter(
      transport: _FakeImportHttpTransport((_) async {
        throw const ImportHttpTransportException(
          kind: ImportHttpTransportErrorKind.responseTooLarge,
          message: 'secret response details',
          retryable: false,
        );
      }),
    );

    await expectLater(
      adapter.fetch(ImportSourceLink.parse('https://v.douyin.com/too-big')),
      throwsA(
        isA<ImportContentAdapterException>()
            .having(
              (error) => error.kind,
              'kind',
              ImportContentAdapterErrorKind.invalidPayload,
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret response details')),
            ),
      ),
    );
  });

  test('rejects a page that exposes neither text nor media', () async {
    final adapter = XiaohongshuPublicContentAdapter(
      transport: _FakeImportHttpTransport((_) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: '<html><body><div></div></body></html>',
          resolvedUri: Uri.parse('https://www.xiaohongshu.com/explore/empty'),
          redirectCount: 0,
        );
      }),
    );

    await expectLater(
      adapter.fetch(
        ImportSourceLink.parse('https://www.xiaohongshu.com/explore/empty'),
      ),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.invalidPayload,
        ),
      ),
    );
  });
}

typedef _TransportHandler =
    Future<ImportHttpResponse> Function(ImportHttpRequest request);

class _FakeImportHttpTransport implements ImportHttpTransport {
  _FakeImportHttpTransport(this.handler);

  final _TransportHandler handler;
  ImportHttpRequest? lastRequest;

  @override
  Future<ImportHttpResponse> get(
    ImportHttpRequest request, {
    cancellationToken,
  }) {
    lastRequest = request;
    return handler(request);
  }
}
