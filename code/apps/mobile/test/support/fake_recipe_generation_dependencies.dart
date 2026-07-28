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
    bool includeDeleted = false,
  }) async {
    return recipes.values.where((recipe) {
      if (!includeDeleted && recipe.deletedAt != null) return false;
      if (favorite != null && recipe.favorite != favorite) return false;
      if (query != null && !recipe.title.contains(query)) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> permanentlyDeleteRecipe(String id) async {
    recipes.remove(id);
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
