import '../../domain/ingredient/ingredient_canonicalizer.dart';
import '../../domain/ingredient/ingredient_spec.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../domain/inventory/inventory_repository.dart';
import '../../domain/recipe/recipe.dart';

typedef InventoryIdGenerator = String Function();
typedef InventoryClock = DateTime Function();

/// 库存批次新增/更新输入（FRIDGE-002）。
class InventoryBatchInput {
  const InventoryBatchInput({
    required this.ingredientName,
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
    this.sortOrder,
  });

  final String ingredientName;

  /// 数量，可为空；为空保存为“数量未知”，不写 0。
  final double? quantity;
  final String? unit;
  final String? category;
  final InventoryZone zone;
  final DateTime? purchasedAt;
  final DateTime? expiresAt;
  final String? note;

  // ---- ADR-0022：可选规格（渐进式录入，用户选择后显式传入）----
  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;
  final IngredientSpecSource specSource;

  /// 分区内排序权重（null 表示按创建顺序；拖动排序时显式传入）。
  final int? sortOrder;
}

/// 库存批次管理用例（FRIDGE-002）。
class InventoryLibraryUseCases {
  InventoryLibraryUseCases({
    required InventoryRepository repository,
    required InventoryIdGenerator idGenerator,
    required InventoryClock clock,
    IngredientCanonicalizer? canonicalizer,
  }) : _repository = repository,
       _idGenerator = idGenerator,
       _clock = clock,
       _canonicalizer = canonicalizer ?? IngredientCanonicalizer();

  final InventoryRepository _repository;
  final InventoryIdGenerator _idGenerator;
  final InventoryClock _clock;

  /// 食材统一标准化器（ADR-0022）：录入批次时把名称解析为规格候选。
  final IngredientCanonicalizer _canonicalizer;

  IngredientCanonicalizer get canonicalizer => _canonicalizer;

  Future<InventoryBatch> createBatch(InventoryBatchInput input) async {
    final now = _clock();
    final spec = _resolveBatchSpec(input);
    final batch = InventoryBatch(
      id: _idGenerator(),
      ingredientName: input.ingredientName.trim(),
      quantity: input.quantity,
      unit: _emptyToNull(input.unit),
      category: _emptyToNull(input.category),
      zone: input.zone,
      purchasedAt: input.purchasedAt,
      expiresAt: input.expiresAt,
      note: _emptyToNull(input.note),
      baseConceptId: spec.baseConceptId,
      baseConceptName: spec.baseConceptName,
      cut: spec.cut,
      fatLevel: spec.fatLevel,
      form: spec.form,
      processing: spec.processing,
      specSource: spec.specSource,
      sortOrder: input.sortOrder ?? 0,
      status: InventoryBatchStatus.available,
      createdAt: now,
      updatedAt: now,
      localVersion: 1,
    );
    await _repository.upsertBatch(batch);
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: batch.id,
        changeType: InventoryChangeType.create,
        confirmedByUser: true,
        createdAt: now,
      ),
    );
    return batch;
  }

  Future<InventoryBatch> updateBatch(
    String id,
    InventoryBatchInput input,
  ) async {
    final existing = await _requireBatch(id);
    final spec = _resolveBatchSpec(input);
    final updated = InventoryBatch(
      id: existing.id,
      ingredientName: input.ingredientName.trim(),
      quantity: input.quantity,
      unit: _emptyToNull(input.unit),
      category: _emptyToNull(input.category),
      zone: input.zone,
      purchasedAt: input.purchasedAt,
      expiresAt: input.expiresAt,
      note: _emptyToNull(input.note),
      baseConceptId: spec.baseConceptId,
      baseConceptName: spec.baseConceptName,
      cut: spec.cut,
      fatLevel: spec.fatLevel,
      form: spec.form,
      processing: spec.processing,
      specSource: spec.specSource,
      sortOrder: input.sortOrder ?? existing.sortOrder,
      status: existing.status,
      createdAt: existing.createdAt,
      updatedAt: _clock(),
      localVersion: existing.localVersion + 1,
    );
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.adjust,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    return updated;
  }

  /// 标记用完（状态改为 usedUp，记录变更）。
  Future<InventoryBatch> useUpBatch(String id) async {
    final existing = await _requireBatch(id);
    final updated = _copyWith(existing, status: InventoryBatchStatus.usedUp);
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.usedUp,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    return updated;
  }

  /// 标记丢弃（状态改为 discarded，记录变更）。
  Future<InventoryBatch> discardBatch(String id) async {
    final existing = await _requireBatch(id);
    final updated = _copyWith(
      existing,
      status: InventoryBatchStatus.discarded,
    );
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.discard,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    return updated;
  }

  /// 移动批次到其他分区（拖动跨区用；记录 adjust 变更）。
  Future<InventoryBatch> moveBatchToZone(
    String id,
    InventoryZone zone,
  ) async {
    final existing = await _requireBatch(id);
    if (existing.zone == zone) return existing;
    final updated = _copyWith(existing, zone: zone);
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.adjust,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    return updated;
  }

  /// 更新批次在分区内的排序权重（长按拖动排序用；记录 adjust 变更）。
  Future<InventoryBatch> reorderBatch(String id, int sortOrder) async {
    final existing = await _requireBatch(id);
    if (existing.sortOrder == sortOrder) return existing;
    final updated = _copyWith(existing, sortOrder: sortOrder);
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.adjust,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    return updated;
  }

  /// 删除批次（物理删除并记录丢弃变更）。
  Future<void> deleteBatch(String id) async {
    final existing = await _requireBatch(id);
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: existing.id,
        changeType: InventoryChangeType.discard,
        confirmedByUser: true,
        createdAt: _clock(),
      ),
    );
    await _repository.permanentlyDeleteBatch(id);
  }

  /// 消耗扣减（FRIDGE-003）：确认后才执行并记录 consume 变更。
  ///
  /// 数量未知的批次不允许自动扣减（需用户确认）；扣减后剩余 ≤ 0 视为用完，
  /// 不产生负库存。
  Future<InventoryBatch> consumeBatch(
    String id,
    double delta, {
    String? relatedRecipeId,
  }) async {
    if (delta <= 0) {
      throw ArgumentError('扣减数量必须大于 0。');
    }
    final existing = await _requireBatch(id);
    final current = existing.quantity;
    if (current == null) {
      throw StateError('该批次数量未知，无法自动扣减，请先确认数量。');
    }
    if (current < delta) {
      throw StateError('该批次库存不足，无法扣减 ${delta}${existing.unit ?? ''}。');
    }
    final now = _clock();
    final remaining = current - delta;
    final willUseUp = remaining <= 0.0001;
    final updated = InventoryBatch(
      id: existing.id,
      ingredientName: existing.ingredientName,
      normalizedIngredientName: existing.normalizedIngredientName,
      quantity: willUseUp ? 0.0 : remaining,
      unit: existing.unit,
      category: existing.category,
      zone: existing.zone,
      purchasedAt: existing.purchasedAt,
      expiresAt: existing.expiresAt,
      note: existing.note,
      baseConceptId: existing.baseConceptId,
      baseConceptName: existing.baseConceptName,
      cut: existing.cut,
      fatLevel: existing.fatLevel,
      form: existing.form,
      processing: existing.processing,
      specSource: existing.specSource,
      status: willUseUp ? InventoryBatchStatus.usedUp : existing.status,
      createdAt: existing.createdAt,
      updatedAt: now,
      localVersion: existing.localVersion + 1,
    );
    await _repository.upsertBatch(
      updated,
      expectedLocalVersion: existing.localVersion,
    );
    await _repository.addChange(
      InventoryChange(
        id: _idGenerator(),
        batchId: updated.id,
        changeType: InventoryChangeType.consume,
        quantityDelta: -delta,
        unit: existing.unit,
        relatedRecipeId: relatedRecipeId,
        confirmedByUser: true,
        createdAt: now,
      ),
    );
    return updated;
  }

  /// 全部可用批次（未用完、未丢弃）。
  Future<List<InventoryBatch>> loadAvailableBatches() {
    return _repository.listBatches();
  }

  /// 渐进式录入第一步→第二步（ADR-0022）：
  /// 输入食材名称，返回解析出的基础食材与可选规格候选。
  ///
  /// 候选包含与名称同基础食材的规格条目（如输入“猪肉”给出
  /// 瘦肉/精瘦肉/五花肉/半肥半瘦/肥肉/肉末），UI 可让用户选择或跳过。
  InventoryNameSuggestion suggestIngredientSpec(String rawName) {
    final canonical = canonicalizer.canonicalize(rawName);
    final suggestions = canonicalizer.specSuggestionsFor(rawName);
    return InventoryNameSuggestion(
      name: rawName.trim(),
      canonical: canonical,
      specOptions: suggestions,
    );
  }

  /// 名称是否已被本地词典识别（草稿确认页“种类待确认”轻量标识）。
  bool isIngredientNameKnown(String rawName) {
    return canonicalizer.isKnown(rawName);
  }

  /// 库存摘要：可用批次总数 / 临期 / 已过期 / 数量未知。
  Future<InventorySummary> loadSummary() async {
    final batches = await loadAvailableBatches();
    final now = _clock();
    var soonExpiring = 0;
    var expired = 0;
    var unknownQuantity = 0;
    for (final batch in batches) {
      switch (batch.conditionOn(now)) {
        case InventoryItemCondition.soonExpiring:
          soonExpiring += 1;
        case InventoryItemCondition.expired:
          expired += 1;
        case InventoryItemCondition.unknownQuantity:
          unknownQuantity += 1;
        case InventoryItemCondition.normal:
        case InventoryItemCondition.noDate:
          break;
      }
    }
    return InventorySummary(
      availableBatches: batches.length,
      soonExpiring: soonExpiring,
      expired: expired,
      unknownQuantity: unknownQuantity,
    );
  }

  /// 按名称+分区聚合（同名多批次折叠为一个食材 chip）。
  Future<List<AggregatedInventoryItem>> loadAggregated() async {
    final batches = await loadAvailableBatches();
    final now = _clock();
    final grouped = <String, List<InventoryBatch>>{};
    for (final batch in batches) {
      grouped
          .putIfAbsent('${batch.zone.name}|${batch.ingredientName}', () => <InventoryBatch>[])
          .add(batch);
    }
    final items = grouped.entries.map((entry) {
      final zoneName = entry.key.split('|').first;
      return AggregatedInventoryItem(
        ingredientName: entry.value.first.ingredientName,
        zone: InventoryZone.fromWireName(zoneName),
        batches: List<InventoryBatch>.unmodifiable(entry.value),
        condition: _aggregateCondition(entry.value, now),
      );
    }).toList(growable: false);
    // 先按分区，再按分区内排序权重（首个批次的 sortOrder），保持拖拽顺序。
    items.sort((a, b) {
      final zoneOrder = InventoryZone.values
          .indexOf(a.zone)
          .compareTo(InventoryZone.values.indexOf(b.zone));
      if (zoneOrder != 0) return zoneOrder;
      final orderA = a.batches.fold<int>(
        0,
        (min, batch) => batch.sortOrder < min ? batch.sortOrder : min,
      );
      final orderB = b.batches.fold<int>(
        0,
        (min, batch) => batch.sortOrder < min ? batch.sortOrder : min,
      );
      return orderA.compareTo(orderB);
    });
    return items;
  }

  Future<InventoryBatch> _requireBatch(String id) async {
    final batch = await _repository.getBatchById(id);
    if (batch == null) {
      throw StateError('库存批次不存在：$id');
    }
    return batch;
  }

  /// 复制批次并修改部分字段（状态 / 分区 / 排序权重），localVersion +1。
  static InventoryBatch _copyWith(
    InventoryBatch batch, {
    InventoryBatchStatus? status,
    InventoryZone? zone,
    int? sortOrder,
  }) {
    return InventoryBatch(
      id: batch.id,
      ingredientName: batch.ingredientName,
      normalizedIngredientName: batch.normalizedIngredientName,
      quantity: batch.quantity,
      unit: batch.unit,
      category: batch.category,
      zone: zone ?? batch.zone,
      purchasedAt: batch.purchasedAt,
      expiresAt: batch.expiresAt,
      note: batch.note,
      baseConceptId: batch.baseConceptId,
      baseConceptName: batch.baseConceptName,
      cut: batch.cut,
      fatLevel: batch.fatLevel,
      form: batch.form,
      processing: batch.processing,
      specSource: batch.specSource,
      sortOrder: sortOrder ?? batch.sortOrder,
      status: status ?? batch.status,
      createdAt: batch.createdAt,
      updatedAt: batch.updatedAt.add(const Duration(seconds: 1)),
      localVersion: batch.localVersion + 1,
    );
  }

  /// 解析批次规格（ADR-0022）：
  /// - 用户在录入页显式选择了规格 → 直接使用；
  /// - 否则由本地词典把名称解析为规格（老数据/新录入即时回填）；
  /// - 完全未识别 → 规格为空（保持“规格未设置”，不猜测）。
  _ResolvedBatchSpec _resolveBatchSpec(InventoryBatchInput input) {
    final explicitId = input.baseConceptId?.trim();
    if (explicitId != null && explicitId.isNotEmpty) {
      return _ResolvedBatchSpec(
        baseConceptId: explicitId,
        baseConceptName: input.baseConceptName,
        cut: input.cut,
        fatLevel: input.fatLevel,
        form: input.form,
        processing: input.processing,
        specSource: input.specSource,
      );
    }
    final canonical = canonicalizer.canonicalize(input.ingredientName);
    if (canonical.isKnown) {
      return _ResolvedBatchSpec(
        baseConceptId: canonical.canonicalIngredientId,
        baseConceptName: canonical.canonicalName,
        cut: canonical.cut,
        fatLevel: canonical.fatLevel,
        form: canonical.form,
        processing: canonical.processing,
        specSource: IngredientSpecSource.localRule,
      );
    }
    return const _ResolvedBatchSpec();
  }

  /// 聚合状态取最严重者：已过期 > 临期 > 数量未知 > 正常/未设置日期。
  static InventoryItemCondition _aggregateCondition(
    List<InventoryBatch> batches,
    DateTime now,
  ) {
    var seen = false;
    var hasExpired = false;
    var hasSoon = false;
    var hasUnknown = false;
    var hasNormal = false;
    for (final batch in batches) {
      seen = true;
      switch (batch.conditionOn(now)) {
        case InventoryItemCondition.expired:
          hasExpired = true;
        case InventoryItemCondition.soonExpiring:
          hasSoon = true;
        case InventoryItemCondition.unknownQuantity:
          hasUnknown = true;
        case InventoryItemCondition.normal:
          hasNormal = true;
        case InventoryItemCondition.noDate:
          break;
      }
    }
    if (!seen) return InventoryItemCondition.normal;
    if (hasExpired) return InventoryItemCondition.expired;
    if (hasSoon) return InventoryItemCondition.soonExpiring;
    if (hasUnknown) return InventoryItemCondition.unknownQuantity;
    // 存在“正常”批次时返回 normal（否则会误显示“未设置日期”）。
    return hasNormal
        ? InventoryItemCondition.normal
        : InventoryItemCondition.noDate;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// 常备基础调味品名单（RECO-001）：不计入主要缺失数。
///
/// 名单同时覆盖 AI 导入时常把步骤里的调料解析成食材的情况（水/花椒粉/
/// 小米辣/糍粑辣椒等），避免把调料误计为“缺 N 样”导致菜谱被整体过滤。
const Set<String> kStapleSeasonings = <String>{
  // 基础调味
  '盐', '糖', '白砂糖', '冰糖', '鸡精', '味精', '生抽', '老抽', '酱油', '醋', '陈醋', '香醋',
  '料酒', '蚝油', '油', '食用油', '香油', '橄榄油', '芝麻油', '辣椒油', '藤椒油',
  // 香辛料
  '花椒', '花椒粉', '八角', '桂皮', '香叶', '辣椒', '干辣椒', '辣椒面', '辣椒粉',
  '小米辣', '糍粑辣椒', '葱', '姜', '蒜', '蒜末', '姜末', '葱花', '蒜片',
  '淀粉', '生粉', '胡椒粉', '黑胡椒', '白胡椒粉', '孜然', '孜然粉', '芝麻',
  '五香粉', '十三香', '豆瓣酱', '豆瓣', '甜面酱', '黄豆酱', '番茄酱', '沙拉酱',
  '蜂蜜', '酵母', '泡打粉', '小苏打', '蒸鱼豉油', '火锅底料',
  // 水与基础液体（AI 常把“水”解析成食材，不应计缺失）
  '水', '清水', '热水', '温水', '冷水', '开水', '凉白开',
};

/// 按库存食材确定性推荐本地正式菜谱（RECO-001 / ADR-0022）。
///
/// 匹配采用“基础食材 + 属性规格 + 三值逻辑”：库存规格比菜谱要求更具体
/// 可满足宽泛要求；库存宽泛面对菜谱具体要求只能进入“可能可以做”；
/// 基础食材或属性明确冲突则阻断。缺失只统计确定缺少的食材，不把
/// MAYBE 当作缺失。
class InventoryRecommendationUseCases {
  InventoryRecommendationUseCases({
    IngredientCanonicalizer? canonicalizer,
  }) : _canonicalizer = canonicalizer ?? IngredientCanonicalizer();

  /// 统一食材标准化器：搜索/推荐/扣减共用同一套规则。
  final IngredientCanonicalizer _canonicalizer;

  IngredientCanonicalizer get canonicalizer => _canonicalizer;

  /// [selectedNames] 用户本次选中的食材名；[recipes] 本地正式菜谱；
  /// [batches] 全部可用批次（已过期批次不参与匹配）；
  /// [strictSelected] 为 true 时只使用用户选中的食材，冰箱中未选择的
  /// 其他可用食材按缺失计（ADR-0021 第五节“仅使用已选食材”开关）；
  /// [confirmedBases] 用户本次会话中确认“视为可用”的基础食材 ID
  /// （ADR-0022 第八节：仅本次使用，不改库存、不写全局词典）。
  List<RecipeRecommendation> recommend({
    required Set<String> selectedNames,
    required List<Recipe> recipes,
    required List<InventoryBatch> batches,
    required DateTime now,
    bool strictSelected = false,
    Set<String> confirmedBases = const <String>{},
  }) {
    // 1. 可用批次索引：基础食材 ID 优先；未收录名称退化为“同名匹配键”，
    //    仅允许完全相同的名称互相匹配（鸡蛋≠鸡蛋液，杜绝近似误判）。
    final availableByBase = <String, List<InventoryBatch>>{};
    final expiringKeys = <String>{};
    for (final batch in batches) {
      if (!batch.isAvailable) continue;
      final condition = batch.conditionOn(now);
      if (condition == InventoryItemCondition.expired) continue;
      final baseId = _batchBaseId(batch);
      final key = baseId ?? 'name:${_normalizedName(batch.ingredientName)}';
      availableByBase
          .putIfAbsent(key, () => <InventoryBatch>[])
          .add(batch);
      if (condition == InventoryItemCondition.soonExpiring) {
        expiringKeys.add(key);
      }
    }
    // 哈希索引（解决方案.md 三.1）：家族 → 库存键、宽泛概念 → 具体概念，
    // 让“辣椒→青椒”“猪肉→精瘦肉”等候选查找变成 O(1) 直取，不再逐键扫描。
    final familyIndex = <IngredientFamily, List<String>>{};
    for (final key in availableByBase.keys) {
      final family = familyOf(key.startsWith('name:') ? null : key);
      if (family != null) {
        familyIndex.putIfAbsent(family, () => <String>[]).add(key);
      }
    }
    final childrenIndex = <String, List<String>>{};
    kBaseConceptParents.forEach((specific, generic) {
      childrenIndex.putIfAbsent(generic, () => <String>[]).add(specific);
    });
    // 用户已选食材的匹配键集合（基础食材或同名键）。
    final selectedKeys = selectedNames
        .map(_nameKey)
        .whereType<String>()
        .toSet();

    final results = <RecipeRecommendation>[];
    for (final recipe in recipes) {
      final details = <IngredientMatchDetail>[];

      // 收集本菜谱的需求，按「基础食材 + 属性分面」整体去重，而不是只按
      // 基础 ID 去重：猪肉 与 五花肉 基础相同但规格不同，必须视为两个
      // 独立需求，不能互相吞并（原则 5）。
      final requirements = <_RecipeRequirement>[];
      final seenReq = <String>{};
      for (final ingredient in recipe.ingredients) {
        if (_isOptionalFor(ingredient)) continue; // 可选食材不计缺失
        final name = ingredient.name.trim();
        if (name.isEmpty) continue;
        if (kStapleSeasonings.contains(name)) continue; // 常备调味品不计缺失
        final canonical = canonicalizer.canonicalize(name);
        final recipeBase = _ingredientBaseId(ingredient);
        final recipeKey =
            recipeBase ?? 'name:${canonical.normalizedName}';
        // 需求规格 = 菜谱落库规格（可能为空）合并名称解析结果（ADR-0022）：
        // 大多数菜谱食材未落库 baseConceptId，必须用解析出的基础食材/分面补全，
        // 否则 matchIngredientSpec 会因“规格未识别”误判为 MAYBE。
        final reqSpec = IngredientSpec(
          baseConceptId: recipeBase,
          baseConceptName: canonical.canonicalName,
          cut: ingredient.cut ?? canonical.cut,
          fatLevel: ingredient.fatLevel ?? canonical.fatLevel,
          form: ingredient.form ?? canonical.form,
          processing: ingredient.processing ?? canonical.processing,
        );
        final specKey = _requirementKey(
          recipeBase,
          reqSpec,
          canonical.normalizedName,
        );
        if (!seenReq.add(specKey)) continue;
        requirements.add(
          _RecipeRequirement(
            ingredient: ingredient,
            rawName: name,
            canonicalName: canonical.canonicalName,
            matchType: canonical.matchType,
            baseId: recipeBase,
            recipeKey: recipeKey,
            spec: reqSpec,
          ),
        );
      }

      // ---- 全局批次分配（原则 1-4）----
      // 同一份库存批次在单道菜谱内最多满足一个需求；精确/身份匹配优先，
      // 家族（替代）只负责召回候选、不代表“已拥有”（原则 1）。
      final usedBatchIds = <String>{};

      // 阶段 A：身份匹配（YES）。先分配属性分面最多（最具体）的需求，
      // 让精确库存优先于宽泛需求，避免“五花肉”抢占普通“猪肉”（原则 3）。
      final aOrder = List<_RecipeRequirement>.of(requirements)
        ..sort((a, b) => _facetCount(b.spec).compareTo(_facetCount(a.spec)));
      for (final req in aOrder) {
        if (req.verdict != null) continue;
        final candidates = _candidateBatches(
          availableByBase,
          familyIndex,
          childrenIndex,
          req.recipeKey,
        );
        // 用户本次已确认视为可用：直接取第一个可用候选为 YES。
        if (confirmedBases.contains(req.baseId)) {
          final available =
              candidates.where((b) => !usedBatchIds.contains(b.id)).toList();
          if (available.isNotEmpty) {
            req.assignedBatches = <InventoryBatch>[available.first];
            usedBatchIds.add(available.first.id);
            req.verdict = IngredientMatchVerdict.yes;
            req.matchedName = available.first.ingredientName;
          }
          continue;
        }
        // 身份匹配：同基础（或库存更具体）且无属性冲突 → YES。
        final yesBatches = candidates
            .where((b) => !usedBatchIds.contains(b.id))
            .where((b) => _isYesFor(req, b))
            .toList();
        if (yesBatches.isNotEmpty) {
          req.assignedBatches = yesBatches;
          for (final b in yesBatches) {
            usedBatchIds.add(b.id);
          }
          req.verdict = IngredientMatchVerdict.yes;
          req.matchedName = yesBatches.first.ingredientName;
        }
      }

      // 阶段 B：家族/替代（MAYBE）。仅对尚未分配的需求，取一个可用候选
      // 作为“可能可以做”，并占用该批次——一份身份不明确的库存不能同时
      // 满足多个不同规格（原则 2）。未收录名称没有家族，跳过。
      for (final req in requirements) {
        if (req.verdict != null || req.baseId == null) continue;
        for (final b in _candidateBatches(
          availableByBase,
          familyIndex,
          childrenIndex,
          req.recipeKey,
        )) {
          if (usedBatchIds.contains(b.id)) continue;
          final r = matchIngredientSpec(
            stock: _batchEffectiveSpec(b),
            requirement: req.spec,
          );
          if (r.isMaybe) {
            req.maybeBatch = b;
            usedBatchIds.add(b.id);
            req.verdict = IngredientMatchVerdict.maybe;
            req.reason = r.reason;
            req.matchedName = b.ingredientName;
            break;
          }
        }
      }

      // 阶段 C：缺失 / 规格冲突。剩余未分配需求：无可用候选 → 缺失；
      // 存在可用候选（此时必为 NO，即属性冲突）→ 规格不符。
      for (final req in requirements) {
        if (req.verdict != null) continue;
        final candidates = _candidateBatches(
          availableByBase,
          familyIndex,
          childrenIndex,
          req.recipeKey,
        );
        final available =
            candidates.where((b) => !usedBatchIds.contains(b.id)).toList();
        if (available.isNotEmpty) {
          req.verdict = IngredientMatchVerdict.no;
          final r = matchIngredientSpec(
            stock: _batchEffectiveSpec(available.first),
            requirement: req.spec,
          );
          req.reason = r.reason;
          req.matchedName = available.first.ingredientName;
        }
        // 否则 verdict 保持 null → 缺失。
      }

      // ---- 生成匹配明细（保持菜谱原始需求顺序）----
      for (final req in requirements) {
        final isSelected = selectedKeys.contains(req.recipeKey);
        // strictSelected：未选择的身份匹配按缺失计；MAYBE 替代不因未选而缺失。
        if (strictSelected &&
            !isSelected &&
            req.verdict == IngredientMatchVerdict.yes) {
          details.add(
            IngredientMatchDetail(
              rawName: req.rawName,
              canonicalName: req.canonicalName,
              ingredientBaseId: req.baseId,
              matchType: req.matchType,
              kind: RecommendationMatchKind.missing,
              sufficiency: IngredientSufficiency.sufficient,
              verdict: req.verdict,
              verdictReason: req.reason,
              matchedStockName: req.matchedName,
            ),
          );
          continue;
        }
        switch (req.verdict) {
          case IngredientMatchVerdict.yes:
            final kind = isSelected
                ? RecommendationMatchKind.selectedHit
                : RecommendationMatchKind.inFridgeNotSelected;
            details.add(
              IngredientMatchDetail(
                rawName: req.rawName,
                canonicalName: req.canonicalName,
                ingredientBaseId: req.baseId,
                matchType: req.matchType,
                kind: kind,
                // 数量只统计最终分配给本需求的批次（原则 6）。
                sufficiency: _sufficiency(req.ingredient, req.assignedBatches!),
                requiredQuantity: _parseQuantity(req.ingredient.quantity),
                availableQuantity: _availableTotal(req.assignedBatches!),
                unit: _unitOf(req.assignedBatches!),
                verdict: IngredientMatchVerdict.yes,
                verdictReason: req.reason,
                matchedStockName: req.matchedName,
              ),
            );
          case IngredientMatchVerdict.maybe:
            details.add(
              IngredientMatchDetail(
                rawName: req.rawName,
                canonicalName: req.canonicalName,
                ingredientBaseId: req.baseId,
                matchType: req.matchType,
                kind: isSelected
                    ? RecommendationMatchKind.selectedHit
                    : RecommendationMatchKind.inFridgeNotSelected,
                // 家族替代不代表已拥有：数量视为需确认，不统计。
                sufficiency: IngredientSufficiency.unknown,
                requiredQuantity: _parseQuantity(req.ingredient.quantity),
                availableQuantity: null,
                unit: null,
                verdict: IngredientMatchVerdict.maybe,
                verdictReason: req.reason,
                matchedStockName: req.matchedName,
              ),
            );
          case IngredientMatchVerdict.no:
            details.add(
              IngredientMatchDetail(
                rawName: req.rawName,
                canonicalName: req.canonicalName,
                ingredientBaseId: req.baseId,
                matchType: req.matchType,
                kind: isSelected
                    ? RecommendationMatchKind.selectedHit
                    : RecommendationMatchKind.inFridgeNotSelected,
                sufficiency: IngredientSufficiency.sufficient,
                requiredQuantity: _parseQuantity(req.ingredient.quantity),
                verdict: IngredientMatchVerdict.no,
                verdictReason: req.reason,
                matchedStockName: req.matchedName,
              ),
            );
          case null:
            details.add(
              IngredientMatchDetail(
                rawName: req.rawName,
                canonicalName: req.canonicalName,
                ingredientBaseId: req.baseId,
                matchType: req.matchType,
                kind: RecommendationMatchKind.missing,
                sufficiency: IngredientSufficiency.sufficient,
              ),
            );
        }
      }

      // 2. 汇总各分组。
      final selectedHit = <String>[];
      final inFridgeNotSelected = <String>[];
      final missing = <String>[];
      final maybeNames = <String>[];
      final noMatchNames = <String>[];
      final insufficientNames = <String>[];
      final quantityUnknownNames = <String>[];
      final expiringHit = <String>[];
      for (final detail in details) {
        final key = _nameKey(detail.rawName);
        final hitsExpiring = expiringKeys.contains(key);
        final isNoMatch = detail.verdict == IngredientMatchVerdict.no;
        final isMaybe = detail.verdict == IngredientMatchVerdict.maybe;
        if (isNoMatch) {
          // 规格冲突：不混入“命中”，单独进入 noMatch（规格不符）。
          noMatchNames.add(detail.rawName);
        } else if (isMaybe) {
          // 家族/替代只召回候选，不代表已拥有：只进入“可能可以做”，
          // 不计入命中、不计入缺失、不触发临期标记（原则 1）。
          maybeNames.add(detail.rawName);
        } else if (detail.kind == RecommendationMatchKind.selectedHit) {
          selectedHit.add(detail.rawName);
          if (hitsExpiring) expiringHit.add(detail.rawName);
        } else if (detail.kind == RecommendationMatchKind.inFridgeNotSelected) {
          inFridgeNotSelected.add(detail.rawName);
          if (hitsExpiring) expiringHit.add(detail.rawName);
        } else {
          missing.add(detail.rawName);
        }
        // 数量与临期只对“已拥有”的身份匹配（YES）统计。
        if (!isNoMatch &&
            !isMaybe &&
            detail.kind != RecommendationMatchKind.missing) {
          switch (detail.sufficiency) {
            case IngredientSufficiency.insufficient:
              insufficientNames.add(detail.rawName);
            case IngredientSufficiency.unknown:
              quantityUnknownNames.add(detail.rawName);
            case IngredientSufficiency.sufficient:
              break;
          }
        }
      }
      // 缺失过多不进入推荐（保留“更多缺失”折叠入口）。
      if (missing.length + noMatchNames.length > 4) continue;
      results.add(
        RecipeRecommendation(
          recipe: recipe,
          selectedHit: List<String>.unmodifiable(selectedHit),
          inFridgeNotSelected: List<String>.unmodifiable(inFridgeNotSelected),
          missing: List<String>.unmodifiable(missing),
          maybeNames: List<String>.unmodifiable(maybeNames),
          noMatchNames: List<String>.unmodifiable(noMatchNames),
          expiringHit: List<String>.unmodifiable(expiringHit),
          quantityUncertain: quantityUnknownNames.isNotEmpty,
          matchDetails: List<IngredientMatchDetail>.unmodifiable(details),
          insufficientNames: List<String>.unmodifiable(insufficientNames),
          quantityUnknownNames:
              List<String>.unmodifiable(quantityUnknownNames),
        ),
      );
    }

    results.sort(_compareRecommendations);
    return List<RecipeRecommendation>.unmodifiable(results);
  }

  /// 库存批次的基础食材 ID（落库字段优先，否则即时解析名称）。
  String? _batchBaseId(InventoryBatch batch) {
    final stored = batch.baseConceptId?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return _nameBaseId(batch.ingredientName);
  }

  /// 食材是否按“可选”处理（ADR-0023）：AI optional 标记或要求强度为可选。
  bool _isOptionalFor(Ingredient ingredient) {
    return ingredient.optional ||
        ingredient.importance == IngredientImportance.optional;
  }

  /// 批次有效规格（ADR-0022）：落库规格优先；旧数据/未落库时即时解析名称
  /// 补全规格（含属性分面），保证“瘦肉”这类可解析名称即使库存规格未设置
  /// 也能参与精确匹配。
  IngredientSpec _batchEffectiveSpec(InventoryBatch batch) {
    final stored = batch.baseConceptId?.trim();
    if (stored != null && stored.isNotEmpty) {
      return batch.spec;
    }
    return canonicalizer.canonicalize(batch.ingredientName).spec;
  }

  /// 菜谱食材的基础食材 ID（落库字段优先，否则即时解析名称）。
  String? _ingredientBaseId(Ingredient ingredient) {
    final stored = ingredient.baseConceptId?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return _nameBaseId(ingredient.name);
  }

  /// 名称 → 基础食材 ID（未识别返回 null）。
  String? _nameBaseId(String name) {
    final canonical = canonicalizer.canonicalize(name);
    return canonical.canonicalIngredientId;
  }

  /// 名称 → 匹配键：基础食材 ID 优先，未收录名称退化为“name:规范化名”。
  String? _nameKey(String name) {
    final canonical = canonicalizer.canonicalize(name);
    return canonical.canonicalIngredientId ?? 'name:${canonical.normalizedName}';
  }

  /// 名称的规范化名（格式标准化，去括号/全半角/数量单位）。
  String _normalizedName(String name) {
    return IngredientCanonicalizer.normalizeFormat(name);
  }

  /// 查找与菜谱基础食材兼容的库存批次（解决方案.md 三.1：哈希索引直取）：
  /// 相同基础食材、库存更具体（精瘦肉→猪肉）、库存更宽泛（肉末→猪肉末）、
  /// 或**同一家族**（辣椒→青椒、蘑菇→香菇，ADR-0023）。
  ///
  /// 相比逐键扫描，这里通过 family/children 索引把候选查找降为 O(1) 直取，
  /// 不再对全部库存食材遍历一次。
  List<InventoryBatch> _candidateBatches(
    Map<String, List<InventoryBatch>> byBase,
    Map<IngredientFamily, List<String>> familyIndex,
    Map<String, List<String>> childrenIndex,
    String recipeBase,
  ) {
    final keys = <String>{recipeBase};
    // 库存更宽泛（库存=猪肉，菜谱=肉）：菜谱基础食材的父级。
    final parent = kBaseConceptParents[recipeBase];
    if (parent != null) keys.add(parent);
    // 库存更具体（库存=精瘦肉，菜谱=猪肉）：菜谱基础食材的子级。
    keys.addAll(childrenIndex[recipeBase] ?? const <String>[]);
    // ADR-0023：同一家族（如 辣椒 vs 青椒）也进入候选，
    // 由 matchIngredientSpec 在家族分支判定 MAYBE/NO。
    final family = familyOf(recipeBase);
    if (family != null) {
      keys.addAll(familyIndex[family] ?? const <String>[]);
    }
    final result = <InventoryBatch>[];
    for (final key in keys) {
      final batches = byBase[key];
      if (batches != null) result.addAll(batches);
    }
    return result;
  }

  /// 批次是否在“身份”上满足菜谱需求（原则 4：身份 ≠ 兼容）。
  ///
  /// 只有 [matchIngredientSpec] 返回 YES 才算身份满足——即基础食材一致、
  /// 库存更具体（精瘦肉→猪肉）且属性无冲突。家族替代（辣椒→青椒）、
  /// 库存更宽泛（肉末→猪肉末）等返回 MAYBE，不算身份满足，只作候选召回。
  ///
  /// 未收录基础食材的需求（[Ingredient.baseConceptId] 为 null，如“鸡蛋”）
  /// 退化为**同名精确匹配**：其候选批次只会来自同一“name:规范化名”键，
  /// 直接视为身份命中，否则 matchIngredientSpec 会因“规格未识别”误判为 MAYBE。
  bool _isYesFor(_RecipeRequirement req, InventoryBatch batch) {
    if (req.baseId == null) return true;
    return matchIngredientSpec(
      stock: _batchEffectiveSpec(batch),
      requirement: req.spec,
    ).isYes;
  }

  /// 需求去重键（原则 5）：按「基础食材 ID + 属性分面」整体去重，
  /// 而不是只按基础 ID。这样菜谱中的 猪肉 与 五花肉（基础相同、分面不同）
  /// 会被视为两个独立需求，不会互相吞并；未收录名称退化为“name:规范化名”。
  String _requirementKey(
    String? baseId,
    IngredientSpec spec,
    String normalizedName,
  ) {
    if (baseId == null) return 'name:$normalizedName';
    final facets = [
      spec.cut?.name,
      spec.fatLevel?.name,
      spec.form?.name,
      spec.processing?.name,
    ];
    return '$baseId#${facets.join('-')}';
  }

  /// 需求的属性分面数量：分面越多越具体，分配时越优先（原则 3）。
  static int _facetCount(IngredientSpec spec) {
    var count = 0;
    if (spec.cut != null) count++;
    if (spec.fatLevel != null) count++;
    if (spec.form != null) count++;
    if (spec.processing != null) count++;
    return count;
  }

  /// 从已分配批次中取首个非空单位（原则 6：只统计最终分配批次）。
  static String? _unitOf(List<InventoryBatch> batches) {
    for (final batch in batches) {
      final unit = batch.unit?.trim();
      if (unit != null && unit.isNotEmpty) return unit;
    }
    return null;
  }

  /// 判定命中食材数量是否足够（ADR-0021 第七节）。
  ///
  /// 菜谱需求无法解析、库存数量未知或单位不一致时返回 unknown（需确认），
  /// 不得把名称命中解释为数量一定足够。
  IngredientSufficiency _sufficiency(
    Ingredient ingredient,
    List<InventoryBatch> batches,
  ) {
    final required = _parseQuantity(ingredient.quantity);
    if (required == null) return IngredientSufficiency.unknown;
    double? availableTotal;
    String? batchUnit;
    for (final batch in batches) {
      final quantity = batch.quantity;
      if (quantity == null) return IngredientSufficiency.unknown;
      availableTotal = (availableTotal ?? 0) + quantity;
      batchUnit = batchUnit ?? batch.unit;
    }
    if (availableTotal == null) return IngredientSufficiency.unknown;
    final recipeUnit = ingredient.unit?.trim();
    final batchUnitValue = batchUnit?.trim();
    if (recipeUnit != null &&
        recipeUnit.isNotEmpty &&
        batchUnitValue != null &&
        batchUnitValue.isNotEmpty &&
        recipeUnit != batchUnitValue) {
      return IngredientSufficiency.unknown; // 单位不一致无法判定
    }
    return availableTotal >= required
        ? IngredientSufficiency.sufficient
        : IngredientSufficiency.insufficient;
  }

  static double? _availableTotal(List<InventoryBatch> batches) {
    double? total;
    for (final batch in batches) {
      final quantity = batch.quantity;
      if (quantity == null) return null;
      total = (total ?? 0) + quantity;
    }
    return total;
  }

  /// 从“2 个 / 500 克”等文本中取首个数字；无法解析返回 null。
  static double? _parseQuantity(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final match = RegExp(r'\d+(\.\d+)?').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(0)!);
  }

  static int _compareRecommendations(
    RecipeRecommendation a,
    RecipeRecommendation b,
  ) {
    // 确定无法满足的食材（缺失 + 规格冲突）更少优先。
    final byShortage = a.shortageCount.compareTo(b.shortageCount);
    if (byShortage != 0) return byShortage;
    // 规格待确认（MAYBE）更少优先。
    final byMaybe = a.maybeCount.compareTo(b.maybeCount);
    if (byMaybe != 0) return byMaybe;
    // 库存不足的菜谱排在“能直接做”的后面。
    final byInsufficient = (a.hasInsufficientStock ? 1 : 0)
        .compareTo(b.hasInsufficientStock ? 1 : 0);
    if (byInsufficient != 0) return byInsufficient;
    // 使用临期食材更多优先。
    final byExpiring = b.expiringHit.length.compareTo(a.expiringHit.length);
    if (byExpiring != 0) return byExpiring;
    // 匹配比例更高优先（已选命中计入匹配数）。
    final ratioA = a.requiredIngredientCount == 0
        ? 0.0
        : a.matchedCount / a.requiredIngredientCount;
    final ratioB = b.requiredIngredientCount == 0
        ? 0.0
        : b.matchedCount / b.requiredIngredientCount;
    return ratioB.compareTo(ratioA);
  }
}

/// 单道菜谱的一个食材需求（内部使用）。
///
/// 在推荐匹配主循环中承载：需求原文、基础食材与规格、三值判定结果，
/// 以及全局批次分配的结果（[assignedBatches] 或 [maybeBatch]）。
/// 这些字段在三个匹配阶段（A 身份 / B 家族 / C 缺失）中逐步被填充。
class _RecipeRequirement {
  _RecipeRequirement({
    required this.ingredient,
    required this.rawName,
    required this.canonicalName,
    required this.matchType,
    required this.baseId,
    required this.recipeKey,
    required this.spec,
  });

  final Ingredient ingredient;
  final String rawName;
  final String? canonicalName;
  final IngredientMatchType matchType;

  /// 菜谱侧基础食材 ID（未收录名称为 null）。
  final String? baseId;

  /// 基础食材 ID 或退化“name:规范化名”，用于查候选批次。
  final String recipeKey;

  /// 菜谱需求规格（含属性分面）。
  final IngredientSpec spec;

  /// 三值判定结果；null 表示尚未判定（= 缺失）。
  IngredientMatchVerdict? verdict;
  String? reason;
  String? matchedName;

  /// 阶段 A 身份匹配（YES）最终分配到的批次（原则 6：只统计这些）。
  List<InventoryBatch>? assignedBatches;

  /// 阶段 B 家族替代（MAYBE）所占用的单个候选批次。
  InventoryBatch? maybeBatch;
}

/// 批次规格解析结果（内部使用）。
class _ResolvedBatchSpec {
  const _ResolvedBatchSpec({
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specSource = IngredientSpecSource.unknown,
  });

  final String? baseConceptId;
  final String? baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;
  final IngredientSpecSource specSource;
}

/// 库存名称解析建议（ADR-0022 渐进式录入）。
///
/// 由 [InventoryLibraryUseCases.suggestIngredientSpec] 返回；UI 依据
/// [canonical] 展示解析结果，依据 [specOptions] 生成可选规格 chip。
class InventoryNameSuggestion {
  const InventoryNameSuggestion({
    required this.name,
    required this.canonical,
    required this.specOptions,
  });

  final String name;

  /// 名称的标准化结果（含基础食材与已解析属性）。
  final IngredientCanonicalization canonical;

  /// 同基础食材的可选规格条目（可为空）。
  final List<IngredientKnowledgeEntry> specOptions;
}
