import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';

class RemoteStagingOcrProvider implements OcrProvider {
  const RemoteStagingOcrProvider({
    required OcrProvider inner,
    required OcrRemoteImageStager stager,
  }) : _inner = inner,
       _stager = stager;

  final OcrProvider _inner;
  final OcrRemoteImageStager _stager;

  @override
  OcrProviderKind get kind => _inner.kind;

  @override
  Future<OcrDocument> recognize(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (input.localAssetId != null) {
      return _inner.recognize(input, cancellationToken: cancellationToken);
    }

    StagedOcrImage? staged;
    try {
      staged = await _stager.stage(input, cancellationToken: cancellationToken);
      cancellationToken?.throwIfCancelled();
      return await _inner.recognize(
        staged.input,
        cancellationToken: cancellationToken,
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on OcrProviderException {
      rethrow;
    } catch (_) {
      throw const OcrProviderException(
        kind: OcrProviderErrorKind.unknown,
        message: '获取图片内容失败，请稍后重试。',
      );
    } finally {
      await staged?.dispose();
    }
  }
}
