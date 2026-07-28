import 'dart:io';

import 'package:ai_recipe/application/importing/llm_recipe_generation_processor.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_recipe_generation_dependencies.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteRecipeRepository repository;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_generation_sqlite_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'recipes.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('generated draft survives a real SQLite close and reopen', () async {
    final now = DateTime.utc(2026, 7, 28, 19);
    final provider = FakeLlmProvider((config, apiKey, request, token) async {
      return const LlmGenerationResult(text: validRecipeGenerationJson);
    });
    var nextId = 0;
    final processor = LlmRecipeGenerationProcessor(
      provider: provider,
      config: LlmConnectionConfig(
        id: 'sqlite-config',
        name: 'SQLite integration',
        providerType: LlmProviderType.openAiCompatible,
        baseUrl: 'https://example.com/v1',
        secretRef: 'secret-ref',
        model: 'test-model',
      ),
      apiKey: '',
      recipeRepository: repository,
      idGenerator: () => 'sqlite-${nextId += 1}',
      clock: () => now,
    );
    final source = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/sqlite-integration',
    );
    final content = ImportContent(
      source: source,
      resolvedUrl: source.normalizedUrl,
      contentType: ImportContentType.article,
      title: 'Tomato and eggs source',
      description: 'A quick recipe for two',
      capturedAt: now,
      textFragments: <ImportTextFragment>[
        ImportTextFragment(
          kind: ImportTextFragmentKind.body,
          text: 'Use two tomatoes and three eggs, then stir-fry.',
          order: 0,
        ),
      ],
    );

    final result = await processor.process(
      content,
      onProgress: (stage, progress) async {},
    );

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);
    final loaded = await repository.getRecipeById(result.recipeId);

    expect(loaded, isNotNull);
    expect(loaded!.id, 'sqlite-1');
    expect(loaded.title, '\u756a\u8304\u7092\u86cb');
    expect(loaded.status.name, 'draft');
    expect(loaded.sourceId, source.normalizedUrl);
    expect(loaded.ingredients.single.id, 'sqlite-2');
    expect(loaded.ingredients.single.name, '\u756a\u8304');
    expect(loaded.steps.single.id, 'sqlite-3');
    expect(loaded.steps.single.stepNumber, 1);
    expect(loaded.createdAt, now);
  });
}
