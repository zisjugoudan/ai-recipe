import 'recipe.dart';

abstract interface class RecipeRepository {
  Future<void> upsertRecipe(Recipe recipe);

  Future<Recipe?> getRecipeById(String id, {bool includeDeleted = false});

  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
  });

  /// 菜谱列表摘要分页（解决方案.md 第一~三节）。
  ///
  /// 单条 SQL 一次返回一页卡片所需字段（含食材数量聚合），不再
  /// 逐条调用 `_loadRecipe`；使用 keyset pagination 代替 OFFSET。
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
  });

  /// 列表筛选条件下的菜谱总数（列表页头"共 N 道菜谱"）。
  Future<int> countRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    bool includeDeleted = false,
  });

  /// 各分类下的活跃菜谱数量（首页分类卡片，避免全量读取）。
  Future<Map<String, int>> countRecipesByCategory();

  /// 按 id 批量读取摘要（首页"最近浏览"等小列表用，一次 SQL）。
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids);

  /// 推荐专用轻量批量读取（解决方案.md 第五节）。
  ///
  /// 只加载菜谱主记录 + 全部食材（推荐匹配只需食材与卡片字段），
  /// 不加载步骤/图片/分类关系，从约 5001 次查询降为 2 次。
  Future<List<Recipe>> listRecipesForRecommendation({RecipeStatus? status});

  /// 回收站菜谱轻量列表（单条 SQL，避免 N+1 全量加载）。
  ///
  /// 回收站只展示标题与删除时间，按删除时间倒序返回；
  /// 恢复/永久删除操作仅依赖 id。
  Future<List<TrashRecipeSummary>> listTrashSummaries();

  Future<void> softDeleteRecipe(String id, DateTime deletedAt);

  /// 批量软删除（清空测试数据等）：一次 SQL 一个事务，返回实际删除
  /// 条数。避免逐条「全量加载 + 独立事务提交」在大库下缓慢（如开发者
  /// 工具清空 1000 条测试菜谱时逐条删除需上千次查询与事务）。
  Future<int> softDeleteRecipesByIds(List<String> ids, DateTime deletedAt);

  Future<void> restoreRecipe(String id, DateTime updatedAt);

  Future<void> permanentlyDeleteRecipe(String id);

  /// 批量永久删除（清空回收站/批量删除用）：一次 SQL 一个事务，返回
  /// 实际删除条数。避免逐条「全量加载 + 独立事务提交」在大库下删除
  /// 缓慢（如回收站 2000 条时逐条删除需数千次查询与事务）。
  ///
  /// 由调用方保证 [ids] 均已软删除（回收站）；SQLite 依赖
  /// ON DELETE CASCADE 一并清除子表行。
  Future<int> permanentlyDeleteRecipesByIds(List<String> ids);
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
