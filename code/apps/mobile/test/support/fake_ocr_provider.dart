import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider.dart';

class FakeOcrProvider implements OcrProvider {
  FakeOcrProvider(this.handler, {this.kind = OcrProviderKind.localPlugin});

  final Future<OcrDocument> Function(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  )
  handler;

  @override
  final OcrProviderKind kind;

  final List<OcrImageInput> inputs = <OcrImageInput>[];

  @override
  Future<OcrDocument> recognize(
    OcrImageInput input, {
    ImportCancellationToken? cancellationToken,
  }) {
    inputs.add(input);
    return handler(input, cancellationToken);
  }
}

OcrDocument sampleOcrDocument({
  String text = 'OCR recipe text',
  String providerId = 'paddleocr-local',
  String modelVersion = '1.0.0',
  String language = 'zh-Hans',
  double confidence = 0.9,
}) {
  return OcrDocument(
    providerId: providerId,
    modelVersion: modelVersion,
    language: language,
    blocks: text.trim().isEmpty
        ? const <OcrTextBlock>[]
        : <OcrTextBlock>[
            OcrTextBlock(text: text, confidence: confidence, readingOrder: 0),
          ],
  );
}
