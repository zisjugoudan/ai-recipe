import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_activity_repository.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteRecipeRepository recipes;
  late SqliteRecipeActivityRepository activity;
  final baseTime = DateTime.utc(2026, 7, 30, 8);

  Recipe recipe(String id) => Recipe(
    id: id,
    title: 'Recipe $id',
    createdAt: baseTime,
    updatedAt: baseTime,
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_activity_',
    );
    databasePath = path.join(temporaryDirectory.path, 'activity.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    recipes = SqliteRecipeRepository(appDatabase);
    activity = SqliteRecipeActivityRepository(appDatabase);
    await recipes.upsertRecipe(recipe('recipe-a'));
    await recipes.upsertRecipe(recipe('recipe-b'));
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('records latest view once per recipe and orders by time', () async {
    await activity.recordRecipeView('recipe-a', baseTime);
    await activity.recordRecipeView(
      'recipe-b',
      baseTime.add(const Duration(minutes: 1)),
    );
    await activity.recordRecipeView(
      'recipe-a',
      baseTime.add(const Duration(minutes: 2)),
    );

    final recent = await activity.listRecentViews();
    expect(recent.map((item) => item.recipeId), <String>[
      'recipe-a',
      'recipe-b',
    ]);
    expect(recent.first.viewedAt, baseTime.add(const Duration(minutes: 2)));
    expect(
      (await activity.listRecentViews(limit: 1)).single.recipeId,
      'recipe-a',
    );
  });

  test('clears history and cascades when a recipe is deleted', () async {
    await activity.recordRecipeView('recipe-a', baseTime);
    await activity.recordRecipeView('recipe-b', baseTime);

    await recipes.permanentlyDeleteRecipe('recipe-a');
    expect(
      (await activity.listRecentViews()).map((item) => item.recipeId),
      <String>['recipe-b'],
    );

    await activity.clearRecipeHistory();
    expect(await activity.listRecentViews(), isEmpty);
  });
}
