import 'package:ai_recipe/application/home/home_use_cases.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/application/recipe/recipe_library_use_cases.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_import_dependencies.dart';
import '../support/fake_local_business_repositories.dart';
import '../support/fake_recipe_library_repository.dart';

void main() {
  late MemoryRecipeLibraryRepository recipeRepository;
  late MemoryRecipeActivityRepository activityRepository;
  late MemoryImportTaskRepository importRepository;
  late RecipeLibraryUseCases recipes;
  late HomeUseCases useCases;
  late DateTime now;
  late int idSequence;

  RecipeDraftInput recipeInput({
    required String title,
    bool favorite = false,
    List<String> categoryIds = const <String>[],
  }) => RecipeDraftInput(
    title: title,
    favorite: favorite,
    status: RecipeStatus.published,
    categoryIds: categoryIds,
    ingredients: <RecipeIngredientInput>[
      RecipeIngredientInput(name: '食材-$title'),
    ],
    steps: <RecipeStepInput>[RecipeStepInput(description: '制作-$title')],
  );

  setUp(() {
    recipeRepository = MemoryRecipeLibraryRepository();
    activityRepository = MemoryRecipeActivityRepository();
    importRepository = MemoryImportTaskRepository();
    now = DateTime.utc(2026, 7, 30, 8);
    idSequence = 1;
    recipes = RecipeLibraryUseCases(
      recipeRepository: recipeRepository,
      categoryRepository: recipeRepository,
      idGenerator: () => 'id-${idSequence++}',
      clock: () => now,
    );
    useCases = HomeUseCases(
      recipes: recipes,
      activityRepository: activityRepository,
      importTaskRepository: importRepository,
    );
  });

  test(
    'aggregates recent recipes, categories, favorites and unfinished imports',
    () async {
      final breakfast = await recipes.createCategory(
        const RecipeCategoryInput(name: '早餐', sortOrder: 2),
      );
      final quick = await recipes.createCategory(
        const RecipeCategoryInput(name: '快手菜', sortOrder: 1),
      );
      final congee = await recipes.createRecipe(
        recipeInput(
          title: '白粥',
          favorite: true,
          categoryIds: <String>[breakfast.id],
        ),
      );
      now = now.add(const Duration(minutes: 1));
      final eggs = await recipes.createRecipe(
        recipeInput(
          title: '煎蛋',
          favorite: true,
          categoryIds: <String>[breakfast.id, quick.id],
        ),
      );
      now = now.add(const Duration(minutes: 1));
      final salad = await recipes.createRecipe(
        recipeInput(title: '沙拉', categoryIds: <String>[quick.id]),
      );
      await activityRepository.recordRecipeView(congee.id, now);
      await activityRepository.recordRecipeView(
        eggs.id,
        now.add(const Duration(minutes: 2)),
      );
      await activityRepository.recordRecipeView(
        salad.id,
        now.add(const Duration(minutes: 1)),
      );

      final queued = ImportTask.queued(
        id: 'task-queued',
        source: ImportSourceLink.parse('https://v.douyin.com/queued/'),
        now: now,
      );
      final failed =
          ImportTask.queued(
            id: 'task-failed',
            source: ImportSourceLink.parse(
              'https://www.xiaohongshu.com/explore/failed',
            ),
            now: now,
          ).fail(
            code: ImportTaskErrorCode.networkUnavailable,
            canRetry: true,
            now: now.add(const Duration(minutes: 1)),
          );
      final completed =
          ImportTask.queued(
                id: 'task-completed',
                source: ImportSourceLink.parse(
                  'https://v.douyin.com/completed/',
                ),
                now: now,
              )
              .start(now.add(const Duration(seconds: 1)))
              .advance(
                nextStage: ImportTaskStage.generating,
                nextProgress: 0.9,
                now: now.add(const Duration(seconds: 2)),
              )
              .markNeedsReview(
                recipeId: eggs.id,
                now: now.add(const Duration(seconds: 3)),
              )
              .complete(now.add(const Duration(seconds: 4)));
      importRepository.tasks
        ..[queued.id] = queued
        ..[failed.id] = failed
        ..[completed.id] = completed;

      final snapshot = await useCases.load(recentLimit: 2, favoriteLimit: 1);

      expect(snapshot.recentRecipes.map((recipe) => recipe.title), <String>[
        '煎蛋',
        '沙拉',
      ]);
      expect(snapshot.categories.map((item) => item.category.name), <String>[
        '快手菜',
        '早餐',
      ]);
      expect(snapshot.categories.map((item) => item.recipeCount), <int>[2, 2]);
      expect(snapshot.favoriteRecipes.map((recipe) => recipe.title), <String>[
        '煎蛋',
      ]);
      expect(
        snapshot.unfinishedImportTasks.map((task) => task.id),
        containsAll(<String>['task-queued', 'task-failed']),
      );
      expect(
        snapshot.unfinishedImportTasks.map((task) => task.id),
        isNot(contains('task-completed')),
      );
    },
  );

  test(
    'does not return a recently viewed recipe after it is deleted',
    () async {
      final recipe = await recipes.createRecipe(recipeInput(title: '待删除'));
      await activityRepository.recordRecipeView(recipe.id, now);
      await recipes.softDeleteRecipe(recipe.id);

      final snapshot = await useCases.load();

      expect(snapshot.recentRecipes, isEmpty);
    },
  );

  test('rejects negative limits without touching repositories', () async {
    await expectLater(
      useCases.load(recentLimit: -1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('maps repository failures to HomeLoadException', () async {
    activityRepository.error = StateError('database detail');

    await expectLater(useCases.load(), throwsA(isA<HomeLoadException>()));
  });
}
