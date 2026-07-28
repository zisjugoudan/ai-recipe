import '../importing/import_cancellation_token.dart';
import 'ocr_models.dart';

abstract interface class OcrProvider {
  OcrProviderKind get kind;

  Future<OcrDocument> recognize(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  });
}
