import 'dart:io';

import '../../domain/importing/import_cancellation_token.dart';

typedef OcrTemporaryDirectoryProvider = Future<Directory> Function();
typedef OcrHostResolver = Future<List<InternetAddress>> Function(String host);

abstract interface class OcrRemoteImageDownloadClient {
  Future<OcrRemoteImageDownload> download(
    Uri uri,
    File destination, {
    ImportCancellationToken? cancellationToken,
  });
}

class OcrRemoteImageDownload {
  const OcrRemoteImageDownload({
    required this.mimeType,
    required this.byteLength,
  });

  final String mimeType;
  final int byteLength;
}

abstract interface class OcrPinnedHttpsConnection {
  Stream<List<int>> get incoming;
  void add(List<int> bytes);
  Future<void> flush();
  Future<void> close();
  void destroy();
}

typedef OcrPinnedHttpsConnector =
    Future<OcrPinnedHttpsConnection> Function({
      required Uri uri,
      required InternetAddress address,
      required Duration connectionTimeout,
      required Duration tlsTimeout,
      ImportCancellationToken? cancellationToken,
    });
