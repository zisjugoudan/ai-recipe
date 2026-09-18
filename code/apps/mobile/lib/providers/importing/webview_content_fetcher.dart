import 'package:flutter/services.dart';

/// 浏览器内核抓取结果（IMPORT-008）。
///
/// 对应原生 WebView 在页面渲染完成后从 DOM 提取的标题、正文、作者与图片地址；
/// [images] 是浏览器会话已下载到本地文件的图片（避开客户端直连被拒）。
class WebViewFetchResult {
  const WebViewFetchResult({
    required this.title,
    required this.description,
    required this.authorName,
    required this.bodyText,
    required this.imageUrls,
    required this.images,
    required this.resolvedUrl,
  });

  final String title;
  final String description;
  final String authorName;
  final String bodyText;
  final List<String> imageUrls;
  final List<WebViewDownloadedImage> images;
  final String resolvedUrl;

  bool get hasText =>
      title.isNotEmpty || description.isNotEmpty || bodyText.isNotEmpty;

  static WebViewFetchResult fromMap(Map<Object?, Object?> map) {
    return WebViewFetchResult(
      title: _string(map['title']),
      description: _string(map['description']),
      authorName: _string(map['authorName']),
      bodyText: _string(map['bodyText']),
      imageUrls: _stringList(map['imageUrls']),
      images: _imageList(map['images']),
      resolvedUrl: _string(map['resolvedUrl']),
    );
  }

  static String _string(Object? value) {
    if (value is String) return value.trim();
    return '';
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<WebViewDownloadedImage> _imageList(Object? value) {
    if (value is! List) return const <WebViewDownloadedImage>[];
    final result = <WebViewDownloadedImage>[];
    for (final item in value) {
      if (item is! Map) continue;
      final localPath = item['localPath'];
      final url = item['url'];
      if (localPath is String && localPath.isNotEmpty) {
        result.add(
          WebViewDownloadedImage(
            url: url is String ? url : '',
            localPath: localPath,
          ),
        );
      }
    }
    return List<WebViewDownloadedImage>.unmodifiable(result);
  }
}

/// 浏览器会话已下载到本地的图片（含对应远程地址，便于溯源与排序）。
class WebViewDownloadedImage {
  const WebViewDownloadedImage({required this.url, required this.localPath});

  final String url;
  final String localPath;
}

/// 浏览器内核抓取失败分类。
enum WebViewFetchErrorKind {
  invalidUrl,
  network,
  timeout,
  loginRequired,
  verificationRequired,
  emptyContent,
  unavailable,
  /// 用户主动取消（原生已停止导航/JS/图片下载写盘）。
  cancelled,
  /// 旧请求被新请求替代（不显示为超时）。
  superseded,
  /// 渲染进程崩溃（RendererProcessGone），非普通网络不可用。
  rendererGone,
}

class WebViewFetchException implements Exception {
  const WebViewFetchException(this.kind, this.message);

  final WebViewFetchErrorKind kind;
  final String message;

  @override
  String toString() => 'WebViewFetchException(${kind.name}): $message';
}

/// 浏览器内核抓取抽象，便于测试注入 Fake。
abstract interface class WebViewContentFetcher {
  /// 加载 [url] 并返回从 DOM 提取的文本与图片地址。
  ///
  /// [platform] 用于选择平台特化提取规则（如小红书读取笔记数据源）。
  Future<WebViewFetchResult> fetch(
    String url, {
    String platform = 'web',
    Duration timeout = const Duration(seconds: 45),
  });

  /// 取消当前正在进行的抓取；原生立即停止导航、JS 与图片下载写盘。
  Future<void> cancel();
}

/// 基于 MethodChannel 的浏览器内核抓取实现（Android 原生 WebView）。
class MethodChannelWebViewContentFetcher implements WebViewContentFetcher {
  MethodChannelWebViewContentFetcher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('ai_recipe/webview_fetch');

  final MethodChannel _channel;

  @override
  Future<WebViewFetchResult> fetch(
    String url, {
    String platform = 'web',
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'fetchPage',
        <String, Object?>{
          'url': url,
          'platform': platform,
          'timeoutMs': timeout.inMilliseconds,
        },
      );
      if (result == null) {
        throw const WebViewFetchException(
          WebViewFetchErrorKind.emptyContent,
          '网页未返回内容。',
        );
      }
      return WebViewFetchResult.fromMap(result);
    } on PlatformException catch (error) {
      throw WebViewFetchException(
        _mapErrorCode(error.code),
        error.message ?? '网页抓取失败。',
      );
    } on MissingPluginException {
      // iOS（WKWebView 未实现）或非 Flutter 环境。
      throw const WebViewFetchException(
        WebViewFetchErrorKind.unavailable,
        '当前设备暂不支持浏览器内核抓取。',
      );
    }
  }

  @override
  Future<void> cancel() async {
    // 原生端取消当前请求；若没有活跃请求，调用也会安全返回。
    try {
      await _channel.invokeMethod<void>('cancelFetch');
    } on MissingPluginException {
      // iOS（WKWebView 未实现）：忽略即可，取消由 Dart 侧令牌兜底。
    } on PlatformException {
      // 取消失败不向上抛，避免打断调用方。
    }
  }

  static WebViewFetchErrorKind _mapErrorCode(String code) {
    return switch (code) {
      'invalidUrl' => WebViewFetchErrorKind.invalidUrl,
      'network' => WebViewFetchErrorKind.network,
      'timeout' => WebViewFetchErrorKind.timeout,
      'loginRequired' => WebViewFetchErrorKind.loginRequired,
      'verificationRequired' => WebViewFetchErrorKind.verificationRequired,
      'emptyContent' => WebViewFetchErrorKind.emptyContent,
      'cancelled' => WebViewFetchErrorKind.cancelled,
      'superseded' => WebViewFetchErrorKind.superseded,
      'rendererGone' => WebViewFetchErrorKind.rendererGone,
      _ => WebViewFetchErrorKind.emptyContent,
    };
  }
}
