import 'dart:convert';

import '../ingredient/ingredient_spec.dart';
import '../recipe/recipe.dart';

/// 媒体引用（菜谱/分类字段中的图片占位）。
///
/// `sha256` 即媒体资产稳定 ID（mediaAssetId，内容寻址），归档内
/// 真实文件位于 `media/sha256/<ab>/<hash>.<ext>`；排序信息用于恢复时
/// 还原封面顺序。领域层不携带设备绝对路径，保证跨设备可恢复。
class BackupMediaReference {
  const BackupMediaReference({required this.sha256, this.sortOrder});

  final String sha256;

  /// 在所属记录内的排序（recipe_images 的 sort_order；封面可缺省为 0）。
  final int? sortOrder;

  Map<String, Object?> toJson() => <String, Object?>{
    'sha256': sha256,
    if (sortOrder != null) 'sortOrder': sortOrder,
  };

  factory BackupMediaReference.fromJson(Map<String, Object?> json) {
    final sha256 = json['sha256'];
    final sortOrder = json['sortOrder'];
    if (sha256 is! String || !_isSha256(sha256)) {
      throw const FormatException('媒体引用 sha256 非法');
    }
    if (sortOrder != null && (sortOrder is! int || sortOrder < 0)) {
      throw const FormatException('媒体引用 sortOrder 非法');
    }
    return BackupMediaReference(
      sha256: sha256.toLowerCase(),
      sortOrder: sortOrder as int?,
    );
  }
}

/// 媒体索引条目（media/index.v1.ndjson 一行）。
///
/// 记录每个唯一媒体文件的元数据与全部引用位置，导入端据此建立
/// "媒体文件 → 菜谱/分类"的引用关系并支持复用（同哈希不重复导入）。
class BackupMediaIndexEntry {
  const BackupMediaIndexEntry({
    required this.sha256,
    required this.mime,
    required this.byteSize,
    required this.relativeKey,
    this.recipeRefs = const <String>[],
    this.categoryRefs = const <String>[],
  });

  final String sha256;
  final String mime;
  final int byteSize;

  /// 归档内稳定相对存储键（如 `media/sha256/ab/<hash>.jpg`）。
  final String relativeKey;

  /// 引用该媒体的菜谱 ID 列表。
  final List<String> recipeRefs;

  /// 引用该媒体的分类 ID 列表。
  final List<String> categoryRefs;

  Map<String, Object?> toJson() => <String, Object?>{
    'sha256': sha256,
    'mime': mime,
    'byteSize': byteSize,
    'relativeKey': relativeKey,
    'recipeRefs': recipeRefs,
    'categoryRefs': categoryRefs,
  };

  factory BackupMediaIndexEntry.fromJson(Map<String, Object?> json) {
    final sha256 = json['sha256'];
    final mime = json['mime'];
    final byteSize = json['byteSize'];
    final relativeKey = json['relativeKey'];
    final recipeRefs = json['recipeRefs'];
    final categoryRefs = json['categoryRefs'];
    if (sha256 is! String || !_isSha256(sha256)) {
      throw const FormatException('媒体索引 sha256 非法');
    }
    if (mime is! String || mime.trim().isEmpty) {
      throw const FormatException('媒体索引 mime 非法');
    }
    if (byteSize is! int || byteSize < 0) {
      throw const FormatException('媒体索引 byteSize 非法');
    }
    if (relativeKey is! String || relativeKey.trim().isEmpty) {
      throw const FormatException('媒体索引 relativeKey 非法');
    }
    if (recipeRefs is! List<Object?> || recipeRefs.any((ref) => ref is! String)) {
      throw const FormatException('媒体索引 recipeRefs 非法');
    }
    if (categoryRefs is! List<Object?> ||
        categoryRefs.any((ref) => ref is! String)) {
      throw const FormatException('媒体索引 categoryRefs 非法');
    }
    return BackupMediaIndexEntry(
      sha256: sha256.toLowerCase(),
      mime: mime,
      byteSize: byteSize,
      relativeKey: relativeKey,
      recipeRefs: recipeRefs.cast<String>(),
      categoryRefs: categoryRefs.cast<String>(),
    );
  }
}

/// 菜谱备份记录（data/recipes.v1.ndjson 一行）。
///
/// 内容为完整菜谱快照 + 媒体引用，涵盖正式、草稿、归档和回收站
/// （deletedAt 非空即回收站软删除），与 SQLite 表结构解耦。
class RecipeBackupRecord {
  const RecipeBackupRecord({
    required this.id,
    this.userId,
    required this.title,
    this.description,
    this.coverImage,
    this.images = const <BackupMediaReference>[],
    this.servings,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.totalTimeMinutes,
    this.difficulty = RecipeDifficulty.unspecified,
    this.notes,
    this.favorite = false,
    this.status = RecipeStatus.draft,
    this.sourceId,
    this.ingredients = const <Ingredient>[],
    this.steps = const <RecipeStep>[],
    this.categoryIds = const <String>[],
    this.tags = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    this.localVersion = 1,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final String title;
  final String? description;
  final BackupMediaReference? coverImage;
  final List<BackupMediaReference> images;
  final int? servings;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final int? totalTimeMinutes;
  final RecipeDifficulty difficulty;
  final String? notes;
  final bool favorite;
  final RecipeStatus status;
  final String? sourceId;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  final List<String> categoryIds;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    if (userId != null) 'userId': userId,
    'title': title,
    if (description != null) 'description': description,
    if (coverImage != null) 'coverImage': coverImage!.toJson(),
    'images': images.map((image) => image.toJson()).toList(),
    if (servings != null) 'servings': servings,
    if (prepTimeMinutes != null) 'prepTimeMinutes': prepTimeMinutes,
    if (cookTimeMinutes != null) 'cookTimeMinutes': cookTimeMinutes,
    if (totalTimeMinutes != null) 'totalTimeMinutes': totalTimeMinutes,
    'difficulty': difficulty.wireName,
    if (notes != null) 'notes': notes,
    'favorite': favorite,
    'status': status.wireName,
    if (sourceId != null) 'sourceId': sourceId,
    'ingredients': ingredients.map(_ingredientToJson).toList(),
    'steps': steps.map(_stepToJson).toList(),
    'categoryIds': categoryIds,
    'tags': tags,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'localVersion': localVersion,
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  String encodeNdjson() => const JsonEncoder().convert(toJson());

  /// 从备份 NDJSON 行严格解析（字段类型、枚举与范围非法时抛异常）。
  factory RecipeBackupRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final userId = json['userId'];
    final title = json['title'];
    final description = json['description'];
    final coverImage = json['coverImage'];
    final images = json['images'];
    final servings = json['servings'];
    final prep = json['prepTimeMinutes'];
    final cook = json['cookTimeMinutes'];
    final total = json['totalTimeMinutes'];
    final difficulty = json['difficulty'];
    final notes = json['notes'];
    final favorite = json['favorite'];
    final status = json['status'];
    final sourceId = json['sourceId'];
    final ingredients = json['ingredients'];
    final steps = json['steps'];
    final categoryIds = json['categoryIds'];
    final tags = json['tags'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    final localVersion = json['localVersion'];
    final deletedAt = json['deletedAt'];

    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('菜谱 ID 缺失');
    }
    if (userId != null && userId is! String) {
      throw const FormatException('菜谱 userId 非法');
    }
    if (title is! String || title.trim().isEmpty) {
      throw const FormatException('菜谱标题缺失');
    }
    if (description != null && description is! String) {
      throw const FormatException('菜谱描述非法');
    }
    if (coverImage != null) {
      if (coverImage is! Map<Object?, Object?>) {
        throw const FormatException('菜谱 coverImage 非法');
      }
    }
    if (images is! List<Object?>) {
      throw const FormatException('菜谱 images 非法');
    }
    for (final value in <Object?>[servings, prep, cook, total, localVersion]) {
      if (value != null && value is! int) {
        throw const FormatException('菜谱数值字段非法');
      }
    }
    if (localVersion is int && localVersion < 1) {
      throw const FormatException('菜谱 localVersion 非法');
    }
    if (difficulty is! String) {
      throw const FormatException('菜谱难度缺失');
    }
    if (notes != null && notes is! String) {
      throw const FormatException('菜谱 notes 非法');
    }
    if (favorite is! bool) {
      throw const FormatException('菜谱收藏状态非法');
    }
    if (status is! String) {
      throw const FormatException('菜谱状态缺失');
    }
    if (sourceId != null && sourceId is! String) {
      throw const FormatException('菜谱来源非法');
    }
    if (ingredients is! List<Object?>) {
      throw const FormatException('菜谱食材非法');
    }
    if (steps is! List<Object?>) {
      throw const FormatException('菜谱步骤非法');
    }
    if (categoryIds is! List<Object?> ||
        categoryIds.any((item) => item is! String)) {
      throw const FormatException('菜谱分类关系非法');
    }
    if (tags is! List<Object?> || tags.any((item) => item is! String)) {
      throw const FormatException('菜谱标签非法');
    }
    if (createdAt is! String || updatedAt is! String) {
      throw const FormatException('菜谱时间字段缺失');
    }
    if (deletedAt != null && deletedAt is! String) {
      throw const FormatException('菜谱软删除时间非法');
    }

    return RecipeBackupRecord(
      id: id,
      userId: userId as String?,
      title: title,
      description: description as String?,
      coverImage: coverImage == null
          ? null
          : BackupMediaReference.fromJson(
              (coverImage as Map<Object?, Object?>).cast<String, Object?>(),
            ),
      images: images
          .map((item) => BackupMediaReference.fromJson(
              (item as Map<Object?, Object?>).cast<String, Object?>()))
          .toList(),
      servings: servings as int?,
      prepTimeMinutes: prep as int?,
      cookTimeMinutes: cook as int?,
      totalTimeMinutes: total as int?,
      difficulty: RecipeDifficulty.fromWireName(difficulty),
      notes: notes as String?,
      favorite: favorite,
      status: RecipeStatus.fromWireName(status),
      sourceId: sourceId as String?,
      ingredients: ingredients
          .map((item) => _ingredientFromJson(
              (item as Map<Object?, Object?>).cast<String, Object?>()))
          .toList(),
      steps: steps
          .map((item) => _stepFromJson(
              (item as Map<Object?, Object?>).cast<String, Object?>()))
          .toList(),
      categoryIds: categoryIds.cast<String>(),
      tags: tags.cast<String>(),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      localVersion: localVersion as int? ?? 1,
      deletedAt: deletedAt == null ? null : DateTime.parse(deletedAt as String),
    );
  }
}

/// 分类备份记录（data/categories.v1.ndjson 一行），含空分类。
class CategoryBackupRecord {
  const CategoryBackupRecord({
    required this.id,
    this.userId,
    required this.name,
    this.coverImage,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.localVersion = 1,
    this.deletedAt,
  });

  final String id;
  final String? userId;
  final String name;
  final BackupMediaReference? coverImage;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 1,
    'id': id,
    if (userId != null) 'userId': userId,
    'name': name,
    if (coverImage != null) 'coverImage': coverImage!.toJson(),
    'sortOrder': sortOrder,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'localVersion': localVersion,
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  String encodeNdjson() => const JsonEncoder().convert(toJson());

  factory CategoryBackupRecord.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final userId = json['userId'];
    final name = json['name'];
    final coverImage = json['coverImage'];
    final sortOrder = json['sortOrder'];
    final createdAt = json['createdAt'];
    final updatedAt = json['updatedAt'];
    final localVersion = json['localVersion'];
    final deletedAt = json['deletedAt'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('分类 ID 缺失');
    }
    if (userId != null && userId is! String) {
      throw const FormatException('分类 userId 非法');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('分类名称缺失');
    }
    if (coverImage != null && coverImage is! Map<Object?, Object?>) {
      throw const FormatException('分类 coverImage 非法');
    }
    if (sortOrder is! int || sortOrder < 0) {
      throw const FormatException('分类排序非法');
    }
    if (localVersion is! int || localVersion < 1) {
      throw const FormatException('分类 localVersion 非法');
    }
    if (createdAt is! String || updatedAt is! String) {
      throw const FormatException('分类时间字段缺失');
    }
    if (deletedAt != null && deletedAt is! String) {
      throw const FormatException('分类软删除时间非法');
    }
    return CategoryBackupRecord(
      id: id,
      userId: userId as String?,
      name: name,
      coverImage: coverImage == null
          ? null
          : BackupMediaReference.fromJson(
              (coverImage as Map<Object?, Object?>).cast<String, Object?>(),
            ),
      sortOrder: sortOrder,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      localVersion: localVersion,
      deletedAt: deletedAt == null ? null : DateTime.parse(deletedAt as String),
    );
  }
}

/// 食材序列化（与 SQLite 列一一对应，枚举走 wireName）。
Map<String, Object?> _ingredientToJson(Ingredient ingredient) =>
    <String, Object?>{
      'id': ingredient.id,
      if (ingredient.groupName != null) 'groupName': ingredient.groupName,
      'name': ingredient.name,
      if (ingredient.quantity != null) 'quantity': ingredient.quantity,
      if (ingredient.unit != null) 'unit': ingredient.unit,
      'optional': ingredient.optional,
      if (ingredient.preparation != null)
        'preparation': ingredient.preparation,
      'substitutes': ingredient.substitutes,
      'sortOrder': ingredient.sortOrder,
      if (ingredient.confidence != null) 'confidence': ingredient.confidence,
      if (ingredient.baseConceptId != null)
        'baseConceptId': ingredient.baseConceptId,
      if (ingredient.baseConceptName != null)
        'baseConceptName': ingredient.baseConceptName,
      if (ingredient.cut != null) 'cut': ingredient.cut!.wireName,
      if (ingredient.fatLevel != null) 'fatLevel': ingredient.fatLevel!.wireName,
      if (ingredient.form != null) 'form': ingredient.form!.wireName,
      if (ingredient.processing != null)
        'processing': ingredient.processing!.wireName,
      if (ingredient.specConfidence != null)
        'specConfidence': ingredient.specConfidence,
      'specSource': ingredient.specSource.wireName,
      'importance': ingredient.importance.wireName,
    };

Ingredient _ingredientFromJson(Map<String, Object?> json) {
  final id = json['id'];
  final name = json['name'];
  final sortOrder = json['sortOrder'];
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('食材 ID 缺失');
  }
  if (name is! String || name.trim().isEmpty) {
    throw const FormatException('食材名称缺失');
  }
  if (sortOrder is! int || sortOrder < 0) {
    throw const FormatException('食材排序非法');
  }
  final substitutes = json['substitutes'];
  if (substitutes is! List<Object?> ||
      substitutes.any((item) => item is! String)) {
    throw const FormatException('食材替代品非法');
  }
  final confidence = json['confidence'];
  final specConfidence = json['specConfidence'];
  if (confidence != null && confidence is! num) {
    throw const FormatException('食材置信度非法');
  }
  if (specConfidence != null && specConfidence is! num) {
    throw const FormatException('食材规格置信度非法');
  }
  return Ingredient(
    id: id,
    name: name,
    groupName: json['groupName'] as String?,
    quantity: json['quantity'] as String?,
    unit: json['unit'] as String?,
    optional: json['optional'] as bool? ?? false,
    preparation: json['preparation'] as String?,
    substitutes: substitutes.cast<String>(),
    sortOrder: sortOrder,
    confidence: (confidence as num?)?.toDouble(),
    baseConceptId: json['baseConceptId'] as String?,
    baseConceptName: json['baseConceptName'] as String?,
    cut: _nullableWireEnum(json['cut'], IngredientCut.fromWireName),
    fatLevel: _nullableWireEnum(
      json['fatLevel'],
      IngredientFatLevel.fromWireName,
    ),
    form: _nullableWireEnum(json['form'], IngredientForm.fromWireName),
    processing: _nullableWireEnum(
      json['processing'],
      IngredientProcessing.fromWireName,
    ),
    specConfidence: (specConfidence as num?)?.toDouble(),
    specSource: IngredientSpecSource.fromWireName(
      json['specSource'] as String?,
    ),
    // importance 的 fromWireName 只接受非空字符串，缺失/非法时回退必需。
    importance: json['importance'] is String
        ? IngredientImportance.fromWireName(json['importance'] as String)
        : IngredientImportance.required,
  );
}

Map<String, Object?> _stepToJson(RecipeStep step) => <String, Object?>{
  'id': step.id,
  'stepNumber': step.stepNumber,
  'description': step.description,
  if (step.durationSeconds != null) 'durationSeconds': step.durationSeconds,
  if (step.temperature != null) 'temperature': step.temperature,
  if (step.heatLevel != null) 'heatLevel': step.heatLevel,
  if (step.cookware != null) 'cookware': step.cookware,
  if (step.tips != null) 'tips': step.tips,
  if (step.mediaUrl != null) 'mediaUrl': step.mediaUrl,
  if (step.confidence != null) 'confidence': step.confidence,
};

RecipeStep _stepFromJson(Map<String, Object?> json) {
  final id = json['id'];
  final stepNumber = json['stepNumber'];
  final description = json['description'];
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('步骤 ID 缺失');
  }
  if (stepNumber is! int || stepNumber <= 0) {
    throw const FormatException('步骤序号非法');
  }
  if (description is! String || description.trim().isEmpty) {
    throw const FormatException('步骤说明缺失');
  }
  final duration = json['durationSeconds'];
  if (duration != null && duration is! int) {
    throw const FormatException('步骤时长非法');
  }
  final confidence = json['confidence'];
  if (confidence != null && confidence is! num) {
    throw const FormatException('步骤置信度非法');
  }
  return RecipeStep(
    id: id,
    stepNumber: stepNumber,
    description: description,
    durationSeconds: duration as int?,
    temperature: json['temperature'] as String?,
    heatLevel: json['heatLevel'] as String?,
    cookware: json['cookware'] as String?,
    tips: json['tips'] as String?,
    mediaUrl: json['mediaUrl'] as String?,
    confidence: (confidence as num?)?.toDouble(),
  );
}

/// 可空枚举解析：值缺失或无法识别时返回 null（规格未知，符合领域语义）。
T? _nullableWireEnum<T>(Object? value, T? Function(String?) fromWire) {
  if (value is! String) return null;
  return fromWire(value);
}

bool _isSha256(String value) {
  final trimmed = value.toLowerCase();
  return trimmed.length == 64 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(trimmed);
}
