import 'package:ai_recipe/application/importing/asr_enriching_import_content_processor.dart';
import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_asr_provider.dart';
import '../support/fake_import_dependencies.dart';

void main() {
  test('runner advances through ASR before generation and review', () async {
    final now = DateTime.utc(2026, 7, 28, 20);
    final source = ImportSourceLink.parse(
      'https://www.douyin.com/video/asr-integration',
    );
    final repository = MemoryImportTaskRepository();
    repository.tasks['task-asr-001'] = ImportTask.queued(
      id: 'task-asr-001',
      source: source,
      now: now,
    );
    final adapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (source, token) async => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.video,
        title: 'ASR integration title',
        capturedAt: now,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.video,
            remoteUrl: 'https://example.com/recipe.mp4',
            mimeType: 'video/mp4',
            durationMs: 5000,
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresAsr,
          ImportContentWarning.missingText,
        ],
      ),
    );
    ImportContent? generatedFrom;
    final generatingProcessor = FakeImportContentProcessor((
      content,
      onProgress,
      token,
    ) async {
      generatedFrom = content;
      await onProgress(ImportTaskStage.generating, 0.7);
      await onProgress(ImportTaskStage.generating, 0.9);
      return ImportRecipeDraftResult(recipeId: 'recipe-from-asr');
    });
    final processor = AsrEnrichingImportContentProcessor(
      provider: FakeAsrProvider((input, token) async {
        return sampleAsrTranscript(
          text: '番茄两个，鸡蛋三个。先炒鸡蛋，再炒番茄。',
          language: 'zh-Hans',
          startMs: 500,
          endMs: 4200,
          speakerLabel: 'speaker-1',
        );
      }),
      downstream: generatingProcessor,
    );
    final runner = ImportTaskRunner(
      repository: repository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]),
      processor: processor,
      clock: () => now,
    );

    final result = await runner.run('task-asr-001');

    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(result.task.stage, ImportTaskStage.review);
    expect(result.task.resultRecipeId, 'recipe-from-asr');
    expect(generatedFrom, isNotNull);
    expect(
      generatedFrom!.warnings,
      isNot(contains(ImportContentWarning.requiresAsr)),
    );
    expect(
      generatedFrom!.warnings,
      isNot(contains(ImportContentWarning.missingText)),
    );
    final transcript = generatedFrom!.textFragments.single;
    expect(transcript.text, contains('番茄两个'));
    expect(transcript.sourceLanguage, 'zh-Hans');
    expect(transcript.sourceStartMs, 500);
    expect(transcript.sourceEndMs, 4200);
    expect(transcript.speakerLabel, 'speaker-1');

    final stages = repository.savedTasks.map((task) => task.stage).toList();
    expect(
      _firstOccurrenceOrder(stages, <ImportTaskStage>[
        ImportTaskStage.fetching,
        ImportTaskStage.extracting,
        ImportTaskStage.transcribing,
        ImportTaskStage.generating,
        ImportTaskStage.review,
      ]),
      isTrue,
      reason: stages.map((stage) => stage.name).join(' -> '),
    );
  });
}

bool _firstOccurrenceOrder(
  List<ImportTaskStage> actual,
  List<ImportTaskStage> expected,
) {
  var previousIndex = -1;
  for (final stage in expected) {
    final index = actual.indexOf(stage);
    if (index <= previousIndex) {
      return false;
    }
    previousIndex = index;
  }
  return true;
}
