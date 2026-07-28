import 'package:ai_recipe/domain/ocr/ocr_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrImageInput', () {
    test('accepts an HTTPS URL and normalizes optional text', () {
      final input = OcrImageInput(
        remoteUrl: ' https://example.com/image.jpg ',
        mimeType: ' image/jpeg ',
        width: 1080,
        height: 1920,
        order: 2,
      );

      expect(input.remoteUrl, 'https://example.com/image.jpg');
      expect(input.localAssetId, isNull);
      expect(input.mimeType, 'image/jpeg');
      expect(input.order, 2);
    });

    test('accepts an application media asset id', () {
      final input = OcrImageInput(localAssetId: ' asset-1 ', order: 0);

      expect(input.localAssetId, 'asset-1');
      expect(input.remoteUrl, isNull);
    });

    test('rejects insecure URLs and missing sources', () {
      expect(
        () =>
            OcrImageInput(remoteUrl: 'http://example.com/image.jpg', order: 0),
        throwsArgumentError,
      );
      expect(() => OcrImageInput(order: 0), throwsArgumentError);
    });

    test('rejects invalid dimensions and order', () {
      expect(
        () => OcrImageInput(localAssetId: 'asset', width: 0, order: 0),
        throwsArgumentError,
      );
      expect(
        () => OcrImageInput(localAssetId: 'asset', height: -1, order: 0),
        throwsArgumentError,
      );
      expect(
        () => OcrImageInput(localAssetId: 'asset', order: -1),
        throwsArgumentError,
      );
    });
  });

  group('OCR output models', () {
    test('validates confidence, points, and four-point polygons', () {
      expect(() => OcrPoint(x: -0.1, y: 0.5), throwsArgumentError);
      expect(
        () => OcrTextBlock(text: 'bad', confidence: 1.1, readingOrder: 0),
        throwsArgumentError,
      );
      expect(
        () => OcrTextBlock(
          text: 'bad polygon',
          confidence: 0.8,
          readingOrder: 0,
          polygon: <OcrPoint>[
            OcrPoint(x: 0, y: 0),
            OcrPoint(x: 1, y: 0),
            OcrPoint(x: 1, y: 1),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('orders blocks by page and reading order', () {
      final document = OcrDocument(
        providerId: ' provider ',
        modelVersion: ' 1.0.0 ',
        language: ' zh-Hans ',
        blocks: <OcrTextBlock>[
          OcrTextBlock(
            text: 'third',
            confidence: 0.6,
            readingOrder: 1,
            pageIndex: 1,
          ),
          OcrTextBlock(text: 'second', confidence: 0.8, readingOrder: 1),
          OcrTextBlock(text: 'first', confidence: 1, readingOrder: 0),
        ],
      );

      expect(document.providerId, 'provider');
      expect(document.blocks.map((block) => block.text), <String>[
        'first',
        'second',
        'third',
      ]);
      expect(document.fullText, 'first\nsecond\nthird');
      expect(document.averageConfidence, closeTo(0.8, 0.000001));
    });

    test('empty documents expose no average confidence', () {
      final document = OcrDocument(
        providerId: 'provider',
        modelVersion: '1.0.0',
        language: 'und',
      );

      expect(document.fullText, isEmpty);
      expect(document.averageConfidence, isNull);
    });
  });
}
