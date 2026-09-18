import 'package:ai_recipe/domain/llm/llm_cancellation_token.dart';
import 'package:ai_recipe/domain/llm/llm_connection_config.dart';
import 'package:ai_recipe/domain/llm/llm_models.dart';
import 'package:ai_recipe/domain/llm/llm_provider.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_repository.dart';

typedef FakeLlmHandler =
    Future<LlmGenerationResult> Function(
      LlmConnectionConfig config,
      String apiKey,
      LlmGenerationRequest request,
      LlmCancellationToken? cancellationToken,
    );

class FakeLlmProvider extends LlmProvider {
  FakeLlmProvider(this.handler);

  final FakeLlmHandler handler;
  int callCount = 0;
  LlmGenerationRequest? lastRequest;

  @override
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  }) {
    callCount += 1;
    lastRequest = request;
    return handler(config, apiKey, request, cancellationToken);
  }
}

class MemoryRecipeRepository implements RecipeRepository {
  final Map<String, Recipe> recipes = <String, Recipe>{};
  Object? upsertError;
  void Function(Recipe recipe)? afterUpsert;

  @override
  Future<Recipe?> getRecipeById(
    String id, {
    bool includeDeleted = false,
  }) async {
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
    return recipes.values.where((recipe) {
      if (!includeDeleted && recipe.deletedAt != null) return false;
      if (favorite != null && recipe.favorite != favorite) return false;
      if (status != null && recipe.status != status) return false;
      if (categoryId != null && !recipe.categoryIds.contains(categoryId)) {
        return false;
      }
      if (query != null && !recipe.title.contains(query)) return false;
      if (tag != null &&
          !recipe.tags.any(
            (recipeTag) => recipeTag.toLowerCase() == tag.toLowerCase(),
          )) {
        return false;
      }
      return true;
    }).toList();
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
    // 生成测试不依赖分页细节：一次性返回全部摘要。
    final matched = await listRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      includeDeleted: includeDeleted,
    );
    return RecipeSummaryPage(
      items: matched
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
          .toList(growable: false),
      hasMore: false,
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
    return (await listRecipes(
      query: query,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      includeDeleted: includeDeleted,
    )).length;
  }

  @override
  Future<Map<String, int>> countRecipesByCategory() async {
    return <String, int>{};
  }

  @override
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids) async {
    final idSet = ids.toSet();
    return recipes.values
        .where((recipe) => idSet.contains(recipe.id))
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
  }

  @override
  Future<List<Recipe>> listRecipesForRecommendation({
    RecipeStatus? status,
  }) async {
    return listRecipes(status: status);
  }

  @override
  Future<List<TrashRecipeSummary>> listTrashSummaries() async {
    return recipes.values
        .where((recipe) => recipe.deletedAt != null)
        .map(
          (recipe) => TrashRecipeSummary(
            id: recipe.id,
            title: recipe.title,
            deletedAt: recipe.deletedAt!,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> permanentlyDeleteRecipe(String id) async {
    recipes.remove(id);
  }

  @override
  Future<int> permanentlyDeleteRecipesByIds(List<String> ids) async {
    var removed = 0;
    for (final id in ids) {
      if (recipes.remove(id) != null) removed += 1;
    }
    return removed;
  }

  @override
  Future<int> softDeleteRecipesByIds(List<String> ids, DateTime deletedAt) async {
    var removed = 0;
    for (final id in ids) {
      if (recipes.remove(id) != null) removed += 1;
    }
    return removed;
  }

  @override
  Future<void> restoreRecipe(String id, DateTime updatedAt) async {
    throw UnimplementedError();
  }

  @override
  Future<void> softDeleteRecipe(String id, DateTime deletedAt) async {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertRecipe(Recipe recipe) async {
    if (upsertError != null) throw upsertError!;
    recipes[recipe.id] = recipe;
    afterUpsert?.call(recipe);
  }
}

const String validRecipeGenerationJson = '''
{
  "schemaVersion": 1,
  "title": "番茄炒蛋",
  "description": "家常快手菜",
  "servings": 2,
  "prepTimeMinutes": 5,
  "cookTimeMinutes": 8,
  "totalTimeMinutes": 13,
  "difficulty": "easy",
  "notes": null,
  "ingredients": [
    {
      "groupName": null,
      "name": "番茄",
      "quantity": "2",
      "unit": "个",
      "optional": false,
      "preparation": "切块",
      "substitutes": [],
      "confidence": 0.95
    }
  ],
  "steps": [
    {
      "description": "番茄炒软后加入蛋液炒匀。",
      "durationSeconds": 180,
      "temperature": null,
      "heatLevel": "中火",
      "cookware": "炒锅",
      "tips": null,
      "confidence": 0.9
    }
  ]
}
''';
