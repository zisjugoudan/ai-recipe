import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_repository.dart';

typedef RecipeLibraryIdGenerator = String Function();
typedef RecipeLibraryClock = DateTime Function();

class RecipeLibraryUseCases {
  const RecipeLibraryUseCases({
    required RecipeRepository recipeRepository,
    required RecipeCategoryRepository categoryRepository,
    required RecipeLibraryIdGenerator idGenerator,
    required RecipeLibraryClock clock,
  }) : _recipeRepository = recipeRepository,
       _categoryRepository = categoryRepository,
       _idGenerator = idGenerator,
       _clock = clock;

  final RecipeRepository _recipeRepository;
  final RecipeCategoryRepository _categoryRepository;
  final RecipeLibraryIdGenerator _idGenerator;
  final RecipeLibraryClock _clock;

  Future<Recipe> createRecipe(
    RecipeDraftInput input, {
    String? userId,
    String? sourceId,
  }) async {
    final categoryIds = _normalizeCategoryIds(input.categoryIds);
    await _ensureCategoriesAvailable(categoryIds);
    final now = _clock();
    final recipe = _buildRecipe(
      id: _nextId(),
      userId: _emptyToNull(userId),
      sourceId: _emptyToNull(sourceId),
      input: input,
      categoryIds: categoryIds,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
      existingIngredientIds: const <String>{},
      existingStepIds: const <String>{},
      preserveInputIds: false,
    );
    await _storage(() => _recipeRepository.upsertRecipe(recipe));
    return recipe;
  }

  Future<Recipe> updateRecipe(String id, RecipeDraftInput input) async {
    final existing = await _requireRecipe(id);
    final categoryIds = _normalizeCategoryIds(input.categoryIds);
    await _ensureCategoriesAvailable(categoryIds);
    final updated = _buildRecipe(
      id: existing.id,
      userId: existing.userId,
      sourceId: existing.sourceId,
      input: input,
      categoryIds: categoryIds,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      localVersion: existing.localVersion + 1,
      existingIngredientIds: existing.ingredients
          .map((item) => item.id)
          .toSet(),
      existingStepIds: existing.steps.map((item) => item.id).toSet(),
      preserveInputIds: true,
    );
    await _storage(() => _recipeRepository.upsertRecipe(updated));
    return updated;
  }

  Future<Recipe> getRecipe(String id, {bool includeDeleted = false}) async {
    final recipe = await _storage(
      () => _recipeRepository.getRecipeById(
        _requireId(id, '菜谱 ID'),
        includeDeleted: includeDeleted,
      ),
    );
    if (recipe == null) {
      throw RecipeNotFoundException(id);
    }
    return recipe;
  }

  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) async {
    final recipes = await _storage(
      () => _recipeRepository.listRecipes(
        query: _emptyToNull(query),
        favorite: favorite,
        status: status,
        categoryId: _emptyToNull(categoryId),
        includeDeleted:
            deletionFilter != RecipeLibraryDeletionFilter.activeOnly,
      ),
    );
    if (deletionFilter != RecipeLibraryDeletionFilter.deletedOnly) {
      return recipes;
    }
    return recipes.where((recipe) => recipe.deletedAt != null).toList();
  }

  Future<Recipe> setRecipeFavorite(String id, bool favorite) async {
    final existing = await _requireRecipe(id);
    if (existing.favorite == favorite) {
      return existing;
    }
    final updated = _copyRecipe(
      existing,
      favorite: favorite,
      updatedAt: _clock(),
      localVersion: existing.localVersion + 1,
    );
    await _storage(() => _recipeRepository.upsertRecipe(updated));
    return updated;
  }

  Future<void> softDeleteRecipe(String id) async {
    final existing = await _requireRecipe(id);
    await _storage(
      () => _recipeRepository.softDeleteRecipe(existing.id, _clock()),
    );
  }

  Future<void> restoreRecipe(String id) async {
    final existing = await _requireRecipe(id, includeDeleted: true);
    if (existing.deletedAt == null) {
      return;
    }
    await _storage(
      () => _recipeRepository.restoreRecipe(existing.id, _clock()),
    );
  }

  Future<void> permanentlyDeleteRecipe(String id) async {
    final existing = await _requireRecipe(id, includeDeleted: true);
    if (existing.deletedAt == null) {
      throw const RecipeLibraryValidationException('只有回收站中的菜谱才能永久删除');
    }
    await _storage(
      () => _recipeRepository.permanentlyDeleteRecipe(existing.id),
    );
  }

  Future<RecipeCategory> createCategory(
    RecipeCategoryInput input, {
    String? userId,
  }) async {
    final now = _clock();
    final category = _buildCategory(
      id: _nextId(),
      userId: _emptyToNull(userId),
      input: input,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
    );
    await _storage(() => _categoryRepository.upsertCategory(category));
    return category;
  }

  Future<RecipeCategory> updateCategory(
    String id,
    RecipeCategoryInput input,
  ) async {
    final existing = await _requireCategory(id);
    final updated = _buildCategory(
      id: existing.id,
      userId: existing.userId,
      input: input,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      localVersion: existing.localVersion + 1,
    );
    await _storage(() => _categoryRepository.upsertCategory(updated));
    return updated;
  }

  Future<RecipeCategory> getCategory(
    String id, {
    bool includeDeleted = false,
  }) async {
    final category = await _storage(
      () => _categoryRepository.getCategoryById(
        _requireId(id, '分类 ID'),
        includeDeleted: includeDeleted,
      ),
    );
    if (category == null) {
      throw RecipeCategoryNotFoundException(id);
    }
    return category;
  }

  Future<List<RecipeCategory>> listCategories({
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) async {
    final categories = await _storage(
      () => _categoryRepository.listCategories(
        includeDeleted:
            deletionFilter != RecipeLibraryDeletionFilter.activeOnly,
      ),
    );
    if (deletionFilter != RecipeLibraryDeletionFilter.deletedOnly) {
      return categories;
    }
    return categories.where((category) => category.deletedAt != null).toList();
  }

  Future<void> softDeleteCategory(String id) async {
    final existing = await _requireCategory(id);
    await _storage(
      () => _categoryRepository.softDeleteCategory(existing.id, _clock()),
    );
  }

  Future<void> restoreCategory(String id) async {
    final existing = await _requireCategory(id, includeDeleted: true);
    if (existing.deletedAt == null) {
      return;
    }
    await _storage(
      () => _categoryRepository.restoreCategory(existing.id, _clock()),
    );
  }

  Future<void> permanentlyDeleteCategory(String id) async {
    final existing = await _requireCategory(id, includeDeleted: true);
    if (existing.deletedAt == null) {
      throw const RecipeLibraryValidationException('只有回收站中的分类才能永久删除');
    }
    await _storage(
      () => _categoryRepository.permanentlyDeleteCategory(existing.id),
    );
  }

  Future<Recipe> _requireRecipe(
    String id, {
    bool includeDeleted = false,
  }) async {
    final normalizedId = _requireId(id, '菜谱 ID');
    final recipe = await _storage(
      () => _recipeRepository.getRecipeById(
        normalizedId,
        includeDeleted: includeDeleted,
      ),
    );
    if (recipe == null) {
      throw RecipeNotFoundException(normalizedId);
    }
    return recipe;
  }

  Future<RecipeCategory> _requireCategory(
    String id, {
    bool includeDeleted = false,
  }) async {
    final normalizedId = _requireId(id, '分类 ID');
    final category = await _storage(
      () => _categoryRepository.getCategoryById(
        normalizedId,
        includeDeleted: includeDeleted,
      ),
    );
    if (category == null) {
      throw RecipeCategoryNotFoundException(normalizedId);
    }
    return category;
  }

  Future<void> _ensureCategoriesAvailable(List<String> categoryIds) async {
    for (final categoryId in categoryIds) {
      final category = await _storage(
        () => _categoryRepository.getCategoryById(
          categoryId,
          includeDeleted: true,
        ),
      );
      if (category == null) {
        throw RecipeCategoryNotFoundException(categoryId);
      }
      if (category.deletedAt != null) {
        throw RecipeCategoryUnavailableException(categoryId);
      }
    }
  }

  Recipe _buildRecipe({
    required String id,
    required String? userId,
    required String? sourceId,
    required RecipeDraftInput input,
    required List<String> categoryIds,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int localVersion,
    required Set<String> existingIngredientIds,
    required Set<String> existingStepIds,
    required bool preserveInputIds,
  }) {
    try {
      return Recipe(
        id: id,
        userId: userId,
        title: input.title.trim(),
        description: _emptyToNull(input.description),
        coverImage: _emptyToNull(input.coverImage),
        servings: input.servings,
        prepTimeMinutes: input.prepTimeMinutes,
        cookTimeMinutes: input.cookTimeMinutes,
        totalTimeMinutes: input.totalTimeMinutes,
        difficulty: input.difficulty,
        notes: _emptyToNull(input.notes),
        favorite: input.favorite,
        status: input.status,
        sourceId: sourceId,
        ingredients: input.ingredients.indexed.map((entry) {
          final item = entry.$2;
          return Ingredient(
            id: _resolveChildId(
              item.id,
              existingIds: existingIngredientIds,
              preserveInputIds: preserveInputIds,
              entityName: '食材',
            ),
            name: item.name.trim(),
            groupName: _emptyToNull(item.groupName),
            quantity: _emptyToNull(item.quantity),
            unit: _emptyToNull(item.unit),
            optional: item.optional,
            preparation: _emptyToNull(item.preparation),
            substitutes: item.substitutes
                .map((value) => value.trim())
                .where((value) => value.isNotEmpty)
                .toList(),
            sortOrder: entry.$1,
            confidence: item.confidence,
          );
        }).toList(),
        steps: input.steps.indexed.map((entry) {
          final item = entry.$2;
          return RecipeStep(
            id: _resolveChildId(
              item.id,
              existingIds: existingStepIds,
              preserveInputIds: preserveInputIds,
              entityName: '步骤',
            ),
            stepNumber: entry.$1 + 1,
            description: item.description.trim(),
            durationSeconds: item.durationSeconds,
            temperature: _emptyToNull(item.temperature),
            heatLevel: _emptyToNull(item.heatLevel),
            cookware: _emptyToNull(item.cookware),
            tips: _emptyToNull(item.tips),
            mediaUrl: _emptyToNull(item.mediaUrl),
            confidence: item.confidence,
          );
        }).toList(),
        categoryIds: categoryIds,
        createdAt: createdAt,
        updatedAt: updatedAt,
        localVersion: localVersion,
      );
    } on RecipeLibraryException {
      rethrow;
    } on FormatException catch (error) {
      throw RecipeLibraryValidationException(error.message.toString());
    } on ArgumentError catch (error) {
      throw RecipeLibraryValidationException(error.message.toString());
    }
  }

  RecipeCategory _buildCategory({
    required String id,
    required String? userId,
    required RecipeCategoryInput input,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int localVersion,
  }) {
    try {
      return RecipeCategory(
        id: id,
        userId: userId,
        name: input.name.trim(),
        coverImage: _emptyToNull(input.coverImage),
        sortOrder: input.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt,
        localVersion: localVersion,
      );
    } on FormatException catch (error) {
      throw RecipeLibraryValidationException(error.message.toString());
    } on ArgumentError catch (error) {
      throw RecipeLibraryValidationException(error.message.toString());
    }
  }

  Recipe _copyRecipe(
    Recipe recipe, {
    required bool favorite,
    required DateTime updatedAt,
    required int localVersion,
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
      favorite: favorite,
      status: recipe.status,
      sourceId: recipe.sourceId,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      categoryIds: recipe.categoryIds,
      createdAt: recipe.createdAt,
      updatedAt: updatedAt,
      localVersion: localVersion,
      deletedAt: recipe.deletedAt,
    );
  }

  String _resolveChildId(
    String? inputId, {
    required Set<String> existingIds,
    required bool preserveInputIds,
    required String entityName,
  }) {
    if (!preserveInputIds || inputId == null || inputId.trim().isEmpty) {
      return _nextId();
    }
    final normalizedId = inputId.trim();
    if (!existingIds.contains(normalizedId)) {
      throw RecipeLibraryValidationException(
        '$entityName ID 不属于当前菜谱：$normalizedId',
      );
    }
    return normalizedId;
  }

  List<String> _normalizeCategoryIds(List<String> categoryIds) {
    final normalized = categoryIds
        .map((id) => _requireId(id, '分类 ID'))
        .toList();
    if (normalized.toSet().length != normalized.length) {
      throw const RecipeLibraryValidationException('同一菜谱不能重复关联分类');
    }
    return normalized;
  }

  String _nextId() {
    try {
      final id = _idGenerator().trim();
      if (id.isEmpty) {
        throw const RecipeLibraryIdGenerationException();
      }
      return id;
    } on RecipeLibraryException {
      rethrow;
    } catch (_) {
      throw const RecipeLibraryIdGenerationException();
    }
  }

  static String _requireId(String value, String fieldName) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw RecipeLibraryValidationException('$fieldName 不能为空');
    }
    return normalized;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static Future<T> _storage<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on RecipeLibraryException {
      rethrow;
    } catch (_) {
      throw const RecipeLibraryStorageException();
    }
  }
}
