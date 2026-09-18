import 'dart:io';

import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteRecipeRepository repository;
  late RecipeLibraryUseCases useCases;
  late DateTime now;
  late int idSequence;

  String nextId() => 'sqlite-${idSequence++}';

  RecipeLibraryUseCases buildUseCases() {
    return RecipeLibraryUseCases(
      recipeRepository: repository,
      categoryRepository: repository,
      idGenerator: nextId,
      clock: () => now,
    );
  }

  RecipeDraftInput draft({
    required String title,
    bool favorite = false,
    RecipeStatus status = RecipeStatus.draft,
    List<String> categoryIds = const <String>[],
    List<String> tags = const <String>[],
    String ingredient = '鸡蛋',
  }) {
    return RecipeDraftInput(
      title: title,
      description: '适合工作日晚餐',
      notes: '少油，出锅前再调味',
      favorite: favorite,
      status: status,
      categoryIds: categoryIds,
      tags: tags,
      ingredients: <RecipeIngredientInput>[
        RecipeIngredientInput(
          name: ingredient,
          quantity: '2',
          unit: '个',
          groupName: '主料',
          preparation: '打散',
          substitutes: const <String>['嫩豆腐'],
        ),
      ],
      steps: const <RecipeStepInput>[
        RecipeStepInput(
          description: '中火翻炒至凝固',
          durationSeconds: 180,
          heatLevel: '中火',
          cookware: '炒锅',
        ),
      ],
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_library_application_',
    );
    databasePath = path.join(temporaryDirectory.path, 'recipes.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);
    now = DateTime.utc(2026, 7, 28, 9);
    idSequence = 1;
    useCases = buildUseCases();
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('guest aggregate survives a real SQLite close and reopen', () async {
    final category = await useCases.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    final created = await useCases.createRecipe(
      draft(
        title: '番茄炒蛋',
        favorite: true,
        status: RecipeStatus.published,
        categoryIds: <String>[category.id],
        tags: const <String>[' quick ', 'dinner', 'quick'],
      ),
    );

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);
    useCases = buildUseCases();

    final loaded = await useCases.getRecipe(created.id);
    final loadedCategory = await useCases.getCategory(category.id);

    expect(loaded.userId, isNull);
    expect(loaded.title, '番茄炒蛋');
    expect(loaded.favorite, isTrue);
    expect(loaded.status, RecipeStatus.published);
    expect(loaded.ingredients.single.name, '鸡蛋');
    expect(loaded.ingredients.single.substitutes, <String>['嫩豆腐']);
    expect(loaded.steps.single.description, '中火翻炒至凝固');
    expect(loaded.categoryIds, <String>[category.id]);
    expect(loaded.tags, <String>['quick', 'dinner']);
    expect(
      (await useCases.listRecipes(tag: 'QUICK')).map((item) => item.id),
      <String>[created.id],
    );
    expect(loadedCategory.userId, isNull);
    expect(loadedCategory.name, '家常菜');
  });

  test('real SQLite supports application filters and recycle bins', () async {
    final category = await useCases.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    final published = await useCases.createRecipe(
      draft(
        title: '番茄汤',
        favorite: true,
        status: RecipeStatus.published,
        categoryIds: <String>[category.id],
        ingredient: '番茄',
      ),
    );
    now = now.add(const Duration(minutes: 1));
    final draftRecipe = await useCases.createRecipe(
      draft(title: '米饭', ingredient: '大米'),
    );

    expect(
      (await useCases.listRecipes(query: '番茄')).map((item) => item.id),
      <String>[published.id],
    );
    expect(
      (await useCases.listRecipes(
        favorite: true,
        status: RecipeStatus.published,
        categoryId: category.id,
      )).map((item) => item.id),
      <String>[published.id],
    );

    await useCases.softDeleteRecipe(draftRecipe.id);
    expect(
      (await useCases.listRecipes(
        deletionFilter: RecipeLibraryDeletionFilter.deletedOnly,
      )).map((item) => item.id),
      <String>[draftRecipe.id],
    );
    await useCases.restoreRecipe(draftRecipe.id);
    expect(await useCases.listRecipes(), hasLength(2));

    await useCases.softDeleteCategory(category.id);
    expect((await useCases.getRecipe(published.id)).categoryIds, isEmpty);
    await useCases.restoreCategory(category.id);
    expect((await useCases.getRecipe(published.id)).categoryIds, isEmpty);
    await useCases.softDeleteCategory(category.id);
    await useCases.permanentlyDeleteCategory(category.id);
    await expectLater(
      useCases.getCategory(category.id, includeDeleted: true),
      throwsA(isA<RecipeCategoryNotFoundException>()),
    );
  });
}
