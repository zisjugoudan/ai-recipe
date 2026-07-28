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

  final http.Client _client;

  @override
  Future<OcrModelDownloadResponse> open(Uri uri) async {
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client.send(request);
    return OcrModelDownloadResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength,
      bytes: response.stream,
    );
  }
}
