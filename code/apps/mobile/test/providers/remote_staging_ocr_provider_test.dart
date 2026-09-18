import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:ai_recipe/domain/ocr/ocr_remote_image_stager.dart';
import 'package:ai_recipe/providers/ocr/remote_staging_ocr_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passes local image directly to inner provider', () async {
    final inner = _FakeOcrProvider();
    final stager = _FakeStager();
    final provider = RemoteStagingOcrProvider(inner: inner, stager: stager);
    final input = OcrImageInput(localAssetId: 'local-file', order: 2);

    await provider.recognize(input);

    expect(inner.input, same(input));
    expect(stager.stageCount, 0);
  });

  test('stages a remote image and disposes it after success', () async {
    final inner = _FakeOcrProvider();
    final stager = _FakeStager();
    final provider = RemoteStagingOcrProvider(inner: inner, stager: stager);

    await provider.recognize(
      OcrImageInput(remoteUrl: 'https://images.example.test/a.png', order: 1),
    );

    expect(stager.stageCount, 1);
    expect(inner.input?.remoteUrl, isNull);
    expect(inner.input?.localAssetId, 'staged-image');
    expect(stager.disposeCount, 1);
  });

  test('disposes staged image when inner provider fails', () async {
    final inner = _FakeOcrProvider(
      error: const OcrProviderException(
        kind: OcrProviderErrorKind.inferenceFailed,
        message: 'failed',
      ),
    );
    final stager = _FakeStager();
    final provider = RemoteStagingOcrProvider(inner: inner, stager: stager);

    await expectLater(
      provider.recognize(
        OcrImageInput(remoteUrl: 'https://images.example.test/a.png', order: 0),
      ),
      throwsA(isA<OcrProviderException>()),
    );
    expect(stager.disposeCount, 1);
  });

  test('disposes staged image when recognition is cancelled', () async {
    final token = ImportCancellationToken();
    final inner = _FakeOcrProvider(
      onRecognize: () {
        token.cancel();
        throw const ImportOperationCancelledException();
      },
    );
    final stager = _FakeStager();
    final provider = RemoteStagingOcrProvider(inner: inner, stager: stager);

    await expectLater(
      provider.recognize(
        OcrImageInput(remoteUrl: 'https://images.example.test/a.png', order: 0),
        cancellationToken: token,
      ),
      throwsA(isA<ImportOperationCancelledException>()),
    );
    expect(stager.disposeCount, 1);
  });
}

class _FakeOcrProvider implements OcrProvider {
  _FakeOcrProvider({this.error, this.onRecognize});

  final Object? error;
  final void Function()? onRecognize;
  OcrImageInput? input;

  @override
  OcrProviderKind get kind => OcrProviderKind.localPlugin;

  @override
  Future<OcrDocument> recognize(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    this.input = input;
    onRecognize?.call();
    final failure = error;
    if (failure != null) throw failure;
    return OcrDocument(
      providerId: 'fake-local',
      modelVersion: 'test',
      language: 'zh-Hans',
    );
  }
}

class _FakeStager implements OcrRemoteImageStager {
  var stageCount = 0;
  var disposeCount = 0;

  @override
  Future<StagedOcrImage> stage(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    stageCount += 1;
    return StagedOcrImage(
      input: OcrImageInput(
        localAssetId: 'staged-image',
        mimeType: 'image/png',
        width: 1,
        height: 1,
        order: input.order,
      ),
      byteLength: 24,
      width: 1,
      height: 1,
      dispose: () async {
        disposeCount += 1;
      },
    );
  }
}
