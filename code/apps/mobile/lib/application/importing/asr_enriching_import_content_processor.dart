import '../../domain/asr/asr_models.dart';
import '../../domain/asr/asr_provider.dart';
import '../../domain/asr/asr_provider_exception.dart';
import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import 'import_pipeline_contracts.dart';

class AsrEnrichingImportContentProcessor implements ImportContentProcessor {
  AsrEnrichingImportContentProcessor({
    required AsrProvider provider,
    required ImportContentProcessor downstream,
    this.maxMediaItems = 3,
    this.maxMediaDurationMs = 30 * 60 * 1000,
    this.languageHint,
  }) : _provider = provider,
       _downstream = downstream {
    if (maxMediaItems <= 0) {
      throw ArgumentError.value(
        maxMediaItems,
        'maxMediaItems',
        'must be positive',
      );
    }
    if (maxMediaDurationMs <= 0) {
      throw ArgumentError.value(
        maxMediaDurationMs,
        'maxMediaDurationMs',
        'must be positive',
      );
    }
  }

  final AsrProvider _provider;
  final ImportContentProcessor _downstream;
  final int maxMediaItems;
  final int maxMediaDurationMs;
  final String? languageHint;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (!content.warnings.contains(ImportContentWarning.requiresAsr)) {
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

    final allMedia = content.media
        .where(
          (media) =>
              media.kind == ImportMediaKind.audio ||
              media.kind == ImportMediaKind.video,
        )
        .toList(growable: false);
    if (allMedia.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.asrFailed,
        message: 'ASR requires at least one audio or video item.',
        retryable: false,
      );
    }

    final mediaItems = allMedia.take(maxMediaItems).toList(growable: false);
    for (final media in mediaItems) {
      if (media.durationMs case final duration?
          when duration > maxMediaDurationMs) {
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.asrFailed,
          message: 'ASR media duration exceeds the configured limit.',
          retryable: false,
        );
      }
    }

    await onProgress(ImportTaskStage.transcribing, 0.61);
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
    var partial = allMedia.length > mediaItems.length;
    ImportPipelineException? firstFailure;

    for (var index = 0; index < mediaItems.length; index += 1) {
      cancellationToken?.throwIfCancelled();
      final media = mediaItems[index];
      try {
        final transcript = await _transcribe(
          AsrMediaInput(
            kind: media.kind == ImportMediaKind.audio
                ? AsrMediaKind.audio
                : AsrMediaKind.video,
            remoteUrl: media.remoteUrl,
            localAssetId: media.localAssetId,
            mimeType: media.mimeType,
            durationMs: media.durationMs,
            languageHint: languageHint,
            order: media.order,
          ),
          cancellationToken,
        );
        cancellationToken?.throwIfCancelled();
        if (transcript.segments.isEmpty) {
          partial = true;
        }
        for (final segment in transcript.segments) {
          final text = segment.text.trim();
          if (text.isEmpty || !seen.add(text)) {
            partial = true;
            continue;
          }
          nextOrder += 1;
          fragments.add(
            ImportTextFragment(
              kind: ImportTextFragmentKind.caption,
              text: text,
              order: nextOrder,
              confidence: segment.confidence,
              sourceMediaOrder: media.order,
              sourceProvider: transcript.providerId,
              sourceLanguage: transcript.language,
              sourceStartMs: segment.startMs,
              sourceEndMs: segment.endMs,
              speakerLabel: segment.speakerLabel,
            ),
          );
        }
      } on ImportOperationCancelledException {
        rethrow;
      } on ImportPipelineException catch (error) {
        if (error.code == ImportTaskErrorCode.cancelled) {
          throw ImportOperationCancelledException();
        }
        firstFailure ??= error;
        partial = true;
      }
      await onProgress(
        ImportTaskStage.transcribing,
        0.61 + (0.03 * (index + 1) / mediaItems.length),
      );
    }

    if (fragments.isEmpty) {
      throw firstFailure ??
          const ImportPipelineException(
            code: ImportTaskErrorCode.asrFailed,
            message: 'ASR did not return usable text.',
            retryable: false,
          );
    }

    final warnings = content.warnings.toSet()
      ..remove(ImportContentWarning.requiresAsr)
      ..remove(ImportContentWarning.missingText);
    if (partial) {
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

  Future<AsrTranscript> _transcribe(
    AsrMediaInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    try {
      return await _provider.transcribe(
        input,
        cancellationToken: cancellationToken,
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on AsrProviderException catch (error) {
      throw _mapProviderError(error);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.asrFailed,
        message: 'ASR processing failed unexpectedly.',
        retryable: true,
      );
    }
  }

  static ImportPipelineException _mapProviderError(AsrProviderException error) {
    final message = _sanitizeMessage(error.message);
    return switch (error.kind) {
      AsrProviderErrorKind.cancelled => ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: message,
        retryable: false,
      ),
      AsrProviderErrorKind.networkUnavailable => ImportPipelineException(
        code: ImportTaskErrorCode.networkUnavailable,
        message: message,
        retryable: true,
      ),
      AsrProviderErrorKind.timeout => ImportPipelineException(
        code: ImportTaskErrorCode.timeout,
        message: message,
        retryable: true,
      ),
      AsrProviderErrorKind.rateLimited ||
      AsrProviderErrorKind.unknown => ImportPipelineException(
        code: ImportTaskErrorCode.asrFailed,
        message: message,
        retryable: true,
      ),
      _ => ImportPipelineException(
        code: ImportTaskErrorCode.asrFailed,
        message: message,
        retryable: false,
      ),
    };
  }

  static String _sanitizeMessage(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'ASR processing failed.';
    }
    return normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 237)}...';
  }
}
