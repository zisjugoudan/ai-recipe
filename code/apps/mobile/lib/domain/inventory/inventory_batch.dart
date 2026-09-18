import '../ingredient/ingredient_canonicalizer.dart';
import '../ingredient/ingredient_spec.dart';
import '../recipe/recipe.dart';

/// 库存存放区域（产品 5.8.1：冷藏、冷冻、常温、其他）。
enum InventoryZone {
  chilled,
  frozen,
  roomTemperature,
  other;

  static InventoryZone fromWireName(String value) {
    return InventoryZone.values.firstWhere(
      (zone) => zone.name == value,
      orElse: () => throw FormatException('未知存放区域：$value'),
    );
  }
}

/// 批次底层生命周期状态（产品 8.13：available/used_up/discarded）。
enum InventoryBatchStatus {
  available,
  usedUp,
  discarded;

  static InventoryBatchStatus fromWireName(String value) {
    return InventoryBatchStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw FormatException('未知批次状态：$value'),
    );
  }
}

/// 库存变更类型（产品 8.14：create/adjust/consume/used_up/discard）。
enum InventoryChangeType {
  create,
  adjust,
  consume,
  usedUp,
  discard;

  static InventoryChangeType fromWireName(String value) {
    return InventoryChangeType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw FormatException('未知库存变更类型：$value'),
    );
  }
}

/// 界面展示的食材状态（由到期日与数量派生，不单独存储）。
enum InventoryItemCondition {
  normal,
  soonExpiring,
  expired,
  noDate,
  unknownQuantity,
}

/// 库存批次（产品 8.13 InventoryBatch）。
///
/// 底层按批次存储；同名食材允许存在多个批次，界面可聚合展示，
/// 但编辑、扣减和丢弃必须定位到具体批次。
class InventoryBatch {
  InventoryBatch({
    required this.id,
    required this.ingredientName,
    this.normalizedIngredientName,
    this.quantity,
    this.unit,
    this.category,
    required this.zone,
    this.purchasedAt,
    this.expiresAt,
    this.note,
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specSource = IngredientSpecSource.unknown,
    this.sortOrder = 0,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.localVersion,
    this.deletedAt,
  }) {
    _requireNonEmpty(id, '批次 ID');
    _requireNonEmpty(ingredientName, '食材名称');
  }

  static const int soonExpiryDays = 3;

  final String id;
  final String ingredientName;
  final String? normalizedIngredientName;

  /// 数量，可为空；为空表示“数量未知”，不得默认写 0。
  final double? quantity;
  final String? unit;
  final String? category;
  final InventoryZone zone;
  final DateTime? purchasedAt;
  final DateTime? expiresAt;
  final String? note;

  // ---- 渐进式语义食材系统（ADR-0022）：批次实际规格 ----
  /// 基础食材稳定 ID（如 ingredient.pork）；null 表示规格未设置/未识别。
  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;

  /// 规格来源（用户选择 / 本地规则 / 未知）。
  final IngredientSpecSource specSource;

  /// 分区内排序权重（长按拖动排序用；数值越小越靠前）。
  final int sortOrder;

  final InventoryBatchStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int localVersion;
  final DateTime? deletedAt;

  bool get isAvailable => status == InventoryBatchStatus.available;

  /// 数量为空表示“数量未知”。
  bool get hasUnknownQuantity => quantity == null;

  /// 批次的实际规格（规格未设置时各属性为 null）。
  IngredientSpec get spec => IngredientSpec(
    baseConceptId: baseConceptId,
    baseConceptName: baseConceptName,
    cut: cut,
    fatLevel: fatLevel,
    form: form,
    processing: processing,
  );

  /// 是否已经设置了基础食材规格。
  bool get hasSpecifiedBase => baseConceptId != null;

  /// 派生食材状态（正常/临期/已过期/未设置日期/数量未知）。
  InventoryItemCondition conditionOn(DateTime now) {
    if (status != InventoryBatchStatus.available) {
      return InventoryItemCondition.normal;
    }
    final expiresAtValue = expiresAt;
    if (expiresAtValue != null) {
      final day = DateTime(now.year, now.month, now.day);
      final expiryDay = DateTime(
        expiresAtValue.year,
        expiresAtValue.month,
        expiresAtValue.day,
      );
      if (expiryDay.isBefore(day)) return InventoryItemCondition.expired;
      if (expiryDay
          .isBefore(day.add(const Duration(days: soonExpiryDays + 1)))) {
        return InventoryItemCondition.soonExpiring;
      }
      return InventoryItemCondition.normal;
    }
    if (quantity == null) return InventoryItemCondition.unknownQuantity;
    return InventoryItemCondition.noDate;
  }

  static void _requireNonEmpty(String value, String label) {
    if (value.trim().isEmpty) {
      throw ArgumentError('$label不能为空。');
    }
  }
}

/// 库存变更记录（产品 8.14 InventoryChange）。
class InventoryChange {
  InventoryChange({
    required this.id,
    required this.batchId,
    required this.changeType,
    this.quantityDelta,
    this.unit,
    this.relatedRecipeId,
    required this.confirmedByUser,
    required this.createdAt,
  });

  final String id;
  final String batchId;
  final InventoryChangeType changeType;
  final double? quantityDelta;
  final String? unit;
  final String? relatedRecipeId;
  final bool confirmedByUser;
  final DateTime createdAt;
}

/// 库存摘要（冰箱页顶部四项统计）。
class InventorySummary {
  const InventorySummary({
    required this.availableBatches,
    required this.soonExpiring,
    required this.expired,
    required this.unknownQuantity,
  });

  final int availableBatches;
  final int soonExpiring;
  final int expired;
  final int unknownQuantity;
}

/// 按名称聚合后的库存条目（UI 食材 chip）。
class AggregatedInventoryItem {
  const AggregatedInventoryItem({
    required this.ingredientName,
    required this.zone,
    required this.batches,
    required this.condition,
  });

  final String ingredientName;
  final InventoryZone zone;
  final List<InventoryBatch> batches;

  /// 聚合条目整体状态：优先取最早到期/最严重的批次状态。
  final InventoryItemCondition condition;

  int get batchCount => batches.length;

  /// 稳定身份：所属批次 ID 集合排序后的串联。
  ///
  /// 用于长按拖拽/冷冻动画事件的唯一识别——同名多批次、批次重命名、
  /// 页面重建都不会让事件串到错误的食材上；不用显示名称或列表下标。
  String get stableId {
    final ids = batches.map((b) => b.id).toList()..sort();
    return ids.join('|');
  }

  String get summary {
    final total = batches.fold<double>(
      0,
      (sum, batch) => sum + (batch.quantity ?? 0),
    );
    if (total <= 0) return '数量未知';
    final unit = batches.firstWhere(
      (batch) => batch.unit?.trim().isNotEmpty == true,
      orElse: () => batches.first,
    ).unit;
    final quantityText = total == total.roundToDouble()
        ? total.toInt().toString()
        : total.toString();
    return batchCount > 1
        ? '共 $quantityText ${unit ?? ''} · $batchCount 批次'
        : '共 $quantityText ${unit ?? ''}';
  }
}

/// 推荐匹配结果中某一食材的状态（已选命中 / 冰箱已有未选 / 缺失）。
enum RecommendationMatchKind { selectedHit, inFridgeNotSelected, missing }

/// 命中食材的数量是否足够（ADR-0021 第七节）。
enum IngredientSufficiency {
  /// 库存数量满足菜谱需要。
  sufficient,

  /// 有该食材但数量不足（显示“库存不足：还需要 X”）。
  insufficient,

  /// 数量或单位无法判定（数量未知/单位不一致），需用户确认。
  unknown,
}

/// 推荐卡片用于解释“为什么匹配”的单条依据（ADR-0021 / ADR-0022）。
class IngredientMatchDetail {
  const IngredientMatchDetail({
    required this.rawName,
    this.canonicalName,
    this.ingredientBaseId,
    required this.matchType,
    required this.kind,
    required this.sufficiency,
    this.requiredQuantity,
    this.availableQuantity,
    this.unit,
    this.verdict,
    this.verdictReason,
    this.matchedStockName,
  });

  /// 库存或菜谱中的原始写法（如 西红柿）。
  final String rawName;

  /// 标准显示名（如 番茄）；与 rawName 不同说明是别名/标准化命中。
  final String? canonicalName;

  /// 菜谱侧基础食材 ID（如 ingredient.pork），供确认交互使用。
  final String? ingredientBaseId;

  final IngredientMatchType matchType;
  final RecommendationMatchKind kind;
  final IngredientSufficiency sufficiency;

  /// 菜谱需要的数量（可解析时）。
  final double? requiredQuantity;

  /// 库存可提供的总量（数量未知为 null）。
  final double? availableQuantity;

  final String? unit;

  /// ADR-0022 三值匹配结果（missing 时为 null）。
  final IngredientMatchVerdict? verdict;

  /// MAYBE/NO 的判定原因（如“库存未确认是否为精瘦”）。
  final String? verdictReason;

  /// 判定命中/替代所对应的库存食材名（如“替代 牛肉→猪肉”中的“猪肉”）；
  /// 用于 MAYBE（同家族替代）标签展示，缺失时为 null。
  final String? matchedStockName;

  /// 匹配依据文本，如 `西红柿 → 番茄（同义词匹配）`。
  String get explanation {
    final target = canonicalName == null || canonicalName == rawName
        ? rawName
        : '$rawName → $canonicalName';
    return switch (matchType) {
      IngredientMatchType.alias => '$target（同义词匹配）',
      IngredientMatchType.spec => '$target（规格识别）',
      IngredientMatchType.format => '$target（名称标准化匹配）',
      IngredientMatchType.exact => '$target（名称一致）',
      IngredientMatchType.unknown => target,
    };
  }
}

/// 单个菜谱的推荐结果（RECO-001 / ADR-0022）。
class RecipeRecommendation {
  const RecipeRecommendation({
    required this.recipe,
    required this.selectedHit,
    required this.inFridgeNotSelected,
    required this.missing,
    required this.maybeNames,
    required this.noMatchNames,
    required this.expiringHit,
    required this.quantityUncertain,
    required this.matchDetails,
    required this.insufficientNames,
    required this.quantityUnknownNames,
  });

  final Recipe recipe;

  /// 已选食材中命中的名称。
  final List<String> selectedHit;

  /// 冰箱已有但未选择的名称（可补选）。
  final List<String> inFridgeNotSelected;

  /// 确定缺失（冰箱没有该基础食材）的主要必需食材名称。
  final List<String> missing;

  /// 规格待确认（MAYBE）的食材名称（进入“可能可以做”）。
  final List<String> maybeNames;

  /// 规格冲突（NO）的食材名称（有基础食材但规格不符）。
  final List<String> noMatchNames;

  /// 命中到临期批次的食材名称。
  final List<String> expiringHit;

  /// 命中的食材中存在数量未知批次，需要用户确认数量是否足够。
  final bool quantityUncertain;

  /// 匹配依据明细（ADR-0021 第九节，卡片展示“为什么匹配”）。
  final List<IngredientMatchDetail> matchDetails;

  /// 库存不足（有但数量不够）的命中食材。
  final List<String> insufficientNames;

  /// 数量/单位无法判定（需确认）的命中食材。
  final List<String> quantityUnknownNames;

  int get missingCount => missing.length;
  int get maybeCount => maybeNames.length;
  int get noMatchCount => noMatchNames.length;
  int get matchedCount => selectedHit.length + inFridgeNotSelected.length;

  /// 确定无法满足的食材数 = 缺失 + 规格冲突。
  int get shortageCount => missing.length + noMatchNames.length;

  /// 主要必需食材总数 = 命中 + 缺失 + 规格待确认 + 规格冲突。
  int get requiredIngredientCount =>
      matchedCount + missing.length + maybeCount + noMatchCount;

  /// 库存不足导致不能进入“现在能做”。
  bool get hasInsufficientStock => insufficientNames.isNotEmpty;
}
