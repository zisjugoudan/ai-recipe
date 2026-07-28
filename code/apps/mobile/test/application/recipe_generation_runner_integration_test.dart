import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/importing/llm_recipe_generation_processor.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_recipe_generation_dependencies.dart';

void main() {
  test(
    'runner reaches review only after generated recipe is persisted',
    () async {
      final now = DateTime.utc(2026, 7, 28, 17);
      final source = ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/integration',
      );
      final taskRepository = MemoryImportTaskRepository();
      taskRepository.tasks['task-ai-002'] = ImportTask.queued(
        id: 'task-ai-002',
        source: source,
        now: now,
      );
      final recipeRepository = MemoryRecipeRepository();
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      var nextId = 0;
      final processor = LlmRecipeGenerationProcessor(
        provider: provider,
        config: LlmConnectionConfig(
          id: 'config-1',
          name: 'Integration',
          providerType: LlmProviderType.gemini,
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          secretRef: 'secret-ref',
          model: 'gemini-test',
        ),
        apiKey: '',
        recipeRepository: recipeRepository,
        idGenerator: () => 'id-${nextId += 1}',
        clock: () => now,
      );
      final adapter = FakeImportContentAdapter(
        platform: ImportSourcePlatform.xiaohongshu,
        handler: (source, cancellationToken) async {
          return sampleImportContent(
            source,
            title: '番茄炒蛋原文',
            resolvedUrl: source.normalizedUrl,
          );
        },
      );
      final runner = ImportTaskRunner(
        repository: taskRepository,
        adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
          adapter,
        ]),
        processor: processor,
        clock: () => now,
      );

      final result = await runner.run('task-ai-002');

      expect(result.outcome, ImportTaskRunOutcome.needsReview);
      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(result.task.resultRecipeId, 'id-1');
      final saved = recipeRepository.recipes['id-1'];
      expect(saved, isNotNull);
      expect(saved!.title, '番茄炒蛋');
      expect(saved.sourceId, source.normalizedUrl);
      expect(saved.ingredients.single.id, 'id-2');
      expect(saved.steps.single.id, 'id-3');
    },
  );

  test(
    'processor success is a commit point even when cancellation arrives after save',
    () async {
      final now = DateTime.utc(2026, 7, 28, 18);
      final source = ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/commit-point',
      );
      final taskRepository = MemoryImportTaskRepository();
      taskRepository.tasks['task-commit-point'] = ImportTask.queued(
        id: 'task-commit-point',
        source: source,
        now: now,
      );
      final cancellationToken = ImportCancellationToken();
      final recipeRepository = MemoryRecipeRepository()
        ..afterUpsert = (_) => cancellationToken.cancel();
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      var nextId = 0;
      final processor = LlmRecipeGenerationProcessor(
        provider: provider,
        config: LlmConnectionConfig(
          id: 'config-commit-point',
          name: 'Commit point',
          providerType: LlmProviderType.openAiCompatible,
          baseUrl: 'https://example.com/v1',
          secretRef: 'secret-ref',
          model: 'test-model',
        ),
        apiKey: '',
        recipeRepository: recipeRepository,
        idGenerator: () => 'commit-${nextId += 1}',
        clock: () => now,
      );
      final adapter = FakeImportContentAdapter(
        platform: ImportSourcePlatform.xiaohongshu,
        handler: (source, cancellationToken) async {
          return sampleImportContent(source, resolvedUrl: source.normalizedUrl);
        },
      );
      final runner = ImportTaskRunner(
        repository: taskRepository,
        adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
          adapter,
        ]),
        processor: processor,
        clock: () => now,
      );

      final result = await runner.run(
        'task-commit-point',
        cancellationToken: cancellationToken,
      );

      expect(cancellationToken.isCancelled, isTrue);
      expect(result.outcome, ImportTaskRunOutcome.needsReview);
      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(result.task.resultRecipeId, 'commit-1');
      expect(recipeRepository.recipes, contains('commit-1'));
    },
  );
}
