import '../ingredient/ingredient_spec.dart';

enum RecipeStatus {
  draft('draft'),
  published('published'),
  archived('archived');
  const RecipeStatus(this.wireName);

  final String wireName;

  static RecipeStatus fromWireName(String value) {
    return RecipeStatus.values.firstWhere(
      (status) => status.wireName == value,
      orElse: () => throw FormatException('未知菜谱状态：$value'),
    );
  }
}

enum RecipeDifficulty {
  unspecified('unspecified'),
  easy('easy'),
  medium('medium'),
  hard('hard');

  const RecipeDifficulty(this.wireName);

  final String wireName;

  static RecipeDifficulty fromWireName(String value) {
    return RecipeDifficulty.values.firstWhere(
      (difficulty) => difficulty.wireName == value,
      orElse: () => throw FormatException('未知菜谱难度：$value'),
    );
  }
}

/// 菜谱食材要求强度（ADR-0023）。
enum IngredientImportance {
  /// 菜名中的核心食材，缺少时明确计入缺失。
  core('core', '核心'),

  /// 必需食材（默认），缺少时计入缺失。
  required('required', '必需'),

  /// 可选/按个人口味，不计入缺失。
  optional('optional', '可选');

  const IngredientImportance(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientImportance fromWireName(String value) {
    return IngredientImportance.values.firstWhere(
      (importance) => importance.wireName == value,
      orElse: () => IngredientImportance.required,
    );
  }
}

class Ingredient {
  Ingredient({
    required this.id,
    required this.name,
    this.groupName,
    this.quantity,
    this.unit,
    this.optional = false,
    this.preparation,
    List<String> substitutes = const <String>[],
    required this.sortOrder,
    this.confidence,
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specConfidence,
    this.specSource = IngredientSpecSource.unknown,
    this.importance = IngredientImportance.required,
  }) : substitutes = List<String>.unmodifiable(substitutes) {
    _requireNonEmpty(id, '食材 ID');
    _requireNonEmpty(name, '食材名称');
    if (sortOrder < 0) {
      throw const FormatException('食材排序不能小于 0');
    }
    _validateConfidence(confidence, '食材置信度');
    _validateConfidence(specConfidence, '食材规格置信度');
  }

  final String id;
  final String? groupName;
  final String name;
  final String? quantity;
  final String? unit;
  final bool optional;
  final String? preparation;
  final List<String> substitutes;
  final int sortOrder;
  final double? confidence;

  // ---- 渐进式语义食材系统（ADR-0022）：菜谱侧解析出的规格 ----
  /// 基础食材稳定 ID（如 ingredient.pork）；null 表示未识别/未解析。
  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;

  /// 规格解析置信度（本地规则解析 ≈0.9，用户确认 =1.0，未知 =0）。
  final double? specConfidence;

  /// 规格来源（localRule / user / unknown）。
  final IngredientSpecSource specSource;

  /// 要求强度（ADR-0023）：core 菜名核心 / required 必需 / optional 可选。
  final IngredientImportance importance;

  /// 该食材在菜谱侧要求的规格（规格可能未知）。
  IngredientSpec get requirementSpec => IngredientSpec(
    baseConceptId: baseConceptId,
    baseConceptName: baseConceptName,
    cut: cut,
    fatLevel: fatLevel,
    form: form,
    processing: processing,
  );
}

class RecipeStep {
  RecipeStep({
    required this.id,
    required this.stepNumber,
    required this.description,
    this.durationSeconds,
    this.temperature,
    this.heatLevel,
    this.cookware,
    this.tips,
    this.mediaUrl,
    this.confidence,
  }) {
    _requireNonEmpty(id, '步骤 ID');
    _requireNonEmpty(description, '步骤说明');
    if (stepNumber <= 0) {
      throw const FormatException('步骤序号必须大于 0');
    }
    if (durationSeconds != null && durationSeconds! < 0) {
      throw const FormatException('步骤时长不能小于 0');
    }
    _validateConfidence(confidence, '步骤置信度');
  }

  final String id;
  final int stepNumber;
  final String description;
  final int? durationSeconds;
  final String? temperature;
  final String? heatLevel;
  final String? cookware;
  final String? tips;
  final String? mediaUrl;
  final double? confidence;
}

class Recipe {
  Recipe({
    required this.id,
    this.userId,
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
    this.sourceId,
    List<Ingredient> ingredients = const <Ingredient>[],
    List<RecipeStep> steps = const <RecipeStep>[],
    List<String> categoryIds = const <String>[],
    List<String> tags = const <String>[],
    required this.createdAt,
    required this.updatedAt,
    this.localVersion = 1,
    this.deletedAt,
  }) : images = List<String>.unmodifiable(images),
       ingredients = List<Ingredient>.unmodifiable(ingredients),
       steps = List<RecipeStep>.unmodifiable(steps),
       categoryIds = List<String>.unmodifiable(categoryIds),
       tags = List<String>.unmodifiable(tags) {
    _requireNonEmpty(id, '菜谱 ID');
    _requireNonEmpty(title, '菜谱名称');
    _validateNonNegative(servings, '份量');
    _validateNonNegative(prepTimeMinutes, '准备时间');
    _validateNonNegative(cookTimeMinutes, '烹饪时间');
    _validateNonNegative(totalTimeMinutes, '总时间');
    if (localVersion <= 0) {
      throw const FormatException('本地版本必须大于 0');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException('更新时间不能早于创建时间');
    }
    if (images.any((image) => image.trim().isEmpty)) {
      throw const FormatException('菜谱封面图片路径不能为空');
    }
    if (images.toSet().length != images.length) {
      throw const FormatException('同一菜谱的封面图片不能重复');
    }
    if (ingredients.map((item) => item.id).toSet().length !=
        ingredients.length) {
      throw const FormatException('同一菜谱内的食材 ID 不能重复');
    }
    if (steps.map((item) => item.id).toSet().length != steps.length) {
      throw const FormatException('同一菜谱内的步骤 ID 不能重复');
    }
    if (steps.map((item) => item.stepNumber).toSet().length != steps.length) {
      throw const FormatException('同一菜谱内的步骤序号不能重复');
    }
    if (categoryIds.toSet().length != categoryIds.length) {
      throw const FormatException('同一菜谱不能重复关联分类');
    }
    if (tags.any((tag) => tag.trim().isEmpty)) {
      throw const FormatException('Recipe tags must not be empty.');
    }
    if (tags.toSet().length != tags.length) {
      throw const FormatException('Recipe tags must be unique.');
    }
  }

  final String id;
  final String? userId;
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
  final String? sourceId;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  final List<String> categoryIds;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;
}

/// 菜谱列表排序方式（解决方案.md 第三节：列表按 SQL 排序 + 游标分页，
/// 不再把全部菜谱读出来后在前端排序）。
enum RecipeSort {
  /// 最近更新（updated_at DESC, id DESC）。
  updated,

  /// 创建时间（created_at DESC, id DESC）。
  created,

  /// 名称（title COLLATE NOCASE ASC, id ASC）。
  title,
}

/// 菜谱列表分页游标（keyset pagination）。
///
/// 只携带上一页最后一条的排序键与 id，下一页通过比较条件继续读取，
/// 避免数据量增大后 OFFSET 越来越慢。
class RecipeCursor {
  const RecipeCursor({this.timestamp, this.title, required this.id});

  /// updated/created 排序下的游标时间（毫秒精度）。
  final DateTime? timestamp;

  /// title 排序下的游标标题。
  final String? title;

  /// 上一页最后一条菜谱的 id（同键时按 id 继续）。
  final String id;
}

/// 菜谱列表摘要（解决方案.md 第一节）。
///
/// 列表页只读取卡片所需字段：标题、封面、收藏状态、烹饪时间、难度、
/// 食材数量、更新时间；详情页打开时才调用完整聚合读取方法，
/// 避免一次读取全部步骤、食材与图片关系。
class RecipeSummary {
  RecipeSummary({
    required this.id,
    required this.title,
    this.coverImage,
    this.favorite = false,
    this.totalTimeMinutes,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.servings,
    this.difficulty = RecipeDifficulty.unspecified,
    this.sourceId,
    this.ingredientCount = 0,
    List<String> tags = const <String>[],
    required this.updatedAt,
    this.status = RecipeStatus.draft,
  }) : tags = List<String>.unmodifiable(tags);

  final String id;
  final String title;
  final String? coverImage;
  final bool favorite;
  final int? totalTimeMinutes;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final int? servings;
  final RecipeDifficulty difficulty;
  final String? sourceId;

  /// 食材数量（用于卡片"X 种食材"展示）。
  final int ingredientCount;

  final List<String> tags;
  final DateTime updatedAt;
  final RecipeStatus status;
}

/// 一页菜谱列表摘要（keyset pagination 返回体）。
class RecipeSummaryPage {
  const RecipeSummaryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<RecipeSummary> items;

  /// 是否还有下一页。
  final bool hasMore;

  /// 下一页游标（hasMore 为 true 时非空）。
  final RecipeCursor? nextCursor;
}

/// 回收站菜谱摘要（轻量读取，避免 N+1 全量加载）。
///
/// 回收站列表只需要标题与删除时间，无需加载食材、步骤、分类与图片；
/// 单条 SQL 一次返回全部条目，替代 `listRecipes` 的"逐条全量加载"。
class TrashRecipeSummary {
  const TrashRecipeSummary({
    required this.id,
    required this.title,
    required this.deletedAt,
  });

  final String id;
  final String title;
  final DateTime deletedAt;
}

class RecipeCategory {
  RecipeCategory({
    required this.id,
    this.userId,
    required this.name,
    this.coverImage,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.localVersion = 1,
    this.deletedAt,
  }) {
    _requireNonEmpty(id, '分类 ID');
    _requireNonEmpty(name, '分类名称');
    if (sortOrder < 0) {
      throw const FormatException('分类排序不能小于 0');
    }
    if (localVersion <= 0) {
      throw const FormatException('本地版本必须大于 0');
    }
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException('更新时间不能早于创建时间');
    }
  }

  final String id;
  final String? userId;
  final String name;
  final String? coverImage;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;
}

void _requireNonEmpty(String value, String fieldName) {
  if (value.trim().isEmpty) {
    throw FormatException('$fieldName不能为空');
  }
}

void _validateNonNegative(int? value, String fieldName) {
  if (value != null && value < 0) {
    throw FormatException('$fieldName不能小于 0');
  }
}

void _validateConfidence(double? value, String fieldName) {
  if (value != null && (value < 0 || value > 1)) {
    throw FormatException('$fieldName必须在 0 到 1 之间');
  }
}
