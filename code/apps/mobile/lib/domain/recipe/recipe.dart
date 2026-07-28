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
  }) : substitutes = List<String>.unmodifiable(substitutes) {
    _requireNonEmpty(id, '食材 ID');
    _requireNonEmpty(name, '食材名称');
    if (sortOrder < 0) {
      throw const FormatException('食材排序不能小于 0');
    }
    _validateConfidence(confidence, '食材置信度');
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
    required this.createdAt,
    required this.updatedAt,
    this.localVersion = 1,
    this.deletedAt,
  }) : ingredients = List<Ingredient>.unmodifiable(ingredients),
       steps = List<RecipeStep>.unmodifiable(steps),
       categoryIds = List<String>.unmodifiable(categoryIds) {
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
  }

  final String id;
  final String? userId;
  final String title;
  final String? description;
  final String? coverImage;
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
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;
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
