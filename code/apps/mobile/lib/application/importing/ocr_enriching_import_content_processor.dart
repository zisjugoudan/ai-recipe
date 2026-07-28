import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import 'import_pipeline_contracts.dart';

class OcrEnrichingImportContentProcessor implements ImportContentProcessor {
  OcrEnrichingImportContentProcessor({
    required OcrProvider provider,
    required ImportContentProcessor downstream,
    this.maxImages = 20,
  }) : _provider = provider,
       _downstream = downstream {
    if (maxImages <= 0) {
      throw ArgumentError.value(maxImages, 'maxImages', 'must be positive');
    }
  }

  final OcrProvider _provider;
  final ImportContentProcessor _downstream;
  final int maxImages;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (!content.warnings.contains(ImportContentWarning.requiresOcr)) {
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    final images = content.media
        .where((media) => media.kind == ImportMediaKind.image)
        .take(maxImages)
        .toList(growable: false);
    if (images.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: 'OCR requires at least one image.',
        retryable: false,
      );
    }

    await onProgress(ImportTaskStage.ocr, 0.35);
    final seen = <String>{
      if (content.title case final value?) value.trim(),
      if (content.description case final value?) value.trim(),
      ...content.textFragments.map((fragment) => fragment.text.trim()),
    }..remove('');
    final fragments = <ImportTextFragment>[];
    var nextOrder = content.textFragments.fold<int>(
      -1,
      (largest, fragment) =>
          fragment.order > largest ? fragment.order : largest,
    );
    var hadEmptyResult = false;

    for (var index = 0; index < images.length; index += 1) {
      cancellationToken?.throwIfCancelled();
      final media = images[index];
      final document = await _recognize(
        OcrImageInput(
          remoteUrl: media.remoteUrl,
          localAssetId: media.localAssetId,
          mimeType: media.mimeType,
          width: media.width,
          height: media.height,
          order: media.order,
        ),
        cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      final text = document.fullText.trim();
      if (text.isEmpty || !seen.add(text)) {
        hadEmptyResult = true;
      } else {
        nextOrder += 1;
        fragments.add(
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: text,
            order: nextOrder,
            confidence: document.averageConfidence,
            sourceMediaOrder: media.order,
            sourceProvider: document.providerId,
          ),
        );
      }
      await onProgress(
        ImportTaskStage.ocr,
        0.35 + (0.25 * (index + 1) / images.length),
      );
    }

    if (fragments.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: 'OCR did not return usable text.',
        retryable: false,
      );
    }

    final warnings = content.warnings.toSet()
      ..remove(ImportContentWarning.requiresOcr)
      ..remove(ImportContentWarning.missingText);
    if (hadEmptyResult ||
        content.media
                .where((item) => item.kind == ImportMediaKind.image)
                .length >
            images.length) {
      warnings.add(ImportContentWarning.partialContent);
    }

    final enriched = ImportContent(
      source: content.source,
      resolvedUrl: content.resolvedUrl,
      contentType: content.contentType,
      title: content.title,
      description: content.description,
      authorName: content.authorName,
      publishedAt: content.publishedAt,
      capturedAt: content.capturedAt,
      textFragments: <ImportTextFragment>[
        ...content.textFragments,
        ...fragments,
      ],
      media: content.media,
      warnings: warnings,
    );
    return _downstream.process(
      enriched,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }

  Future<OcrDocument> _recognize(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    try {
      return await _provider.recognize(
        input,
        cancellationToken: cancellationToken,
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on OcrProviderException catch (error) {
      throw _mapProviderError(error);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: 'OCR processing failed unexpectedly.',
        retryable: true,
      );
    }
  }

  static ImportPipelineException _mapProviderError(OcrProviderException error) {
    final message = _sanitizeMessage(error.message);
    return switch (error.kind) {
      OcrProviderErrorKind.cancelled => ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: message,
        retryable: false,
      ),
      OcrProviderErrorKind.networkUnavailable => ImportPipelineException(
        code: ImportTaskErrorCode.networkUnavailable,
        message: message,
        retryable: true,
      ),
      OcrProviderErrorKind.timeout => ImportPipelineException(
        code: ImportTaskErrorCode.timeout,
        message: message,
        retryable: true,
      ),
      OcrProviderErrorKind.rateLimited ||
      OcrProviderErrorKind.unknown => ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: message,
        retryable: true,
      ),
      _ => ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: message,
        retryable: false,
      ),
    };
  }

  static String _sanitizeMessage(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'OCR processing failed.';
    }
    return normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 237)}...';
  }
}
