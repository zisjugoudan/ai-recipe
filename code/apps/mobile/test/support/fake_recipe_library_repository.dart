import 'dart:math' as math;

import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_repository.dart';

class MemoryRecipeLibraryRepository
    implements RecipeRepository, RecipeCategoryRepository {
  final Map<String, Recipe> recipes = <String, Recipe>{};
  final Map<String, RecipeCategory> categories = <String, RecipeCategory>{};
  Object? error;

  void _throwIfNeeded() {
    if (error != null) throw error!;
  }

  @override
  Future<void> upsertRecipe(Recipe recipe) async {
    _throwIfNeeded();
    recipes[recipe.id] = recipe;
  }

  @override
  Future<Recipe?> getRecipeById(
    String id, {
    bool includeDeleted = false,
  }) async {
    _throwIfNeeded();
    final recipe = recipes[id];
    if (recipe == null || (!includeDeleted && recipe.deletedAt != null)) {
      return null;
    }
    return recipe;
  }

  @override
  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
  }) async {
    final result = _matchingRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      includeDeleted: includeDeleted,
    );
    result.sort((left, right) {
      final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
      return byUpdatedAt != 0 ? byUpdatedAt : left.id.compareTo(right.id);
    });
    return result;
  }

  @override
  Future<RecipeSummaryPage> listRecipeSummaries({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
    RecipeSort sort = RecipeSort.updated,
    int limit = 40,
    RecipeCursor? after,
  }) async {
    final result = _matchingRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      includeDeleted: includeDeleted,
    );
    result.sort((left, right) {
      switch (sort) {
        case RecipeSort.updated:
          final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
          return byUpdatedAt != 0
              ? byUpdatedAt
              : right.id.compareTo(left.id);
        case RecipeSort.created:
          final byCreatedAt = right.createdAt.compareTo(left.createdAt);
          return byCreatedAt != 0
              ? byCreatedAt
              : right.id.compareTo(left.id);
        case RecipeSort.title:
          final byTitle = left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          );
          return byTitle != 0 ? byTitle : left.id.compareTo(right.id);
      }
    });
    final start = after == null
        ? 0
        : result.indexWhere((recipe) => recipe.id == after.id) + 1;
    final page = start >= 0 && start <= result.length
        ? result.sublist(
            start,
            math.min(start + limit, result.length),
          )
        : <Recipe>[];
    final hasMore = start + limit < result.length;
    final items = page
        .map(
          (recipe) => RecipeSummary(
            id: recipe.id,
            title: recipe.title,
            coverImage: recipe.coverImage,
            favorite: recipe.favorite,
            totalTimeMinutes: recipe.totalTimeMinutes,
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            servings: recipe.servings,
            difficulty: recipe.difficulty,
            sourceId: recipe.sourceId,
            ingredientCount: recipe.ingredients.length,
            tags: recipe.tags,
            updatedAt: recipe.updatedAt,
            status: recipe.status,
          ),
        )
        .toList(growable: false);
    RecipeCursor? nextCursor;
    if (hasMore && items.isNotEmpty) {
      final last = items.last;
      nextCursor = switch (sort) {
        RecipeSort.title => RecipeCursor(title: last.title, id: last.id),
        _ => RecipeCursor(timestamp: last.updatedAt, id: last.id),
      };
    }
    return RecipeSummaryPage(
      items: items,
      hasMore: hasMore,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<int> countRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
  }) async {
    return _matchingRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      includeDeleted: includeDeleted,
    ).length;
  }

  @override
  Future<Map<String, int>> countRecipesByCategory() async {
    final counts = <String, int>{};
    for (final recipe in recipes.values) {
      if (recipe.deletedAt != null) continue;
      for (final categoryId in recipe.categoryIds) {
        final category = categories[categoryId];
        if (category == null || category.deletedAt != null) continue;
        counts[categoryId] = (counts[categoryId] ?? 0) + 1;
      }
    }
    return counts;
  }

  @override
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids) async {
    final idSet = ids.toSet();
    final result = recipes.values
        .where(
          (recipe) => idSet.contains(recipe.id) && recipe.deletedAt == null,
        )
        .map(
          (recipe) => RecipeSummary(
            id: recipe.id,
            title: recipe.title,
            coverImage: recipe.coverImage,
            favorite: recipe.favorite,
            totalTimeMinutes: recipe.totalTimeMinutes,
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            servings: recipe.servings,
            difficulty: recipe.difficulty,
            sourceId: recipe.sourceId,
            ingredientCount: recipe.ingredients.length,
            tags: recipe.tags,
            updatedAt: recipe.updatedAt,
            status: recipe.status,
          ),
        )
        .toList(growable: false);
    // 保持传入 id 的顺序（首页"最近浏览"按浏览时间展示）。
    result.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));
    return result;
  }

  @override
  Future<List<Recipe>> listRecipesForRecommendation({
    RecipeStatus? status,
  }) async {
    final result = recipes.values
        .where(
          (recipe) =>
              recipe.deletedAt == null &&
              (status == null || recipe.status == status),
        )
        .toList();
    // 推荐只需主记录 + 食材；为保持与 SQLite 实现一致，这里直接返回完整
    // Recipe（步骤/图片/分类字段在匹配中不会被使用）。
    return result;
  }

  @override
  Future<List<TrashRecipeSummary>> listTrashSummaries() async {
    _throwIfNeeded();
    final items = recipes.values
        .where((recipe) => recipe.deletedAt != null)
        .map(
          (recipe) => TrashRecipeSummary(
            id: recipe.id,
            title: recipe.title,
            deletedAt: recipe.deletedAt!,
          ),
        )
        .toList();
    // 与 SQLite 实现一致：按删除时间倒序。
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  List<Recipe> _matchingRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
  }) {
    _throwIfNeeded();
    final normalizedQuery = query?.toLowerCase();
    return recipes.values.where((recipe) {
      if (!includeDeleted && recipe.deletedAt != null) return false;
      if (favorite != null && recipe.favorite != favorite) return false;
      if (status != null && recipe.status != status) return false;
      if (categoryId != null && !recipe.categoryIds.contains(categoryId)) {
        return false;
      }
      final normalizedTag = tag?.trim().toLowerCase();
      if (normalizedTag != null &&
          normalizedTag.isNotEmpty &&
          !recipe.tags.any((value) => value.toLowerCase() == normalizedTag)) {
        return false;
      }
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        final searchable = <String?>[
          recipe.title,
          recipe.description,
          recipe.notes,
          ...recipe.tags,
          ...recipe.ingredients.map((item) => item.name),
        ].whereType<String>().join('\n').toLowerCase();
        if (!searchable.contains(normalizedQuery)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<void> softDeleteRecipe(String id, DateTime deletedAt) async {
    _throwIfNeeded();
    final recipe = recipes[id];
    if (recipe == null) throw StateError('missing recipe: $id');
    recipes[id] = _copyRecipe(
      recipe,
      updatedAt: deletedAt,
      localVersion: recipe.localVersion + 1,
      deletedAt: deletedAt,
    );
  }

  @override
  Future<int> softDeleteRecipesByIds(List<String> ids, DateTime deletedAt) async {
    _throwIfNeeded();
    var removed = 0;
    for (final id in ids) {
      final recipe = recipes[id];
      if (recipe == null) continue;
      recipes[id] = _copyRecipe(
        recipe,
        updatedAt: deletedAt,
        localVersion: recipe.localVersion + 1,
        deletedAt: deletedAt,
      );
      removed += 1;
    }
    return removed;
  }

  @override
  Future<void> restoreRecipe(String id, DateTime updatedAt) async {
    _throwIfNeeded();
    final recipe = recipes[id];
    if (recipe == null) throw StateError('missing recipe: $id');
    recipes[id] = _copyRecipe(
      recipe,
      updatedAt: updatedAt,
      localVersion: recipe.localVersion + 1,
      clearDeletedAt: true,
    );
  }

  @override
  Future<void> permanentlyDeleteRecipe(String id) async {
    _throwIfNeeded();
    if (recipes.remove(id) == null) throw StateError('missing recipe: $id');
  }

  @override
  Future<int> permanentlyDeleteRecipesByIds(List<String> ids) async {
    _throwIfNeeded();
    var removed = 0;
    for (final id in ids) {
      if (recipes.remove(id) != null) removed += 1;
    }
    return removed;
  }

  @override
  Future<void> upsertCategory(RecipeCategory category) async {
    _throwIfNeeded();
    categories[category.id] = category;
  }

  @override
  Future<RecipeCategory?> getCategoryById(
    String id, {
    bool includeDeleted = false,
  }) async {
    _throwIfNeeded();
    final category = categories[id];
    if (category == null || (!includeDeleted && category.deletedAt != null)) {
      return null;
    }
    return category;
  }

  @override
  Future<List<RecipeCategory>> listCategories({
    bool includeDeleted = false,
  }) async {
    _throwIfNeeded();
    final result = categories.values
        .where((category) => includeDeleted || category.deletedAt == null)
        .toList();
    result.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      if (byOrder != 0) return byOrder;
      final byName = left.name.toLowerCase().compareTo(
        right.name.toLowerCase(),
      );
      return byName != 0 ? byName : left.id.compareTo(right.id);
    });
    return result;
  }

  @override
  Future<void> softDeleteCategory(String id, DateTime deletedAt) async {
    _throwIfNeeded();
    final category = categories[id];
    if (category == null) throw StateError('missing category: $id');
    categories[id] = _copyCategory(
      category,
      updatedAt: deletedAt,
      localVersion: category.localVersion + 1,
      deletedAt: deletedAt,
    );
    for (final entry in recipes.entries.toList()) {
      if (!entry.value.categoryIds.contains(id)) continue;
      recipes[entry.key] = _copyRecipe(
        entry.value,
        categoryIds: entry.value.categoryIds
            .where((categoryId) => categoryId != id)
            .toList(),
      );
    }
  }

  @override
  Future<void> restoreCategory(String id, DateTime updatedAt) async {
    _throwIfNeeded();
    final category = categories[id];
    if (category == null) throw StateError('missing category: $id');
    categories[id] = _copyCategory(
      category,
      updatedAt: updatedAt,
      localVersion: category.localVersion + 1,
      clearDeletedAt: true,
    );
  }

  @override
  Future<void> permanentlyDeleteCategory(String id) async {
    _throwIfNeeded();
    if (categories.remove(id) == null) {
      throw StateError('missing category: $id');
    }
    for (final entry in recipes.entries.toList()) {
      if (!entry.value.categoryIds.contains(id)) continue;
      recipes[entry.key] = _copyRecipe(
        entry.value,
        categoryIds: entry.value.categoryIds
            .where((categoryId) => categoryId != id)
            .toList(),
      );
    }
  }

  static Recipe _copyRecipe(
    Recipe recipe, {
    DateTime? updatedAt,
    int? localVersion,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<String>? categoryIds,
  }) {
    return Recipe(
      id: recipe.id,
      userId: recipe.userId,
      title: recipe.title,
      description: recipe.description,
      coverImage: recipe.coverImage,
      servings: recipe.servings,
      prepTimeMinutes: recipe.prepTimeMinutes,
      cookTimeMinutes: recipe.cookTimeMinutes,
      totalTimeMinutes: recipe.totalTimeMinutes,
      difficulty: recipe.difficulty,
      notes: recipe.notes,
      favorite: recipe.favorite,
      status: recipe.status,
      sourceId: recipe.sourceId,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      categoryIds: categoryIds ?? recipe.categoryIds,
      tags: recipe.tags,
      createdAt: recipe.createdAt,
      updatedAt: updatedAt ?? recipe.updatedAt,
      localVersion: localVersion ?? recipe.localVersion,
      deletedAt: clearDeletedAt ? null : deletedAt ?? recipe.deletedAt,
    );
  }

  static RecipeCategory _copyCategory(
    RecipeCategory category, {
    required DateTime updatedAt,
    required int localVersion,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return RecipeCategory(
      id: category.id,
      userId: category.userId,
      name: category.name,
      coverImage: category.coverImage,
      sortOrder: category.sortOrder,
      createdAt: category.createdAt,
      updatedAt: updatedAt,
      localVersion: localVersion,
      deletedAt: clearDeletedAt ? null : deletedAt ?? category.deletedAt,
    );
  }
}
