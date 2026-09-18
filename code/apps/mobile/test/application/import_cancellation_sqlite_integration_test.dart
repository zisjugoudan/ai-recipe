import 'dart:async';
import 'dart:io';

import 'package:ai_recipe/application/importing/import_recipe_draft_discarder.dart';
import 'package:ai_recipe/application/importing/import_task_runner.dart';
import 'package:ai_recipe/application/importing/import_task_use_cases.dart';
import 'package:ai_recipe/application/importing/llm_recipe_generation_processor.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_import_task_repository.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_recipe_generation_dependencies.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteImportTaskRepository taskRepository;
  late SqliteRecipeRepository recipeRepository;

  const taskId = 'task-cancel-race-sqlite';
  final now = DateTime.utc(2026, 8, 1, 12);
  final source = ImportSourceLink.parse(
    'https://www.xiaohongshu.com/explore/cancel-race-sqlite',
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_import_cancel_race_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'ai_recipe.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    taskRepository = SqliteImportTaskRepository(appDatabase);
    recipeRepository = SqliteRecipeRepository(appDatabase);
    await taskRepository.upsertTask(
      ImportTask.queued(id: taskId, source: source, now: now),
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  ImportTaskRunner buildRunner(FakeLlmProvider provider) {
    var nextId = 0;
    final processor = LlmRecipeGenerationProcessor(
      provider: provider,
      config: LlmConnectionConfig(
        id: 'cancel-race-config',
        name: 'Cancellation race integration',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 'test-secret-ref',
        model: 'test-model',
      ),
      apiKey: '',
      recipeRepository: recipeRepository,
      idGenerator: () => 'cancel-race-${nextId += 1}',
      clock: () => now,
    );
    final adapter = FakeImportContentAdapter(
      platform: ImportSourcePlatform.xiaohongshu,
      handler: (source, cancellationToken) async {
        return sampleImportContent(source, resolvedUrl: source.normalizedUrl);
      },
    );
    return ImportTaskRunner(
      repository: taskRepository,
      adapterRegistry: ImportContentAdapterRegistry(<ImportContentAdapter>[
        adapter,
      ]),
      processor: processor,
      discardRecipeDraft: SafeImportRecipeDraftDiscarder(recipeRepository).call,
      clock: () => now,
    );
  }

  Future<void> cancelAfterProviderStarts(
    Completer<void> providerEntered,
  ) async {
    await providerEntered.future;
    final cancelled = await CancelImportTask(
      repository: taskRepository,
      clock: () => now,
    ).call(taskId);
    expect(cancelled.status, ImportTaskStatus.cancelled);
    expect(cancelled.resultRecipeId, isNull);
  }

  Future<void> reopenDatabase() async {
    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    taskRepository = SqliteImportTaskRepository(appDatabase);
    recipeRepository = SqliteRecipeRepository(appDatabase);
  }

  test(
    'persisted cancellation wins over a late schema failure after SQLite reopen',
    () async {
      final providerEntered = Completer<void>();
      final providerRelease = Completer<void>();
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        providerEntered.complete();
        await providerRelease.future;
        return const LlmGenerationResult(text: '{"schemaVersion":1}');
      });
      final runner = buildRunner(provider);

      final runFuture = runner.run(taskId);
      await cancelAfterProviderStarts(providerEntered);
      providerRelease.complete();
      final result = await runFuture;

      expect(result.outcome, ImportTaskRunOutcome.cancelled);
      expect(result.task.status, ImportTaskStatus.cancelled);
      expect(result.task.resultRecipeId, isNull);
      expect(await recipeRepository.listRecipes(includeDeleted: true), isEmpty);

      await reopenDatabase();

      final reopenedTask = await taskRepository.getTaskById(taskId);
      expect(reopenedTask, isNotNull);
      expect(reopenedTask!.status, ImportTaskStatus.cancelled);
      expect(reopenedTask.resultRecipeId, isNull);
      expect(await recipeRepository.listRecipes(includeDeleted: true), isEmpty);
    },
  );

  test(
    'persisted cancellation removes a late generated draft after SQLite reopen',
    () async {
      final providerEntered = Completer<void>();
      final providerRelease = Completer<void>();
      final provider = FakeLlmProvider((config, apiKey, request, token) async {
        providerEntered.complete();
        await providerRelease.future;
        return const LlmGenerationResult(text: validRecipeGenerationJson);
      });
      final runner = buildRunner(provider);

      final runFuture = runner.run(taskId);
      await cancelAfterProviderStarts(providerEntered);
      providerRelease.complete();
      final result = await runFuture;

      expect(result.outcome, ImportTaskRunOutcome.cancelled);
      expect(result.task.status, ImportTaskStatus.cancelled);
      expect(result.task.resultRecipeId, isNull);
      expect(
        await recipeRepository.getRecipeById(
          'cancel-race-1',
          includeDeleted: true,
        ),
        isNull,
      );
      expect(await recipeRepository.listRecipes(includeDeleted: true), isEmpty);

      await reopenDatabase();

      final reopenedTask = await taskRepository.getTaskById(taskId);
      expect(reopenedTask, isNotNull);
      expect(reopenedTask!.status, ImportTaskStatus.cancelled);
      expect(reopenedTask.resultRecipeId, isNull);
      expect(
        await recipeRepository.getRecipeById(
          'cancel-race-1',
          includeDeleted: true,
        ),
        isNull,
      );
      expect(await recipeRepository.listRecipes(includeDeleted: true), isEmpty);
    },
  );
}
