import 'package:ai_recipe/application/importing/asr_enriching_import_content_processor.dart';
import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/domain/asr/asr_models.dart';
import 'package:ai_recipe/domain/asr/asr_provider_exception.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_asr_provider.dart';
import '../support/fake_import_dependencies.dart';

void main() {
  final source = ImportSourceLink.parse(
    'https://www.douyin.com/video/asr-test',
  );

  test('skips ASR when the content does not require it', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript();
    });
    final downstream = _successfulDownstream();
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );

    final result = await processor.process(
      buildContent(source, warnings: const <ImportContentWarning>[]),
      onProgress: (_, _) async {},
    );

    expect(result.recipeId, 'recipe-asr');
    expect(provider.inputs, isEmpty);
    expect(downstream.callCount, 1);
  });

  test('reports progress after OCR and before LLM generation', () async {
    final events = <(ImportTaskStage, double)>[];
    final processor = AsrEnrichingImportContentProcessor(
      provider: FakeAsrProvider((input, token) async {
        return sampleAsrTranscript();
      }),
      downstream: _successfulDownstream(),
    );

    await processor.process(
      buildContent(source),
      onProgress: (stage, progress) async => events.add((stage, progress)),
    );

    expect(events.first, (ImportTaskStage.transcribing, 0.61));
    expect(events.last.$1, ImportTaskStage.transcribing);
    expect(events.last.$2, closeTo(0.64, 0.000001));
  });

  test('fails before downstream when ASR is required without media', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript();
    });
    final downstream = _successfulDownstream();
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
    );
    final content = ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.article,
      title: 'video title',
      capturedAt: DateTime.utc(2026, 7, 28),
      warnings: const <ImportContentWarning>[ImportContentWarning.requiresAsr],
    );

    await expectLater(
      processor.process(content, onProgress: (_, _) async {}),
      throwsA(
        isA<ImportPipelineException>().having(
          (error) => error.code,
          'code',
          ImportTaskErrorCode.asrFailed,
        ),
      ),
    );
    expect(provider.inputs, isEmpty);
    expect(downstream.callCount, 0);
  });

  test('transcribes media in order and appends timestamp evidence', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript(
        text: input.kind == AsrMediaKind.audio ? 'audio step' : 'video step',
        providerId: 'asr-provider',
        language: 'zh-Hans',
        startMs: input.order * 1000,
        endMs: (input.order + 1) * 1000,
        speakerLabel: 'cook',
      );
    });
    ImportContent? received;
    final downstream = FakeImportContentProcessor((
      content,
      progress,
      token,
    ) async {
      received = content;
      return ImportRecipeDraftResult(recipeId: 'recipe-asr');
    });
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: downstream,
      languageHint: 'zh-Hans',
    );

    await processor.process(buildContent(source), onProgress: (_, _) async {});

    expect(provider.inputs.map((input) => input.order), <int>[1, 2]);
    expect(provider.inputs.first.kind, AsrMediaKind.video);
    expect(provider.inputs.last.kind, AsrMediaKind.audio);
    expect(provider.inputs.first.languageHint, 'zh-Hans');
    final fragments = received!.textFragments
        .where((fragment) => fragment.kind == ImportTextFragmentKind.caption)
        .toList();
    expect(fragments.map((fragment) => fragment.text), <String>[
      'video step',
      'audio step',
    ]);
    expect(fragments.first.sourceMediaOrder, 1);
    expect(fragments.first.sourceProvider, 'asr-provider');
    expect(fragments.first.sourceLanguage, 'zh-Hans');
    expect(fragments.first.sourceStartMs, 1000);
    expect(fragments.first.sourceEndMs, 2000);
    expect(fragments.first.speakerLabel, 'cook');
    expect(
      received!.warnings,
      isNot(contains(ImportContentWarning.requiresAsr)),
    );
    expect(
      received!.warnings,
      isNot(contains(ImportContentWarning.missingText)),
    );
  });

  test('marks partial content when media limit truncates work', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript(text: 'text-${input.order}');
    });
    ImportContent? received;
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      maxMediaItems: 1,
      downstream: FakeImportContentProcessor((content, progress, token) async {
        received = content;
        return ImportRecipeDraftResult(recipeId: 'recipe-asr');
      }),
    );

    await processor.process(buildContent(source), onProgress: (_, _) async {});

    expect(provider.inputs, hasLength(1));
    expect(received!.warnings, contains(ImportContentWarning.partialContent));
  });

  test('rejects known media duration beyond the configured limit', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript();
    });
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      maxMediaDurationMs: 1000,
      downstream: _successfulDownstream(),
    );

    await expectLater(
      processor.process(
        buildContent(source, firstDurationMs: 1001),
        onProgress: (_, _) async {},
      ),
      throwsA(
        isA<ImportPipelineException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskErrorCode.asrFailed,
            )
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    expect(provider.inputs, isEmpty);
  });

  test('keeps successful media when another provider call fails', () async {
    final provider = FakeAsrProvider((input, token) async {
      if (input.order == 2) {
        throw const AsrProviderException(
          kind: AsrProviderErrorKind.timeout,
          message: 'provider timeout',
        );
      }
      return sampleAsrTranscript(text: 'usable transcript');
    });
    ImportContent? received;
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: FakeImportContentProcessor((content, progress, token) async {
        received = content;
        return ImportRecipeDraftResult(recipeId: 'recipe-asr');
      }),
    );

    await processor.process(buildContent(source), onProgress: (_, _) async {});

    expect(received!.textFragments.last.text, 'usable transcript');
    expect(received!.warnings, contains(ImportContentWarning.partialContent));
  });

  test('deduplicates transcript segments and marks partial content', () async {
    final provider = FakeAsrProvider((input, token) async {
      return AsrTranscript(
        providerId: 'provider',
        modelVersion: 'model',
        language: 'en',
        durationMs: 2000,
        segments: <AsrTranscriptSegment>[
          AsrTranscriptSegment(text: 'same', startMs: 0, endMs: 1000),
          AsrTranscriptSegment(text: 'same', startMs: 1000, endMs: 2000),
        ],
      );
    });
    ImportContent? received;
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      maxMediaItems: 1,
      downstream: FakeImportContentProcessor((content, progress, token) async {
        received = content;
        return ImportRecipeDraftResult(recipeId: 'recipe-asr');
      }),
    );

    await processor.process(buildContent(source), onProgress: (_, _) async {});

    expect(
      received!.textFragments.where((item) => item.text == 'same'),
      hasLength(1),
    );
    expect(received!.warnings, contains(ImportContentWarning.partialContent));
  });

  test('fails when every ASR result is empty', () async {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript(text: '');
    });
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: _successfulDownstream(),
    );

    await expectLater(
      processor.process(buildContent(source), onProgress: (_, _) async {}),
      throwsA(
        isA<ImportPipelineException>().having(
          (error) => error.code,
          'code',
          ImportTaskErrorCode.asrFailed,
        ),
      ),
    );
  });

  test('maps provider failures to stable pipeline errors', () async {
    final cases = <AsrProviderErrorKind, (ImportTaskErrorCode, bool)>{
      AsrProviderErrorKind.cancelled: (ImportTaskErrorCode.cancelled, false),
      AsrProviderErrorKind.networkUnavailable: (
        ImportTaskErrorCode.networkUnavailable,
        true,
      ),
      AsrProviderErrorKind.timeout: (ImportTaskErrorCode.timeout, true),
      AsrProviderErrorKind.rateLimited: (ImportTaskErrorCode.asrFailed, true),
      AsrProviderErrorKind.unknown: (ImportTaskErrorCode.asrFailed, true),
      AsrProviderErrorKind.modelNotInstalled: (
        ImportTaskErrorCode.asrFailed,
        false,
      ),
    };

    for (final entry in cases.entries) {
      final provider = FakeAsrProvider((input, token) async {
        throw AsrProviderException(
          kind: entry.key,
          message: '  provider\n failure  ',
        );
      });
      final processor = AsrEnrichingImportContentProcessor(
        provider: provider,
        downstream: _successfulDownstream(),
      );

      if (entry.key == AsrProviderErrorKind.cancelled) {
        await expectLater(
          processor.process(
            buildContent(source, includeSecondMedia: false),
            onProgress: (_, _) async {},
          ),
          throwsA(isA<ImportOperationCancelledException>()),
        );
      } else {
        await expectLater(
          processor.process(
            buildContent(source, includeSecondMedia: false),
            onProgress: (_, _) async {},
          ),
          throwsA(
            isA<ImportPipelineException>()
                .having((error) => error.code, 'code', entry.value.$1)
                .having((error) => error.retryable, 'retryable', entry.value.$2)
                .having(
                  (error) => error.message,
                  'message',
                  'provider failure',
                ),
          ),
          reason: entry.key.name,
        );
      }
    }
  });

  test('redacts unknown exceptions behind a stable message', () async {
    const secret = 'raw-response-with-secret';
    final provider = FakeAsrProvider((input, token) async {
      throw StateError(secret);
    });
    final processor = AsrEnrichingImportContentProcessor(
      provider: provider,
      downstream: _successfulDownstream(),
    );

    await expectLater(
      processor.process(
        buildContent(source, includeSecondMedia: false),
        onProgress: (_, _) async {},
      ),
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
              'ASR processing failed unexpectedly.',
            ),
      ),
    );
  });

  test('propagates cancellation before calling provider', () async {
    final token = ImportCancellationToken()..cancel();
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript();
    });
    final downstream = _successfulDownstream();
    final processor = AsrEnrichingImportContentProcessor(
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

  test('rejects non-positive limits', () {
    final provider = FakeAsrProvider((input, token) async {
      return sampleAsrTranscript();
    });

    expect(
      () => AsrEnrichingImportContentProcessor(
        provider: provider,
        downstream: _successfulDownstream(),
        maxMediaItems: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => AsrEnrichingImportContentProcessor(
        provider: provider,
        downstream: _successfulDownstream(),
        maxMediaDurationMs: 0,
      ),
      throwsArgumentError,
    );
  });
}

FakeImportContentProcessor _successfulDownstream() {
  return FakeImportContentProcessor((content, progress, token) async {
    return ImportRecipeDraftResult(recipeId: 'recipe-asr');
  });
}

ImportContent buildContent(
  ImportSourceLink source, {
  Iterable<ImportContentWarning> warnings = const <ImportContentWarning>[
    ImportContentWarning.requiresAsr,
    ImportContentWarning.missingText,
  ],
  int firstDurationMs = 1000,
  bool includeSecondMedia = true,
}) {
  return ImportContent(
    source: source,
    resolvedUrl: source.normalizedUrl,
    contentType: ImportContentType.video,
    title: 'ASR title',
    capturedAt: DateTime.utc(2026, 7, 28),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.metadata,
        text: 'Existing metadata',
        order: 4,
      ),
    ],
    media: <ImportMediaReference>[
      ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'https://example.com/cover.jpg',
        order: 0,
      ),
      ImportMediaReference(
        kind: ImportMediaKind.video,
        localAssetId: 'video-1',
        mimeType: 'video/mp4',
        durationMs: firstDurationMs,
        order: 1,
      ),
      if (includeSecondMedia)
        ImportMediaReference(
          kind: ImportMediaKind.audio,
          remoteUrl: 'https://example.com/audio.mp3',
          mimeType: 'audio/mpeg',
          durationMs: 3000,
          order: 2,
        ),
    ],
    warnings: warnings,
  );
}
