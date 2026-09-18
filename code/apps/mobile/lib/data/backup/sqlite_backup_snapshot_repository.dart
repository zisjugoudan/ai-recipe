import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/backup/backup_cancellation_token.dart';
import 'package:ai_recipe/domain/backup/backup_errors.dart';
import 'package:ai_recipe/domain/backup/backup_repository.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:crypto/crypto.dart';

/// SQLite 一致性快照读取实现（BACKUP-002）。
///
/// 在单个事务内读取全部菜谱（含软删除）、分类（含空分类与软删除）、
/// 图片关系、食材、步骤与分类关系，保证快照来自同一时间点；
/// 媒体哈希计算与可读性校验在导出用例中逐文件执行。
class SqliteBackupSnapshotRepository implements BackupSnapshotRepository {
  SqliteBackupSnapshotRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<BackupSnapshot> loadSnapshot({BackupCancellationToken? token}) async {
    final database = await _appDatabase.database;
    return database.transaction((transaction) async {
      token?.throwIfCancelled();

      // 全部菜谱（含回收站软删除）。
      final recipeRows = await transaction.query(
        'recipes',
        orderBy: 'id ASC',
      );
      // 全部分类（含空分类与软删除）。
      final categoryRows = await transaction.query(
        'recipe_categories',
        orderBy: 'id ASC',
      );
      // 图片关系、食材、步骤与分类关系按主体排序，便于一次遍历分组。
      final imageRows = await transaction.query(
        'recipe_images',
        orderBy: 'recipe_id ASC, sort_order ASC',
      );
      final relationRows = await transaction.query(
        'recipe_category_relations',
        orderBy: 'recipe_id ASC, category_id ASC',
      );
      final ingredientRows = await transaction.query(
        'ingredients',
        orderBy: 'recipe_id ASC, sort_order ASC, id ASC',
      );
      final stepRows = await transaction.query(
        'recipe_steps',
        orderBy: 'recipe_id ASC, step_number ASC, id ASC',
      );

      // 按 recipe_id 分组（sqflite 查询结果已按 recipe_id 排序，顺序分组）。
      final ingredientsByRecipe = _groupBy<String, Map<String, Object?>>(
        ingredientRows,
        (row) => row['recipe_id']! as String,
      );
      final stepsByRecipe = _groupBy<String, Map<String, Object?>>(
        stepRows,
        (row) => row['recipe_id']! as String,
      );
      final relationsByRecipe = _groupBy<String, Map<String, Object?>>(
        relationRows,
        (row) => row['recipe_id']! as String,
      );
      final imagesByRecipe = _groupBy<String, Map<String, Object?>>(
        imageRows,
        (row) => row['recipe_id']! as String,
      );

      final recipes = <Recipe>[];
      final media = <BackupSnapshotMedia>[];
      for (final row in recipeRows) {
        token?.throwIfCancelled();
        final id = row['id']! as String;
        final recipe = _recipeFromRows(
          row,
          ingredientsByRecipe[id] ?? const <Map<String, Object?>>[],
          stepsByRecipe[id] ?? const <Map<String, Object?>>[],
          relationsByRecipe[id] ?? const <Map<String, Object?>>[],
          imagesByRecipe[id] ?? const <Map<String, Object?>>[],
        );
        recipes.add(recipe);
        _collectRecipeMedia(recipe, media);
      }

      final categories = <RecipeCategory>[];
      for (final row in categoryRows) {
        token?.throwIfCancelled();
        final category = _categoryFromRow(row);
        categories.add(category);
        final coverImage = category.coverImage;
        if (coverImage != null && coverImage.trim().isNotEmpty) {
          media.add(
            BackupSnapshotMedia(
              sourcePath: coverImage,
              role: BackupMediaRole.categoryCover,
              ownerId: category.id,
            ),
          );
        }
      }

      return BackupSnapshot(
        recipes: recipes,
        categories: categories,
        media: media,
      );
    });
  }

  @override
  Future<int> mediaFileSize(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw BackupException(
        BackupErrorCode.mediaMissing,
        '必需图片不存在：$sourcePath',
      );
    }
    try {
      return await file.length();
    } on FileSystemException {
      throw BackupException(
        BackupErrorCode.mediaUnreadable,
        '必需图片无法读取：$sourcePath',
      );
    }
  }

  @override
  Future<String> hashMediaFile(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw BackupException(
        BackupErrorCode.mediaMissing,
        '必需图片不存在：$sourcePath',
      );
    }
    try {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } on FileSystemException {
      throw BackupException(
        BackupErrorCode.mediaUnreadable,
        '必需图片无法读取：$sourcePath',
      );
    }
  }

  @override
  Future<Uint8List> readMediaBytes(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw BackupException(
        BackupErrorCode.mediaMissing,
        '必需图片不存在：$sourcePath',
      );
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      throw BackupException(
        BackupErrorCode.mediaUnreadable,
        '必需图片无法读取：$sourcePath',
      );
    }
  }

  /// 收集菜谱的封面与画廊图引用（封面与画廊重复引用同一路径时
  /// 各保留一次，去重由导出用例按 sha256 聚合）。
  static void _collectRecipeMedia(Recipe recipe, List<BackupSnapshotMedia> media) {
    final cover = recipe.coverImage;
    if (cover != null && cover.trim().isNotEmpty) {
      media.add(
        BackupSnapshotMedia(
          sourcePath: cover,
          role: BackupMediaRole.cover,
          ownerId: recipe.id,
        ),
      );
    }
    for (final entry in recipe.images.indexed) {
      final imagePath = entry.$2;
      if (imagePath.trim().isEmpty) continue;
      media.add(
        BackupSnapshotMedia(
          sourcePath: imagePath,
          role: BackupMediaRole.gallery,
          ownerId: recipe.id,
          sortOrder: entry.$1,
        ),
      );
    }
  }

  /// 由原始行组装菜谱领域对象（与 sqlite_recipe_repository 同一映射，
  /// 备份模块独立维护以保持"备份格式与仓库实现解耦"）。
  static Recipe _recipeFromRows(
    Map<String, Object?> recipeRow,
    List<Map<String, Object?>> ingredientRows,
    List<Map<String, Object?>> stepRows,
    List<Map<String, Object?>> relationRows,
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
      categoryIds: relationRows
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

  /// 按键顺序分组（输入行已按键排序，直接累积，保持组内顺序）。
  static Map<K, List<Map<String, Object?>>> _groupBy<K, T>(
    List<Map<String, Object?>> rows,
    K Function(Map<String, Object?>) keyOf,
  ) {
    final result = <K, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final key = keyOf(row);
      result.putIfAbsent(key, () => <Map<String, Object?>>[]).add(row);
    }
    return result;
  }

  static List<String> _decodeStringList(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <String>[];
    return decoded.whereType<String>().toList(growable: false);
  }

  static DateTime _fromEpoch(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static DateTime? _nullableFromEpoch(int? value) =>
      value == null ? null : _fromEpoch(value);
}
