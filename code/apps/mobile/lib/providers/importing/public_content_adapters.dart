import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_content_adapter.dart';
import '../../domain/importing/import_task.dart';
import 'import_http_transport.dart';
import 'public_page_metadata_parser.dart';

typedef ImportClock = DateTime Function();

abstract class PublicPageImportContentAdapter implements ImportContentAdapter {
  PublicPageImportContentAdapter({
    required ImportHttpTransport transport,
    PublicPageMetadataParser parser = const PublicPageMetadataParser(),
    ImportClock? clock,
  }) : _transport = transport,
       _parser = parser,
       _clock = clock ?? DateTime.now;

  final ImportHttpTransport _transport;
  final PublicPageMetadataParser _parser;
  final ImportClock _clock;

  Set<String> get allowedHosts;

  Map<String, String> get requestHeaders => const <String, String>{
    'Accept':
        'text/html,application/xhtml+xml,application/json,text/plain;q=0.8',
    'User-Agent': 'AIRecipe/1.0 PublicMetadataImporter',
  };

  /// 页面明确要求登录后继续查看的标记，命中后映射为 authorizationRequired。
  Iterable<String> get loginRequiredMarkers => const <String>[
    '请先登录',
    '登录后查看',
    '登录后继续',
    '需要登录',
    '登录后访问',
    'login required',
    'sign in to continue',
    'sign in required',
  ];

  /// 页面明确说明目标内容不存在或已删除的标记，命中后映射为 contentUnavailable。
  Iterable<String> get contentUnavailableMarkers => const <String>[
    '内容不存在',
    '作品不存在',
    '内容已删除',
    '作品已删除',
    '笔记不存在',
    '笔记已删除',
    '内容已失效',
    '该内容暂时无法查看',
    '仅作者可见',
    'content unavailable',
    'content is unavailable',
    'page not found',
  ];

  /// 平台风控/验证/临时限流类标记，命中后映射为可重试的 networkUnavailable。
  Iterable<String> get accessRestrictedMarkers => const <String>[
    '安全验证',
    '拖动滑块',
    '滑动验证',
    '请完成验证',
    '访问过于频繁',
    '请求过于频繁',
    '操作频率过高',
    'captcha',
    'security verification',
    'risk control',
  ];

  @override
  Future<ImportContent> fetch(
    ImportSourceLink source, {
    ImportCancellationToken? cancellationToken,
  }) async {
    if (source.platform != platform) {
      throw ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unsupportedPlatform,
        message: 'The source platform does not match this content adapter.',
        retryable: false,
      );
    }

    final requestUri = Uri.parse(source.normalizedUrl);
    final request = ImportHttpRequest(
      uri: requestUri,
      allowedHosts: <String>{...allowedHosts, requestUri.host.toLowerCase()},
      headers: requestHeaders,
    );

    try {
      final response = await _transport.get(
        request,
        cancellationToken: cancellationToken,
      );
      _throwForStatus(response.statusCode);
      _throwForSecurityOrNotFound(response);
      _throwForKnownPageState(response.body);

      final metadata = _parser.parse(
        response.body,
        baseUri: response.resolvedUri,
        contentType: response.headers['content-type'],
      );
      if (!metadata.hasText && !metadata.hasMedia) {
        throw _noUsableContentError(source, response);
      }

      final textFragments = <ImportTextFragment>[];
      void addText(ImportTextFragmentKind kind, String? text) {
        if (text == null || text.trim().isEmpty) return;
        if (textFragments.any((fragment) => fragment.text == text.trim())) {
          return;
        }
        textFragments.add(
          ImportTextFragment(
            kind: kind,
            text: text,
            order: textFragments.length,
          ),
        );
      }

      addText(ImportTextFragmentKind.title, metadata.title);
      addText(ImportTextFragmentKind.description, metadata.description);
      addText(ImportTextFragmentKind.caption, metadata.caption);
      addText(ImportTextFragmentKind.body, metadata.bodyText);

      final media = <ImportMediaReference>[];
      for (final imageUrl in metadata.imageUrls) {
        media.add(
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: imageUrl,
            mimeType: metadata.imageMimeType,
            order: media.length,
          ),
        );
      }
      for (final videoUrl in metadata.videoUrls) {
        media.add(
          ImportMediaReference(
            kind: ImportMediaKind.video,
            remoteUrl: videoUrl,
            mimeType: metadata.videoMimeType,
            order: media.length,
          ),
        );
      }

      final hasText = metadata.hasText;
      final hasMedia = metadata.hasMedia;
      final hasImages = metadata.imageUrls.isNotEmpty;
      final hasVideos = metadata.videoUrls.isNotEmpty;
      final redirected =
          response.redirectCount > 0 ||
          response.resolvedUri.toString() != source.normalizedUrl;
      final warnings = <ImportContentWarning>{
        if (metadata.title == null) ImportContentWarning.missingTitle,
        if (!hasText) ImportContentWarning.missingText,
        if (!hasMedia) ImportContentWarning.missingMedia,
        if (!hasText || !hasMedia) ImportContentWarning.partialContent,
        if (hasImages) ImportContentWarning.requiresOcr,
        if (hasVideos) ImportContentWarning.requiresAsr,
        if (redirected) ImportContentWarning.redirected,
      };

      return ImportContent(
        source: source,
        resolvedUrl: response.resolvedUri.toString(),
        contentType: _contentType(
          hasText: hasText,
          hasImages: hasImages,
          hasVideos: hasVideos,
        ),
        title: metadata.title,
        description: metadata.description ?? metadata.caption,
        authorName: metadata.authorName,
        publishedAt: metadata.publishedAt,
        capturedAt: _clock().toUtc(),
        textFragments: textFragments,
        media: media,
        warnings: warnings,
      );
    } on ImportContentAdapterException {
      rethrow;
    } on ImportHttpTransportException catch (error) {
      throw _mapTransportError(error);
    } on ImportOperationCancelledException {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.cancelled,
        message: 'The public content import was cancelled.',
        retryable: false,
      );
    } on FormatException {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The public content response was malformed.',
        retryable: false,
      );
    } catch (_) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.unknown,
        message: 'The public content import failed unexpectedly.',
        retryable: false,
      );
    }
  }

  void _throwForStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.authorizationRequired,
        message: 'The public content requires authorization.',
        retryable: false,
      );
    }
    if (statusCode == 404 || statusCode == 410) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.contentUnavailable,
        message: 'The public content is unavailable.',
        retryable: false,
      );
    }
    if (statusCode == 408) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.timeout,
        message: 'The public content request timed out.',
        retryable: true,
      );
    }
    if (statusCode == 429 || statusCode >= 500) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: 'The public content service is temporarily unavailable.',
        retryable: true,
      );
    }
    if (statusCode >= 400) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The public content request returned an unsupported response.',
        retryable: false,
      );
    }
  }

  /// 识别平台把请求重定向到 `/404` 安全验证页的情况（如 `/404/sec_...`）。
  ///
  /// 这类页面以 HTTP 200 返回，正文是验证/失效壳页，不含目标笔记内容；
  /// 平台安全机制可能随时间或请求特征变化，因此映射为可重试的
  /// networkUnavailable，并提示用户使用完整分享链接或降级继续。
  void _throwForSecurityOrNotFound(ImportHttpResponse response) {
    final path = response.resolvedUri.path.toLowerCase();
    if (path == '/404' || path.startsWith('/404/')) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: '平台未返回笔记内容（可能正在执行安全验证，或笔记已失效）。'
            '请稍后重试，或改用完整分享链接、粘贴正文等方式继续整理。',
        retryable: true,
      );
    }
  }

  void _throwForKnownPageState(String body) {
    final normalized = body.toLowerCase();
    if (accessRestrictedMarkers.any(normalized.contains)) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: '平台正在执行访问验证或临时限流，请稍后重试。',
        retryable: true,
      );
    }
    if (loginRequiredMarkers.any(normalized.contains)) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.authorizationRequired,
        message: 'The public page requires the user to sign in.',
        retryable: false,
      );
    }
    if (contentUnavailableMarkers.any(normalized.contains)) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.contentUnavailable,
        message: 'The public page reports that the content is unavailable.',
        retryable: false,
      );
    }
  }

  /// 页面没有可提取文本或媒体时，按“是否返回了目标笔记页”分类给出可操作错误：
  /// - 响应中包含目标笔记 ID：目标页已获取但无法提取，属于固定解析问题，不可重试。
  /// - 响应中不包含目标笔记 ID：平台未返回目标内容（可能已失效、需要登录或临时限流），
  ///   提示检查链接或降级继续，并允许稍后重试。
  ///
  /// 调试摘要只通过 [debugPrint] 输出到控制台/Logcat（不含完整正文、Cookie、
  /// Authorization、访问令牌或完整查询参数），不进入用户可见的错误消息。
  ImportContentAdapterException _noUsableContentError(
    ImportSourceLink source,
    ImportHttpResponse response,
  ) {
    final targetId =
        _targetNoteId(response.resolvedUri) ??
        _targetNoteId(Uri.parse(source.normalizedUrl));
    final containsTarget = targetId != null && response.body.contains(targetId);
    debugPrint('[AIRecipe][PublicContentAdapter] no usable content: '
        '${_debugSummary(response, targetId: targetId, containsTarget: containsTarget)}');
    if (containsTarget) {
      return const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: '已获取到该笔记页面，但暂时无法提取有效内容。'
            '请稍后重试，或使用“粘贴正文”等方式继续整理。',
        retryable: false,
      );
    }
    return const ImportContentAdapterException(
      kind: ImportContentAdapterErrorKind.contentUnavailable,
      message: '未获取到目标笔记内容。链接可能已失效、需要登录，'
          '或平台临时限制了访问；请检查链接后重试，'
          '或使用“粘贴正文”等方式继续整理。',
      retryable: true,
    );
  }

  /// 从 URL 路径中提取目标笔记 ID（路径中较长的字母数字段）。
  static String? _targetNoteId(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final last = segments.last;
    if (last.length >= 8 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(last)) {
      return last;
    }
    return null;
  }

  /// 生成页面结构与解析结果的脱敏调试摘要。
  ///
  /// 只输出结构特征（状态码、内容类型、体积、是否存在 __INITIAL_STATE__、
  /// noteData、OG 标签、JSON-LD、页面标题前 24 字符、目标 ID 是否出现），
  /// 不输出完整正文、Cookie、Authorization、访问令牌或完整查询参数。
  static String _debugSummary(
    ImportHttpResponse response, {
    required String? targetId,
    required bool containsTarget,
  }) {
    final body = response.body;
    final lower = body.toLowerCase();
    final initState = body.contains('__INITIAL_STATE__');
    final noteDataCount = initState
        ? RegExp('noteData', caseSensitive: false).allMatches(body).length
        : 0;
    final metaCount = RegExp(
      r'<meta\b',
      caseSensitive: false,
    ).allMatches(body).length;
    final hasOgTitle = lower.contains('property="og:title"') ||
        lower.contains("property='og:title'");
    final hasOgImage = lower.contains('og:image');
    final ldJsonCount = RegExp(
      r'application/ld\+json',
      caseSensitive: false,
    ).allMatches(body).length;
    final pageTitle = _debugPageTitle(body);
    final finalPath = response.resolvedUri.path;
    return '[调试] finalHost=${response.resolvedUri.host} '
        'finalPath=${_clip(finalPath, 48)} '
        'redirect=${response.redirectCount} '
        'status=${response.statusCode} '
        'type=${response.headers['content-type']} '
        'size=${body.length} initState=$initState noteData=$noteDataCount '
        'meta=$metaCount ogTitle=$hasOgTitle ogImage=$hasOgImage '
        'ldjson=$ldJsonCount title=${pageTitle ?? 'null'} '
        'targetId=${targetId ?? 'none'} hasTarget=$containsTarget';
  }

  /// 提取 <title> 标签文本，截断到 24 字符，避免把超长标题塞进错误消息。
  static String? _debugPageTitle(String body) {
    final match = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return null;
    final value = match.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value == null || value.isEmpty) return null;
    return value.length <= 24 ? value : '${value.substring(0, 24)}…';
  }

  static String _clip(String value, int maxLength) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';

  static ImportContentType _contentType({
    required bool hasText,
    required bool hasImages,
    required bool hasVideos,
  }) {
    if (hasVideos && (hasImages || hasText)) return ImportContentType.mixed;
    if (hasVideos) return ImportContentType.video;
    if (hasImages && hasText) return ImportContentType.mixed;
    if (hasImages) return ImportContentType.imageGallery;
    if (hasText) return ImportContentType.article;
    return ImportContentType.unknown;
  }

  static ImportContentAdapterException _mapTransportError(
    ImportHttpTransportException error,
  ) {
    return switch (error.kind) {
      ImportHttpTransportErrorKind.network => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.networkUnavailable,
        message: 'The public content network request failed.',
        retryable: true,
      ),
      ImportHttpTransportErrorKind.timeout => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.timeout,
        message: 'The public content request timed out.',
        retryable: true,
      ),
      ImportHttpTransportErrorKind.cancelled => ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.cancelled,
        message: 'The public content import was cancelled.',
        retryable: false,
      ),
      ImportHttpTransportErrorKind.invalidRequest ||
      ImportHttpTransportErrorKind.invalidRedirect ||
      ImportHttpTransportErrorKind.tooManyRedirects ||
      ImportHttpTransportErrorKind.responseTooLarge ||
      ImportHttpTransportErrorKind.unsupportedContentType =>
        ImportContentAdapterException(
          kind: ImportContentAdapterErrorKind.invalidPayload,
          message: 'The public content response failed safety validation.',
          retryable: false,
        ),
    };
  }
}

class XiaohongshuPublicContentAdapter extends PublicPageImportContentAdapter {
  XiaohongshuPublicContentAdapter({
    required super.transport,
    super.parser,
    super.clock,
  });

  @override
  ImportSourcePlatform get platform => ImportSourcePlatform.xiaohongshu;

  @override
  Set<String> get allowedHosts => const <String>{
    'xiaohongshu.com',
    'www.xiaohongshu.com',
    'xhslink.com',
    'www.xhslink.com',
  };

  @override
  Map<String, String> get requestHeaders => const <String, String>{
    'Accept':
        'text/html,application/xhtml+xml,application/json,text/plain;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Mobile) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Mobile Safari/537.36',
  };
}

class DouyinPublicContentAdapter extends PublicPageImportContentAdapter {
  DouyinPublicContentAdapter({
    required super.transport,
    super.parser,
    super.clock,
  });

  @override
  ImportSourcePlatform get platform => ImportSourcePlatform.douyin;

  @override
  Set<String> get allowedHosts => const <String>{
    'douyin.com',
    'www.douyin.com',
    'v.douyin.com',
    'iesdouyin.com',
    'www.iesdouyin.com',
  };
}
