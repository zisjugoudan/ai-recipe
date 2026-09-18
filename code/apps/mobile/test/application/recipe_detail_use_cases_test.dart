import 'package:ai_recipe/application/recipe/recipe_detail_use_cases.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/settings/local_app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_local_business_repositories.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
  late MemoryRecipeLibraryRepository recipeRepository;
  late MemoryRecipeActivityRepository activityRepository;
  late MemoryLocalAppSettingsRepository settingsRepository;
  late MemoryImportTaskRepository importRepository;
  late RecipeLibraryUseCases recipes;
  late RecipeDetailUseCases useCases;
  late DateTime now;
  late int idSequence;

  setUp(() {
    recipeRepository = MemoryRecipeLibraryRepository();
    activityRepository = MemoryRecipeActivityRepository();
    settingsRepository = MemoryLocalAppSettingsRepository();
    importRepository = MemoryImportTaskRepository();
    now = DateTime.utc(2026, 7, 30, 10);
    idSequence = 1;
    recipes = RecipeLibraryUseCases(
      recipeRepository: recipeRepository,
      categoryRepository: recipeRepository,
      idGenerator: () => 'id-${idSequence++}',
      clock: () => now,
    );
    useCases = RecipeDetailUseCases(
      recipes: recipes,
      activityRepository: activityRepository,
      settingsRepository: settingsRepository,
      importTaskRepository: importRepository,
      clock: () => now,
    );
  });

  Future<Recipe> createRecipe({String? sourceId}) async {
    final category = await recipes.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    return recipes.createRecipe(
      RecipeDraftInput(
        title: '番茄炒蛋',
        status: RecipeStatus.published,
        categoryIds: <String>[category.id],
        ingredients: <RecipeIngredientInput>[RecipeIngredientInput(name: '番茄')],
        steps: const <RecipeStepInput>[RecipeStepInput(description: '翻炒')],
      ),
      sourceId: sourceId,
    );
  }

  test(
    'opens aggregate, records history and returns source import task',
    () async {
      final recipe = await createRecipe();
      final task =
          ImportTask.queued(
                id: 'task-1',
                source: ImportSourceLink.parse('https://v.douyin.com/recipe/'),
                now: now,
              )
              .start(now.add(const Duration(seconds: 1)))
              .advance(
                nextStage: ImportTaskStage.generating,
                nextProgress: 0.9,
                now: now.add(const Duration(seconds: 2)),
              )
              .markNeedsReview(
                recipeId: recipe.id,
                now: now.add(const Duration(seconds: 3)),
              );
      importRepository.tasks[task.id] = task;

      final snapshot = await useCases.open(recipe.id);

      expect(snapshot.recipe.id, recipe.id);
      expect(snapshot.categories.map((category) => category.name), <String>[
        '家常菜',
      ]);
      expect(snapshot.sourceImportTask?.id, task.id);
      expect(activityRepository.views[recipe.id]?.viewedAt, now);
    },
  );

  test('matches source task by normalized source URL', () async {
    final sourceUrl = ImportSourceLink.parse(
      'https://www.xiaohongshu.com/explore/recipe?xsec_token=removed',
    ).normalizedUrl;
    final recipe = await createRecipe(sourceId: sourceUrl);
    final task = ImportTask.queued(
      id: 'task-source',
      source: ImportSourceLink.parse(sourceUrl),
      now: now,
    );
    importRepository.tasks[task.id] = task;

    final snapshot = await useCases.open(recipe.id, recordView: false);

    expect(snapshot.sourceImportTask?.id, task.id);
  });

  test('does not record when history is disabled', () async {
    final recipe = await createRecipe();
    settingsRepository.settings = LocalAppSettings(
      recordRecipeHistory: false,
      updatedAt: now,
    );

    await useCases.open(recipe.id);

    expect(activityRepository.views, isEmpty);
  });

  test('recordView false overrides the enabled setting', () async {
    final recipe = await createRecipe();
    settingsRepository.settings = LocalAppSettings(updatedAt: now);

    await useCases.open(recipe.id, recordView: false);

    expect(activityRepository.views, isEmpty);
  });

  test(
    'maps aggregate repository errors to RecipeDetailLoadException',
    () async {
      final recipe = await createRecipe();
      settingsRepository.loadError = StateError('private database detail');

      await expectLater(
        useCases.open(recipe.id),
        throwsA(isA<RecipeDetailLoadException>()),
      );
    },
  );
}
