import 'dart:convert';
import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/backup/backup_cancellation_token.dart';
import 'package:ai_recipe/domain/backup/backup_import_repository.dart';
import 'package:ai_recipe/domain/backup/backup_record_hashing.dart';
import 'package:ai_recipe/domain/backup/backup_records.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 导入目标仓库（BACKUP-004）。
///
/// 职责：
/// - 预检只读：加载当前库全部菜谱/分类的规范化内容哈希（含软删除），
///   供导入用例生成 ImportPlan；本阶段不修改数据库或文件系统。
/// - 提交写入：替换模式 [clearLibrary] 清空菜谱库范围（保留账号、密钥、
///   设置、冰箱等非备份数据）；[applyImport] 在单个事务内写入全部
///   最终菜谱与分类（含食材、步骤、画廊图、分类关系）。
/// - 清理：替换后删除不再被任何记录引用的孤儿封面目录。
///
/// 与 sqlite_recipe_repository 的行映射保持一致，但备份模块独立维护，
/// 避免备份导入与普通仓库实现耦合。
class SqliteBackupImportRepository
    implements
        BackupImportPreflightRepository,
        BackupImportCommitRepository {
  SqliteBackupImportRepository(
    this._appDatabase, {
    Future<Directory> Function()? coverRootProvider,
  }) : _coverRootProvider = coverRootProvider ?? _defaultCoverRoot;

  final AppDatabase _appDatabase;

  /// 菜谱封面根目录提供器（默认应用文档目录下 recipe_covers）。
  final Future<Directory> Function() _coverRootProvider;

  static Future<Directory> _defaultCoverRoot() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'recipe_covers'));
  }

  // ---- 预检（只读） ----

  @override
  Future<Map<String, String>> loadRecipeIdHashes({
    BackupCancellationToken? token,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      token?.throwIfCancelled();
      // 全部菜谱（含回收站软删除），与快照读取同一时间点语义。
      final recipeRows = await transaction.query(
        'recipes',
        orderBy: 'id ASC',
      );
      final ingredientRows = await transaction.query(
        'ingredients',
        orderBy: 'recipe_id ASC, sort_order ASC, id ASC',
      );
      final stepRows = await transaction.query(
        'recipe_steps',
        orderBy: 'recipe_id ASC, step_number ASC, id ASC',
      );
      final relationRows = await transaction.query(
        'recipe_category_relations',
        orderBy: 'recipe_id ASC, category_id ASC',
      );
      final imageRows = await transaction.query(
        'recipe_images',
        orderBy: 'recipe_id ASC, sort_order ASC',
      );
      final byRecipe = <String, List<Map<String, Object?>>>{};
      for (final rows in <List<Map<String, Object?>>>[
        ingredientRows,
        stepRows,
        relationRows,
        imageRows,
      ]) {
        for (final row in rows) {
          byRecipe
              .putIfAbsent(row['recipe_id']! as String, () => <Map<String, Object?>>[])
              .add(row);
        }
      }
      final result = <String, String>{};
      for (final row in recipeRows) {
        token?.throwIfCancelled();
        final id = row['id']! as String;
        final recipe = _recipeFromRows(
          row,
          byRecipe[id] ?? const <Map<String, Object?>>[],
        );
        result[id] = canonicalRecipeHashFromDomain(recipe);
      }
      return result;
    });
  }

  @override
  Future<Map<String, String>> loadCategoryIdHashes({
    BackupCancellationToken? token,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'recipe_categories',
      orderBy: 'id ASC',
    );
    token?.throwIfCancelled();
    final result = <String, String>{};
    for (final row in rows) {
      result[row['id']! as String] = canonicalCategoryHashFromDomain(
        _categoryFromRow(row),
      );
    }
    return result;
  }

  @override
  Future<BackupLibrarySummary> loadLibrarySummary({
    BackupCancellationToken? token,
  }) async {
    token?.throwIfCancelled();
    final database = await _appDatabase.database;
    final recipeCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM recipes'),
        ) ??
        0;
    token?.throwIfCancelled();
    final categoryCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM recipe_categories'),
        ) ??
        0;
    // 去重媒体数：菜谱封面 + 画廊图 + 分类封面（空字符串不计）。
    final coverCount = Sqflite.firstIntValue(
          await database.rawQuery(
            '''
              SELECT COUNT(DISTINCT cover_image) FROM recipes
              WHERE cover_image IS NOT NULL AND cover_image != ''
            ''',
          ),
        ) ??
        0;
    final galleryCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(DISTINCT image_path) FROM recipe_images',
          ),
        ) ??
        0;
    final categoryCoverCount = Sqflite.firstIntValue(
          await database.rawQuery(
            '''
              SELECT COUNT(DISTINCT cover_image) FROM recipe_categories
              WHERE cover_image IS NOT NULL AND cover_image != ''
            ''',
          ),
        ) ??
        0;
    return BackupLibrarySummary(
      recipeCount: recipeCount,
      categoryCount: categoryCount,
      mediaCount: coverCount + galleryCount + categoryCoverCount,
    );
  }

  // ---- 提交（两阶段第二段） ----

  @override
  Future<int> clearLibrary({BackupCancellationToken? token}) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      token?.throwIfCancelled();
      // 菜谱库范围全部删除：recipes 的关联表（食材/步骤/画廊图/分类关系/
      // 最近浏览/烹饪会话）依赖 ON DELETE CASCADE 一并清除；
      // recipe_categories 同样级联清除分类关系。
      final deletedRecipes = await transaction.delete('recipes');
      token?.throwIfCancelled();
      await transaction.delete('recipe_categories');
      return deletedRecipes;
    });
  }

  @override
  Future<int> applyImport({
    required List<RecipeBackupRecord> recipes,
    required List<CategoryBackupRecord> categories,
    required Map<String, BackupRecipeMediaPaths> recipeMediaPaths,
    required Map<String, String> categoryCoverPaths,
    BackupCancellationToken? token,
    bool clearExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      token?.throwIfCancelled();
      // 替换模式：在同一事务内先清空菜谱库范围，再写入备份内容。
      // 整体要么全部成功要么全部回滚，避免两步之间失败导致空库。
      if (clearExisting) {
        // recipes 的关联表依赖 ON DELETE CASCADE 一并清除。
        await transaction.delete('recipes');
        token?.throwIfCancelled();
        await transaction.delete('recipe_categories');
      }
      // 备份内合法分类 ID 集合：菜谱分类关系只允许引用备份自带分类，
      // 防止伪造备份引用不存在的分类导致外键失败。
      final backupCategoryIds = categories.map((item) => item.id).toSet();

      // 进度总量 = 分类数 + 菜谱数（写入主体），逐条上报供 UI 展示百分比。
      final totalWrites = categories.length + recipes.length;
      var processedWrites = 0;

      // 先写分类（菜谱关系的外键依赖分类先存在）。
      for (final record in categories) {
        token?.throwIfCancelled();
        await _upsertCategory(
          transaction,
          _categoryRecordToDomain(record, categoryCoverPaths),
        );
        processedWrites += 1;
        onProgress?.call(processedWrites, totalWrites);
      }

      // 再写菜谱（含全部子表）。
      for (final record in recipes) {
        token?.throwIfCancelled();
        final recipe = _recipeRecordToDomain(
          record,
          recipeMediaPaths,
          backupCategoryIds,
        );
        await _upsertRecipe(transaction, recipe);
        processedWrites += 1;
        onProgress?.call(processedWrites, totalWrites);
      }
      return recipes.length;
    });
  }

  @override
  Future<int> removeOrphanedCoverFiles({
    BackupCancellationToken? token,
  }) async {
    token?.throwIfCancelled();
    final database = await _appDatabase.database;
    // 收集当前库仍在引用的全部封面/画廊路径（菜谱 + 分类 + 画廊表）。
    final referenced = <String>{};
    final recipeRows = await database.query('recipes', columns: ['cover_image']);
    for (final row in recipeRows) {
      final cover = row['cover_image'] as String?;
      if (cover != null && cover.trim().isNotEmpty) {
        referenced.add(cover);
      }
    }
    final imageRows = await database.query(
      'recipe_images',
      columns: ['image_path'],
    );
    for (final row in imageRows) {
      final image = row['image_path'] as String?;
      if (image != null && image.trim().isNotEmpty) {
        referenced.add(image);
      }
    }
    final categoryRows = await database.query(
      'recipe_categories',
      columns: ['cover_image'],
    );
    for (final row in categoryRows) {
      final cover = row['cover_image'] as String?;
      if (cover != null && cover.trim().isNotEmpty) {
        referenced.add(cover);
      }
    }

    final root = await _coverRootProvider();
    var removed = 0;
    try {
      if (!await root.exists()) return 0;
      await for (final entity in root.list()) {
        token?.throwIfCancelled();
        if (entity is! Directory) continue;
        final containerPath = path.normalize(entity.path);
        final inUse = referenced.any((entry) {
          final normalized = path.normalize(entry);
          return normalized == containerPath ||
              normalized.startsWith('$containerPath${path.separator}');
        });
        if (inUse) continue;
        // 无任何引用：整个容器目录删除。
        try {
          await entity.delete(recursive: true);
          removed += 1;
        } catch (_) {
          // best-effort：删除失败留待下次清理。
        }
      }
    } catch (_) {
      // best-effort：扫描失败不阻断导入完成。
    }
    return removed;
  }

  // ---- 记录 → 领域对象（媒体引用替换为本地路径） ----

  /// 把菜谱备份记录还原为领域对象，媒体引用按 [recipeMediaPaths] 替换
  /// 为导入后本地绝对路径；分类关系裁剪到备份自带分类集合。
  static Recipe _recipeRecordToDomain(
    RecipeBackupRecord record,
    Map<String, BackupRecipeMediaPaths> recipeMediaPaths,
    Set<String> backupCategoryIds,
  ) {
    final local = recipeMediaPaths[record.id];
    return Recipe(
      id: record.id,
      userId: record.userId,
      title: record.title,
      description: record.description,
      coverImage: local?.coverImage,
      images: local?.images ?? const <String>[],
      servings: record.servings,
      prepTimeMinutes: record.prepTimeMinutes,
      cookTimeMinutes: record.cookTimeMinutes,
      totalTimeMinutes: record.totalTimeMinutes,
      difficulty: record.difficulty,
      notes: record.notes,
      favorite: record.favorite,
      status: record.status,
      sourceId: record.sourceId,
      ingredients: record.ingredients,
      steps: record.steps,
      categoryIds: record.categoryIds
          .where(backupCategoryIds.contains)
          .toList(growable: false),
      tags: record.tags,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      localVersion: record.localVersion,
      deletedAt: record.deletedAt,
    );
  }

  /// 把分类备份记录还原为领域对象，封面路径来自 [categoryCoverPaths]。
  static RecipeCategory _categoryRecordToDomain(
    CategoryBackupRecord record,
    Map<String, String> categoryCoverPaths,
  ) {
    return RecipeCategory(
      id: record.id,
      userId: record.userId,
      name: record.name,
      coverImage: categoryCoverPaths[record.id],
      sortOrder: record.sortOrder,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      localVersion: record.localVersion,
      deletedAt: record.deletedAt,
    );
  }

  // ---- 领域对象 → SQLite 行（与 sqlite_recipe_repository 同构） ----

  static Future<void> _upsertRecipe(
    DatabaseExecutor executor,
    Recipe recipe,
  ) async {
    await _upsert(
      executor,
      table: 'recipes',
      id: recipe.id,
      values: _recipeToRow(recipe),
    );
    await executor.delete(
      'ingredients',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[recipe.id],
    );
    for (final ingredient in recipe.ingredients) {
      await executor.insert(
        'ingredients',
        _ingredientToRow(recipe.id, ingredient),
      );
    }
    await executor.delete(
      'recipe_steps',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[recipe.id],
    );
    for (final step in recipe.steps) {
      await executor.insert('recipe_steps', _stepToRow(recipe.id, step));
    }
    await executor.delete(
      'recipe_category_relations',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[recipe.id],
    );
    for (final categoryId in recipe.categoryIds) {
      await executor.insert('recipe_category_relations', <String, Object?>{
        'recipe_id': recipe.id,
        'category_id': categoryId,
      });
    }
    await executor.delete(
      'recipe_images',
      where: 'recipe_id = ?',
      whereArgs: <Object?>[recipe.id],
    );
    for (final entry in recipe.images.indexed) {
      await executor.insert('recipe_images', <String, Object?>{
        'recipe_id': recipe.id,
        'image_path': entry.$2,
        'sort_order': entry.$1,
      });
    }
  }

  static Future<void> _upsertCategory(
    DatabaseExecutor executor,
    RecipeCategory category,
  ) {
    return _upsert(
      executor,
      table: 'recipe_categories',
      id: category.id,
      values: _categoryToRow(category),
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

  // ---- 行 → 领域对象（预检哈希用，与快照仓库同构） ----

  static Recipe _recipeFromRows(
    Map<String, Object?> recipeRow,
    List<Map<String, Object?>> childRows,
  ) {
    final ingredients = <Ingredient>[];
    final steps = <RecipeStep>[];
    final categoryIds = <String>[];
    final images = <String>[];
    for (final row in childRows) {
      if (row.containsKey('name') && row.containsKey('sort_order') &&
          !row.containsKey('step_number') &&
          !row.containsKey('image_path')) {
        ingredients.add(_ingredientFromRow(row));
      } else if (row.containsKey('step_number')) {
        steps.add(_stepFromRow(row));
      } else if (row.containsKey('category_id')) {
        categoryIds.add(row['category_id']! as String);
      } else if (row.containsKey('image_path')) {
        images.add(row['image_path']! as String);
      }
    }
    return Recipe(
      id: recipeRow['id']! as String,
      userId: recipeRow['user_id'] as String?,
      title: recipeRow['title']! as String,
      description: recipeRow['description'] as String?,
      coverImage: recipeRow['cover_image'] as String?,
      images: images,
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
      ingredients: ingredients,
      steps: steps,
      categoryIds: categoryIds,
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

  // ---- 工具 ----

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
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
}
