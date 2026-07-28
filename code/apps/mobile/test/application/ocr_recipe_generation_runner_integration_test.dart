import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/importing/ocr_enriching_import_content_processor.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_ocr_provider.dart';

void main() {
  test('runner advances through OCR before generation and review', () async {
    final now = DateTime.utc(2026, 7, 28, 19);
    final source = ImportSourceLink.parse(
      'https://www.douyin.com/video/ocr-integration',
    );
    final repository = MemoryImportTaskRepository();
    repository.tasks['task-ocr-001'] = ImportTask.queued(
      id: 'task-ocr-001',
      source: source,
      now: now,
    );
    final adapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.douyin,
      handler: (source, token) async => ImportContent(
        source: source,
        resolvedUrl: source.normalizedUrl,
        contentType: ImportContentType.imageGallery,
        title: 'OCR integration title',
        capturedAt: now,
        media: <ImportMediaReference>[
          ImportMediaReference(
            kind: ImportMediaKind.image,
            remoteUrl: 'https://example.com/recipe.jpg',
            order: 0,
          ),
        ],
        warnings: const <ImportContentWarning>[
          ImportContentWarning.requiresOcr,
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
      return ImportRecipeDraftResult(recipeId: 'recipe-from-ocr');
    });
    final processor = OcrEnrichingImportContentProcessor(
      provider: FakeOcrProvider((input, token) async {
        return sampleOcrDocument(text: '番茄两个，鸡蛋三个。先炒鸡蛋，再炒番茄。');
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

    final result = await runner.run('task-ocr-001');

    expect(result.outcome, ImportTaskRunOutcome.needsReview);
    expect(result.task.status, ImportTaskStatus.needsReview);
    expect(result.task.stage, ImportTaskStage.review);
    expect(result.task.resultRecipeId, 'recipe-from-ocr');
    expect(generatedFrom, isNotNull);
    expect(
      generatedFrom!.warnings,
      isNot(contains(ImportContentWarning.requiresOcr)),
    );
    expect(generatedFrom!.textFragments.single.text, contains('番茄两个'));

    final stages = repository.savedTasks.map((task) => task.stage).toList();
    expect(
      _firstOccurrenceOrder(stages, <ImportTaskStage>[
        ImportTaskStage.fetching,
        ImportTaskStage.extracting,
        ImportTaskStage.ocr,
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
