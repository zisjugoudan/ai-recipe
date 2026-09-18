import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/providers/importing/webview_content_fetcher.dart';
import 'package:ai_recipe/providers/importing/webview_import_content_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = ImportSourceLink.parse('https://www.xiaohongshu.com/explore/1');

  WebViewImportContentAdapter adapter({
    required WebViewContentFetcher fetcher,
    ImportSourcePlatform platform = ImportSourcePlatform.xiaohongshu,
  }) {
    return WebViewImportContentAdapter(
      fetcher: fetcher,
      platform: platform,
      clock: () => DateTime.utc(2026, 8, 3, 12),
    );
  }

  test('maps WebView DOM extraction to ImportContent', () async {
    // 通用 web 平台：浏览器会话未下载到图片时保留远程直连快速路径。
    final webSource = ImportSourceLink.parse('https://example.com/recipe');
    final adapter = adapter(
      fetcher: _FakeWebViewContentFetcher(
        const WebViewFetchResult(
          title: '青椒炒肉',
          description: '家常下饭菜',
          authorName: '美食博主',
          bodyText: '食材：青椒、猪肉。做法：大火翻炒。',
          imageUrls: <String>[
            'http://cdn.example.com/photo1.jpg',
            '/local/photo2.jpg',
          ],
          images: const <WebViewDownloadedImage>[],
          resolvedUrl: 'https://example.com/recipe',
        ),
      ),
      platform: ImportSourcePlatform.web,
    );

    final content = await adapter.fetch(webSource);

    expect(content.title, '青椒炒肉');
    expect(content.description, '家常下饭菜');
    expect(content.authorName, '美食博主');
    expect(
      content.textFragments.map((fragment) => fragment.text),
      <String>['青椒炒肉', '家常下饭菜', '食材：青椒、猪肉。做法：大火翻炒。'],
    );
    // 相对路径图片以页面地址解析为绝对 URL（web 平台回退直连）。
    expect(content.media.map((media) => media.remoteUrl), <String>[
      'http://cdn.example.com/photo1.jpg',
      'https://example.com/local/photo2.jpg',
    ]);
    expect(content.media.every((media) => media.kind == ImportMediaKind.image),
        isTrue);
  });

  test('xiaohongshu 平台图片未下载时不回退远程直连（ADR-0019）', () async {
    // 已知小红书 CDN 拒绝应用网络栈，回退只会重复 403 并混淆日志。
    final adapter = adapter(
      fetcher: _FakeWebViewContentFetcher(
        const WebViewFetchResult(
          title: '青椒炒肉',
          description: '',
          authorName: '',
          bodyText: '正文内容',
          imageUrls: <String>['http://cdn.xhscdn.com/note1.webp'],
          images: const <WebViewDownloadedImage>[],
          resolvedUrl: 'https://www.xiaohongshu.com/explore/1',
        ),
      ),
    );

    final content = await adapter.fetch(source);

    expect(content.media, isEmpty);
    expect(content.warnings, contains(ImportContentWarning.missingMedia));
  });

  test('rejects platform mismatch and non-http URLs', () async {
    final adapter = adapter(
      fetcher: _FakeWebViewContentFetcher(
        const WebViewFetchResult(
          title: '标题',
          description: '',
          authorName: '',
          bodyText: '',
          imageUrls: <String>[], images: const <WebViewDownloadedImage>[],
          resolvedUrl: 'https://example.com/',
        ),
      ),
      platform: ImportSourcePlatform.douyin,
    );

    await expectLater(
      adapter.fetch(source),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.unsupportedPlatform,
        ),
      ),
    );

    final webAdapter = adapter(
      fetcher: _FakeWebViewContentFetcher(
        const WebViewFetchResult(
          title: '标题',
          description: '',
          authorName: '',
          bodyText: '',
          imageUrls: <String>[], images: const <WebViewDownloadedImage>[],
          resolvedUrl: '',
        ),
      ),
    );
    await expectLater(
      webAdapter.fetch(
        ImportSourceLink.parse('https://example.com/recipe'),
      ),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.unsupportedPlatform,
        ),
      ),
    );
  });

  test('maps WebView errors to adapter error kinds', () async {
    final cases = <String, (ImportContentAdapterErrorKind, bool)>{
      'loginRequired': (ImportContentAdapterErrorKind.authorizationRequired, false),
      'timeout': (ImportContentAdapterErrorKind.timeout, true),
      'network': (ImportContentAdapterErrorKind.networkUnavailable, true),
      'emptyContent': (ImportContentAdapterErrorKind.contentUnavailable, false),
      'unavailable': (ImportContentAdapterErrorKind.invalidPayload, false),
    };

    for (final entry in cases.entries) {
      final kind = entry.key;
      final adapter = adapter(
        fetcher: _FakeWebViewContentFetcher(
          const WebViewFetchResult(
            title: '',
            description: '',
            authorName: '',
            bodyText: '',
            imageUrls: <String>[], images: const <WebViewDownloadedImage>[],
            resolvedUrl: '',
          ),
          throwError: WebViewFetchException(
            WebViewFetchErrorKind.values.byName(kind),
            'error-$kind',
          ),
        ),
      );
      await expectLater(
        adapter.fetch(source),
        throwsA(
          isA<ImportContentAdapterException>()
              .having((error) => error.kind, 'kind', entry.value.$1)
              .having((error) => error.retryable, 'retryable', entry.value.$2),
        ),
      );
    }
  });

  test('throws contentUnavailable when page has neither text nor images',
      () async {
    final adapter = adapter(
      fetcher: _FakeWebViewContentFetcher(
        const WebViewFetchResult(
          title: '',
          description: '',
          authorName: '',
          bodyText: '',
          imageUrls: <String>[], images: const <WebViewDownloadedImage>[],
          resolvedUrl: '',
        ),
      ),
    );

    await expectLater(
      adapter.fetch(source),
      throwsA(
        isA<ImportContentAdapterException>().having(
          (error) => error.kind,
          'kind',
          ImportContentAdapterErrorKind.contentUnavailable,
        ),
      ),
    );
  });
}

class _FakeWebViewContentFetcher implements WebViewContentFetcher {
  _FakeWebViewContentFetcher(this._result, {this.throwError});

  final WebViewFetchResult _result;
  final WebViewFetchException? throwError;

  @override
  Future<WebViewFetchResult> fetch(
    String url, {
    String platform = 'web',
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final error = throwError;
    if (error != null) throw error;
    return _result;
  }

  @override
  Future<void> cancel() async {
    // 测试替身：无副作用。
  }
}
