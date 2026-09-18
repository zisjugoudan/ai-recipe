class RecipeRecentView {
  const RecipeRecentView({required this.recipeId, required this.viewedAt});

  final String recipeId;
  final DateTime viewedAt;
}

abstract interface class RecipeActivityRepository {
  Future<void> recordRecipeView(String recipeId, DateTime viewedAt);

  Future<List<RecipeRecentView>> listRecentViews({int limit = 20});

  Future<void> clearRecipeHistory();
}
