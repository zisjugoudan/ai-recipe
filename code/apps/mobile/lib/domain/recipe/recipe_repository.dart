import 'recipe.dart';

abstract interface class RecipeRepository {
  Future<void> upsertRecipe(Recipe recipe);

  Future<Recipe?> getRecipeById(String id, {bool includeDeleted = false});

  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    bool includeDeleted = false,
  });

  Future<void> softDeleteRecipe(String id, DateTime deletedAt);

  Future<void> restoreRecipe(String id, DateTime updatedAt);

  Future<void> permanentlyDeleteRecipe(String id);
}

abstract interface class RecipeCategoryRepository {
  Future<void> upsertCategory(RecipeCategory category);

  Future<RecipeCategory?> getCategoryById(
    String id, {
    bool includeDeleted = false,
  });

  Future<List<RecipeCategory>> listCategories({bool includeDeleted = false});

  Future<void> softDeleteCategory(String id, DateTime deletedAt);

  Future<void> restoreCategory(String id, DateTime updatedAt);

  Future<void> permanentlyDeleteCategory(String id);
}
