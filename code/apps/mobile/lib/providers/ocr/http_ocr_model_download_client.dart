import 'dart:async';

import 'package:http/http.dart' as http;

class OcrModelDownloadResponse {
  const OcrModelDownloadResponse({
    required this.statusCode,
    required this.bytes,
    this.contentLength,
  });

  final int statusCode;
  final int? contentLength;
  final Stream<List<int>> bytes;
}

abstract interface class OcrModelDownloadClient {
  Future<OcrModelDownloadResponse> open(Uri uri);
}

class HttpOcrModelDownloadClient implements OcrModelDownloadClient {
  HttpOcrModelDownloadClient({http.Client? client})
    : _client = client ?? http.Client();

  /// 最大跟随跳数：超过即视为异常，避免被无限重定向拖死。
  static const int _maxRedirects = 5;

  final http.Client _client;

  @override
  Future<OcrModelDownloadResponse> open(Uri uri) async {
    var current = uri;
    // 不依赖 http 包自动跟随（保持 followRedirects=false 的原测试语义），
    // 手动逐跳处理：只允许 HTTPS 重定向，且最多 _maxRedirects 跳。
    // 安全兜底：即使重定向到非预期主机，模型包下载仍按 SHA-256 与
    // 字节数双重校验，任何篡改都会在 checksumMismatch 处失败。
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('GET', current)..followRedirects = false;
      final response = await _client.send(request);
      final status = response.statusCode;
      if (status < 300 || status >= 400) {
        return OcrModelDownloadResponse(
          statusCode: status,
          contentLength: response.contentLength,
          bytes: response.stream,
        );
      }
      // 3xx：读取 Location 决定是否继续；失败/缺失/非 HTTPS 直接返回
      // 该响应，由调用方按非 200 判定为下载失败（安全拒绝，不降级）。
      final location = response.headers['location'];
      Uri? next;
      if (location != null && location.isNotEmpty) {
        try {
          final parsed = Uri.parse(location);
          if (parsed.scheme == 'https') next = current.resolveUri(parsed);
        } on FormatException {
          next = null;
        }
      }
      await response.stream.drain<void>();
      if (next == null) {
        return OcrModelDownloadResponse(
          statusCode: status,
          bytes: const Stream<List<int>>.empty(),
        );
      }
      current = next;
    }
    throw StateError(
      'OCR model download exceeded $_maxRedirects redirects.',
    );
  }
}
