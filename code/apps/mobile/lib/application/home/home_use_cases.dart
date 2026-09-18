import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import '../../domain/recipe/recipe.dart';
import '../recipe/recipe_library_use_cases.dart';
import '../../domain/activity/recipe_activity.dart';

class CategorySummary {
  const CategorySummary({required this.category, required this.recipeCount});

  final RecipeCategory category;
  final int recipeCount;
}

class HomeSnapshot {
  const HomeSnapshot({
    required this.recentRecipes,
    required this.categories,
    required this.favoriteRecipes,
    required this.unfinishedImportTasks,
  });

  /// 最近浏览的菜谱摘要（解决方案.md：首页也只读卡片所需字段）。
  final List<RecipeSummary> recentRecipes;
  final List<CategorySummary> categories;

  /// 收藏菜谱摘要（首页卡片展示）。
  final List<RecipeSummary> favoriteRecipes;
  final List<ImportTask> unfinishedImportTasks;
}

class HomeLoadException implements Exception {
  const HomeLoadException();
}

class HomeUseCases {
  const HomeUseCases({
    required RecipeLibraryUseCases recipes,
    required RecipeActivityRepository activityRepository,
    required ImportTaskRepository importTaskRepository,
  }) : _recipes = recipes,
       _activityRepository = activityRepository,
       _importTaskRepository = importTaskRepository;

  final RecipeLibraryUseCases _recipes;
  final RecipeActivityRepository _activityRepository;
  final ImportTaskRepository _importTaskRepository;

  Future<HomeSnapshot> load({
    int recentLimit = 10,
    int favoriteLimit = 10,
  }) async {
    if (recentLimit < 0 || favoriteLimit < 0) {
      throw ArgumentError('Home limits must not be negative.');
    }
    try {
      // 不再全量读取完整菜谱聚合（原先约 5001 次 SQL），改为：
      // 最近浏览按 id 批量取摘要、分类计数一次 SQL、收藏摘要一次 SQL。
      final recentViews = await _activityRepository.listRecentViews(
        limit: recentLimit,
      );
      final recentIds = recentViews.map((view) => view.recipeId).toList();
      final recentById = <String, RecipeSummary>{
        for (final summary in await _recipes.getRecipeSummariesByIds(
          recentIds,
        ))
          summary.id: summary,
      };
      final recent = <RecipeSummary>[
        for (final view in recentViews)
          if (recentById.containsKey(view.recipeId)) recentById[view.recipeId]!,
      ];
      final categories = await _recipes.listCategories();
      final counts = await _recipes.countRecipesByCategory();
      final summaries =
          categories
              .map(
                (category) => CategorySummary(
                  category: category,
                  recipeCount: counts[category.id] ?? 0,
                ),
              )
              .toList()
            ..sort((left, right) {
              final byCount = right.recipeCount.compareTo(left.recipeCount);
              if (byCount != 0) return byCount;
              return left.category.sortOrder.compareTo(
                right.category.sortOrder,
              );
            });
      final favorites = await _recipes.listRecipeSummaries(
        favorite: true,
        limit: favoriteLimit,
      );
      final unfinished = await _importTaskRepository.listTasks(
        statuses: <ImportTaskStatus>{
          ImportTaskStatus.queued,
          ImportTaskStatus.running,
          ImportTaskStatus.needsReview,
          ImportTaskStatus.failed,
        },
      );
      return HomeSnapshot(
        recentRecipes: recent,
        categories: summaries,
        favoriteRecipes: favorites.items,
        unfinishedImportTasks: unfinished,
      );
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw const HomeLoadException();
    }
  }
}
