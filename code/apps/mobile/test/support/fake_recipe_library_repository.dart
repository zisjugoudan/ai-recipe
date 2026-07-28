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
    bool includeDeleted = false,
  }) async {
    _throwIfNeeded();
    final normalizedQuery = query?.toLowerCase();
    final result = recipes.values.where((recipe) {
      if (!includeDeleted && recipe.deletedAt != null) return false;
      if (favorite != null && recipe.favorite != favorite) return false;
      if (status != null && recipe.status != status) return false;
      if (categoryId != null && !recipe.categoryIds.contains(categoryId)) {
        return false;
      }
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        final searchable = <String?>[
          recipe.title,
          recipe.description,
          recipe.notes,
          ...recipe.ingredients.map((item) => item.name),
        ].whereType<String>().join('\n').toLowerCase();
        if (!searchable.contains(normalizedQuery)) return false;
      }
      return true;
    }).toList();
    result.sort((left, right) {
      final byUpdatedAt = right.updatedAt.compareTo(left.updatedAt);
      return byUpdatedAt != 0 ? byUpdatedAt : left.id.compareTo(right.id);
    });
    return result;
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
