import 'dart:io';

import 'package:ai_recipe/app/ai_recipe_backend_composition_root.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/data/llm_config_repository.dart';
import 'package:ai_recipe/domain/access/app_capability.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fake_app_access_dependencies.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'composition root owns an injected database and preserves data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-recipe-backend-root-',
      );
      final databasePath = path.join(directory.path, 'backend.db');
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final root = AiRecipeBackendCompositionRoot.device(
        database: database,
        sessionRepository: FakeAppSessionRepository(),
        llmConfigRepository: MemoryLlmConfigRepository(),
        capabilityRuntimeRepository: FakeAppCapabilityRuntimeRepository(
          runtime: AppCapabilityRuntime(),
        ),
        idGenerator: () => 'persistent-recipe',
        clock: () => DateTime.utc(2026, 7, 28, 23),
      );

      AppDatabase? reopened;
      try {
        final created = await root.backend.recipes.createRecipe(
          RecipeDraftInput(title: '持久化菜谱'),
        );
        expect(created.id, 'persistent-recipe');

        await root.close();
        await root.close();

        reopened = AppDatabase(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        final saved = await SqliteRecipeRepository(
          reopened,
        ).getRecipeById(created.id);
        expect(saved, isNotNull);
        expect(saved!.title, '持久化菜谱');
      } finally {
        await root.close();
        await reopened?.close();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
}

class MemoryLlmConfigRepository implements LlmConfigRepository {
  @override
  Future<void> clearApiKey(String secretRef) async {}

  @override
  Future<LlmConnectionConfig?> load() async => null;

  @override
  Future<String> readApiKey(String secretRef) async => '';

  @override
  Future<void> save(LlmConnectionConfig config, {String? apiKey}) async {}
}
