import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';

class RecipeIngredientInput {
  RecipeIngredientInput({
    this.id,
    required this.name,
    this.groupName,
    this.quantity,
    this.unit,
    this.optional = false,
    this.preparation,
    List<String> substitutes = const <String>[],
    this.confidence,
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specConfidence,
    this.specSource = IngredientSpecSource.unknown,
  }) : substitutes = List<String>.unmodifiable(substitutes);

  final String? id;
  final String name;
  final String? groupName;
  final String? quantity;
  final String? unit;
  final bool optional;
  final String? preparation;
  final List<String> substitutes;
  final double? confidence;

  // ---- ADR-0022：可选的显式规格（编辑页回显时透传）----
  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;
  final double? specConfidence;
  final IngredientSpecSource specSource;
}

class RecipeStepInput {
  const RecipeStepInput({
    this.id,
    required this.description,
    this.durationSeconds,
    this.temperature,
    this.heatLevel,
    this.cookware,
    this.tips,
    this.mediaUrl,
    this.confidence,
  });

  final String? id;
  final String description;
  final int? durationSeconds;
  final String? temperature;
  final String? heatLevel;
  final String? cookware;
  final String? tips;
  final String? mediaUrl;
  final double? confidence;
}

class RecipeDraftInput {
  RecipeDraftInput({
    required this.title,
    this.description,
    this.coverImage,
    List<String> images = const <String>[],
    this.servings,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.totalTimeMinutes,
    this.difficulty = RecipeDifficulty.unspecified,
    this.notes,
    this.favorite = false,
    this.status = RecipeStatus.draft,
    List<RecipeIngredientInput> ingredients = const <RecipeIngredientInput>[],
    List<RecipeStepInput> steps = const <RecipeStepInput>[],
    List<String> categoryIds = const <String>[],
    List<String> tags = const <String>[],
  }) : images = List<String>.unmodifiable(images),
       ingredients = List<RecipeIngredientInput>.unmodifiable(ingredients),
       steps = List<RecipeStepInput>.unmodifiable(steps),
       categoryIds = List<String>.unmodifiable(categoryIds),
       tags = List<String>.unmodifiable(tags);

  final String title;
  final String? description;
  final String? coverImage;
  final List<String> images;
  final int? servings;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final int? totalTimeMinutes;
  final RecipeDifficulty difficulty;
  final String? notes;
  final bool favorite;
  final RecipeStatus status;
  final List<RecipeIngredientInput> ingredients;
  final List<RecipeStepInput> steps;
  final List<String> categoryIds;
  final List<String> tags;
}

class RecipeCategoryInput {
  const RecipeCategoryInput({
    required this.name,
    this.coverImage,
    required this.sortOrder,
  });

  final String name;
  final String? coverImage;
  final int sortOrder;
}

enum RecipeLibraryDeletionFilter { activeOnly, includeDeleted, deletedOnly }

abstract class RecipeLibraryException implements Exception {
  const RecipeLibraryException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class RecipeNotFoundException extends RecipeLibraryException {
  RecipeNotFoundException(String id) : super('菜谱不存在：$id');
}

class RecipeCategoryNotFoundException extends RecipeLibraryException {
  RecipeCategoryNotFoundException(String id) : super('分类不存在：$id');
}

class RecipeCategoryUnavailableException extends RecipeLibraryException {
  RecipeCategoryUnavailableException(String id) : super('分类已删除，不能关联：$id');
}

class RecipeLibraryValidationException extends RecipeLibraryException {
  const RecipeLibraryValidationException(super.message);
}

class RecipeLibraryIdGenerationException extends RecipeLibraryException {
  const RecipeLibraryIdGenerationException() : super('无法生成有效的本地 ID');
}

class RecipeLibraryStorageException extends RecipeLibraryException {
  const RecipeLibraryStorageException() : super('菜谱库暂时不可用，请稍后重试');
}
