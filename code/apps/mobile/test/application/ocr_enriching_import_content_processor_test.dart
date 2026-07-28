import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/ocr_enriching_import_content_processor.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/ocr/ocr_provider_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_ocr_provider.dart';

void main() {
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/ocr-test',
  );

  test('skips OCR when the content does not require it', () async {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument();
    });
    ImportContent? received;
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      received = content;
      return ImportRecipeDraftResult(recipeId: 'recipe-1');
    });
    final content = buildContent(
      source,
      warnings: const <ImportContentWarning>[],
    );
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );

    final result = await processor.process(
      content,
      onProgress: (_, _) async {},
    );

    expect(result.recipeId, 'recipe-1');
    expect(provider.inputs, isEmpty);
    expect(received, same(content));
  });

  test('fails before downstream when OCR is required without images', () async {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument();
    });
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      return ImportRecipeDraftResult(recipeId: 'unexpected');
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );
    final content = ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.article,
      title: 'Image recipe',
      capturedAt: DateTime.utc(2026, 7, 28),
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.metadata,
          text: 'metadata only',
          order: 0,
        ),
      ],
      warnings: const <ImportContentWarning>[ImportContentWarning.requiresOcr],
    );

    await expectLater(
      processor.process(content, onProgress: (_, _) async {}),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.ocrFailed,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    expect(provider.inputs, isEmpty);
    expect(downstream.callCount, 0);
  });

  test('recognizes images in media order and appends OCR evidence', () async {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(
        text: input.order == 1 ? '先切番茄' : '再炒鸡蛋',
        confidence: input.order == 1 ? 0.8 : 1,
      );
    });
    ImportContent? received;
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      received = content;
      return ImportRecipeDraftResult(recipeId: 'recipe-ocr');
    });
    final progressEvents = <(ImportTaskStage, double)>[];
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );

    final result = await processor.process(
      buildContent(source),
      onProgress: (stage, progress) async {
        progressEvents.add((stage, progress));
      },
    );

    expect(result.recipeId, 'recipe-ocr');
    expect(provider.inputs.map((input) => input.order), <int>[1, 3]);
    expect(received, isNotNull);
    expect(received!.textFragments.map((fragment) => fragment.order), <int>[
      4,
      5,
      6,
    ]);
    final ocrFragments = received!.textFragments.skip(1).toList();
    expect(ocrFragments.map((fragment) => fragment.text), <String>[
      '先切番茄',
      '再炒鸡蛋',
    ]);
    expect(ocrFragments.first.confidence, 0.8);
    expect(ocrFragments.first.sourceMediaOrder, 1);
    expect(ocrFragments.first.sourceProvider, 'paddleocr-local');
    expect(
      received!.warnings,
      isNot(contains(ImportContentWarning.requiresOcr)),
    );
    expect(
      received!.warnings,
      isNot(contains(ImportContentWarning.missingText)),
    );
    expect(progressEvents.first, (ImportTaskStage.ocr, 0.35));
    expect(progressEvents.last.$1, ImportTaskStage.ocr);
    expect(progressEvents.last.$2, closeTo(0.6, 0.000001));
  });

  test('marks partial content when image limit truncates work', () async {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: 'text-${input.order}');
    });
    ImportContent? received;
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      received = content;
      return ImportRecipeDraftResult(recipeId: 'recipe-limited');
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
      maxImages: 1,
    );

    await processor.process(buildContent(source), onProgress: (_, _) async {});

    expect(provider.inputs, hasLength(1));
    expect(received!.warnings, contains(ImportContentWarning.partialContent));
  });

  test(
    'keeps usable text and marks partial when another result is empty',
    () async {
      final provider = FakeOcrProvider((input, token) async {
        return sampleOcrDocument(
          text: input.order == 1 ? 'usable text' : '   ',
        );
      });
      ImportContent? received;
      final downstream = FakeImportContentProcessor((
        content,
        progress,
        token,
      ) async {
        received = content;
        return ImportRecipeDraftResult(recipeId: 'recipe-partial');
      });
      final processor = OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: downstream,
      );

      await processor.process(
        buildContent(source),
        onProgress: (_, _) async {},
      );

      expect(
        received!.textFragments.where((item) => item.sourceProvider != null),
        hasLength(1),
      );
      expect(received!.warnings, contains(ImportContentWarning.partialContent));
    },
  );

  test('fails when all OCR results are empty', () async {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument(text: '');
    });
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      return ImportRecipeDraftResult(recipeId: 'unexpected');
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );

    await expectLater(
      processor.process(buildContent(source), onProgress: (_, _) async {}),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.ocrFailed,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    expect(downstream.callCount, 0);
  });

  test(
    'does not append duplicate OCR text when another image is usable',
    () async {
      final provider = FakeOcrProvider((input, token) async {
        return sampleOcrDocument(
          text: input.order == 1 ? 'Existing extracted text' : 'New OCR text',
        );
      });
      ImportContent? received;
      final downstream = FakeImportContentProcessor((
        content,
        progress,
        token,
      ) async {
        received = content;
        return ImportRecipeDraftResult(recipeId: 'recipe-dedup');
      });
      final processor = OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: downstream,
      );

      await processor.process(
        buildContent(source),
        onProgress: (_, _) async {},
      );

      expect(
        received!.textFragments.where(
          (fragment) => fragment.text == 'Existing extracted text',
        ),
        hasLength(1),
      );
      expect(received!.textFragments.last.text, 'New OCR text');
      expect(received!.warnings, contains(ImportContentWarning.partialContent));
    },
  );

  test('maps provider failures to stable pipeline errors', () async {
    final cases = <OcrProviderErrorKind, (ImportTaskErrorCode, bool)>{
      OcrProviderErrorKind.cancelled: (ImportTaskErrorCode.cancelled, false),
      OcrProviderErrorKind.networkUnavailable: (
        ImportTaskErrorCode.networkUnavailable,
        true,
      ),
      OcrProviderErrorKind.timeout: (ImportTaskErrorCode.timeout, true),
      OcrProviderErrorKind.rateLimited: (ImportTaskErrorCode.ocrFailed, true),
      OcrProviderErrorKind.unknown: (ImportTaskErrorCode.ocrFailed, true),
      OcrProviderErrorKind.modelNotInstalled: (
        ImportTaskErrorCode.ocrFailed,
        false,
      ),
    };

    for (final entry in cases.entries) {
      final provider = FakeOcrProvider((input, token) async {
        throw OcrProviderException(
          kind: entry.key,
          message: '  provider\n failure  ',
        );
      });
      final processor = OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: FakeImportContentProcessor((
          content,
          progress,
          token,
        ) async {
          return ImportRecipeDraftResult(recipeId: 'unexpected');
        }),
      );

      await expectLater(
        processor.process(buildContent(source), onProgress: (_, _) async {}),
        throwsA(
          isA<ImportPipelineException>()
              .having((error) => error.code, 'code', entry.value.$1)
              .having((error) => error.retryable, 'retryable', entry.value.$2)
              .having((error) => error.message, 'message', 'provider failure'),
        ),
        reason: entry.key.name,
      );
    }
  });

  test('redacts unknown provider exceptions behind a stable message', () async {
    const secret = 'raw-response-with-secret';
    final provider = FakeOcrProvider((input, token) async {
      throw StateError(secret);
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: FakeImportContentProcessor((content, progress, token) async {
        return ImportRecipeDraftResult(recipeId: 'unexpected');
      }),
    );

    await expectLater(
      processor.process(buildContent(source), onProgress: (_, _) async {}),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.message,
              'message',
              isNot(contains(secret)),
            )
            .having(
              (error) => error.message,
              'message',
              'OCR processing failed unexpectedly.',
            ),
      ),
    );
  });

  test('propagates cancellation without calling downstream', () async {
    final token = ImportCancellationToken()..cancel();
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument();
    });
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      return ImportRecipeDraftResult(recipeId: 'unexpected');
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );

    await expectLater(
      processor.process(
        buildContent(source),
        onProgress: (_, _) async {},
        cancellationToken: token,
      ),
      throwsA(isA<ImportOperationCancelledException>()),
    );
    expect(provider.inputs, isEmpty);
    expect(downstream.callCount, 0);
  });

  test('rejects a non-positive image limit', () {
    final provider = FakeOcrProvider((input, token) async {
      return sampleOcrDocument();
    });

    expect(
      () => OcrEnrichingImportContentProcessor(
        provider: provider,
        downstream: FakeImportContentProcessor((
          content,
          progress,
          token,
        ) async {
          return ImportRecipeDraftResult(recipeId: 'unused');
        }),
        maxImages: 0,
      ),
      throwsArgumentError,
    );
  });
}

ImportContent buildContent(
  ImportSourceLink source, {
  Iterable<ImportContentWarning> warnings = const <ImportContentWarning>[
    ImportContentWarning.requiresOcr,
    ImportContentWarning.missingText,
  ],
}) {
  return ImportContent(
    source: source,
    resolvedUrl: source.normalizedUrl,
    contentType: ImportContentType.imageGallery,
    title: 'OCR title',
    capturedAt: DateTime.utc(2026, 7, 28),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.metadata,
        text: 'Existing extracted text',
        order: 4,
      ),
    ],
    media: <ImportMediaReference>[
      ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'https://example.com/second.jpg',
        order: 3,
      ),
      ImportMediaReference(
        kind: ImportMediaKind.video,
        remoteUrl: 'https://example.com/video.mp4',
        order: 2,
      ),
      ImportMediaReference(
        kind: ImportMediaKind.image,
        localAssetId: 'first-image',
        mimeType: 'image/jpeg',
        width: 1080,
        height: 1920,
        order: 1,
      ),
    ],
    warnings: warnings,
  );
}
