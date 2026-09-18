import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';
import 'ocr_remote_image_download_client.dart';
import 'pinned_https_ocr_image_download_client.dart';

class SecureRemoteOcrImageStager implements OcrRemoteImageStager {
  SecureRemoteOcrImageStager({
    OcrRemoteImageDownloadClient? downloadClient,
    OcrTemporaryDirectoryProvider? temporaryDirectoryProvider,
    this.maxBytes = 16 * 1024 * 1024,
    this.maxDimension = 16384,
    this.maxPixels = 20000000,
  }) : _downloadClient = downloadClient ?? PinnedHttpsOcrImageDownloadClient(),
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory {
    if (maxBytes <= 0 || maxDimension <= 0 || maxPixels <= 0) {
      throw ArgumentError('Remote OCR image limits must be positive.');
    }
  }

  final OcrRemoteImageDownloadClient _downloadClient;
  final OcrTemporaryDirectoryProvider _temporaryDirectoryProvider;
  final int maxBytes;
  final int maxDimension;
  final int maxPixels;

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final rawUrl = input.remoteUrl;
    if (rawUrl == null) {
      // 本地文件直通（IMPORT-008）：浏览器会话已下载的图片直接进入 OCR/封面
      // 流程，不经过远程下载；仍执行存在性、大小、尺寸与 MIME 校验。
      final localAssetId = input.localAssetId;
      if (localAssetId == null || localAssetId.isEmpty) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '获取图片内容需要图片地址。',
        );
      }
      final file = File(localAssetId);
      if (!await file.exists()) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '本地图片文件不存在。',
        );
      }
      final byteLength = await file.length();
      if (byteLength <= 0 || byteLength > maxBytes) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '图片超过允许的大小限制。',
        );
      }
      final metadata = await _inspectImage(
        file,
        expectedMimeType: input.mimeType ?? _inferMimeFromPath(localAssetId),
        cancellationToken: cancellationToken,
      );
      if (metadata.width > maxDimension ||
          metadata.height > maxDimension ||
          metadata.width * metadata.height > maxPixels) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '图片尺寸超过允许的限制。',
        );
      }
      return StagedOcrImage(
        input: OcrImageInput(
          localAssetId: file.path,
          mimeType: metadata.mimeType,
          width: metadata.width,
          height: metadata.height,
          order: input.order,
        ),
        byteLength: byteLength,
        width: metadata.width,
        height: metadata.height,
        // 本地文件由 WebView 会话在下次抓取时统一清理，这里不删除。
        dispose: () async {},
      );
    }

    File? temporaryFile;
    try {
      final baseDirectory = await _temporaryDirectoryProvider();
      cancellationToken?.throwIfCancelled();
      final stagingDirectory = Directory(
        path.join(baseDirectory.path, 'ocr-remote-staging'),
      );
      await stagingDirectory.create(recursive: true);
      cancellationToken?.throwIfCancelled();
      temporaryFile = File(
        path.join(stagingDirectory.path, _temporaryFileName()),
      );

      final download = await _downloadClient.download(
        Uri.parse(rawUrl),
        temporaryFile,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      if (download.byteLength <= 0 || download.byteLength > maxBytes) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '图片超过允许的大小限制。',
        );
      }

      final metadata = await _inspectImage(
        temporaryFile,
        expectedMimeType: download.mimeType,
        cancellationToken: cancellationToken,
      );
      if (metadata.width > maxDimension ||
          metadata.height > maxDimension ||
          metadata.width * metadata.height > maxPixels) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '图片尺寸超过允许的限制。',
        );
      }

      final stagedFile = temporaryFile;
      temporaryFile = null;
      return StagedOcrImage(
        input: OcrImageInput(
          localAssetId: stagedFile.path,
          mimeType: metadata.mimeType,
          width: metadata.width,
          height: metadata.height,
          order: input.order,
        ),
        byteLength: download.byteLength,
        width: metadata.width,
        height: metadata.height,
        dispose: () => _deleteQuietly(stagedFile),
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on OcrProviderException {
      rethrow;
    } on FileSystemException {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.unavailable,
        message: '图片暂存空间不可用，请稍后重试。',
      );
    } catch (_) {
      if (cancellationToken?.isCancelled ?? false) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.cancelled,
          message: '获取图片内容已取消。',
        );
      }
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: '图片内容无效。',
      );
    } finally {
      if (temporaryFile != null) await _deleteQuietly(temporaryFile);
    }
  }

  /// 本地文件直通时按扩展名推断 MIME（浏览器会话下载的图片扩展名由写入方保证）。
  static String _inferMimeFromPath(String localAssetId) {
    final lower = localAssetId.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<_ImageMetadata> _inspectImage(
    File file, {
    required String expectedMimeType,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final bytes = await file.readAsBytes();
    cancellationToken?.throwIfCancelled();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidInput,
        message: '图片超过允许的大小限制。',
      );
    }
    final metadata = _ImageMetadata.parse(bytes);
    if (metadata == null || metadata.mimeType != expectedMimeType) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.invalidResponse,
        message: '图片格式与文件签名不一致。',
      );
    }
    return metadata;
  }

  static String _temporaryFileName() {
    final random = Random.secure();
    final suffix = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'ocr-$suffix.img';
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup is best-effort and never exposes local paths.
    }
  }
}

class _ImageMetadata {
  const _ImageMetadata({
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final String mimeType;
  final int width;
  final int height;

  static _ImageMetadata? parse(Uint8List bytes) {
    return _parsePng(bytes) ?? _parseJpeg(bytes) ?? _parseWebp(bytes);
  }

  static _ImageMetadata? _parsePng(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 24 || !_startsWith(bytes, signature)) return null;
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;
    final width = _readUint32BigEndian(bytes, 16);
    final height = _readUint32BigEndian(bytes, 20);
    if (width <= 0 || height <= 0) return null;
    return _ImageMetadata(mimeType: 'image/png', width: width, height: height);
  }

  static _ImageMetadata? _parseJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    var offset = 2;
    while (offset + 3 < bytes.length) {
      while (offset < bytes.length && bytes[offset] != 0xff) {
        offset += 1;
      }
      while (offset < bytes.length && bytes[offset] == 0xff) {
        offset += 1;
      }
      if (offset >= bytes.length) return null;
      final marker = bytes[offset++];
      if (marker == 0xd9 || marker == 0xda) return null;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset + 1 >= bytes.length) return null;
      final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
      if (segmentLength < 2 || offset + segmentLength > bytes.length) {
        return null;
      }
      if (_jpegSofMarkers.contains(marker)) {
        if (segmentLength < 7) return null;
        final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
        final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        if (width <= 0 || height <= 0) return null;
        return _ImageMetadata(
          mimeType: 'image/jpeg',
          width: width,
          height: height,
        );
      }
      offset += segmentLength;
    }
    return null;
  }

  static _ImageMetadata? _parseWebp(Uint8List bytes) {
    if (bytes.length < 30 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') {
      return null;
    }
    final chunk = String.fromCharCodes(bytes.sublist(12, 16));
    int width;
    int height;
    if (chunk == 'VP8X') {
      width = 1 + _readUint24LittleEndian(bytes, 24);
      height = 1 + _readUint24LittleEndian(bytes, 27);
    } else if (chunk == 'VP8L' && bytes[20] == 0x2f) {
      width = 1 + bytes[21] + ((bytes[22] & 0x3f) << 8);
      height =
          1 + (bytes[22] >> 6) + (bytes[23] << 2) + ((bytes[24] & 0x0f) << 10);
    } else if (chunk == 'VP8 ' &&
        bytes[23] == 0x9d &&
        bytes[24] == 0x01 &&
        bytes[25] == 0x2a) {
      width = (bytes[26] | (bytes[27] << 8)) & 0x3fff;
      height = (bytes[28] | (bytes[29] << 8)) & 0x3fff;
    } else {
      return null;
    }
    if (width <= 0 || height <= 0) return null;
    return _ImageMetadata(mimeType: 'image/webp', width: width, height: height);
  }

  static const Set<int> _jpegSofMarkers = <int>{
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  };

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static int _readUint32BigEndian(Uint8List bytes, int offset) {
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static int _readUint24LittleEndian(Uint8List bytes, int offset) {
    return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
  }
}
