import 'package:ai_recipe/application/backend/import_execution_plan.dart';
import 'package:ai_recipe/application/backend/import_task_runner_factory.dart';
import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/data/device_import_task_runner_factory.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:ai_recipe/providers/llm/llm_provider_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_recipe_generation_dependencies.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
  final now = DateTime.utc(2026, 7, 28, 21);

  test(
    'custom LLM route reads config and persists authenticated user id',
    () async {
      final taskRepository = MemoryImportTaskRepository();
      final recipeRepository = MemoryRecipeLibraryRepository();
      final source = ImportSourceLink.parse(
        'https://www.xiaohongshu.com/explore/backend-factory',
      );
      taskRepository.tasks['task-custom'] = ImportTask.queued(
        id: 'task-custom',
        source: source,
        now: now,
      );
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        expect(config.model, 'test-model');
        expect(apiKey, 'test-placeholder');
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      final providerFactory = FakeLlmProviderFactory(provider);
      var id = 0;
      final factory = DeviceImportTaskRunnerFactory(
        importTaskRepository: taskRepository,
        recipeRepository: recipeRepository,
        discardRecipeDraft: discardImportRecipeDraft,
        adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
          FakeImportContentAdapter(
            platform: ImportSourcePlatform.xiaohongshu,
            handler: (source, token) async => sampleImportContent(source),
          ),
        ]),
        llmConfigRepository: MemoryLlmConfigRepository(
          config: testLlmConfig,
          apiKey: 'test-placeholder',
        ),
        llmProviderFactory: providerFactory,
        idGenerator: () => 'generated-${id += 1}',
        clock: () => now,
      );

      final runner = await factory.create(
        const ImportExecutionPlan(),
        userId: '  user-123  ',
      );
      final result = await runner.run('task-custom');

      expect(result.task.status, ImportTaskStatus.needsReview);
      expect(providerFactory.lastType, LlmProviderType.openAiCompatible);
      expect(provider.callCount, 1);
      final recipe = recipeRepository.recipes[result.task.resultRecipeId];
      expect(recipe, isNotNull);
      expect(recipe!.userId, 'user-123');
    },
  );

  test('custom LLM route rejects missing config and empty key', () async {
    final withoutConfig = buildFactory(
      now: now,
      llmConfigRepository: MemoryLlmConfigRepository(),
    );
    await expectLater(
      withoutConfig.create(const ImportExecutionPlan()),
      throwsFactoryError(
        ImportTaskRunnerFactoryErrorCode.configurationUnavailable,
      ),
    );

    final withoutKey = buildFactory(
      now: now,
      llmConfigRepository: MemoryLlmConfigRepository(config: testLlmConfig),
    );
    await expectLater(
      withoutKey.create(const ImportExecutionPlan()),
      throwsFactoryError(
        ImportTaskRunnerFactoryErrorCode.configurationUnavailable,
      ),
    );
  });

  test('unbound managed and OCR routes return stable route errors', () async {
    final factory = buildFactory(
      now: now,
      llmConfigRepository: MemoryLlmConfigRepository(
        config: testLlmConfig,
        apiKey: 'test-placeholder',
      ),
    );

    await expectLater(
      factory.create(const ImportExecutionPlan(llm: ImportLlmRoute.managed)),
      throwsFactoryError(ImportTaskRunnerFactoryErrorCode.routeNotBound),
    );

    final managedFactory = buildFactory(
      now: now,
      llmConfigRepository: MemoryLlmConfigRepository(),
      managedLlmBuilder: (_) async => FakeImportContentProcessor(
        (content, onProgress, token) async =>
            ImportRecipeDraftResult(recipeId: 'managed-recipe'),
      ),
    );
    await expectLater(
      managedFactory.create(
        const ImportExecutionPlan(
          llm: ImportLlmRoute.managed,
          imageRecognition: ImportImageRecognitionRoute.ocr,
        ),
      ),
      throwsFactoryError(ImportTaskRunnerFactoryErrorCode.routeNotBound),
    );
  });

  test('provider builder failures are sanitized', () async {
    final factory = buildFactory(
      now: now,
      llmConfigRepository: MemoryLlmConfigRepository(),
      managedLlmBuilder: (_) async {
        throw StateError('Authorization: private-placeholder');
      },
    );

    await expectLater(
      factory.create(const ImportExecutionPlan(llm: ImportLlmRoute.managed)),
      throwsA(
        isA<ImportTaskRunnerFactoryException>()
            .having(
              (error) => error.code,
              'code',
              ImportTaskRunnerFactoryErrorCode.providerUnavailable,
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('private-placeholder')),
            ),
      ),
    );
  });
}

DeviceImportTaskRunnerFactory buildFactory({
  required DateTime now,
  required LlmConfigRepository llmConfigRepository,
  ImportLlmProcessorBuilder? managedLlmBuilder,
}) {
  return DeviceImportTaskRunnerFactory(
    importTaskRepository: MemoryImportTaskRepository(),
    recipeRepository: MemoryRecipeLibraryRepository(),
    discardRecipeDraft: discardImportRecipeDraft,
    adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
      FakeImportContentAdapter(
        platform: ImportSourcePlatform.xiaohongshu,
        handler: (source, token) async => sampleImportContent(source),
      ),
    ]),
    llmConfigRepository: llmConfigRepository,
    llmProviderFactory: FakeLlmProviderFactory(
      FakeLlmProvider((config, apiKey, request, token) async {
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      }),
    ),
    idGenerator: () => 'generated-id',
    clock: () => now,
    managedLlmBuilder: managedLlmBuilder,
  );
}

Matcher throwsFactoryError(ImportTaskRunnerFactoryErrorCode code) {
  return throwsA(
    isA<ImportTaskRunnerFactoryException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}

final LlmConnectionConfig testLlmConfig = LlmConnectionConfig(
  id: 'test-config',
  name: 'Test provider',
  providerType: LlmProviderType.openAiCompatible,
  baseUrl: 'https://example.com/v1',
  secretRef: 'test-secret-ref',
  model: 'test-model',
);

class MemoryLlmConfigRepository implements LlmConfigRepository {
  MemoryLlmConfigRepository({this.config, this.apiKey = ''});

  LlmConnectionConfig? config;
  String apiKey;

  @override
  Future<void> clearApiKey(String secretRef) async {
    apiKey = '';
  }

  @override
  Future<LlmConnectionConfig?> load() async => config;

  @override
  Future<String> readApiKey(String secretRef) async => apiKey;

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {
    this.config = config;
    if (apiKey != null) this.apiKey = apiKey;
  }
}

class FakeLlmProviderFactory extends LlmProviderFactory {
  FakeLlmProviderFactory(this.provider);

  final LlmProvider provider;
  LlmProviderType? lastType;

  @override
  LlmProvider create(LlmProviderType type) {
    lastType = type;
    return provider;
  }
}
