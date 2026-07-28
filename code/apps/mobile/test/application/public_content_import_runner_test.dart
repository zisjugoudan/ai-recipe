import 'dart:io';

import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/providers/importing/import_http_transport.dart';
import 'package:ai_recipe/providers/importing/public_content_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';

void main() {
  test(
    'public fixture adapter runs through the task runner into review',
    () async {
      final now = DateTime.utc(2026, 7, 28, 14);
      final source = ImportSourceLink.parse(
        'https://www.douyin.com/video/123456',
      );
      final repository = MemoryImportTaskRepository();
      repository.tasks['task-public-fixture'] = ImportTask.queued(
        id: 'task-public-fixture',
        source: source,
        now: now,
      );
      final adapter = DouyinPublicContentAdapter(
        transport: _FixtureTransport(
          File('test/fixtures/importing/douyin_public.html').readAsStringSync(),
        ),
        clock: () => now,
      );
      ImportContent? processedContent;
      final processor = FakeImportContentProcessor((
        content,
        onProgress,
        cancellationToken,
      ) async {
        processedContent = content;
        await onProgress(ImportTaskStage.ocr, 0.5);
        await onProgress(ImportTaskStage.transcribing, 0.7);
        await onProgress(ImportTaskStage.generating, 0.9);
        return ImportRecipeDraftResult(recipeId: 'recipe-public-fixture');
      });
      final runner = ImportTaskRunner(
        repository: repository,
        adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
          adapter,
        ]),
        processor: processor,
        clock: () => now,
      );

      final result = await runner.run('task-public-fixture');

      expect(result.outcome, ImportTaskRunOutcome.needsReview);
      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(result.task.resultRecipeId, 'recipe-public-fixture');
      expect(result.content?.title, 'Quick Tomato Egg Stir Fry');
      expect(processedContent, same(result.content));
      expect(
        processedContent?.warnings,
        containsAll(<ImportContentWarning>{
          ImportContentWarning.requiresOcr,
          ImportContentWarning.requiresAsr,
        }),
      );
    },
  );
}

class _FixtureTransport implements ImportHttpTransport {
  _FixtureTransport(this.body);

  final String body;

  @override
  Future<ImportHttpResponse> get(
    ImportHttpRequest request, {
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    return ImportHttpResponse(
      statusCode: 200,
      headers: const <String, String>{'content-type': 'text/html'},
      body: body,
      resolvedUri: request.uri,
      redirectCount: 0,
    );
  }
}
