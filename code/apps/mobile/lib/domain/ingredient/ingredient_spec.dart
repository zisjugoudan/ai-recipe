/// 食材规格模型与三值匹配（ADR-0022 / 解决方案.md）。
///
/// 食材统一由“基础食材概念（baseConcept）+ 可选属性分面（facet）”描述，
/// 不再把“精瘦肉”“五花肉”“肉末”当成互不相关的独立食材：
/// - 精瘦肉 = pork + fatLevel: veryLean
/// - 五花肉 = pork + cut: belly + fatLevel: mixed
/// - 肉末   = meat + form: minced（物种未知）
///
/// 每个属性可为未知（null），未知不等于缺失；推荐采用 YES / MAYBE / NO
/// 三值逻辑，避免把“可能有的食材”算成缺失、把“规格不符的食材”算成能做。
library;

/// 部位分面（null 表示未知）。
enum IngredientCut {
  belly('belly', '五花/腹部'),
  tenderloin('tenderloin', '里脊'),
  rib('rib', '排骨'),
  breast('breast', '胸肉'),
  thigh('thigh', '腿肉'),
  wing('wing', '翅');

  const IngredientCut(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientCut? fromWireName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in IngredientCut.values) {
      if (item.wireName == value) return item;
    }
    return null;
  }
}

/// 肥瘦分面（null 表示未知）。
enum IngredientFatLevel {
  veryLean('veryLean', '精瘦'),
  lean('lean', '瘦'),
  mixed('mixed', '半肥半瘦'),
  fatty('fatty', '肥');

  const IngredientFatLevel(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientFatLevel? fromWireName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in IngredientFatLevel.values) {
      if (item.wireName == value) return item;
    }
    return null;
  }
}

/// 形态分面（null 表示未知）。
enum IngredientForm {
  whole('whole', '整块'),
  sliced('sliced', '切片'),
  minced('minced', '绞碎/末'),
  shredded('shredded', '丝'),
  chunked('chunked', '块'),
  strips('strips', '条');

  const IngredientForm(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientForm? fromWireName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in IngredientForm.values) {
      if (item.wireName == value) return item;
    }
    return null;
  }
}

/// 加工状态分面（null 表示未知）。
enum IngredientProcessing {
  raw('raw', '生'),
  fresh('fresh', '新鲜'),
  cooked('cooked', '熟制'),
  dried('dried', '干制'),
  cured('cured', '腌制'),
  smoked('smoked', '熏制');

  const IngredientProcessing(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientProcessing? fromWireName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in IngredientProcessing.values) {
      if (item.wireName == value) return item;
    }
    return null;
  }
}

/// 食材家族（ADR-0023，粗粒度概念）。
///
/// 家族只表示共同归属，**不代表互为别名**；宽泛概念（辣椒、蘑菇、鱼）
/// 与具体概念（青椒、香菇、鲈鱼）可以属于同一家族，用于产生“可能匹配”。
enum IngredientFamily {
  meat('meat', '肉'),
  capsicum('capsicum', '辣椒'),
  mushroom('mushroom', '菌菇'),
  fish('fish', '鱼'),
  leafyVegetable('leafy_vegetable', '叶菜'),
  cheese('cheese', '奶酪');

  const IngredientFamily(this.wireName, this.label);

  final String wireName;
  final String label;

  static IngredientFamily? fromWireName(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in IngredientFamily.values) {
      if (item.wireName == value) return item;
    }
    return null;
  }
}

/// 基础概念 → 家族映射（ADR-0023）。
///
/// 未收录的基础概念返回 null（退化为现有“家族不同=NO”规则）。
const Map<String, IngredientFamily> kBaseConceptFamilies =
    <String, IngredientFamily>{
  // 肉
  'ingredient.meat': IngredientFamily.meat,
  'ingredient.pork': IngredientFamily.meat,
  'ingredient.beef': IngredientFamily.meat,
  'ingredient.chicken': IngredientFamily.meat,
  'ingredient.duck': IngredientFamily.meat,
  'ingredient.lamb': IngredientFamily.meat,
  // 辣椒类
  'ingredient.capsicum': IngredientFamily.capsicum,
  'ingredient.green_pepper': IngredientFamily.capsicum,
  'ingredient.hot_pepper': IngredientFamily.capsicum,
  'ingredient.bell_pepper': IngredientFamily.capsicum,
  // 菌菇
  'ingredient.mushroom': IngredientFamily.mushroom,
  'ingredient.shiitake': IngredientFamily.mushroom,
  'ingredient.pleurotus': IngredientFamily.mushroom,
  'ingredient.enoki': IngredientFamily.mushroom,
  // 鱼
  'ingredient.fish': IngredientFamily.fish,
  'ingredient.bass': IngredientFamily.fish,
  'ingredient.carp': IngredientFamily.fish,
  'ingredient.grass_carp': IngredientFamily.fish,
  // 叶菜
  'ingredient.leafy_green': IngredientFamily.leafyVegetable,
  'ingredient.pakchoi': IngredientFamily.leafyVegetable,
  'ingredient.spinach': IngredientFamily.leafyVegetable,
  'ingredient.lettuce': IngredientFamily.leafyVegetable,
  // 奶酪
  'ingredient.cheese': IngredientFamily.cheese,
  'ingredient.mozzarella': IngredientFamily.cheese,
};

/// 基础概念 → 家族（未收录返回 null）。
IngredientFamily? familyOf(String? baseConceptId) {
  if (baseConceptId == null) return null;
  return kBaseConceptFamilies[baseConceptId];
}

/// 规格来源（用于解释“这个规格是怎么来的”）。
enum IngredientSpecSource {
  /// 用户手动选择/确认。
  user('user'),

  /// 本地词典规则解析。
  localRule('local_rule'),

  /// 菜谱原文明确表达（AI 或人工录入，当前 MVP 由本地规则承担）。
  explicitText('explicit_text'),

  /// 未解析（规格未知）。
  unknown('unknown');

  const IngredientSpecSource(this.wireName);

  final String wireName;

  static IngredientSpecSource fromWireName(String? value) {
    for (final item in IngredientSpecSource.values) {
      if (item.wireName == value) return item;
    }
    return IngredientSpecSource.unknown;
  }
}

/// 食材规格：基础食材概念 + 可选属性分面。
class IngredientSpec {
  const IngredientSpec({
    this.baseConceptId,
    this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
  });

  /// 基础食材稳定 ID，如 `ingredient.pork`；null 表示未识别。
  final String? baseConceptId;

  /// 基础食材显示名，如 `猪肉`。
  final String? baseConceptName;

  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;

  /// 基础食材是否已识别。
  bool get isKnown => baseConceptId?.isNotEmpty == true;

  /// 是否一个属性都没确定。
  bool get hasNoFacets =>
      cut == null && fatLevel == null && form == null && processing == null;

  /// 是否“已知基础食材且至少一个属性确定”（比纯名称更具体）。
  bool get isResolved =>
      isKnown &&
      (cut != null ||
          fatLevel != null ||
          form != null ||
          processing != null);

  /// 与另一规格比较是否等价（含未知属性视为相同值）。
  bool isEquivalentTo(IngredientSpec other) {
    return baseConceptId == other.baseConceptId &&
        cut == other.cut &&
        fatLevel == other.fatLevel &&
        form == other.form &&
        processing == other.processing;
  }

  /// 显示规格摘要，如 `猪肉 · 精瘦`；无属性返回基础名或 null。
  String? get summary {
    if (!isKnown) return null;
    final parts = <String>[
      baseConceptName ?? baseConceptId!,
      if (cut != null) cut!.label,
      if (fatLevel != null) fatLevel!.label,
      if (form != null) form!.label,
      if (processing != null) processing!.label,
    ];
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) {
    return other is IngredientSpec && isEquivalentTo(other);
  }

  @override
  int get hashCode => Object.hash(
    baseConceptId,
    cut,
    fatLevel,
    form,
    processing,
  );

  @override
  String toString() => 'IngredientSpec($summary)';
}

/// 三值匹配结果（解决方案.md 第九节）。
enum IngredientMatchVerdict {
  /// 确定满足。
  yes,

  /// 可能满足，但信息不足，需要确认。
  maybe,

  /// 明确不满足。
  no,
}

/// 单条匹配判定结果。
class IngredientMatchResult {
  const IngredientMatchResult(this.verdict, [this.reason]);

  final IngredientMatchVerdict verdict;

  /// 用户可读的判定原因；YES 时通常为 null。
  final String? reason;

  bool get isYes => verdict == IngredientMatchVerdict.yes;
  bool get isMaybe => verdict == IngredientMatchVerdict.maybe;
  bool get isNo => verdict == IngredientMatchVerdict.no;
}

/// 基础食材上下位关系表（specific → generic）。
///
/// MVP 只维护“具体肉 → 通用肉”一层；用于判断“库存更具体可满足菜谱宽泛
/// 要求”或“库存宽泛面对菜谱具体要求需确认”两个不对称方向。
const Map<String, String> kBaseConceptParents = <String, String>{
  'ingredient.pork': 'ingredient.meat',
  'ingredient.beef': 'ingredient.meat',
  'ingredient.chicken': 'ingredient.meat',
  'ingredient.duck': 'ingredient.meat',
  'ingredient.lamb': 'ingredient.meat',
  'ingredient.fish': 'ingredient.meat',
  'ingredient.shrimp': 'ingredient.meat',
  'ingredient.crab': 'ingredient.meat',
  'ingredient.squid': 'ingredient.meat',
};

/// [specific] 是否为 [generic] 的下位（具体）食材，最多向上追溯两级。
bool isSubtypeOf(String specific, String generic) {
  var current = specific;
  for (var depth = 0; depth < 3; depth++) {
    final parent = kBaseConceptParents[current];
    if (parent == null) return false;
    if (parent == generic) return true;
    current = parent;
  }
  return false;
}

/// 肥瘦层级：精瘦 ⊂ 瘦（精瘦肉可满足“瘦肉”要求，反向需确认）。
bool isMoreSpecificFat(IngredientFatLevel specific, IngredientFatLevel generic) {
  return specific == IngredientFatLevel.veryLean &&
      generic == IngredientFatLevel.lean;
}

/// 家族匹配时检查菜谱要求属性与库存属性是否明确冲突（ADR-0023）。
///
/// 只检查“库存属性已明确且与菜谱要求不同”的情况；库存属性未知（null）
/// 不构成冲突（交给 MAYBE）。返回冲突原因，无冲突返回 null。
String? firstFacetConflict(
  IngredientSpec stock,
  IngredientSpec requirement,
) {
  final reqProcessing = requirement.processing;
  if (reqProcessing != null &&
      stock.processing != null &&
      stock.processing != reqProcessing) {
    return '加工状态冲突：菜谱需要${reqProcessing.label}，'
        '库存为${stock.processing!.label}';
  }
  final reqCut = requirement.cut;
  if (reqCut != null && stock.cut != null && stock.cut != reqCut) {
    return '部位冲突：菜谱需要${reqCut.label}，库存为${stock.cut!.label}';
  }
  final reqForm = requirement.form;
  if (reqForm != null && stock.form != null && stock.form != reqForm) {
    return '形态冲突：菜谱需要${reqForm.label}，库存为${stock.form!.label}';
  }
  final reqFat = requirement.fatLevel;
  if (reqFat != null &&
      stock.fatLevel != null &&
      stock.fatLevel != reqFat &&
      !isMoreSpecificFat(stock.fatLevel!, reqFat) &&
      !isMoreSpecificFat(reqFat, stock.fatLevel!)) {
    return '肥瘦冲突：菜谱需要${reqFat.label}，库存为${stock.fatLevel!.label}';
  }
  return null;
}

/// 判定库存规格是否满足菜谱要求规格（ADR-0022 / ADR-0023）。
///
/// 规则：
/// - 基础食材一致，或库存比菜谱要求更具体 → 通过；
/// - 库存基础食材比菜谱要求更宽泛（如 肉末→猪肉末）→ MAYBE；
/// - 基础食材不同但**同一家族**且无明确属性冲突 → MAYBE
///   （如 辣椒→青椒、蘑菇→香菇、鱼→鲈鱼，ADR-0023）；
/// - 同一家族但存在明确属性冲突（如 干辣椒→青椒：干制 vs 新鲜）→ NO；
/// - 基础食材与家族都不同 → NO。
/// - 菜谱有属性约束时：库存属性相同或更具体 → 通过；库存属性未知 → MAYBE；
///   库存属性冲突 → NO。
IngredientMatchResult matchIngredientSpec({
  required IngredientSpec stock,
  required IngredientSpec requirement,
}) {
  final recipeBase = requirement.baseConceptId;
  if (recipeBase == null) {
    return const IngredientMatchResult(
      IngredientMatchVerdict.maybe,
      '菜谱食材规格未识别',
    );
  }
  final stockBase = stock.baseConceptId;
  if (stockBase == null) {
    return const IngredientMatchResult(
      IngredientMatchVerdict.maybe,
      '库存食材规格未设置',
    );
  }
  if (stockBase != recipeBase) {
    if (isSubtypeOf(stockBase, recipeBase)) {
      // 库存更具体，可满足宽泛要求（精瘦肉→猪肉）。
    } else if (isSubtypeOf(recipeBase, stockBase)) {
      // 库存宽泛，菜谱具体：方向不确定（肉末→猪肉末）。
      return IngredientMatchResult(
        IngredientMatchVerdict.maybe,
        '库存「${stock.baseConceptName ?? stockBase}」较宽泛，需确认是否为'
        '「${requirement.baseConceptName ?? recipeBase}」',
      );
    } else {
      // ADR-0023 家族匹配：同一家族且无明确属性冲突 → MAYBE。
      final stockFamily = familyOf(stockBase);
      final recipeFamily = familyOf(recipeBase);
      if (stockFamily != null && stockFamily == recipeFamily) {
        final conflict = firstFacetConflict(stock, requirement);
        if (conflict != null) {
          return IngredientMatchResult(
            IngredientMatchVerdict.no,
            conflict,
          );
        }
        return IngredientMatchResult(
          IngredientMatchVerdict.maybe,
          '冰箱中的「${stock.baseConceptName ?? stockBase}」与'
          '「${requirement.baseConceptName ?? recipeBase}」同属'
          '${stockFamily.label}类，具体规格待确认',
        );
      }
      return IngredientMatchResult(
        IngredientMatchVerdict.no,
        '基础食材不同：'
        '${requirement.baseConceptName ?? recipeBase} ≠ '
        '${stock.baseConceptName ?? stockBase}',
      );
    }
  }

  final reasons = <String>[];
  var maybe = false;

  // 肥瘦约束。
  final reqFat = requirement.fatLevel;
  if (reqFat != null) {
    final stockFat = stock.fatLevel;
    if (stockFat == null) {
      maybe = true;
      reasons.add('库存未确认是否为${reqFat.label}');
    } else if (stockFat != reqFat) {
      if (isMoreSpecificFat(stockFat, reqFat)) {
        // 库存更具体：精瘦肉满足“瘦肉”。
      } else if (isMoreSpecificFat(reqFat, stockFat)) {
        maybe = true;
        reasons.add('库存为${stockFat.label}，菜谱需要${reqFat.label}');
      } else {
        return IngredientMatchResult(
          IngredientMatchVerdict.no,
          '肥瘦冲突：菜谱需要${reqFat.label}，库存为${stockFat.label}',
        );
      }
    }
  }

  // 部位约束。
  final reqCut = requirement.cut;
  if (reqCut != null) {
    final stockCut = stock.cut;
    if (stockCut == null) {
      maybe = true;
      reasons.add('库存未确认是否为${reqCut.label}');
    } else if (stockCut != reqCut) {
      return IngredientMatchResult(
        IngredientMatchVerdict.no,
        '部位冲突：菜谱需要${reqCut.label}，库存为${stockCut.label}',
      );
    }
  }

  // 形态约束。
  final reqForm = requirement.form;
  if (reqForm != null) {
    final stockForm = stock.form;
    if (stockForm == null) {
      maybe = true;
      reasons.add('库存未确认形态（${reqForm.label}）');
    } else if (stockForm != reqForm) {
      return IngredientMatchResult(
        IngredientMatchVerdict.no,
        '形态冲突：菜谱需要${reqForm.label}，库存为${stockForm.label}',
      );
    }
  }

  // 加工状态约束。
  final reqProcessing = requirement.processing;
  if (reqProcessing != null) {
    final stockProcessing = stock.processing;
    if (stockProcessing == null) {
      maybe = true;
      reasons.add('库存未确认加工状态（${reqProcessing.label}）');
    } else if (stockProcessing != reqProcessing) {
      return IngredientMatchResult(
        IngredientMatchVerdict.no,
        '加工状态冲突：菜谱需要${reqProcessing.label}，'
        '库存为${stockProcessing.label}',
      );
    }
  }

  return IngredientMatchResult(
    maybe ? IngredientMatchVerdict.maybe : IngredientMatchVerdict.yes,
    maybe ? reasons.join('；') : null,
  );
}

/// 本地规格词典条目：一个“名称 → 基础食材 + 属性约束”的确定映射。
class IngredientKnowledgeEntry {
  const IngredientKnowledgeEntry({
    required this.name,
    required this.baseConceptId,
    required this.baseConceptName,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
  });

  /// 格式标准化后的名称（如 精瘦肉）。
  final String name;
  final String baseConceptId;
  final String baseConceptName;
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;

  IngredientSpec get spec => IngredientSpec(
    baseConceptId: baseConceptId,
    baseConceptName: baseConceptName,
    cut: cut,
    fatLevel: fatLevel,
    form: form,
    processing: processing,
  );
}

/// 本地规格词典（ADR-0022）。
///
/// 只收录“名称本身就确定了规格”的常见写法；未收录名称由 Canonicalizer
/// 退化为格式匹配或待确认，不猜测。
class IngredientSpecRepository {
  IngredientSpecRepository({List<IngredientKnowledgeEntry>? entries})
    : _entries = entries ?? defaultEntries,
      _byName = <String, IngredientKnowledgeEntry>{
        for (final entry in entries ?? defaultEntries) entry.name: entry,
      };

  final List<IngredientKnowledgeEntry> _entries;

  /// 标准化名称 → 条目 的哈希索引（解决方案.md 第八节：线性遍历改 Map 查找）。
  final Map<String, IngredientKnowledgeEntry> _byName;

  /// 按格式标准化后的名称查找规格条目。
  IngredientKnowledgeEntry? findByNormalizedName(String name) {
    return _byName[name];
  }

  /// 返回属于同一基础食材的全部规格条目（渐进式录入的候选）。
  List<IngredientKnowledgeEntry> entriesForBase(String baseConceptId) {
    return _entries
        .where((entry) => entry.baseConceptId == baseConceptId)
        .toList(growable: false);
  }

  /// 当前词典中所有规格条目。
  List<IngredientKnowledgeEntry> get entries =>
      List<IngredientKnowledgeEntry>.unmodifiable(_entries);

  static const List<IngredientKnowledgeEntry> defaultEntries =
      <IngredientKnowledgeEntry>[
    // ---- 基础食材名称本身（无属性，供“猪肉→pork”这类宽泛要求识别）----
    IngredientKnowledgeEntry(
      name: '猪肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
    ),
    IngredientKnowledgeEntry(
      name: '牛肉',
      baseConceptId: 'ingredient.beef',
      baseConceptName: '牛肉',
    ),
    IngredientKnowledgeEntry(
      name: '鸡肉',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
    ),
    IngredientKnowledgeEntry(
      name: '鸭肉',
      baseConceptId: 'ingredient.duck',
      baseConceptName: '鸭肉',
    ),
    IngredientKnowledgeEntry(
      name: '羊肉',
      baseConceptId: 'ingredient.lamb',
      baseConceptName: '羊肉',
    ),
    IngredientKnowledgeEntry(
      name: '鱼肉',
      baseConceptId: 'ingredient.fish',
      baseConceptName: '鱼肉',
    ),
    IngredientKnowledgeEntry(
      name: '虾',
      baseConceptId: 'ingredient.shrimp',
      baseConceptName: '虾',
    ),
    IngredientKnowledgeEntry(
      name: '蟹',
      baseConceptId: 'ingredient.crab',
      baseConceptName: '蟹',
    ),
    IngredientKnowledgeEntry(
      name: '鱿鱼',
      baseConceptId: 'ingredient.squid',
      baseConceptName: '鱿鱼',
    ),
    IngredientKnowledgeEntry(
      name: '肉',
      baseConceptId: 'ingredient.meat',
      baseConceptName: '肉',
    ),
    // ---- 猪肉规格（pork）----
    IngredientKnowledgeEntry(
      name: '精瘦肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      fatLevel: IngredientFatLevel.veryLean,
    ),
    IngredientKnowledgeEntry(
      name: '瘦肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      fatLevel: IngredientFatLevel.lean,
    ),
    IngredientKnowledgeEntry(
      name: '五花肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      cut: IngredientCut.belly,
      fatLevel: IngredientFatLevel.mixed,
    ),
    IngredientKnowledgeEntry(
      name: '半肥半瘦',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      fatLevel: IngredientFatLevel.mixed,
    ),
    IngredientKnowledgeEntry(
      name: '半肥半瘦的猪肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      fatLevel: IngredientFatLevel.mixed,
    ),
    IngredientKnowledgeEntry(
      name: '肥肉',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      fatLevel: IngredientFatLevel.fatty,
    ),
    IngredientKnowledgeEntry(
      name: '猪里脊',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      cut: IngredientCut.tenderloin,
    ),
    IngredientKnowledgeEntry(
      name: '里脊',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      cut: IngredientCut.tenderloin,
    ),
    IngredientKnowledgeEntry(
      name: '猪排骨',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      cut: IngredientCut.rib,
    ),
    IngredientKnowledgeEntry(
      name: '排骨',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      cut: IngredientCut.rib,
    ),
    IngredientKnowledgeEntry(
      name: '猪肉末',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      form: IngredientForm.minced,
    ),
    IngredientKnowledgeEntry(
      name: '猪肉丝',
      baseConceptId: 'ingredient.pork',
      baseConceptName: '猪肉',
      form: IngredientForm.shredded,
    ),
    // ---- 通用肉（物种未知）----
    IngredientKnowledgeEntry(
      name: '肉末',
      baseConceptId: 'ingredient.meat',
      baseConceptName: '肉',
      form: IngredientForm.minced,
    ),
    IngredientKnowledgeEntry(
      name: '肉丝',
      baseConceptId: 'ingredient.meat',
      baseConceptName: '肉',
      form: IngredientForm.shredded,
    ),
    IngredientKnowledgeEntry(
      name: '肉片',
      baseConceptId: 'ingredient.meat',
      baseConceptName: '肉',
      form: IngredientForm.sliced,
    ),
    // ---- 牛肉规格 ----
    IngredientKnowledgeEntry(
      name: '牛肉末',
      baseConceptId: 'ingredient.beef',
      baseConceptName: '牛肉',
      form: IngredientForm.minced,
    ),
    IngredientKnowledgeEntry(
      name: '牛里脊',
      baseConceptId: 'ingredient.beef',
      baseConceptName: '牛肉',
      cut: IngredientCut.tenderloin,
    ),
    // ---- 鸡肉规格 ----
    IngredientKnowledgeEntry(
      name: '鸡胸',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.breast,
    ),
    IngredientKnowledgeEntry(
      name: '鸡胸肉',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.breast,
    ),
    IngredientKnowledgeEntry(
      name: '鸡腿',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.thigh,
    ),
    IngredientKnowledgeEntry(
      name: '鸡腿肉',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.thigh,
    ),
    IngredientKnowledgeEntry(
      name: '鸡翅',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.wing,
    ),
    IngredientKnowledgeEntry(
      name: '鸡翅中',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      cut: IngredientCut.wing,
    ),
    IngredientKnowledgeEntry(
      name: '鸡肉末',
      baseConceptId: 'ingredient.chicken',
      baseConceptName: '鸡肉',
      form: IngredientForm.minced,
    ),
    // ---- 辣椒类（capsicum 家族，ADR-0023）----
    IngredientKnowledgeEntry(
      name: '辣椒',
      baseConceptId: 'ingredient.capsicum',
      baseConceptName: '辣椒',
    ),
    IngredientKnowledgeEntry(
      name: '青椒',
      baseConceptId: 'ingredient.green_pepper',
      baseConceptName: '青椒',
      processing: IngredientProcessing.fresh,
    ),
    IngredientKnowledgeEntry(
      name: '柿子椒',
      baseConceptId: 'ingredient.green_pepper',
      baseConceptName: '青椒',
      processing: IngredientProcessing.fresh,
    ),
    IngredientKnowledgeEntry(
      name: '尖椒',
      baseConceptId: 'ingredient.hot_pepper',
      baseConceptName: '尖椒',
    ),
    IngredientKnowledgeEntry(
      name: '小米辣',
      baseConceptId: 'ingredient.hot_pepper',
      baseConceptName: '小米辣',
    ),
    IngredientKnowledgeEntry(
      name: '干辣椒',
      baseConceptId: 'ingredient.hot_pepper',
      baseConceptName: '干辣椒',
      processing: IngredientProcessing.dried,
    ),
    IngredientKnowledgeEntry(
      name: '彩椒',
      baseConceptId: 'ingredient.bell_pepper',
      baseConceptName: '彩椒',
    ),
    // ---- 菌菇类（mushroom 家族）----
    IngredientKnowledgeEntry(
      name: '蘑菇',
      baseConceptId: 'ingredient.mushroom',
      baseConceptName: '蘑菇',
    ),
    IngredientKnowledgeEntry(
      name: '香菇',
      baseConceptId: 'ingredient.shiitake',
      baseConceptName: '香菇',
    ),
    IngredientKnowledgeEntry(
      name: '平菇',
      baseConceptId: 'ingredient.pleurotus',
      baseConceptName: '平菇',
    ),
    IngredientKnowledgeEntry(
      name: '金针菇',
      baseConceptId: 'ingredient.enoki',
      baseConceptName: '金针菇',
    ),
    // ---- 鱼类（fish 家族）----
    IngredientKnowledgeEntry(
      name: '鱼',
      baseConceptId: 'ingredient.fish',
      baseConceptName: '鱼',
    ),
    IngredientKnowledgeEntry(
      name: '鲈鱼',
      baseConceptId: 'ingredient.bass',
      baseConceptName: '鲈鱼',
    ),
    IngredientKnowledgeEntry(
      name: '鲫鱼',
      baseConceptId: 'ingredient.carp',
      baseConceptName: '鲫鱼',
    ),
    IngredientKnowledgeEntry(
      name: '草鱼',
      baseConceptId: 'ingredient.grass_carp',
      baseConceptName: '草鱼',
    ),
    // ---- 叶菜类（leafy_vegetable 家族）----
    IngredientKnowledgeEntry(
      name: '青菜',
      baseConceptId: 'ingredient.leafy_green',
      baseConceptName: '青菜',
    ),
    IngredientKnowledgeEntry(
      name: '小白菜',
      baseConceptId: 'ingredient.pakchoi',
      baseConceptName: '小白菜',
    ),
    IngredientKnowledgeEntry(
      name: '菠菜',
      baseConceptId: 'ingredient.spinach',
      baseConceptName: '菠菜',
    ),
    IngredientKnowledgeEntry(
      name: '生菜',
      baseConceptId: 'ingredient.lettuce',
      baseConceptName: '生菜',
    ),
    // ---- 奶酪类（cheese 家族）----
    IngredientKnowledgeEntry(
      name: '奶酪',
      baseConceptId: 'ingredient.cheese',
      baseConceptName: '奶酪',
    ),
    IngredientKnowledgeEntry(
      name: '马苏里拉',
      baseConceptId: 'ingredient.mozzarella',
      baseConceptName: '马苏里拉',
    ),
  ];
}
