import '../../domain/recipe/recipe.dart';
import '../../domain/recipe/recipe_cover_image_storer.dart';
import '../../domain/recipe/recipe_repository.dart';
import 'import_pipeline_contracts.dart';

class SafeImportRecipeDraftDiscarder {
  SafeImportRecipeDraftDiscarder(
    this._repository, {
    RecipeCoverImageStorer? coverImageStorer,
  }) : _coverImageStorer = coverImageStorer;

  final RecipeRepository _repository;
  final RecipeCoverImageStorer? _coverImageStorer;

  ImportRecipeDraftDiscarder get call => discard;

  Future<void> discard({
    required String recipeId,
    required String sourceId,
  }) async {
    final normalizedRecipeId = recipeId.trim();
    final normalizedSourceId = sourceId.trim();
    if (normalizedRecipeId.isEmpty || normalizedSourceId.isEmpty) {
      return;
    }

    final recipe = await _repository.getRecipeById(
      normalizedRecipeId,
      includeDeleted: true,
    );
    if (recipe == null ||
        recipe.status != RecipeStatus.draft ||
        recipe.deletedAt != null ||
        recipe.sourceId != normalizedSourceId) {
      return;
    }

    await _repository.permanentlyDeleteRecipe(recipe.id);
    // 同步清理该草稿的私有封面目录，避免遗留孤儿图片文件（best-effort）。
    await _coverImageStorer?.deleteContainer(recipe.id);
  }
}
