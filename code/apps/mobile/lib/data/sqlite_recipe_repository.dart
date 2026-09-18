import 'dart:convert';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
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

      await transaction.delete(
        'recipe_images',
        where: 'recipe_id = ?',
        whereArgs: <Object?>[recipe.id],
      );
      for (final entry in recipe.images.indexed) {
        await transaction.insert('recipe_images', <String, Object?>{
          'recipe_id': recipe.id,
          'image_path': entry.$2,
          'sort_order': entry.$1,
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
    String? tag,
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      final filter = _buildListFilter(
        includeDeleted: includeDeleted,
        favorite: favorite,
        status: status,
        categoryId: categoryId,
        tag: tag,
        query: query,
      );

      final idRows = await transaction.rawQuery('''
          SELECT r.id
          FROM recipes r
          ${filter.parts.isEmpty ? '' : 'WHERE ${filter.parts.join(' AND ')}'}
          ORDER BY r.updated_at DESC, r.id DESC
        ''', filter.args);

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
  Future<List<TrashRecipeSummary>> listTrashSummaries() async {
    final database = await _appDatabase.database;
    // 单条 SQL 一次返回回收站全部条目（软删除菜谱），只取列表所需
    // 字段，替代 listRecipes 的"先查 id 再逐条 _loadRecipe 全量加载"
    // N+1 模式，避免大数据量回收站卡顿。
    final rows = await database.rawQuery('''
        SELECT r.id, r.title, r.deleted_at
        FROM recipes r
        WHERE r.deleted_at IS NOT NULL
        ORDER BY r.deleted_at DESC, r.id DESC
      ''');
    return rows
        .map(
          (row) => TrashRecipeSummary(
            id: row['id']! as String,
            title: row['title']! as String,
            deletedAt: _nullableFromEpoch(row['deleted_at'] as int?)!,
          ),
        )
        .toList(growable: false);
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
    final safeLimit = limit < 1 ? 1 : limit;
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      final filter = _buildListFilter(
        includeDeleted: includeDeleted,
        favorite: favorite,
        status: status,
        categoryId: categoryId,
        tag: tag,
        query: query,
      );
      final whereParts = List<String>.of(filter.parts);
      final whereArgs = List<Object?>.of(filter.args);

      // keyset pagination：按排序键 + id 继续读取，避免 OFFSET 变慢。
      final timestampColumn = switch (sort) {
        RecipeSort.updated => 'r.updated_at',
        RecipeSort.created => 'r.created_at',
        RecipeSort.title => 'r.title',
      };
      if (after != null) {
        if (sort == RecipeSort.title) {
          final titleKey = after.title ?? '';
          whereParts.add(
            '(r.title COLLATE NOCASE > ? '
            'OR (r.title COLLATE NOCASE = ? AND r.id > ?))',
          );
          whereArgs.addAll(<Object?>[titleKey, titleKey, after.id]);
        } else {
          final ts = after.timestamp?.toUtc().millisecondsSinceEpoch;
          whereParts.add(
            '($timestampColumn < ? OR ($timestampColumn = ? AND r.id < ?))',
          );
          whereArgs.addAll(<Object?>[ts, ts, after.id]);
        }
      }

      final orderBy = switch (sort) {
        RecipeSort.updated => 'r.updated_at DESC, r.id DESC',
        RecipeSort.created => 'r.created_at DESC, r.id DESC',
        RecipeSort.title => 'r.title COLLATE NOCASE ASC, r.id ASC',
      };

      // 多取一条判断是否还有下一页（避免额外 COUNT）。
      final rows = await transaction.rawQuery('''
          SELECT r.id, r.title, r.cover_image, r.favorite,
                 r.total_time_minutes, r.prep_time_minutes,
                 r.cook_time_minutes, r.servings, r.difficulty,
                 r.source_id, r.tags_json, r.status, r.updated_at,
                 COUNT(i.id) AS ingredient_count
          FROM recipes r
          LEFT JOIN ingredients i ON i.recipe_id = r.id
          ${whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}'}
          GROUP BY r.id
          ORDER BY $orderBy
          LIMIT ?
        ''', <Object?>[...whereArgs, safeLimit + 1]);

      final hasMore = rows.length > safeLimit;
      final pageRows = hasMore ? rows.sublist(0, safeLimit) : rows;
      final items = pageRows
          .map(_summaryFromRow)
          .toList(growable: false);
      RecipeCursor? nextCursor;
      if (hasMore && items.isNotEmpty) {
        final last = items.last;
        nextCursor = switch (sort) {
          RecipeSort.title => RecipeCursor(title: last.title, id: last.id),
          _ => RecipeCursor(timestamp: last.updatedAt, id: last.id),
        };
      }
      return RecipeSummaryPage(
        items: items,
        hasMore: hasMore,
        nextCursor: nextCursor,
      );
    });
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
    final database = await _appDatabase.database;
    final filter = _buildListFilter(
      includeDeleted: includeDeleted,
      favorite: favorite,
      status: status,
      categoryId: categoryId,
      tag: tag,
      query: query,
    );
    final rows = await database.rawQuery(
      '''
        SELECT COUNT(*) AS recipe_count
        FROM recipes r
        ${filter.parts.isEmpty ? '' : 'WHERE ${filter.parts.join(' AND ')}'}
      ''',
      filter.args,
    );
    return (rows.single['recipe_count']! as num).toInt();
  }

  @override
  Future<Map<String, int>> countRecipesByCategory() async {
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
        SELECT relation.category_id AS category_id, COUNT(*) AS recipe_count
        FROM recipe_category_relations relation
        INNER JOIN recipes r
          ON r.id = relation.recipe_id AND r.deleted_at IS NULL
        INNER JOIN recipe_categories category
          ON category.id = relation.category_id AND category.deleted_at IS NULL
        GROUP BY relation.category_id
      ''');
    return <String, int>{
      for (final row in rows)
        row['category_id']! as String: (row['recipe_count']! as num).toInt(),
    };
  }

  @override
  Future<List<RecipeSummary>> getRecipeSummariesByIds(List<String> ids) async {
    final normalized = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalized.isEmpty) return const <RecipeSummary>[];
    final database = await _appDatabase.database;
    final rows = await database.rawQuery('''
        SELECT r.id, r.title, r.cover_image, r.favorite,
               r.total_time_minutes, r.prep_time_minutes,
               r.cook_time_minutes, r.servings, r.difficulty,
               r.source_id, r.tags_json, r.status, r.updated_at,
               COUNT(i.id) AS ingredient_count
        FROM recipes r
        LEFT JOIN ingredients i ON i.recipe_id = r.id
        WHERE r.id IN (${List.filled(normalized.length, '?').join(',')})
          AND r.deleted_at IS NULL
        GROUP BY r.id
        ORDER BY r.updated_at DESC, r.id DESC
      ''', normalized);
    return rows.map(_summaryFromRow).toList(growable: false);
  }

  @override
  Future<List<Recipe>> listRecipesForRecommendation({
    RecipeStatus? status,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      final whereParts = <String>['r.deleted_at IS NULL'];
      final whereArgs = <Object?>[];
      if (status != null) {
        whereParts.add('r.status = ?');
        whereArgs.add(status.wireName);
      }
      final recipeRows = await transaction.rawQuery('''
          SELECT r.* FROM recipes r
          WHERE ${whereParts.join(' AND ')}
          ORDER BY r.updated_at DESC, r.id DESC
        ''', whereArgs);
      if (recipeRows.isEmpty) return const <Recipe>[];

      // 一次批量读取全部食材（推荐匹配只需食材，不含步骤/图片/分类）。
      final ingredientRows = await transaction.rawQuery('''
          SELECT i.* FROM ingredients i
          INNER JOIN recipes r ON r.id = i.recipe_id
          WHERE ${whereParts.join(' AND ')}
          ORDER BY i.recipe_id, i.sort_order, i.id
        ''', whereArgs);
      final byRecipe = <String, List<Map<String, Object?>>>{};
      for (final row in ingredientRows) {
        final recipeId = row['recipe_id']! as String;
        byRecipe
            .putIfAbsent(recipeId, () => <Map<String, Object?>>[])
            .add(row);
      }
      return recipeRows.map((row) {
        final id = row['id']! as String;
        return _recipeFromRows(
          row,
          byRecipe[id] ?? const <Map<String, Object?>>[],
          const <Map<String, Object?>>[],
          const <Map<String, Object?>>[],
          const <Map<String, Object?>>[],
        );
      }).toList(growable: false);
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
  Future<int> softDeleteRecipesByIds(
    List<String> ids,
    DateTime deletedAt,
  ) async {
    if (ids.isEmpty) return 0;
    final database = await _appDatabase.database;
    final epoch = _toEpoch(deletedAt);
    return database.transaction((transaction) async {
      var removed = 0;
      // 单事务内分批 IN 更新：SQLite 绑定变量上限默认 999，按 500 一批。
      // 整个清空只提交一次事务（原逐条删除对每条做一次全量加载 +
      // 独立事务，1000 条测试数据需上千次查询与提交）。
      const batchSize = 500;
      for (var offset = 0; offset < ids.length; offset += batchSize) {
        final end = offset + batchSize < ids.length
            ? offset + batchSize
            : ids.length;
        final batch = ids.sublist(offset, end);
        removed += await transaction.rawUpdate(
          '''
            UPDATE recipes
            SET deleted_at = ?, updated_at = ?, local_version = local_version + 1
            WHERE id IN (${List.filled(batch.length, '?').join(',')})
          ''',
          <Object?>[epoch, epoch, ...batch],
        );
      }
      return removed;
    });
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
  Future<int> permanentlyDeleteRecipesByIds(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      var removed = 0;
      // 单事务内分批 IN 删除：SQLite 绑定变量上限默认 999，按 500 一批。
      // 子表依赖 ON DELETE CASCADE 一并清除；整个清空只需一次事务提交
      // （原逐条删除对每条做一次全量加载 + 独立事务，大库下极慢）。
      const batchSize = 500;
      for (var offset = 0; offset < ids.length; offset += batchSize) {
        final end = offset + batchSize < ids.length
            ? offset + batchSize
            : ids.length;
        final batch = ids.sublist(offset, end);
        removed += await transaction.delete(
          'recipes',
          where: 'id IN (${List.filled(batch.length, '?').join(',')})',
          whereArgs: batch,
        );
      }
      return removed;
    });
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
    final imageRows = await executor.query(
      'recipe_images',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'sort_order ASC',
    );

    return _recipeFromRows(
      rows.single,
      ingredientRows,
      stepRows,
      categoryRows,
      imageRows,
    );
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
      'tags_json': jsonEncode(recipe.tags),
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
      // ---- ADR-0022 规格落库 ----
      'base_concept_id': _emptyToNull(ingredient.baseConceptId),
      'base_concept_name': _emptyToNull(ingredient.baseConceptName),
      'cut': ingredient.cut?.wireName,
      'fat_level': ingredient.fatLevel?.wireName,
      'form': ingredient.form?.wireName,
      'processing': ingredient.processing?.wireName,
      'spec_confidence': ingredient.specConfidence,
      'spec_source': ingredient.specSource.wireName,
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

  /// 菜谱列表筛选条件（listRecipes / listRecipeSummaries / countRecipes 共用）。
  ///
  /// 统一生成 WHERE 片段与参数，保证摘要分页、总数与全量读取过滤一致。
  static ({List<String> parts, List<Object?> args}) _buildListFilter({
    required bool includeDeleted,
    bool? favorite,
    RecipeStatus? status,
    String? categoryId,
    String? tag,
    String? query,
  }) {
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
    final normalizedTag = tag?.trim();
    if (normalizedTag != null && normalizedTag.isNotEmpty) {
      whereParts.add(
        r'''r.tags_json LIKE ? ESCAPE char(92) COLLATE NOCASE''',
      );
      whereArgs.add('%"${_escapeLike(normalizedTag)}"%');
    }
    final normalizedQuery = query?.trim();
    if (normalizedQuery != null && normalizedQuery.isNotEmpty) {
      whereParts.add('''
        (
          r.title LIKE ? ESCAPE char(92) COLLATE NOCASE
          OR r.description LIKE ? ESCAPE char(92) COLLATE NOCASE
          OR r.notes LIKE ? ESCAPE char(92) COLLATE NOCASE
          OR r.tags_json LIKE ? ESCAPE char(92) COLLATE NOCASE
          OR EXISTS (
            SELECT 1 FROM ingredients i
            WHERE i.recipe_id = r.id
              AND i.name LIKE ? ESCAPE char(92) COLLATE NOCASE
          )
        )
      ''');
      final likeQuery = '%${_escapeLike(normalizedQuery)}%';
      whereArgs.addAll(<Object?>[
        likeQuery,
        likeQuery,
        likeQuery,
        likeQuery,
        likeQuery,
      ]);
    }
    return (parts: whereParts, args: whereArgs);
  }

  /// 从菜谱列表摘要行构造 [RecipeSummary]（含食材数量聚合）。
  static RecipeSummary _summaryFromRow(Map<String, Object?> row) {
    return RecipeSummary(
      id: row['id']! as String,
      title: row['title']! as String,
      coverImage: row['cover_image'] as String?,
      favorite: row['favorite'] == 1,
      totalTimeMinutes: row['total_time_minutes'] as int?,
      prepTimeMinutes: row['prep_time_minutes'] as int?,
      cookTimeMinutes: row['cook_time_minutes'] as int?,
      servings: row['servings'] as int?,
      difficulty: RecipeDifficulty.fromWireName(
        row['difficulty']! as String,
      ),
      sourceId: row['source_id'] as String?,
      ingredientCount: (row['ingredient_count'] as num?)?.toInt() ?? 0,
      tags: _decodeStringList(row['tags_json'] as String?),
      updatedAt: _fromEpoch(row['updated_at']! as int),
      status: RecipeStatus.fromWireName(row['status']! as String),
    );
  }

  static Recipe _recipeFromRows(
    Map<String, Object?> recipeRow,
    List<Map<String, Object?>> ingredientRows,
    List<Map<String, Object?>> stepRows,
    List<Map<String, Object?>> categoryRows,
    List<Map<String, Object?>> imageRows,
  ) {
    return Recipe(
      id: recipeRow['id']! as String,
      userId: recipeRow['user_id'] as String?,
      title: recipeRow['title']! as String,
      description: recipeRow['description'] as String?,
      coverImage: recipeRow['cover_image'] as String?,
      images: imageRows.map((row) => row['image_path']! as String).toList(),
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
      tags: _decodeStringList(recipeRow['tags_json'] as String?),
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
      // ---- ADR-0022 规格读取 ----
      baseConceptId: row['base_concept_id'] as String?,
      baseConceptName: row['base_concept_name'] as String?,
      cut: IngredientCut.fromWireName(row['cut'] as String?),
      fatLevel: IngredientFatLevel.fromWireName(row['fat_level'] as String?),
      form: IngredientForm.fromWireName(row['form'] as String?),
      processing: IngredientProcessing.fromWireName(
        row['processing'] as String?,
      ),
      specConfidence: (row['spec_confidence'] as num?)?.toDouble(),
      specSource: IngredientSpecSource.fromWireName(
        row['spec_source'] as String?,
      ),
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

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

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
