import '../../domain/activity/recipe_activity.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import '../../domain/recipe/recipe.dart';
import '../../domain/settings/local_app_settings.dart';
import 'recipe_library_use_cases.dart';

class RecipeDetailSnapshot {
  const RecipeDetailSnapshot({
    required this.recipe,
    required this.categories,
    this.sourceImportTask,
  });

  final Recipe recipe;
  final List<RecipeCategory> categories;
  final ImportTask? sourceImportTask;
}

class RecipeDetailLoadException implements Exception {
  const RecipeDetailLoadException();
}

class RecipeDetailUseCases {
  const RecipeDetailUseCases({
    required RecipeLibraryUseCases recipes,
    required RecipeActivityRepository activityRepository,
    required LocalAppSettingsRepository settingsRepository,
    required ImportTaskRepository importTaskRepository,
    required DateTime Function() clock,
  }) : _recipes = recipes,
       _activityRepository = activityRepository,
       _settingsRepository = settingsRepository,
       _importTaskRepository = importTaskRepository,
       _clock = clock;

  final RecipeLibraryUseCases _recipes;
  final RecipeActivityRepository _activityRepository;
  final LocalAppSettingsRepository _settingsRepository;
  final ImportTaskRepository _importTaskRepository;
  final DateTime Function() _clock;

  Future<RecipeDetailSnapshot> open(
    String recipeId, {
    bool recordView = true,
  }) async {
    final recipe = await _recipes.getRecipe(recipeId);
    try {
      final settings = await _settingsRepository.load();
      if (recordView && (settings?.recordRecipeHistory ?? true)) {
        await _activityRepository.recordRecipeView(recipe.id, _clock());
      }
      final allCategories = await _recipes.listCategories();
      final categories = allCategories
          .where((category) => recipe.categoryIds.contains(category.id))
          .toList();
      final importTasks = await _importTaskRepository.listTasks(
        includeDeleted: true,
      );
      ImportTask? sourceTask;
      for (final task in importTasks) {
        if (task.resultRecipeId == recipe.id ||
            task.normalizedUrl == recipe.sourceId) {
          sourceTask = task;
          break;
        }
      }
      return RecipeDetailSnapshot(
        recipe: recipe,
        categories: categories,
        sourceImportTask: sourceTask,
      );
    } catch (_) {
      throw const RecipeDetailLoadException();
    }
  }
}
