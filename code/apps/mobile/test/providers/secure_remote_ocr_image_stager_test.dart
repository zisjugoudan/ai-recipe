import 'dart:io';

import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/providers/ocr/ocr_remote_image_download_client.dart';
import 'package:ai_recipe/providers/ocr/secure_remote_ocr_image_stager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ai-recipe-ocr-stage-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'stages a PNG with verified metadata and deletes it on dispose',
    () async {
      final stager = _stager(root, bytes: _png(width: 3, height: 2));

      final staged = await stager.stage(_remoteInput());
      final file = File(staged.input.localAssetId!);

      expect(await file.exists(), isTrue);
      expect(staged.input.mimeType, 'image/png');
      expect(staged.width, 3);
      expect(staged.height, 2);
      expect(staged.input.order, 4);

      await staged.dispose();
      await staged.dispose();
      expect(await file.exists(), isFalse);
    },
  );

  test('accepts supported JPEG and WebP signatures', () async {
    for (final sample in <({List<int> bytes, String mimeType})>[
      (bytes: _jpeg(width: 2, height: 1), mimeType: 'image/jpeg'),
      (bytes: _webp(width: 4, height: 3), mimeType: 'image/webp'),
    ]) {
      final stager = _stager(
        root,
        bytes: sample.bytes,
        mimeType: sample.mimeType,
      );
      final staged = await stager.stage(_remoteInput());
      expect(staged.input.mimeType, sample.mimeType);
      await staged.dispose();
    }
  });

  test('rejects MIME mismatch and removes partial file', () async {
    final stager = _stager(
      root,
      bytes: _png(width: 1, height: 1),
      mimeType: 'image/jpeg',
    );

    await expectLater(stager.stage(_remoteInput()), throwsA(_invalidResponse));
    await _expectNoStagedFiles(root);
  });

  test('rejects non-image bytes and removes partial file', () async {
    final stager = _stager(root, bytes: <int>[1, 2, 3, 4]);

    await expectLater(stager.stage(_remoteInput()), throwsA(_invalidResponse));
    await _expectNoStagedFiles(root);
  });

  test('rejects byte, dimension, and pixel limits', () async {
    final cases = <SecureRemoteOcrImageStager>[
      _stager(root, bytes: _png(width: 1, height: 1), maxBytes: 20),
      _stager(root, bytes: _png(width: 101, height: 1), maxDimension: 100),
      _stager(root, bytes: _png(width: 11, height: 10), maxPixels: 100),
    ];

    for (final stager in cases) {
      await expectLater(stager.stage(_remoteInput()), throwsA(_invalidInput));
      await _expectNoStagedFiles(root);
    }
  });

  test('removes partial file when download fails', () async {
    final stager = SecureRemoteOcrImageStager(
      downloadClient: _FakeDownloadClient(
        bytes: _png(width: 1, height: 1),
        error: const OcrProviderException(
          kind: OcrProviderErrorKind.networkUnavailable,
          message: 'offline',
        ),
      ),
      temporaryDirectoryProvider: () async => root,
    );

    await expectLater(
      stager.stage(_remoteInput()),
      throwsA(isA<OcrProviderException>()),
    );
    await _expectNoStagedFiles(root);
  });

  test('removes staged file when cancellation is observed', () async {
    final token = ImportCancellationToken();
    final stager = SecureRemoteOcrImageStager(
      downloadClient: _FakeDownloadClient(
        bytes: _png(width: 1, height: 1),
        afterWrite: token.cancel,
      ),
      temporaryDirectoryProvider: () async => root,
    );

    await expectLater(
      stager.stage(_remoteInput(), cancellationToken: token),
      throwsA(isA<ImportOperationCancelledException>()),
    );
    await _expectNoStagedFiles(root);
  });
}

SecureRemoteOcrImageStager _stager(
  Directory root, {
  required List<int> bytes,
  String mimeType = 'image/png',
  int maxBytes = 16 * 1024 * 1024,
  int maxDimension = 16384,
  int maxPixels = 20000000,
}) {
  return SecureRemoteOcrImageStager(
    downloadClient: _FakeDownloadClient(bytes: bytes, mimeType: mimeType),
    temporaryDirectoryProvider: () async => root,
    maxBytes: maxBytes,
    maxDimension: maxDimension,
    maxPixels: maxPixels,
  );
}

OcrImageInput _remoteInput() =>
    OcrImageInput(remoteUrl: 'https://images.example.test/dish.png', order: 4);

class _FakeDownloadClient implements OcrRemoteImageDownloadClient {
  _FakeDownloadClient({
    required this.bytes,
    this.mimeType = 'image/png',
    this.error,
    this.afterWrite,
  });

  final List<int> bytes;
  final String mimeType;
  final Object? error;
  final void Function()? afterWrite;

  @override
  Future<OcrRemoteImageDownload> download(
    Uri uri,
    File destination, {
    ImportCancellationToken? cancellationToken,
  }) async {
    await destination.writeAsBytes(bytes);
    afterWrite?.call();
    final failure = error;
    if (failure != null) throw failure;
    return OcrRemoteImageDownload(mimeType: mimeType, byteLength: bytes.length);
  }
}

List<int> _png({required int width, required int height}) {
  final bytes = List<int>.filled(24, 0);
  bytes.setRange(0, 8, const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  bytes.setRange(12, 16, 'IHDR'.codeUnits);
  _writeBigEndian32(bytes, 16, width);
  _writeBigEndian32(bytes, 20, height);
  return bytes;
}

List<int> _jpeg({required int width, required int height}) => <int>[
  0xff,
  0xd8,
  0xff,
  0xc0,
  0x00,
  0x07,
  0x08,
  height >> 8,
  height & 0xff,
  width >> 8,
  width & 0xff,
];

List<int> _webp({required int width, required int height}) {
  final bytes = List<int>.filled(30, 0);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  bytes.setRange(8, 12, 'WEBP'.codeUnits);
  bytes.setRange(12, 16, 'VP8X'.codeUnits);
  _writeLittleEndian24(bytes, 24, width - 1);
  _writeLittleEndian24(bytes, 27, height - 1);
  return bytes;
}

void _writeBigEndian32(List<int> bytes, int offset, int value) {
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

void _writeLittleEndian24(List<int> bytes, int offset, int value) {
  bytes[offset] = value & 0xff;
  bytes[offset + 1] = (value >> 8) & 0xff;
  bytes[offset + 2] = (value >> 16) & 0xff;
}

Future<void> _expectNoStagedFiles(Directory root) async {
  final staging = Directory(
    '${root.path}${Platform.pathSeparator}ocr-remote-staging',
  );
  if (!await staging.exists()) return;
  expect(await staging.list().toList(), isEmpty);
}

final Matcher _invalidInput = isA<OcrProviderException>().having(
  (error) => error.kind,
  'kind',
  OcrProviderErrorKind.invalidInput,
);
final Matcher _invalidResponse = isA<OcrProviderException>().having(
  (error) => error.kind,
  'kind',
  OcrProviderErrorKind.invalidResponse,
);
