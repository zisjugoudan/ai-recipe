import 'package:flutter/foundation.dart';

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_content_adapter.dart';
import '../../domain/importing/import_task.dart';
import 'webview_content_fetcher.dart';

typedef ImportClock = DateTime Function();

/// 浏览器内核（WebView）链接导入 Adapter（IMPORT-008）。
///
/// 用内置浏览器内核加载任意网页，从 DOM 提取标题、正文、作者与图片地址，
/// 映射为 [ImportContent] 后复用现有 OCR / LLM / 草稿流水线。替代直连抓取，
/// 规避平台 CDN 403 与风控；任意网页链接（含未知域名）均可用。
class WebViewImportContentAdapter implements ImportContentAdapter {
  WebViewImportContentAdapter({
    required WebViewContentFetcher fetcher,
    required ImportSourcePlatform platform,
    ImportClock? clock,
    this.timeout = const Duration(seconds: 45),
  }) : _fetcher = fetcher,
       _platform = platform,
       _clock = clock ?? DateTime.now;

  final WebViewContentFetcher _fetcher;
  final ImportSourcePlatform _platform;
  final ImportClock _clock;
  final Duration timeout;

  @override
  ImportSourcePlatform get platform => _platform;

  @override
  Future<ImportContent> fetch(
    ImportSourceLink source, {
    ImportCancellationToken? cancellationToken,
  }) async {
    if (source.platform != _platform) {
      throw ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unsupportedPlatform,
        message: 'The source platform does not match this content adapter.',
        retryable: false,
      );
    }
    final uri = Uri.tryParse(source.normalizedUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme.toLowerCase() != 'http' &&
            uri.scheme.toLowerCase() != 'https')) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: '链接必须是完整的 HTTP 或 HTTPS 网页地址。',
        retryable: false,
      );
    }
    cancellationToken?.throwIfCancelled();

    final WebViewFetchResult fetched;
    try {
      // 取消令牌触发时通知原生立即停止导航/JS/图片下载写盘（IMPORT-008 竞态加固）。
      // 不做 await：令牌永不取消时该 Future 不会完成，await 会挂起调用方。
      cancellationToken?.whenCancelled.then((_) {
        _fetcher.cancel();
      });
      fetched = await _fetcher.fetch(
        source.normalizedUrl,
        platform: _platform.name,
        timeout: timeout,
      );
    } on WebViewFetchException catch (error) {
      throw _mapFetchError(error);
    }
    cancellationToken?.throwIfCancelled();

    if (!fetched.hasText && fetched.imageUrls.isEmpty) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.contentUnavailable,
        message: '网页未返回可用的文本或图片内容。',
        retryable: false,
      );
    }

    return _buildContent(source, fetched);
  }

  ImportContent _buildContent(
    ImportSourceLink source,
    WebViewFetchResult fetched,
  ) {
    final now = _clock().toUtc();
    final fragments = <ImportTextFragment>[];
    var order = 0;
    if (fetched.title.isNotEmpty) {
      fragments.add(
        ImportTextFragment(
          kind: ImportTextFragmentKind.title,
          text: fetched.title,
          order: order++,
        ),
      );
    }
    if (fetched.description.isNotEmpty &&
        fetched.description.trim() != fetched.bodyText.trim()) {
      fragments.add(
        ImportTextFragment(
          kind: ImportTextFragmentKind.description,
          text: fetched.description,
          order: order++,
        ),
      );
    }
    if (fetched.bodyText.isNotEmpty) {
      fragments.add(
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: fetched.bodyText,
          order: order++,
        ),
      );
    }

    // 图片：优先使用浏览器会话已下载的本地文件（localAssetId，直接进入 OCR/封面
    // 流程，避开客户端直连被 CDN 按特征拒绝）；浏览器会话未下载成功的地址，
    // 仅对通用 web 平台回退远程直连快速路径（ADR-0019）。
    final media = <ImportMediaReference>[];
    for (final entry in fetched.images.indexed) {
      media.add(
        ImportMediaReference(
          kind: ImportMediaKind.image,
          localAssetId: entry.$2.localPath,
          order: entry.$1,
        ),
      );
    }
    // 已知小红书/抖音 CDN 会拒绝应用网络栈（已被证实重复 403），回退只增加
    // 耗时并混淆日志，因此这两个平台不再回退远程直连。
    final allowRemoteFallback = _platform == ImportSourcePlatform.web;
    if (media.isEmpty && fetched.imageUrls.isNotEmpty) {
      debugPrint(
        '[AIRecipe][WebView] 浏览器会话未下载成功图片'
        '（${fetched.imageUrls.length} 个地址），'
        '${allowRemoteFallback ? '回退远程直连快速路径。' : '平台 ${_platform.name} 不回退直连（CDN 拒绝应用网络栈）。'}',
      );
    }
    if (media.isEmpty && allowRemoteFallback) {
      final resolvedUri =
          Uri.tryParse(fetched.resolvedUrl.isNotEmpty
              ? fetched.resolvedUrl
              : source.normalizedUrl) ??
          Uri.parse(source.normalizedUrl);
      var order = 0;
      for (final url in fetched.imageUrls) {
        final absolute = resolvedUri.resolve(url).toString();
        final parsed = Uri.tryParse(absolute);
        if (parsed == null ||
            (parsed.scheme.toLowerCase() != 'http' &&
                parsed.scheme.toLowerCase() != 'https')) {
          continue;
        }
        media.add(
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: absolute,
            order: order++,
          ),
        );
      }
    }

    final warnings = <ImportContentWarning>{
      if (fragments.isEmpty) ImportContentWarning.missingText,
      if (media.isEmpty) ImportContentWarning.missingMedia,
      // ADR-0029：链接导入的图片一律走多模态转录（菜谱文字在手绘图/截图里），
      // 必须标记 requiresOcr，识别处理器才会进入逐张图转录循环；
      // 否则内容会跳过图片识别直接交给结构化 LLM。
      if (media.isNotEmpty) ImportContentWarning.requiresOcr,
    };

    return ImportContent(
      source: source,
      resolvedUrl: fetched.resolvedUrl.isNotEmpty
          ? fetched.resolvedUrl
          : source.normalizedUrl,
      contentType: media.isNotEmpty
          ? ImportContentType.imageGallery
          : ImportContentType.article,
      title: fetched.title.isNotEmpty ? fetched.title : null,
      description: fetched.description.isNotEmpty
          ? fetched.description
          : null,
      authorName: fetched.authorName.isNotEmpty ? fetched.authorName : null,
      capturedAt: now,
      textFragments: fragments,
      media: media,
      warnings: warnings,
    );
  }

  static ImportContentAdapterException _mapFetchError(
    WebViewFetchException error,
  ) {
    return switch (error.kind) {
      WebViewFetchErrorKind.invalidUrl => const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: '链接必须是完整的 HTTP 或 HTTPS 网页地址。',
        retryable: false,
      ),
      WebViewFetchErrorKind.network =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          message: '网页加载失败，请检查网络后重试。',
          retryable: true,
        ),
      WebViewFetchErrorKind.timeout => const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.timeout,
        message: '网页加载超时，请稍后重试。',
        retryable: true,
      ),
      WebViewFetchErrorKind.loginRequired =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.authorizationRequired,
          message: '该网页需要登录后才能查看内容，可改用粘贴正文导入。',
          retryable: false,
        ),
      WebViewFetchErrorKind.verificationRequired =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          message: '平台正在进行安全验证，请稍后重试或改用粘贴正文导入。',
          retryable: true,
        ),
      WebViewFetchErrorKind.emptyContent =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.contentUnavailable,
          message: '网页未返回可用的文本或图片内容，请检查链接是否有效。',
          retryable: false,
        ),
      WebViewFetchErrorKind.unavailable =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.invalidPayload,
          message: '当前设备暂不支持浏览器内核抓取，可改用粘贴正文导入。',
          retryable: false,
        ),
      WebViewFetchErrorKind.cancelled =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.cancelled,
          message: '网页抓取已取消。',
          retryable: false,
        ),
      WebViewFetchErrorKind.superseded =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.cancelled,
          message: '网页抓取已被新任务替代。',
          retryable: false,
        ),
      WebViewFetchErrorKind.rendererGone =>
        const ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.networkUnavailable,
          message: '网页渲染进程异常，请稍后重试。',
          retryable: true,
        ),
    };
  }
}
