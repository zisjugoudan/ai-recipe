/// 食材统一标准化（ADR-0021 / ADR-0022 / 解决方案.md）。
///
/// 库存与菜谱都通过 [IngredientCanonicalizer] 映射到统一的食材规格：
/// 1. 别名/精确匹配：系统词典中的同义词视为同一食材（matchType=alias）。
/// 2. 规格条目匹配：名称本身确定规格（精瘦肉=pork+精瘦），解析出基础
///    食材概念与属性分面（matchType=spec）。
/// 3. 格式标准化匹配：trim、去括号备注、全半角、去标点、简繁轻映射、
///    数量单位拆分（matchType=format）。
/// 4. 未知名称：不自动命中，保留原名称（matchType=unknown，需用户确认）。
///
/// 本阶段只实现 alias 与 spec；小番茄≠番茄、鸡蛋≠鸡蛋液等相近食材
/// 一律不默认等价（variant/substitute/category 留待后续）。
library;

import 'ingredient_spec.dart';

/// 匹配类型（ADR-0021 / ADR-0022）。
enum IngredientMatchType {
  /// 原始名称完全相同。
  exact,

  /// 系统词典同义词命中（如 西红柿→番茄）。
  alias,

  /// 格式标准化后相同（括号/全半角/简繁/数量拆分等）。
  format,

  /// 本地规格词典命中，名称确定规格（如 精瘦肉=pork+精瘦）。
  spec,

  /// 未识别，保留原名称，进入待确认。
  unknown,
}

/// 单个食材的标准化结果。
class IngredientCanonicalization {
  const IngredientCanonicalization({
    required this.rawName,
    required this.normalizedName,
    this.canonicalIngredientId,
    this.canonicalName,
    required this.matchType,
    this.cut,
    this.fatLevel,
    this.form,
    this.processing,
    this.specSource = IngredientSpecSource.unknown,
  });

  final String rawName;

  /// 格式标准化后的名称（去括号/标点/全半角/简繁/数量单位）。
  final String normalizedName;

  /// 标准食材 ID，如 `ingredient.tomato`；未识别为 null。
  final String? canonicalIngredientId;

  /// 标准显示名称，如 `番茄`；未识别为 null。
  final String? canonicalName;

  final IngredientMatchType matchType;

  /// 规格条目解析出的属性分面（仅 spec 命中时非空）。
  final IngredientCut? cut;
  final IngredientFatLevel? fatLevel;
  final IngredientForm? form;
  final IngredientProcessing? processing;

  /// 规格来源（本地规则/用户确认/未知）。
  final IngredientSpecSource specSource;

  bool get isKnown => canonicalIngredientId != null;
  double get confidence => switch (matchType) {
    IngredientMatchType.exact => 1.0,
    IngredientMatchType.alias => 1.0,
    IngredientMatchType.spec => 0.9,
    IngredientMatchType.format => 0.5,
    IngredientMatchType.unknown => 0.0,
  };

  /// 解析出的完整规格（未识别时 base 为 null）。
  IngredientSpec get spec => IngredientSpec(
    baseConceptId: canonicalIngredientId,
    baseConceptName: canonicalName,
    cut: cut,
    fatLevel: fatLevel,
    form: form,
    processing: processing,
  );
}

/// 系统词典条目：一组别名指向同一个标准食材。
class IngredientAliasGroup {
  const IngredientAliasGroup({
    required this.canonicalIngredientId,
    required this.canonicalName,
    required this.aliases,
  });

  final String canonicalIngredientId;
  final String canonicalName;

  /// 该食材的所有别名（含标准名本身）。
  final List<String> aliases;
}

/// 系统食材别名词典（ADR-0021）。
///
/// 只收录确定的同义词；相近食材（小番茄/番茄酱/鸡蛋液/小米椒等）
/// 不放入词典，避免误推荐。
class IngredientAliasRepository {
  IngredientAliasRepository({List<IngredientAliasGroup>? groups})
    : _groups = groups ?? defaultGroups,
      _byAlias = <String, IngredientAliasGroup>{
        for (final group in groups ?? defaultGroups)
          for (final alias in group.aliases) alias: group,
      };

  final List<IngredientAliasGroup> _groups;

  /// 别名 → 分组 的哈希索引（解决方案.md 第八节：线性遍历改 Map 查找）。
  final Map<String, IngredientAliasGroup> _byAlias;

  static const List<IngredientAliasGroup> defaultGroups =
      <IngredientAliasGroup>[
        IngredientAliasGroup(
          canonicalIngredientId: 'ingredient.tomato',
          canonicalName: '番茄',
          aliases: <String>['番茄', '西红柿', '蕃茄'],
        ),
        IngredientAliasGroup(
          canonicalIngredientId: 'ingredient.potato',
          canonicalName: '土豆',
          aliases: <String>['土豆', '马铃薯'],
        ),
        IngredientAliasGroup(
          canonicalIngredientId: 'ingredient.corn',
          canonicalName: '玉米',
          aliases: <String>['玉米', '玉蜀黍', '苞米'],
        ),
        IngredientAliasGroup(
          canonicalIngredientId: 'ingredient.eggplant',
          canonicalName: '茄子',
          aliases: <String>['茄子', '茄瓜'],
        ),
        IngredientAliasGroup(
          canonicalIngredientId: 'ingredient.peanut',
          canonicalName: '花生',
          aliases: <String>['花生', '落花生', '长生果'],
        ),
      ];

  /// 按别名查找标准食材（别名应为格式标准化后的名称）。
  IngredientAliasGroup? findByAlias(String normalizedName) {
    return _byAlias[normalizedName];
  }
}

/// 食材统一标准化器（ADR-0021 / ADR-0022 / 解决方案.md 第八节）。
///
/// 所有入口（手动添加库存、菜谱保存/发布、搜索、库存推荐、烹饪完成扣减）
/// 都使用同一个实例执行标准化，保证“搜索能搜到、推荐也必然能匹配”。
class IngredientCanonicalizer {
  IngredientCanonicalizer({
    IngredientAliasRepository? repository,
    IngredientSpecRepository? specRepository,
  }) : _repository = repository ?? IngredientAliasRepository(),
       _specRepository = specRepository ?? IngredientSpecRepository();

  /// 缓存上限：超过后整体清空，防止无限增长。
  static const int _cacheLimit = 2048;

  final IngredientAliasRepository _repository;
  final IngredientSpecRepository _specRepository;

  /// rawName（trim 后）→ 标准化结果的缓存（解决方案.md 第八节）。
  ///
  /// 推荐匹配会对同一名称反复调用（鸡蛋出现在几十道菜里），
  /// 缓存后每个唯一名称只做一次正则/词典解析。
  final Map<String, IngredientCanonicalization> _cache =
      <String, IngredientCanonicalization>{};

  /// 标准化单个名称（带结果缓存）。
  IngredientCanonicalization canonicalize(String rawName) {
    final trimmed = rawName.trim();
    final cached = _cache[trimmed];
    if (cached != null) return cached;
    final result = _canonicalizeUncached(trimmed);
    if (_cache.length >= _cacheLimit) {
      _cache.clear();
    }
    _cache[trimmed] = result;
    return result;
  }

  IngredientCanonicalization _canonicalizeUncached(String trimmed) {
    if (trimmed.isEmpty) {
      return IngredientCanonicalization(
        rawName: trimmed,
        normalizedName: '',
        matchType: IngredientMatchType.unknown,
      );
    }
    final normalized = normalizeFormat(trimmed);
    if (normalized.isEmpty) {
      return IngredientCanonicalization(
        rawName: trimmed,
        normalizedName: trimmed,
        matchType: IngredientMatchType.unknown,
      );
    }
    // 优先查规格条目：名称本身确定规格（精瘦肉=pork+精瘦）。
    final specEntry = _specRepository.findByNormalizedName(normalized);
    if (specEntry != null) {
      return IngredientCanonicalization(
        rawName: trimmed,
        normalizedName: normalized,
        canonicalIngredientId: specEntry.baseConceptId,
        canonicalName: specEntry.baseConceptName,
        cut: specEntry.cut,
        fatLevel: specEntry.fatLevel,
        form: specEntry.form,
        processing: specEntry.processing,
        matchType: IngredientMatchType.spec,
        specSource: IngredientSpecSource.localRule,
      );
    }
    final group = _repository.findByAlias(normalized);
    if (group != null) {
      final isExact = normalized == group.canonicalName;
      return IngredientCanonicalization(
        rawName: trimmed,
        normalizedName: normalized,
        canonicalIngredientId: group.canonicalIngredientId,
        canonicalName: group.canonicalName,
        matchType: isExact
            ? IngredientMatchType.exact
            : IngredientMatchType.alias,
        specSource: IngredientSpecSource.localRule,
      );
    }
    return IngredientCanonicalization(
      rawName: trimmed,
      normalizedName: normalized,
      matchType: IngredientMatchType.unknown,
    );
  }

  /// 两个名称是否为同一种食材（ADR-0022：规格等价才算同一种）。
  ///
  /// 只有“基础食材 + 属性”完全一致才视为同一种，避免把“猪肉”与“五花肉”
  /// 这类上下位/带规格的写法当成完全等价；方向性满足由推荐引擎的
  /// [matchIngredientSpec] 判定。
  bool isSameIngredient(String a, String b) {
    final ca = canonicalize(a);
    final cb = canonicalize(b);
    if (ca.isKnown && cb.isKnown) {
      return ca.canonicalIngredientId == cb.canonicalIngredientId &&
          ca.cut == cb.cut &&
          ca.fatLevel == cb.fatLevel &&
          ca.form == cb.form &&
          ca.processing == cb.processing;
    }
    if (!ca.isKnown &&
        !cb.isKnown &&
        ca.normalizedName.isNotEmpty &&
        ca.normalizedName == cb.normalizedName) {
      return true;
    }
    return false;
  }

  /// 返回与名称同基础食材的规格候选（ADR-0022 渐进式录入第二步）。
  ///
  /// 输入“猪肉”时给出 瘦肉/精瘦肉/五花肉/半肥半瘦/肥肉/肉末 等候选；
  /// 名称未识别时返回空列表，由调用方提示“规格未设置”。
  List<IngredientKnowledgeEntry> specSuggestionsFor(String rawName) {
    final canonical = canonicalize(rawName);
    if (!canonical.isKnown) return const <IngredientKnowledgeEntry>[];
    return _specRepository.entriesForBase(canonical.canonicalIngredientId!);
  }

  /// 名称是否已收录为标准食材（用于判断“未识别项”）。
  bool isKnown(String name) => canonicalize(name).isKnown;

  /// 格式标准化：trim、去括号备注、全角转半角、去多余空格与标点、简繁轻映射、
  /// 剥离尾部数量与单位。
  static String normalizeFormat(String input) {
    var value = _stripParenthesized(input);
    value = _toHalfWidth(value);
    value = _toSimplified(value);
    value = _stripTrailingQuantity(value);
    // 去多余空白与常见标点（保留中文字符、字母与数字；raw string 中不含
    // ASCII 单引号，避免提前终止字符串）。
    value = value.replaceAll(RegExp(r'[\s\u3000]+'), ' ');
    value = value.replaceAll(
      RegExp(r'[，。、；：！？“”‘’·\-—_/\\,.;:!?"()\[\]{}<>~^$+={}|#@%&*]'),
      ' ',
    );
    value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value;
  }

  /// 去掉括号及其内容：`西红柿（新鲜）` → `西红柿`。
  static String _stripParenthesized(String input) {
    return input.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '');
  }

  /// 全角字符转半角（字母、数字、常见符号）。
  static String _toHalfWidth(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// 剥离尾部“数量+单位”，如 `西红柿 2 个` → `西红柿`。
  static String _stripTrailingQuantity(String input) {
    final trimmed = input.trim();
    final match = RegExp(r'(\d+(\.\d+)?\s*[个只枚颗根把斤两克千克毫克毫升升mlMLgGkg]?\s*)$')
        .firstMatch(trimmed);
    if (match == null) return trimmed;
    return trimmed.substring(0, match.start).trim();
  }

  static const Map<String, String> _traditionalToSimplified = <String, String>{
    '雞': '鸡', '豬': '猪', '蔥': '葱', '薑': '姜', '蒜': '蒜', '麪': '面',
    '麵': '面', '魚': '鱼', '蝦': '虾', '蟹': '蟹', '肉': '肉', '醬': '酱',
    '鹽': '盐', '糖': '糖', '油': '油', '醋': '醋', '茄': '茄', '馬': '马',
    '鈴': '铃', '薯': '薯', '玉': '玉', '蜀': '蜀', '黍': '黍', '菠': '菠',
    '菜': '菜', '萵': '莴', '筍': '笋', '萵苣': '莴苣', '蛋': '蛋',
  };

  /// 简繁轻映射（常见食材用字）。
  static String _toSimplified(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_traditionalToSimplified[char] ?? char);
    }
    return buffer.toString();
  }
}
