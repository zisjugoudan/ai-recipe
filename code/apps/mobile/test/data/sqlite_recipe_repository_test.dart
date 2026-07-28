import 'dart:io';

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

  final createdAt = DateTime.utc(2026, 7, 28, 8);

  RecipeCategory category({
    String id = 'category-home',
    String name = '家常菜',
    int sortOrder = 0,
  }) {
    return RecipeCategory(
      id: id,
      name: name,
      sortOrder: sortOrder,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
  }

  Recipe recipe({
    String id = 'recipe-tomato-eggs',
    String title = '番茄炒蛋',
    bool favorite = true,
    RecipeStatus status = RecipeStatus.published,
    List<String> categoryIds = const <String>['category-home'],
    int localVersion = 1,
    DateTime? updatedAt,
    List<Ingredient>? ingredients,
    List<RecipeStep>? steps,
  }) {
    return Recipe(
      id: id,
      title: title,
      description: '十分钟家常菜',
      servings: 2,
      prepTimeMinutes: 3,
      cookTimeMinutes: 7,
      totalTimeMinutes: 10,
      difficulty: RecipeDifficulty.easy,
      notes: '番茄先炒出汁',
      favorite: favorite,
      status: status,
      ingredients:
          ingredients ??
          <Ingredient>[
            Ingredient(
              id: 'ingredient-tomato',
              groupName: '主料',
              name: '番茄',
              quantity: '2',
              unit: '个',
              preparation: '切块',
              substitutes: const <String>['圣女果'],
              sortOrder: 0,
              confidence: 0.96,
            ),
            Ingredient(
              id: 'ingredient-egg',
              groupName: '主料',
              name: '鸡蛋',
              quantity: '3',
              unit: '个',
              sortOrder: 1,
            ),
          ],
      steps:
          steps ??
          <RecipeStep>[
            RecipeStep(
              id: 'step-1',
              stepNumber: 1,
              description: '鸡蛋炒至凝固后盛出',
              durationSeconds: 90,
              heatLevel: '中火',
              cookware: '炒锅',
              confidence: 0.92,
            ),
            RecipeStep(
              id: 'step-2',
              stepNumber: 2,
              description: '番茄炒出汁后倒回鸡蛋',
              durationSeconds: 180,
              heatLevel: '中火',
              tips: '不要把番茄汁收得太干',
            ),
          ],
      categoryIds: categoryIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? createdAt,
      localVersion: localVersion,
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_sqlite_test_',
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

  test('persists and reloads a structured recipe after reopening', () async {
    await repository.upsertCategory(category());
    await repository.upsertRecipe(recipe());

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteRecipeRepository(appDatabase);

    final loaded = await repository.getRecipeById('recipe-tomato-eggs');

    expect(loaded, isNotNull);
    expect(loaded!.title, '番茄炒蛋');
    expect(loaded.difficulty, RecipeDifficulty.easy);
    expect(loaded.status, RecipeStatus.published);
    expect(loaded.favorite, isTrue);
    expect(loaded.categoryIds, <String>['category-home']);
    expect(loaded.ingredients, hasLength(2));
    expect(loaded.ingredients.first.name, '番茄');
    expect(loaded.ingredients.first.substitutes, <String>['圣女果']);
    expect(loaded.ingredients.first.confidence, 0.96);
    expect(loaded.steps, hasLength(2));
    expect(loaded.steps.last.stepNumber, 2);
    expect(loaded.steps.last.tips, '不要把番茄汁收得太干');
    expect(loaded.createdAt, createdAt);
  });

  test('updates the aggregate and replaces children transactionally', () async {
    await repository.upsertCategory(category());
    await repository.upsertRecipe(recipe());

    final updatedAt = createdAt.add(const Duration(hours: 1));
    await repository.upsertRecipe(
      recipe(
        title: '番茄鸡蛋',
        favorite: false,
        localVersion: 2,
        updatedAt: updatedAt,
        ingredients: <Ingredient>[
          Ingredient(
            id: 'ingredient-egg',
            name: '鸡蛋',
            quantity: '4',
            unit: '个',
            sortOrder: 0,
          ),
        ],
        steps: <RecipeStep>[
          RecipeStep(id: 'step-new', stepNumber: 1, description: '全部食材快速翻炒均匀'),
        ],
      ),
    );

    final loaded = await repository.getRecipeById('recipe-tomato-eggs');

    expect(loaded!.title, '番茄鸡蛋');
    expect(loaded.favorite, isFalse);
    expect(loaded.localVersion, 2);
    expect(loaded.updatedAt, updatedAt);
    expect(loaded.ingredients, hasLength(1));
    expect(loaded.ingredients.single.quantity, '4');
    expect(loaded.steps, hasLength(1));
    expect(loaded.steps.single.id, 'step-new');
  });

  test('rolls back a recipe when a category relation is invalid', () async {
    await expectLater(
      repository.upsertRecipe(
        recipe(categoryIds: const <String>['missing-category']),
      ),
      throwsA(isA<DatabaseException>()),
    );

    expect(await repository.getRecipeById('recipe-tomato-eggs'), isNull);
  });

  test('lists by ingredient search and favorite state', () async {
    await repository.upsertCategory(category());
    await repository.upsertRecipe(recipe());
    await repository.upsertRecipe(
      recipe(
        id: 'recipe-porridge',
        title: '白粥',
        favorite: false,
        categoryIds: const <String>[],
        ingredients: <Ingredient>[
          Ingredient(id: 'ingredient-rice', name: '大米', sortOrder: 0),
        ],
        steps: <RecipeStep>[
          RecipeStep(id: 'step-porridge', stepNumber: 1, description: '小火煮至软烂'),
        ],
      ),
    );

    final tomatoResults = await repository.listRecipes(query: '鸡蛋');
    final favoriteResults = await repository.listRecipes(favorite: true);

    expect(tomatoResults.map((item) => item.id), <String>[
      'recipe-tomato-eggs',
    ]);
    expect(favoriteResults.map((item) => item.id), <String>[
      'recipe-tomato-eggs',
    ]);
  });

  test('soft deletes, restores and permanently deletes a recipe', () async {
    await repository.upsertCategory(category());
    await repository.upsertRecipe(recipe());
    final deletedAt = createdAt.add(const Duration(hours: 2));

    await repository.softDeleteRecipe('recipe-tomato-eggs', deletedAt);

    expect(await repository.getRecipeById('recipe-tomato-eggs'), isNull);
    final deleted = await repository.getRecipeById(
      'recipe-tomato-eggs',
      includeDeleted: true,
    );
    expect(deleted!.deletedAt, deletedAt);
    expect(deleted.localVersion, 2);

    final restoredAt = deletedAt.add(const Duration(minutes: 5));
    await repository.restoreRecipe('recipe-tomato-eggs', restoredAt);
    final restored = await repository.getRecipeById('recipe-tomato-eggs');
    expect(restored!.deletedAt, isNull);
    expect(restored.localVersion, 3);

    await repository.permanentlyDeleteRecipe('recipe-tomato-eggs');
    expect(
      await repository.getRecipeById(
        'recipe-tomato-eggs',
        includeDeleted: true,
      ),
      isNull,
    );
  });

  test('orders categories and removes deleted category relations', () async {
    await repository.upsertCategory(
      category(id: 'category-breakfast', name: '早餐', sortOrder: 1),
    );
    await repository.upsertCategory(category());
    await repository.upsertRecipe(
      recipe(
        categoryIds: const <String>['category-breakfast', 'category-home'],
      ),
    );

    final categories = await repository.listCategories();
    expect(categories.map((item) => item.id), <String>[
      'category-home',
      'category-breakfast',
    ]);

    final deletedAt = createdAt.add(const Duration(hours: 3));
    await repository.softDeleteCategory('category-home', deletedAt);

    final loaded = await repository.getRecipeById('recipe-tomato-eggs');
    expect(loaded!.categoryIds, <String>['category-breakfast']);
    expect(await repository.listCategories(), hasLength(1));
    expect(await repository.listCategories(includeDeleted: true), hasLength(2));
  });
  test('lists recipes by status and active category relation', () async {
    await repository.upsertCategory(category());
    await repository.upsertCategory(
      category(id: 'category-breakfast', name: '早餐', sortOrder: 1),
    );
    await repository.upsertRecipe(recipe());
    await repository.upsertRecipe(
      recipe(
        id: 'recipe-porridge',
        title: '白粥',
        favorite: false,
        status: RecipeStatus.draft,
        categoryIds: const <String>['category-breakfast'],
        ingredients: <Ingredient>[
          Ingredient(id: 'ingredient-rice', name: '大米', sortOrder: 0),
        ],
        steps: <RecipeStep>[
          RecipeStep(id: 'step-porridge', stepNumber: 1, description: '小火煮至软烂'),
        ],
      ),
    );

    expect(
      (await repository.listRecipes(
        status: RecipeStatus.draft,
      )).map((item) => item.id),
      <String>['recipe-porridge'],
    );
    expect(
      (await repository.listRecipes(
        categoryId: 'category-home',
      )).map((item) => item.id),
      <String>['recipe-tomato-eggs'],
    );

    await repository.softDeleteCategory(
      'category-home',
      createdAt.add(const Duration(hours: 1)),
    );
    expect(await repository.listRecipes(categoryId: 'category-home'), isEmpty);
  });

  test('gets, restores and permanently deletes a category', () async {
    await repository.upsertCategory(category());

    final active = await repository.getCategoryById('category-home');
    expect(active, isNotNull);
    expect(active!.name, '家常菜');

    final deletedAt = createdAt.add(const Duration(hours: 2));
    await repository.softDeleteCategory('category-home', deletedAt);
    expect(await repository.getCategoryById('category-home'), isNull);
    final deleted = await repository.getCategoryById(
      'category-home',
      includeDeleted: true,
    );
    expect(deleted!.deletedAt, deletedAt);
    expect(deleted.localVersion, 2);

    final restoredAt = deletedAt.add(const Duration(minutes: 5));
    await repository.restoreCategory('category-home', restoredAt);
    final restored = await repository.getCategoryById('category-home');
    expect(restored!.deletedAt, isNull);
    expect(restored.updatedAt, restoredAt);
    expect(restored.localVersion, 3);

    await repository.softDeleteCategory('category-home', deletedAt);
    await repository.permanentlyDeleteCategory('category-home');
    expect(
      await repository.getCategoryById('category-home', includeDeleted: true),
      isNull,
    );
  });
}
