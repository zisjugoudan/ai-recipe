import 'dart:convert';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/domain/recipe/recipe_repository.dart';
import 'package:sqflite/sqflite.dart';

class SqliteRecipeRepository
    implements RecipeRepository, RecipeCategoryRepository {
  SqliteRecipeRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> upsertRecipe(Recipe recipe) async {
    final database = await _appDatabase.database;
    await database.transaction((transaction) async {
      await _upsert(
        transaction,
        table: 'recipes',
        id: recipe.id,
        values: _recipeToRow(recipe),
      );

      await transaction.delete(
        'ingredients',
        where: 'recipe_id = ?',
        whereArgs: <Object?>[recipe.id],
      );
      for (final ingredient in recipe.ingredients) {
        await transaction.insert(
          'ingredients',
          _ingredientToRow(recipe.id, ingredient),
        );
      }

      await transaction.delete(
        'recipe_steps',
        where: 'recipe_id = ?',
        whereArgs: <Object?>[recipe.id],
      );
      for (final step in recipe.steps) {
        await transaction.insert('recipe_steps', _stepToRow(recipe.id, step));
      }

      await transaction.delete(
        'recipe_category_relations',
        where: 'recipe_id = ?',
        whereArgs: <Object?>[recipe.id],
      );
      for (final categoryId in recipe.categoryIds) {
        await transaction.insert('recipe_category_relations', <String, Object?>{
          'recipe_id': recipe.id,
          'category_id': categoryId,
        });
      }
    });
  }

  @override
  Future<Recipe?> getRecipeById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction(
      (transaction) =>
          _loadRecipe(transaction, id, includeDeleted: includeDeleted),
    );
  }

  @override
  Future<List<Recipe>> listRecipes({
    String? query,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      final whereParts = <String>[];
      final whereArgs = <Object?>[];
      if (!includeDeleted) {
        whereParts.add('r.deleted_at IS NULL');
      }
      if (favorite != null) {
        whereParts.add('r.favorite = ?');
        whereArgs.add(favorite ? 1 : 0);
      }
      if (status != null) {
        whereParts.add('r.status = ?');
        whereArgs.add(status.wireName);
      }
      final normalizedCategoryId = categoryId?.trim();
      if (normalizedCategoryId != null && normalizedCategoryId.isNotEmpty) {
        whereParts.add('''
          EXISTS (
            SELECT 1 FROM recipe_category_relations relation
            INNER JOIN recipe_categories category
              ON category.id = relation.category_id
            WHERE relation.recipe_id = r.id
              AND relation.category_id = ?
              AND category.deleted_at IS NULL
          )
        ''');
        whereArgs.add(normalizedCategoryId);
      }
      final normalizedQuery = query?.trim();
      if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
        whereParts.add('''
          (
            r.title LIKE ? COLLATE NOCASE
            OR r.description LIKE ? COLLATE NOCASE
            OR r.notes LIKE ? COLLATE NOCASE
            OR EXISTS (
              SELECT 1 FROM ingredients i
              WHERE i.recipe_id = r.id
                AND i.name LIKE ? COLLATE NOCASE
            )
          )
        ''');
        final likeQuery = '%$normalizedQuery%';
        whereArgs.addAll(<Object?>[likeQuery, likeQuery, likeQuery, likeQuery]);
      }

      final idRows = await transaction.rawQuery('''
          SELECT r.id
          FROM recipes r
          ${whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}'}
          ORDER BY r.updated_at DESC, r.id ASC
        ''', whereArgs);

      final recipes = <Recipe>[];
      for (final row in idRows) {
        final recipe = await _loadRecipe(
          transaction,
          row['id']! as String,
          includeDeleted: includeDeleted,
        );
        if (recipe != null) {
          recipes.add(recipe);
        }
      }
      return recipes;
    });
  }

  @override
  Future<void> softDeleteRecipe(String id, DateTime deletedAt) async {
    final database = await _appDatabase.database;
    final changed = await database.rawUpdate(
      '''
        UPDATE recipes
        SET deleted_at = ?, updated_at = ?, local_version = local_version + 1
        WHERE id = ?
      ''',
      <Object?>[_toEpoch(deletedAt), _toEpoch(deletedAt), id],
    );
    _requireChanged(changed, '菜谱', id);
  }

  @override
  Future<void> restoreRecipe(String id, DateTime updatedAt) async {
    final database = await _appDatabase.database;
    final changed = await database.rawUpdate(
      '''
        UPDATE recipes
        SET deleted_at = NULL, updated_at = ?, local_version = local_version + 1
        WHERE id = ?
      ''',
      <Object?>[_toEpoch(updatedAt), id],
    );
    _requireChanged(changed, '菜谱', id);
  }

  @override
  Future<void> permanentlyDeleteRecipe(String id) async {
    final database = await _appDatabase.database;
    final changed = await database.delete(
      'recipes',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _requireChanged(changed, '菜谱', id);
  }

  @override
  Future<void> upsertCategory(RecipeCategory category) async {
    final database = await _appDatabase.database;
    await database.transaction((transaction) {
      return _upsert(
        transaction,
        table: 'recipe_categories',
        id: category.id,
        values: _categoryToRow(category),
      );
    });
  }

  @override
  Future<RecipeCategory?> getCategoryById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'recipe_categories',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _categoryFromRow(rows.single);
  }

  @override
  Future<List<RecipeCategory>> listCategories({
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'recipe_categories',
      where: includeDeleted ? null : 'deleted_at IS NULL',
      orderBy: 'sort_order ASC, name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(_categoryFromRow).toList(growable: false);
  }

  @override
  Future<void> softDeleteCategory(String id, DateTime deletedAt) async {
    final database = await _appDatabase.database;
    await database.transaction((transaction) async {
      final changed = await transaction.rawUpdate(
        '''
          UPDATE recipe_categories
          SET deleted_at = ?, updated_at = ?, local_version = local_version + 1
          WHERE id = ?
        ''',
        <Object?>[_toEpoch(deletedAt), _toEpoch(deletedAt), id],
      );
      _requireChanged(changed, '分类', id);
      await transaction.delete(
        'recipe_category_relations',
        where: 'category_id = ?',
        whereArgs: <Object?>[id],
      );
    });
  }

  @override
  Future<void> restoreCategory(String id, DateTime updatedAt) async {
    final database = await _appDatabase.database;
    final changed = await database.rawUpdate(
      '''
        UPDATE recipe_categories
        SET deleted_at = NULL, updated_at = ?, local_version = local_version + 1
        WHERE id = ?
      ''',
      <Object?>[_toEpoch(updatedAt), id],
    );
    _requireChanged(changed, '分类', id);
  }

  @override
  Future<void> permanentlyDeleteCategory(String id) async {
    final database = await _appDatabase.database;
    final changed = await database.delete(
      'recipe_categories',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _requireChanged(changed, '分类', id);
  }

  Future<Recipe?> _loadRecipe(
    DatabaseExecutor executor,
    String id, {
    required bool includeDeleted,
  }) async {
    final rows = await executor.query(
      'recipes',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final ingredientRows = await executor.query(
      'ingredients',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'sort_order ASC, id ASC',
    );
    final stepRows = await executor.query(
      'recipe_steps',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'step_number ASC, id ASC',
    );
    final categoryRows = await executor.rawQuery(
      '''
        SELECT relation.category_id
        FROM recipe_category_relations relation
        INNER JOIN recipe_categories category
          ON category.id = relation.category_id
        WHERE relation.recipe_id = ? AND category.deleted_at IS NULL
        ORDER BY category.sort_order ASC, category.name COLLATE NOCASE ASC,
          category.id ASC
      ''',
      <Object?>[id],
    );

    return _recipeFromRows(rows.single, ingredientRows, stepRows, categoryRows);
  }

  static Future<void> _upsert(
    DatabaseExecutor executor, {
    required String table,
    required String id,
    required Map<String, Object?> values,
  }) async {
    final changed = await executor.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    if (changed == 0) {
      await executor.insert(table, values);
    }
  }

  static Map<String, Object?> _recipeToRow(Recipe recipe) {
    return <String, Object?>{
      'id': recipe.id,
      'user_id': recipe.userId,
      'title': recipe.title.trim(),
      'description': _emptyToNull(recipe.description),
      'cover_image': _emptyToNull(recipe.coverImage),
      'servings': recipe.servings,
      'prep_time_minutes': recipe.prepTimeMinutes,
      'cook_time_minutes': recipe.cookTimeMinutes,
      'total_time_minutes': recipe.totalTimeMinutes,
      'difficulty': recipe.difficulty.wireName,
      'notes': _emptyToNull(recipe.notes),
      'favorite': recipe.favorite ? 1 : 0,
      'status': recipe.status.wireName,
      'source_id': _emptyToNull(recipe.sourceId),
      'created_at': _toEpoch(recipe.createdAt),
      'updated_at': _toEpoch(recipe.updatedAt),
      'local_version': recipe.localVersion,
      'deleted_at': recipe.deletedAt == null
          ? null
          : _toEpoch(recipe.deletedAt!),
    };
  }

  static Map<String, Object?> _ingredientToRow(
    String recipeId,
    Ingredient ingredient,
  ) {
    return <String, Object?>{
      'id': ingredient.id,
      'recipe_id': recipeId,
      'group_name': _emptyToNull(ingredient.groupName),
      'name': ingredient.name.trim(),
      'quantity': _emptyToNull(ingredient.quantity),
      'unit': _emptyToNull(ingredient.unit),
      'optional': ingredient.optional ? 1 : 0,
      'preparation': _emptyToNull(ingredient.preparation),
      'substitutes_json': jsonEncode(ingredient.substitutes),
      'sort_order': ingredient.sortOrder,
      'confidence': ingredient.confidence,
    };
  }

  static Map<String, Object?> _stepToRow(String recipeId, RecipeStep step) {
    return <String, Object?>{
      'id': step.id,
      'recipe_id': recipeId,
      'step_number': step.stepNumber,
      'description': step.description.trim(),
      'duration_seconds': step.durationSeconds,
      'temperature': _emptyToNull(step.temperature),
      'heat_level': _emptyToNull(step.heatLevel),
      'cookware': _emptyToNull(step.cookware),
      'tips': _emptyToNull(step.tips),
      'media_url': _emptyToNull(step.mediaUrl),
      'confidence': step.confidence,
    };
  }

  static Map<String, Object?> _categoryToRow(RecipeCategory category) {
    return <String, Object?>{
      'id': category.id,
      'user_id': category.userId,
      'name': category.name.trim(),
      'cover_image': _emptyToNull(category.coverImage),
      'sort_order': category.sortOrder,
      'created_at': _toEpoch(category.createdAt),
      'updated_at': _toEpoch(category.updatedAt),
      'local_version': category.localVersion,
      'deleted_at': category.deletedAt == null
          ? null
          : _toEpoch(category.deletedAt!),
    };
  }

  static Recipe _recipeFromRows(
    Map<String, Object?> recipeRow,
    List<Map<String, Object?>> ingredientRows,
    List<Map<String, Object?>> stepRows,
    List<Map<String, Object?>> categoryRows,
  ) {
    return Recipe(
      id: recipeRow['id']! as String,
      userId: recipeRow['user_id'] as String?,
      title: recipeRow['title']! as String,
      description: recipeRow['description'] as String?,
      coverImage: recipeRow['cover_image'] as String?,
      servings: recipeRow['servings'] as int?,
      prepTimeMinutes: recipeRow['prep_time_minutes'] as int?,
      cookTimeMinutes: recipeRow['cook_time_minutes'] as int?,
      totalTimeMinutes: recipeRow['total_time_minutes'] as int?,
      difficulty: RecipeDifficulty.fromWireName(
        recipeRow['difficulty']! as String,
      ),
      notes: recipeRow['notes'] as String?,
      favorite: recipeRow['favorite'] == 1,
      status: RecipeStatus.fromWireName(recipeRow['status']! as String),
      sourceId: recipeRow['source_id'] as String?,
      ingredients: ingredientRows.map(_ingredientFromRow).toList(),
      steps: stepRows.map(_stepFromRow).toList(),
      categoryIds: categoryRows
          .map((row) => row['category_id']! as String)
          .toList(),
      createdAt: _fromEpoch(recipeRow['created_at']! as int),
      updatedAt: _fromEpoch(recipeRow['updated_at']! as int),
      localVersion: recipeRow['local_version']! as int,
      deletedAt: _nullableFromEpoch(recipeRow['deleted_at'] as int?),
    );
  }

  static Ingredient _ingredientFromRow(Map<String, Object?> row) {
    final substitutes = (jsonDecode(row['substitutes_json']! as String) as List)
        .cast<String>();
    return Ingredient(
      id: row['id']! as String,
      groupName: row['group_name'] as String?,
      name: row['name']! as String,
      quantity: row['quantity'] as String?,
      unit: row['unit'] as String?,
      optional: row['optional'] == 1,
      preparation: row['preparation'] as String?,
      substitutes: substitutes,
      sortOrder: row['sort_order']! as int,
      confidence: (row['confidence'] as num?)?.toDouble(),
    );
  }

  static RecipeStep _stepFromRow(Map<String, Object?> row) {
    return RecipeStep(
      id: row['id']! as String,
      stepNumber: row['step_number']! as int,
      description: row['description']! as String,
      durationSeconds: row['duration_seconds'] as int?,
      temperature: row['temperature'] as String?,
      heatLevel: row['heat_level'] as String?,
      cookware: row['cookware'] as String?,
      tips: row['tips'] as String?,
      mediaUrl: row['media_url'] as String?,
      confidence: (row['confidence'] as num?)?.toDouble(),
    );
  }

  static RecipeCategory _categoryFromRow(Map<String, Object?> row) {
    return RecipeCategory(
      id: row['id']! as String,
      userId: row['user_id'] as String?,
      name: row['name']! as String,
      coverImage: row['cover_image'] as String?,
      sortOrder: row['sort_order']! as int,
      createdAt: _fromEpoch(row['created_at']! as int),
      updatedAt: _fromEpoch(row['updated_at']! as int),
      localVersion: row['local_version']! as int,
      deletedAt: _nullableFromEpoch(row['deleted_at'] as int?),
    );
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _toEpoch(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static DateTime _fromEpoch(int value) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static DateTime? _nullableFromEpoch(int? value) {
    return value == null ? null : _fromEpoch(value);
  }

  static void _requireChanged(int changed, String entityName, String id) {
    if (changed == 0) {
      throw StateError('$entityName不存在：$id');
    }
  }
}
