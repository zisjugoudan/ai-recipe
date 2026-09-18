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
    'Xiaohongshu PC webshare keeps query and uses fixed mobile headers',
    () async {
      final transport = _FakeImportHttpTransport((request) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: fixture('xiaohongshu_pc_webshare.html'),
          resolvedUri: request.uri,
          redirectCount: 0,
        );
      });
      final adapter = XiaohongshuPublicContentAdapter(
        transport: transport,
        clock: () => capturedAt,
      );
      final source = ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/public-note-fixture'
        '?source=webshare&xhsshare=pc_web'
        '&xsec_token=redacted-fixture-token&xsec_source=pc_share'
        '#ignored-fragment',
      );

      final content = await adapter.fetch(source);

      final request = transport.lastRequest;
      expect(request, isNotNull);
      expect(request!.uri.fragment, isEmpty);
      expect(request.uri.path, '/explore/public-note-fixture');
      expect(
        request.uri.query,
        'source=webshare&xhsshare=pc_web'
        '&xsec_token=redacted-fixture-token&xsec_source=pc_share',
      );
      expect(request.uri.queryParameters, <String, String>{
        'source': 'webshare',
        'xhsshare': 'pc_web',
        'xsec_token': 'redacted-fixture-token',
        'xsec_source': 'pc_share',
      });
      expect(request.headers, const <String, String>{
        'Accept':
            'text/html,application/xhtml+xml,application/json,text/plain;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14; Mobile) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/126.0.0.0 Mobile Safari/537.36',
      });
      final headerNames = request.headers.keys.map((key) => key.toLowerCase());
      expect(headerNames, isNot(contains('cookie')));
      expect(headerNames, isNot(contains('authorization')));
      expect(content.title, '网友没骗我！干锅花菜真的好吃哭');
      expect(content.media, hasLength(4));
      expect(
        content.media.every((item) => item.kind == ImportMediaKind.image),
        isTrue,
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

  test(
    'rejects a page that exposes neither text nor media without the target '
    'note id as retryable contentUnavailable',
    () async {
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
          isA<ImportContentAdapterException>()
              .having(
                (error) => error.kind,
                'kind',
                ImportContentAdapterErrorKind.contentUnavailable,
              )
              .having((error) => error.retryable, 'retryable', isTrue)
              .having(
                (error) => error.message,
                'message',
                contains('未获取到目标笔记内容'),
              ),
        ),
      );
    },
  );

  test(
    'keeps invalidPayload when the target note id exists but cannot be parsed',
    () async {
      final targetId = '6a421c6b00000000170297f9';
      final adapter = XiaohongshuPublicContentAdapter(
        transport: _FakeImportHttpTransport((_) async {
          return ImportHttpResponse(
            statusCode: 200,
            headers: const <String, String>{'content-type': 'text/html'},
            body: '<html><body>note id $targetId is present but no '
                'metadata can be extracted</body></html>',
            resolvedUri: Uri.parse(
              'https://www.xiaohongshu.com/explore/$targetId',
            ),
            redirectCount: 0,
          );
        }),
      );

      await expectLater(
        adapter.fetch(
          ImportSourceLink.parse(
            'https://www.xiaohongshu.com/explore/$targetId',
          ),
        ),
        throwsA(
          isA<ImportContentAdapterException>()
              .having(
                (error) => error.kind,
                'kind',
                ImportContentAdapterErrorKind.invalidPayload,
              )
              .having((error) => error.retryable, 'retryable', isFalse)
              .having(
                (error) => error.message,
                'message',
                contains('已获取到该笔记页面'),
              ),
        ),
      );
    },
  );

  test('maps an access-restricted page to retryable networkUnavailable', () async {
    final adapter = XiaohongshuPublicContentAdapter(
      transport: _FakeImportHttpTransport((_) async {
        return ImportHttpResponse(
          statusCode: 200,
          headers: const <String, String>{'content-type': 'text/html'},
          body: '<html><body>安全验证，请拖动滑块完成验证</body></html>',
          resolvedUri: Uri.parse('https://www.xiaohongshu.com/explore/verify'),
          redirectCount: 0,
        );
      }),
    );

    await expectLater(
      adapter.fetch(
        ImportSourceLink.parse('https://www.xiaohongshu.com/explore/verify'),
      ),
      throwsA(
        isA<ImportContentAdapterException>()
            .having(
              (error) => error.kind,
              'kind',
              ImportContentAdapterErrorKind.networkUnavailable,
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );
  });

  test(
    'maps a redirected /404 security page to retryable networkUnavailable',
    () async {
      final targetId = '6a421c6b00000000170297f9';
      final adapter = XiaohongshuPublicContentAdapter(
        transport: _FakeImportHttpTransport((_) async {
          return ImportHttpResponse(
            statusCode: 200,
            headers: const <String, String>{
              'content-type': 'text/html; charset=utf-8',
            },
            body: '<html><head><title>小红书</title></head>'
                '<body>window.__INITIAL_STATE__={}; '
                'note id $targetId referenced</body></html>',
            resolvedUri: Uri.parse(
              'https://www.xiaohongshu.com/404/sec_AkEqEBfZ',
            ),
            redirectCount: 1,
          );
        }),
      );

      await expectLater(
        adapter.fetch(
          ImportSourceLink.parse(
            'https://www.xiaohongshu.com/explore/$targetId',
          ),
        ),
        throwsA(
          isA<ImportContentAdapterException>()
              .having(
                (error) => error.kind,
                'kind',
                ImportContentAdapterErrorKind.networkUnavailable,
              )
              .having((error) => error.retryable, 'retryable', isTrue)
              .having(
                (error) => error.message,
                'message',
                contains('平台未返回笔记内容'),
              ),
        ),
      );
    },
  );

  test(
    'no-content errors stay user-facing and do not leak page body or debug text',
    () async {
      final targetId = '6a421c6b00000000170297f9';
      final adapter = XiaohongshuPublicContentAdapter(
        transport: _FakeImportHttpTransport((_) async {
          return ImportHttpResponse(
            statusCode: 200,
            headers: const <String, String>{'content-type': 'text/html'},
            body: '<html><head><title>secret recipe title</title></head>'
                '<body>note id $targetId is present but no metadata '
                'can be extracted</body></html>',
            resolvedUri: Uri.parse(
              'https://www.xiaohongshu.com/explore/$targetId',
            ),
            redirectCount: 0,
          );
        }),
      );

      await expectLater(
        adapter.fetch(
          ImportSourceLink.parse(
            'https://www.xiaohongshu.com/explore/$targetId',
          ),
        ),
        throwsA(
          isA<ImportContentAdapterException>()
              .having(
                (error) => error.message,
                'message',
                contains('已获取到该笔记页面'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('[调试]')),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains('metadata can be extracted')),
              ),
        ),
      );
    },
  );
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
