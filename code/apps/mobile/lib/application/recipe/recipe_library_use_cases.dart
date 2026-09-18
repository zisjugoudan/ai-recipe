import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_canonicalizer.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_repository.dart';

import 'default_recipe_categories.dart';

typedef RecipeLibraryIdGenerator = String Function();
typedef RecipeLibraryClock = DateTime Function();

class RecipeLibraryUseCases {
  RecipeLibraryUseCases({
    required RecipeRepository recipeRepository,
    required RecipeCategoryRepository categoryRepository,
    required RecipeLibraryIdGenerator idGenerator,
    required RecipeLibraryClock clock,
    IngredientCanonicalizer? canonicalizer,
  }) : _recipeRepository = recipeRepository,
       _categoryRepository = categoryRepository,
       _idGenerator = idGenerator,
       _clock = clock,
       _canonicalizer = canonicalizer ?? IngredientCanonicalizer();

  final RecipeRepository _recipeRepository;
  final RecipeCategoryRepository _categoryRepository;
  final RecipeLibraryIdGenerator _idGenerator;
  final RecipeLibraryClock _clock;

  /// 食材统一标准化器（ADR-0022）：保存菜谱时把食材名称解析为规格落库。
  final IngredientCanonicalizer _canonicalizer;

  IngredientCanonicalizer get canonicalizer => _canonicalizer;

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

  /// 只更新指定步骤的时长（烹饪模式自定义计时同步用，COOK-001）。
  ///
  /// 只修改目标步骤的 [RecipeStep.durationSeconds]，其余字段全部保留，
  /// 避免为单个字段强制走整份 `RecipeDraftInput` 更新造成覆盖。
  Future<Recipe> updateRecipeStepDuration(
    String recipeId,
    String stepId,
    int durationSeconds,
  ) async {
    if (durationSeconds <= 0) {
      throw const RecipeLibraryValidationException('步骤时长必须大于 0');
    }
    final existing = await _requireRecipe(recipeId);
    final target = existing.steps.where((step) => step.id == stepId).firstOrNull;
    if (target == null) {
      throw RecipeLibraryValidationException('步骤不属于当前菜谱：$stepId');
    }
    // RecipeStep 不可变且无 copyWith，重建目标步骤（保留其他字段）。
    final updatedSteps = existing.steps
        .map(
          (step) => step.id == target.id
              ? RecipeStep(
                  id: step.id,
                  stepNumber: step.stepNumber,
                  description: step.description,
                  durationSeconds: durationSeconds,
                  temperature: step.temperature,
                  heatLevel: step.heatLevel,
                  cookware: step.cookware,
                  tips: step.tips,
                  mediaUrl: step.mediaUrl,
                  confidence: step.confidence,
                )
              : step,
        )
        .toList(growable: false);
    final updated = Recipe(
      id: existing.id,
      userId: existing.userId,
      title: existing.title,
      description: existing.description,
      coverImage: existing.coverImage,
      images: existing.images,
      servings: existing.servings,
      prepTimeMinutes: existing.prepTimeMinutes,
      cookTimeMinutes: existing.cookTimeMinutes,
      totalTimeMinutes: existing.totalTimeMinutes,
      difficulty: existing.difficulty,
      notes: existing.notes,
      favorite: existing.favorite,
      status: existing.status,
      sourceId: existing.sourceId,
      ingredients: existing.ingredients,
      steps: updatedSteps,
      categoryIds: existing.categoryIds,
      tags: existing.tags,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      localVersion: existing.localVersion + 1,
      deletedAt: existing.deletedAt,
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
    String? tag,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) async {
    final recipes = await _storage(
      () => _recipeRepository.listRecipes(
        query: _emptyToNull(query),
        favorite: favorite,
        status: status,
        categoryId: _emptyToNull(categoryId),
        tag: _emptyToNull(tag),
        includeDeleted:
            deletionFilter != RecipeLibraryDeletionFilter.activeOnly,
      ),
    );
    if (deletionFilter != RecipeLibraryDeletionFilter.deletedOnly) {
      return recipes;
    }
    return recipes.where((recipe) => recipe.deletedAt != null).toList();
  }

  /// 菜谱列表摘要分页（解决方案.md：列表页用摘要 + keyset 分页，避免
  /// 全量聚合读取与 OFFSET 变慢）。
  Future<RecipeSummaryPage> listRecipeSummaries({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
    RecipeSort sort = RecipeSort.updated,
    int limit = 40,
    RecipeCursor? after,
  }) {
    return _storage(
      () => _recipeRepository.listRecipeSummaries(
        query: _emptyToNull(query),
        favorite: favorite,
        status: status,
        categoryId: _emptyToNull(categoryId),
        tag: _emptyToNull(tag),
        includeDeleted:
            deletionFilter != RecipeLibraryDeletionFilter.activeOnly,
        sort: sort,
        limit: limit,
        after: after,
      ),
    );
  }

  /// 回收站菜谱轻量列表（单条 SQL，避免 N+1 全量加载卡顿）。
  Future<List<TrashRecipeSummary>> listTrashSummaries() {
    return _storage(
      () => _recipeRepository.listTrashSummaries(),
    );
  }

  /// 列表筛选条件下的菜谱总数（列表页头"共 N 道菜谱"）。
  Future<int> countRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    RecipeLibraryDeletionFilter deletionFilter =
        RecipeLibraryDeletionFilter.activeOnly,
  }) {
    return _storage(
      () => _recipeRepository.countRecipes(
        query: _emptyToNull(query),
        favorite: favorite,
        status: status,
        categoryId: _emptyToNull(categoryId),
        tag: _emptyToNull(tag),
        includeDeleted:
            deletionFilter != RecipeLibraryDeletionFilter.activeOnly,
      ),
    );
  }

  /// 各分类下的活跃菜谱数量（首页分类卡片，避免全量读取）。
  Future<Map<String, int>> countRecipesByCategory() {
    return _storage(() => _recipeRepository.countRecipesByCategory());
  }

  /// 按 id 批量读取摘要（首页"最近浏览"等小列表用）。
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids) {
    return _storage(() => _recipeRepository.getRecipeSummariesByIds(ids));
  }

  /// 推荐专用轻量批量读取（解决方案.md 第五节：只含主记录 + 食材，
  /// 不加载步骤/图片/分类）。
  Future<List<Recipe>> listRecipesForRecommendation({RecipeStatus? status}) {
    return _storage(
      () => _recipeRepository.listRecipesForRecommendation(status: status),
    );
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

  /// 批量软删除（开发者工具清空测试数据等）：一次 SQL 一个事务。
  ///
  /// 原逐条调用 [softDeleteRecipe] 会对每条做一次全量加载 + 独立
  /// 事务提交，1000 条测试数据需上千次查询与提交，明显卡顿。
  Future<void> softDeleteRecipesByIds(Iterable<String> ids) async {
    final normalized = _normalizeIds(ids, '菜谱 ID');
    if (normalized.isEmpty) return;
    await _storage(
      () => _recipeRepository.softDeleteRecipesByIds(normalized, _clock()),
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

  Future<Recipe> copyRecipe(String id, {String? title}) async {
    final source = await _requireRecipe(id);
    final now = _clock();
    final copied = Recipe(
      id: _nextId(),
      userId: source.userId,
      title: _emptyToNull(title) ?? '${source.title} 副本',
      description: source.description,
      coverImage: source.coverImage,
      servings: source.servings,
      prepTimeMinutes: source.prepTimeMinutes,
      cookTimeMinutes: source.cookTimeMinutes,
      totalTimeMinutes: source.totalTimeMinutes,
      difficulty: source.difficulty,
      notes: source.notes,
      favorite: false,
      status: RecipeStatus.draft,
      sourceId: source.sourceId,
      ingredients: source.ingredients
          .map(
            (item) => Ingredient(
              id: _nextId(),
              name: item.name,
              groupName: item.groupName,
              quantity: item.quantity,
              unit: item.unit,
              optional: item.optional,
              preparation: item.preparation,
              substitutes: item.substitutes,
              sortOrder: item.sortOrder,
              confidence: item.confidence,
              // ADR-0022：复制时保留已解析的规格。
              baseConceptId: item.baseConceptId,
              baseConceptName: item.baseConceptName,
              cut: item.cut,
              fatLevel: item.fatLevel,
              form: item.form,
              processing: item.processing,
              specConfidence: item.specConfidence,
              specSource: item.specSource,
            ),
          )
          .toList(),
      steps: source.steps
          .map(
            (item) => RecipeStep(
              id: _nextId(),
              stepNumber: item.stepNumber,
              description: item.description,
              durationSeconds: item.durationSeconds,
              temperature: item.temperature,
              heatLevel: item.heatLevel,
              cookware: item.cookware,
              tips: item.tips,
              mediaUrl: item.mediaUrl,
              confidence: item.confidence,
            ),
          )
          .toList(),
      categoryIds: source.categoryIds,
      tags: source.tags,
      createdAt: now,
      updatedAt: now,
    );
    await _storage(() => _recipeRepository.upsertRecipe(copied));
    return copied;
  }

  Future<void> restoreRecipes(Iterable<String> ids) async {
    for (final id in _normalizeIds(ids, '菜谱 ID')) {
      await restoreRecipe(id);
    }
  }

  Future<void> permanentlyDeleteRecipes(Iterable<String> ids) async {
    final normalized = _normalizeIds(ids, '菜谱 ID');
    if (normalized.isEmpty) return;
    // 批量删除：一次 SQL 一个事务（原逐条加载+逐条事务，大库下极慢）。
    await _storage(
      () => _recipeRepository.permanentlyDeleteRecipesByIds(normalized),
    );
  }

  Future<int> emptyRecipeTrash() async {
    // 回收站只读标题/删除时间的轻量摘要（单条 SQL），避免全量加载
    // 子表；随后批量删除同样只用一个事务，2000 条也能秒级完成。
    final trashed = await _recipeRepository.listTrashSummaries();
    if (trashed.isEmpty) return 0;
    final ids = trashed.map((item) => item.id).toList(growable: false);
    await _storage(
      () => _recipeRepository.permanentlyDeleteRecipesByIds(ids),
    );
    return ids.length;
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
    // HOME-001：首次访问菜谱库时自动创建 12 个默认分类（幂空检查）。
    await ensureDefaultCategories();
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

  /// 若分类表为空，则插入 12 个默认分类（固定 ID 与名称）。
  /// 该检查幂等：已有分类时不执行任何写入。
  Future<void> ensureDefaultCategories() async {
    final existing = await _storage(
      () => _categoryRepository.listCategories(includeDeleted: true),
    );
    if (existing.isNotEmpty) return;

    for (var i = 0; i < defaultRecipeCategories.length; i++) {
      final def = defaultRecipeCategories[i];
      final now = _clock();
      final category = _buildCategory(
        id: def.id,
        userId: null,
        input: RecipeCategoryInput(name: def.name, sortOrder: i),
        createdAt: now,
        updatedAt: now,
        localVersion: 1,
      );
      await _storage(() => _categoryRepository.upsertCategory(category));
    }
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
        images: input.images
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
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
          final spec = _resolveIngredientSpec(item);
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
            // ---- ADR-0022：保存时解析食材规格落库 ----
            baseConceptId: spec.baseConceptId,
            baseConceptName: spec.baseConceptName,
            cut: spec.cut,
            fatLevel: spec.fatLevel,
            form: spec.form,
            processing: spec.processing,
            specConfidence: spec.specConfidence,
            specSource: spec.specSource,
            // ---- ADR-0023：要求强度（菜名核心 / 可选 / 必需）----
            importance: _resolveImportance(item, input.title),
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
        tags: _normalizeTags(input.tags),
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

  /// 解析食材规格（ADR-0022）：
  /// - 编辑页回显时 input 已带显式规格，直接透传；
  /// - 否则由本地词典把名称解析为规格（老数据/新录入即时回填）。
  _ResolvedIngredientSpec _resolveIngredientSpec(RecipeIngredientInput item) {
    final explicitId = item.baseConceptId?.trim();
    if (explicitId != null && explicitId.isNotEmpty) {
      return _ResolvedIngredientSpec(
        baseConceptId: explicitId,
        baseConceptName: item.baseConceptName,
        cut: item.cut,
        fatLevel: item.fatLevel,
        form: item.form,
        processing: item.processing,
        specConfidence: item.specConfidence ?? 1.0,
        specSource: item.specSource,
      );
    }
    final canonical = canonicalizer.canonicalize(item.name);
    if (canonical.isKnown) {
      return _ResolvedIngredientSpec(
        baseConceptId: canonical.canonicalIngredientId,
        baseConceptName: canonical.canonicalName,
        cut: canonical.cut,
        fatLevel: canonical.fatLevel,
        form: canonical.form,
        processing: canonical.processing,
        specConfidence: canonical.confidence,
        specSource: canonical.specSource,
      );
    }
    return const _ResolvedIngredientSpec();
  }

  /// 食材要求强度（ADR-0023）：
  /// 可选标记 → optional；名称出现在菜名中 → core；其余 → required。
  IngredientImportance _resolveImportance(
    RecipeIngredientInput item,
    String title,
  ) {
    if (item.optional) return IngredientImportance.optional;
    final name = item.name.trim();
    if (name.isNotEmpty && title.contains(name)) {
      return IngredientImportance.core;
    }
    return IngredientImportance.required;
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
      images: recipe.images,
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
      tags: recipe.tags,
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

  List<String> _normalizeTags(List<String> tags) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final rawTag in tags) {
      final tag = rawTag.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      if (seen.add(key)) normalized.add(tag);
    }
    return normalized;
  }

  List<String> _normalizeIds(Iterable<String> ids, String fieldName) {
    final normalized = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      final value = _requireId(id, fieldName);
      if (seen.add(value)) normalized.add(value);
    }
    if (normalized.isEmpty) {
      throw RecipeLibraryValidationException('$fieldName 不能为空。');
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

/// 食材规格解析结果（ADR-0022，供菜谱保存落库）。
class _ResolvedIngredientSpec {
  const _ResolvedIngredientSpec({
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specConfidence,
    this.specSource = IngredientSpecSource.unknown,
  });

  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;
  final double? specConfidence;
  final IngredientSpecSource specSource;
}
