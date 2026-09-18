import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/ingredient/ingredient_canonicalizer.dart';
import '../../domain/ingredient/ingredient_spec.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 选择食材推荐视图（RECO-001，UI-016）。
///
/// 从分区点选食材（多选），支持快捷选择（全部/临期优先/冷藏区/冷冻区/清空）；
/// 确定性离线匹配本地正式菜谱，分组展示：已具备 / 缺 1 样 / 缺 2 样 /
/// 优先清库存（命中临期）/ 更多缺失（折叠）。卡片标注“已选命中”与
/// “冰箱已有 · 可补选”，命中数量未知批次时提示“数量是否足够需确认”。
class FridgeRecommendationView extends StatefulWidget {
  const FridgeRecommendationView({
    super.key,
    required this.backend,
    required this.refreshToken,
    required this.onOpenRecipe,
  });

  final AiRecipeBackendFacade backend;
  final int refreshToken;
  final Future<void> Function(Recipe recipe) onOpenRecipe;

  @override
  State<FridgeRecommendationView> createState() =>
      _FridgeRecommendationViewState();
}

class _FridgeRecommendationViewState extends State<FridgeRecommendationView> {
  final _selected = <String>{};
  var _strictSelected = false; // “仅使用已选食材”开关（ADR-0021，默认关闭）

  /// 本次推荐会话中用户确认“视为可用”的基础食材 ID（ADR-0022）。
  final _confirmedBases = <String>{};

  late Future<List<AggregatedInventoryItem>> _future;
  var _computing = false;
  List<RecipeRecommendation>? _results;

  /// 选择变化防抖计时器（解决方案.md 四.1：连续勾选停顿后再计算）。
  Timer? _debounce;

  /// 最新请求编号（解决方案.md 四.2：只有最新请求的结果才允许覆盖界面）。
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _future = widget.backend.loadAggregatedInventory();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FridgeRecommendationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _future = widget.backend.loadAggregatedInventory();
      _results = null;
      _confirmedBases.clear();
      _debounce?.cancel();
      _requestId++;
    }
  }

  /// 选择变化后 250ms 防抖触发推荐；快速连续勾选只计算最后一次。
  void _scheduleRecommendation() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runRecommendation);
  }

  void _toggle(String name) {
    setState(() {
      if (!_selected.add(name)) _selected.remove(name);
      _results = null;
    });
    _scheduleRecommendation();
  }

  void _selectAll(List<AggregatedInventoryItem> items) {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          items.where((item) => item.condition != InventoryItemCondition.expired)
              .map((item) => item.ingredientName),
        );
      _results = null;
    });
    _scheduleRecommendation();
  }

  void _selectCondition(
    List<AggregatedInventoryItem> items,
    InventoryItemCondition condition,
  ) {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          items
              .where((item) => item.condition == condition)
              .map((item) => item.ingredientName),
        );
      _results = null;
    });
    _scheduleRecommendation();
  }

  void _selectZone(List<AggregatedInventoryItem> items, InventoryZone zone) {
    setState(() {
      _selected
        ..clear()
        ..addAll(
          items
              .where(
                (item) =>
                    item.zone == zone &&
                    item.condition != InventoryItemCondition.expired,
              )
              .map((item) => item.ingredientName),
        );
      _results = null;
    });
    _scheduleRecommendation();
  }

  void _clearSelection() {
    _debounce?.cancel();
    setState(() {
      _selected.clear();
      _results = null;
    });
  }

  Future<void> _runRecommendation() async {
    if (_selected.isEmpty) return;
    // 最新请求优先：每次计算拿到新的请求编号，旧请求迟到结果直接丢弃。
    final requestId = ++_requestId;
    setState(() => _computing = true);
    try {
      final results = await widget.backend.recommendRecipesFromInventory(
        Set<String>.of(_selected),
        strictSelected: _strictSelected,
        confirmedBases: Set<String>.of(_confirmedBases),
      );
      if (!mounted || requestId != _requestId) return;
      debugPrint(
        '[AIRecipe][Fridge] 推荐完成 selected=${_selected.length} '
        'confirmed=${_confirmedBases.length} results=${results.length}',
      );
      setState(() {
        _results = results;
        _computing = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _computing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      debugPrint('[AIRecipe][Fridge] 推荐失败：$error');
      setState(() => _computing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('推荐暂时无法计算，请稍后重试。')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 用 Stack 实现底部推荐按钮悬浮覆盖在列表之上，避免挤压结果/选择视窗
    // （项目负责人要求：当前非悬浮布局导致筛选结果视窗太小）。
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: FutureBuilder<List<AggregatedInventoryItem>>(
            future: _future,
            builder: (context, state) {
              if (state.connectionState == ConnectionState.waiting) {
                return const Center(child: PixelLoader(size: 7));
              }
              if (state.hasError) {
                return AppErrorState(
                  message: '库存暂时无法读取。',
                  onRetry: () => setState(() => _future = widget.backend.loadAggregatedInventory()),
                );
              }
              final items = state.requireData;
              if (items.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.kitchen_outlined,
                  title: '冰箱还没有食材',
                  message: '先在「库存」里添加食材，再来推荐菜谱。',
                );
              }
              return ListView(
                // 底部预留悬浮按钮高度，避免最后一项被遮挡。
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 130),
                children: <Widget>[
                  const Text(
                    '选择本次想优先使用的食材',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  _QuickActions(
                    onAll: () => _selectAll(items),
                    onSoon: () => _selectCondition(
                      items,
                      InventoryItemCondition.soonExpiring,
                    ),
                    onChilled: () => _selectZone(items, InventoryZone.chilled),
                    onFrozen: () => _selectZone(items, InventoryZone.frozen),
                    onClear: _clearSelection,
                  ),
                  // ADR-0021 第五节：默认“已选偏好 + 冰箱其他食材可补齐”。
                  // 开关独占一行、文字左对齐（项目负责人要求），作为本次匹配的范围偏好。
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '仅使用已选食材',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.ink2,
                          ),
                        ),
                        Switch(
                          key: const Key('strictSelectedSwitch'),
                          value: _strictSelected,
                          onChanged: (value) {
                            setState(() {
                              _strictSelected = value;
                              _results = null;
                            });
                            _scheduleRecommendation();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final zone in InventoryZone.values) ...<Widget>[
                    if (items.any((item) => item.zone == zone)) ...<Widget>[
                      Text(
                        _zoneLabel(zone),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: items
                            .where((item) => item.zone == zone)
                            .map(
                              (item) => _SelectableChip(
                                name: item.ingredientName,
                                detail: item.summary,
                                selected: _selected.contains(item.ingredientName),
                                disabled:
                                    item.condition ==
                                    InventoryItemCondition.expired,
                                condition: item.condition,
                                onTap: () => _toggle(item.ingredientName),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                  if (_results != null) ...<Widget>[
                    const Divider(height: 28),
                    _ResultsSection(
                      results: _results!,
                      onOpenRecipe: widget.onOpenRecipe,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        // 底部推荐按钮悬浮在列表之上（带纸张背景遮罩，可读且不挤压视窗）。
        Align(
          alignment: Alignment.bottomCenter,
          //child: _buildBottomBar(),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final count = _selected.length;
    final label = count == 0 ? '一键用全部库存推荐' : '用已选食材推荐（$count）';
    // 悬浮条带纸张背景 + 顶部细线，覆盖在列表上时可读，且不挤压视窗。
    return Container(
      // decoration: const BoxDecoration(
      //   color: AppColors.paper,
      //   border: Border(top: BorderSide(color: AppColors.line)),
      // ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
          child: FilledButton.icon(
            key: const Key('runRecommendationButton'),
            // 手动点击立即计算：先取消待触发的防抖，避免重复计算。
            onPressed: count == 0 || _computing
                ? null
                : () {
                    _debounce?.cancel();
                    _runRecommendation();
                  },
            icon: _computing
                ? const PixelLoader(size: 5, color: Colors.white)
                : const Icon(Icons.auto_awesome_outlined),
            label: Text(label),
          ),
        ),
      ),
    );
  }

  static String _zoneLabel(InventoryZone zone) => switch (zone) {
    InventoryZone.chilled => '冷藏区',
    InventoryZone.frozen => '冷冻区',
    InventoryZone.roomTemperature => '常温区',
    InventoryZone.other => '其他区',
  };
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAll,
    required this.onSoon,
    required this.onChilled,
    required this.onFrozen,
    required this.onClear,
  });

  final VoidCallback onAll;
  final VoidCallback onSoon;
  final VoidCallback onChilled;
  final VoidCallback onFrozen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _ActionChip(label: '全部', onTap: onAll),
          _ActionChip(label: '临期优先', onTap: onSoon),
          _ActionChip(label: '冷藏区', onTap: onChilled),
          _ActionChip(label: '冷冻区', onTap: onFrozen),
          _ActionChip(label: '清空选择', onTap: onClear),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // CSS .chip：平直小矩形 + inset 1.5px 描边（与筛选 chip 一致）。
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: AppColors.line2, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableChip extends StatelessWidget {
  const _SelectableChip({
    required this.name,
    required this.detail,
    required this.selected,
    required this.disabled,
    required this.condition,
    required this.onTap,
  });

  final String name;
  final String detail;
  final bool selected;
  final bool disabled;
  final InventoryItemCondition condition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 状态变体（HTML .food-chip.soon/.expired/.unknown）：投影 + 描边色。
    final (shadow, border) = switch (condition) {
      InventoryItemCondition.soonExpiring => (
        const Color(0x73B08D4F),
        const Color(0xFFD3B06A),
      ),
      InventoryItemCondition.unknownQuantity => (
        const Color(0x666E8697),
        const Color(0xFF9AB0BE),
      ),
      InventoryItemCondition.expired => (
        const Color(0x66AF6859),
        const Color(0xFFC98A7E),
      ),
      _ => (const Color(0x2936403A), AppColors.line2),
    };
    // HTML .food-chip.selected：green-soft 底 + green-deep 描边 + 名称后 ✓。
    final effectiveShadow = selected ? const Color(0x80476B52) : shadow;
    final effectiveBorder = selected ? AppColors.greenDeep : border;
    final fg = selected ? AppColors.greenDeep : AppColors.ink;
    return Opacity(
      opacity: disabled ? 0.7 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          // 关闭按压水波纹，避免被误认为动画提前触发。
          onTap: disabled ? null : onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // .food-chip：底部 3px 硬投影。
              boxShadow: <BoxShadow>[
                BoxShadow(color: effectiveShadow, offset: const Offset(0, 3)),
              ],
            ),
            child: CustomPaint(
              // .food-chip：inset 1.5px 平直描边。
              foregroundPainter: _InsetRectBorderPainter(
                color: effectiveBorder,
                width: 1.5,
              ),
              child: Container(
                color: selected ? AppColors.greenSoft : AppColors.card,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // .fc-ic：食材图标。
                    Icon(_foodIcon(name), size: 14, color: fg),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // .fc-name：名称 + 选中 ✓。
                        Text(
                          selected ? '$name ✓' : name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 1),
                        // .fc-qty：数量/状态摘要。
                        Text(
                          disabled ? '已过期' : detail,
                          style: TextStyle(
                            fontSize: 10,
                            color: selected
                                ? AppColors.greenDeep.withValues(alpha: .75)
                                : AppColors.ink3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// .fc-ic：按常见食材名映射图标（与冰箱库存页一致）。
  static IconData _foodIcon(String name) {
    if (name.contains('蛋')) return Icons.egg_alt_outlined;
    if (name.contains('奶')) return Icons.local_drink_outlined;
    if (name.contains('肉') ||
        name.contains('鱼') ||
        name.contains('虾') ||
        name.contains('鸡') ||
        name.contains('牛') ||
        name.contains('猪')) {
      return Icons.set_meal_outlined;
    }
    if (name.contains('米') ||
        name.contains('面') ||
        name.contains('饺') ||
        name.contains('粉')) {
      return Icons.rice_bowl_outlined;
    }
    if (name.contains('菜') ||
        name.contains('椒') ||
        name.contains('瓜') ||
        name.contains('葱') ||
        name.contains('姜') ||
        name.contains('蒜') ||
        name.contains('菇') ||
        name.contains('番茄')) {
      return Icons.eco_outlined;
    }
    return Icons.restaurant_outlined;
  }
}

/// 平直矩形 inset 描边绘制器（等效 CSS `inset 0 0 0 1.5px`）。
class _InsetRectBorderPainter extends CustomPainter {
  const _InsetRectBorderPainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Offset.zero & size;
    final inner = Rect.fromLTWH(
      width,
      width,
      (size.width - width * 2).clamp(0, double.infinity),
      (size.height - width * 2).clamp(0, double.infinity),
    );
    final band = Path.combine(
      PathOperation.difference,
      Path()..addRect(outer),
      Path()..addRect(inner),
    );
    canvas.drawPath(band, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _InsetRectBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.width != width;
  }
}

/// 推荐结果分组展示（ADR-0022）：
/// 现在就能做 / 可能可以做 / 库存不足 / 缺 1 样 / 缺 2 样 /
/// 优先清库存 / 更多缺失。
///
/// 解决方案.md 第七节：每组首批只展示 Top 10，剩余结果通过"查看更多"
/// 增量展示，避免一次构建几百张推荐卡片。
class _ResultsSection extends StatefulWidget {
  const _ResultsSection({
    required this.results,
    required this.onOpenRecipe,
  });

  final List<RecipeRecommendation> results;
  final Future<void> Function(Recipe recipe) onOpenRecipe;

  @override
  State<_ResultsSection> createState() => _ResultsSectionState();
}

class _ResultsSectionState extends State<_ResultsSection> {
  /// 每组首批展示条数上限（解决方案.md：Top 10～20）。
  static const int _maxPerGroup = 10;

  /// 已展开"查看更多"的分组名。
  final _expanded = <String>{};

  /// 整组被折叠（只显示标题）的分组名。
  final _collapsed = <String>{};

  @override
  void initState() {
    super.initState();
    // 项目负责人要求：推荐结果里「缺 N 样」分组默认折叠，只显示标题，
    // 点标题可展开/收起，避免缺食材的菜谱把结果页撑得过长。
    _collapsed.addAll(const <String>['缺 1 样', '缺 2 样']);
  }

  bool _isExpanded(String group) => _expanded.contains(group);

  void _toggleExpand(String group) {
    setState(() {
      if (!_expanded.remove(group)) _expanded.add(group);
    });
  }

  /// 切换某分组的整组折叠状态。
  void _toggleCollapse(String group) {
    setState(() {
      if (!_collapsed.remove(group)) _collapsed.add(group);
    });
  }

  /// 未展开时每组最多返回前 [_maxPerGroup] 条。
  List<RecipeRecommendation> _visible(
    List<RecipeRecommendation> list,
    String group,
  ) {
    if (list.length <= _maxPerGroup || _isExpanded(group)) return list;
    return list.sublist(0, _maxPerGroup);
  }

  /// 渲染一组：旗标带标题 + 卡片 + （折叠时）查看更多按钮。
  ///
  /// [collapsible] 为 true 时该组支持整组折叠（只显示标题，点标题展开/收起）。
  /// [band]/[soft]/[ink] 为方案A像素旗标带的三档配色（实色带/浅底计数/深字）。
  Widget _buildGroup(
    String title,
    List<RecipeRecommendation> list, {
    required Color band,
    required Color soft,
    required Color ink,
    bool emphasizeExpiring = false,
    bool collapsible = false,
  }) {
    if (list.isEmpty) return const SizedBox.shrink();
    final collapsed = collapsible && _collapsed.contains(title);
    final visible = collapsed
        ? const <RecipeRecommendation>[]
        : _visible(list, title);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _GroupRibbon(
          title: title,
          count: list.length,
          band: band,
          soft: soft,
          ink: ink,
          collapsed: collapsed,
          onToggle: collapsible ? () => _toggleCollapse(title) : null,
        ),
        ...visible.map(
          (r) => _RecommendationCard(
            recommendation: r,
            onOpenRecipe: widget.onOpenRecipe,
            emphasizeExpiring: emphasizeExpiring,
          ),
        ),
        if (!collapsed &&
            list.length > _maxPerGroup &&
            !_isExpanded(title))
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OutlinedButton(
                onPressed: () => _toggleExpand(title),
                child: Text(
                  '查看更多（${list.length - _maxPerGroup}）',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results;
    if (results.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_rounded,
        title: '暂无可推荐的菜谱',
        message: '本地正式菜谱中没有与所选食材匹配的结果。\n'
            '请确认菜谱为正式菜谱、食材名称一致，或继续维护库存。',
      );
    }
    final ready = results
        .where(
          (r) =>
              r.shortageCount == 0 &&
              r.maybeCount == 0 &&
              !r.hasInsufficientStock,
        )
        .toList(growable: false);
    final maybe = results
        .where((r) => r.shortageCount == 0 && r.maybeCount > 0)
        .toList(growable: false);
    final insufficient = results
        .where(
          (r) =>
              r.shortageCount == 0 &&
              r.maybeCount == 0 &&
              r.hasInsufficientStock,
        )
        .toList(growable: false);
    final miss1 = results
        .where((r) => r.shortageCount == 1)
        .toList(growable: false);
    final miss2 = results
        .where((r) => r.shortageCount == 2)
        .toList(growable: false);
    final priority = results
        .where((r) => r.expiringHit.isNotEmpty && r.shortageCount <= 2)
        .toList(growable: false);
    final more = results.where((r) => r.shortageCount > 2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _buildGroup(
          '现在就能做',
          ready,
          band: AppColors.green,
          soft: AppColors.greenSoft,
          ink: AppColors.greenInk,
          collapsible: true,
        ),
        _buildGroup(
          '可能可以做',
          maybe,
          band: AppColors.amber,
          soft: AppColors.amberSoft,
          ink: const Color(0xFF75602C),
        ),
        _buildGroup(
          '库存不足',
          insufficient,
          band: AppColors.red,
          soft: AppColors.redSoft,
          ink: const Color(0xFF7C3A2E),
        ),
        _buildGroup(
          '缺 1 样',
          miss1,
          band: AppColors.amber,
          soft: AppColors.amberSoft,
          ink: const Color(0xFF75602C),
          collapsible: true,
        ),
        _buildGroup(
          '缺 2 样',
          miss2,
          band: AppColors.amber,
          soft: AppColors.amberSoft,
          ink: const Color(0xFF75602C),
          collapsible: true,
        ),
        _buildGroup(
          '优先清库存',
          priority,
          band: AppColors.blue,
          soft: AppColors.blueSoft,
          ink: const Color(0xFF3D4B5C),
          emphasizeExpiring: true,
          collapsible: true,
        ),
        if (more.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          _FoldableMore(
            results: more,
            totalCount: more.length,
            onOpenRecipe: widget.onOpenRecipe,
          ),
        ],
      ],
    );
  }
}

/// 方案A · 像素旗标带：色带（rg-band）+ 计数（rg-count）+ 虚线延伸（rg-line）。
///
/// 对照 design/prototypes/prototype.css `.rg-ribbon` 实现。整行可点击时
/// （[onToggle] 非空）带展开/收起箭头，用于「缺 N 样」整组折叠。
class _GroupRibbon extends StatelessWidget {
  const _GroupRibbon({
    required this.title,
    required this.count,
    required this.band,
    required this.soft,
    required this.ink,
    this.collapsed = false,
    this.onToggle,
  });

  final String title;
  final int count;
  final Color band;
  final Color soft;
  final Color ink;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    // 色带：实色底 + 小切角（rg-band + pxc-sm，无投影，项目负责人要求）。
    final bandWidget = ClipPath(
      clipper: const PixelCutClipper(cut: PixelCut.sm),
      child: Container(
        color: band,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Colors.white,
          ),
        ),
      ),
    );
    // 计数徽标：浅底 + 深字 + 小切角（rg-count + pxc-xs）。
    final countWidget = ClipPath(
      clipper: const PixelCutClipper(cut: PixelCut.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        color: soft,
        child: Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
      ),
    );
    // 虚线延伸（rg-line）：同色 6px 色块 + 6px 透明重复。
    final lineWidget = Expanded(
      child: CustomPaint(
        painter: _RibbonLinePainter(color: band),
        child: const SizedBox(height: 2),
      ),
    );

    final ribbon = Row(
      children: <Widget>[
        bandWidget,
        const SizedBox(width: 9),
        countWidget,
        const SizedBox(width: 9),
        lineWidget,
      ],
    );

    // 整体外边距；（可折叠时）整行可点并带展开/收起箭头。
    // 底部留出更大间距，让旗标带标题与下方第一张卡片拉开（项目负责人要求）。
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 14),
      child: onToggle == null
          ? ribbon
          : InkWell(
              onTap: onToggle,
              child: Row(
                children: <Widget>[
                  Expanded(child: ribbon),
                  Icon(
                    collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 20,
                    color: band,
                  ),
                ],
              ),
            ),
    );
  }
}

/// 方案A 虚线延伸的绘制器：6px 色块 + 6px 透明重复（rg-line）。
class _RibbonLinePainter extends CustomPainter {
  const _RibbonLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: 0.45);
    var x = 0.0;
    while (x < size.width) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 6, size.height), paint);
      x += 12;
    }
  }

  @override
  bool shouldRepaint(_RibbonLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RecommendationCard extends StatefulWidget {
  const _RecommendationCard({
    required this.recommendation,
    required this.onOpenRecipe,
    this.emphasizeExpiring = false,
  });

  final RecipeRecommendation recommendation;
  final Future<void> Function(Recipe recipe) onOpenRecipe;
  final bool emphasizeExpiring;

  @override
  State<_RecommendationCard> createState() => _RecommendationCardState();
}

class _RecommendationCardState extends State<_RecommendationCard> {
  /// 卡片内“食材”区（食材标签 + 匹配依据）是否展开；默认展开，
  /// 可折叠以只保留标题/匹配度/操作按钮（项目负责人要求）。
  var _showIngredients = true;

  void _toggleIngredients() =>
      setState(() => _showIngredients = !_showIngredients);

  @override
  Widget build(BuildContext context) {
    final r = widget.recommendation;
    final recipe = r.recipe;
    final minutes = (recipe.prepTimeMinutes ?? 0) + (recipe.cookTimeMinutes ?? 0);
    final difficulty = _difficultyLabel(recipe.difficulty);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PixelSurface(
        cut: 5,
        elevation: 0,
        color: AppColors.card,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 卡片头部（HTML .card：封面 56×56 + 标题 + tiny + 匹配 conf）。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _cardCover(recipe),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        recipe.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (minutes > 0 || difficulty.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (minutes > 0) '$minutes 分钟',
                            difficulty,
                          ].where((part) => part.isNotEmpty).join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                PixelBadge(
                  label: '匹配 ${r.matchedCount}/${r.requiredIngredientCount}',
                  tone: r.shortageCount == 0 && r.maybeCount == 0
                      ? PixelNoticeTone.green
                      : PixelNoticeTone.amber,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 卡片内“食材”区折叠开关（可点击，默认展开）。
            InkWell(
              onTap: _toggleIngredients,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                // children: <Widget>[
                //   const Text(
                //     '食材',
                //     style: TextStyle(
                //       fontSize: 11,
                //       fontWeight: FontWeight.w800,
                //       color: AppColors.ink2,
                //     ),
                //   ),
                //   Row(
                //     mainAxisSize: MainAxisSize.min,
                //     children: <Widget>[
                //       Text(
                //         _showIngredients ? '收起' : '展开',
                //         style: const TextStyle(
                //           fontSize: 10,
                //           color: AppColors.ink3,
                //         ),
                //       ),
                //       Icon(
                //         _showIngredients
                //             ? Icons.keyboard_arrow_up_rounded
                //             : Icons.keyboard_arrow_down_rounded,
                //         size: 18,
                //         color: AppColors.ink3,
                //       ),
                //     ],
                //   ),
                // ],
              ),
            ),
            if (_showIngredients) ...<Widget>[
              // 食材标签区（HTML .mini-tag hit/have/miss 配色）：
              // 已选命中=绿、冰箱已有可补选=蓝、缺失=琥珀（带数量）、
              // 替代（MAYBE，如 牛肉→猪肉）=黄、规格不符=红。
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final detail in r.matchDetails)
                    if (detail.verdict != IngredientMatchVerdict.maybe)
                      switch (detail.kind) {
                        RecommendationMatchKind.selectedHit => _MiniTag(
                          label: '已选命中 · ${detail.rawName}',
                          bg: _tagHitBg,
                          fg: _tagHitFg,
                          border: _tagHitBorder,
                        ),
                        RecommendationMatchKind.inFridgeNotSelected => _MiniTag(
                          label: '冰箱已有 · 可补选 · ${detail.rawName}',
                          bg: _tagHaveBg,
                          fg: _tagHaveFg,
                          border: _tagHaveBorder,
                        ),
                        RecommendationMatchKind.missing => _MiniTag(
                          label: '缺失 · ${_missingLabel(detail)}',
                          bg: _tagMissBg,
                          fg: _tagMissFg,
                          border: _tagMissBorder,
                        ),
                      },
                  // ADR-0023：待确认（MAYBE，同家族替代）用黄色标签表达
                  // “替代 菜谱食材→库存食材”，不再用“待确认：…”文本行。
                  for (final detail in r.matchDetails)
                    if (detail.verdict == IngredientMatchVerdict.maybe)
                      _MiniTag(
                        label: '替代 ${detail.rawName}'
                            '→${detail.matchedStockName ?? detail.verdictReason ?? ''}',
                        bg: _tagSubBg,
                        fg: _tagSubFg,
                        border: _tagSubBorder,
                      ),
                  // ADR-0022：规格冲突标签。
                  for (final name in r.noMatchNames)
                    _MiniTag(
                      label: '规格不符 · $name',
                      bg: _tagNoBg,
                      fg: _tagNoFg,
                      border: _tagNoBorder,
                    ),
                ],
              ),
              // 匹配依据展示（ADR-0021 第九节）。
              // if (r.matchDetails.any(
              //   (detail) =>
              //       detail.kind != RecommendationMatchKind.missing &&
              //       detail.matchType != IngredientMatchType.exact &&
              //       detail.verdict != IngredientMatchVerdict.maybe,
              // )) ...<Widget>[
              //   const SizedBox(height: 6),
              //   for (final detail in r.matchDetails)
              //     if (detail.kind != RecommendationMatchKind.missing &&
              //         detail.matchType != IngredientMatchType.exact &&
              //         detail.verdict != IngredientMatchVerdict.maybe)
              //       Text(
              //         detail.explanation,
              //         style: Theme.of(context).textTheme.bodySmall?.copyWith(
              //           color: AppColors.ink2,
              //         ),
              //       ),
              // ],
              // ADR-0022：规格冲突（NO）原因。
              if (r.noMatchNames.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                for (final detail in r.matchDetails)
                  if (detail.verdict == IngredientMatchVerdict.no)
                    Text(
                      '规格不符：${detail.rawName}'
                      '${detail.verdictReason == null ? '' : ' — ${detail.verdictReason}'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ],
              if (r.insufficientNames.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                for (final detail in r.matchDetails)
                  if (detail.sufficiency == IngredientSufficiency.insufficient)
                    Text(
                      '库存不足：${detail.rawName} 还需要 '
                      '${_shortNumber((detail.requiredQuantity ?? 0) - (detail.availableQuantity ?? 0))}'
                      '${detail.unit ?? ''}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ],
              if (widget.emphasizeExpiring &&
                  r.expiringHit.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  '优先清库存：${r.expiringHit.join('、')} 为临期食材',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => widget.onOpenRecipe(recipe),
                  // 收紧水平内边距、字号 16、补上下边距（项目负责人要求）。
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(fontSize: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('查看详情'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => widget.onOpenRecipe(recipe),
                  // 收紧水平内边距、字号 16、补上下边距（项目负责人要求）。
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(fontSize: 16),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('开始烹饪'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片封面（HTML .card .cover 56×56）：有图显示真实图片，
  /// 无图回退像素图标块。
  Widget _cardCover(Recipe recipe) {
    final cover = recipe.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return PixelSurface(
        cut: 4,
        elevation: 0,
        color: AppColors.greenSofter,
        borderColor: AppColors.line2,
        child: SizedBox.square(
          dimension: 56,
          child: Icon(
            _coverIcon(recipe.title),
            color: AppColors.greenDeep,
            size: 26,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: 56,
        child: Image.file(
          File(cover),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: AppColors.greenSofter,
            child: const Icon(
              Icons.broken_image_outlined,
              color: AppColors.ink3,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  /// 无封面时按菜名映射回退图标。
  static IconData _coverIcon(String title) {
    if (title.contains('鱼') ||
        title.contains('虾') ||
        title.contains('肉') ||
        title.contains('鸡')) {
      return Icons.set_meal_outlined;
    }
    if (title.contains('面') ||
        title.contains('饺') ||
        title.contains('饭') ||
        title.contains('粥')) {
      return Icons.rice_bowl_outlined;
    }
    if (title.contains('菜') || title.contains('汤')) {
      return Icons.eco_outlined;
    }
    return Icons.restaurant_outlined;
  }

  static String _difficultyLabel(RecipeDifficulty difficulty) =>
      switch (difficulty) {
        RecipeDifficulty.easy => '简单',
        RecipeDifficulty.medium => '中等',
        RecipeDifficulty.hard => '较难',
        RecipeDifficulty.unspecified => '',
      };

  /// 缺失标签文案（HTML .mini-tag.miss：“缺失 · 鸡腿 400 g”）。
  /// 菜谱需求可解析时带数量与单位，否则只显示食材名。
  static String _missingLabel(IngredientMatchDetail detail) {
    final qty = detail.requiredQuantity;
    if (qty == null) return detail.rawName;
    final unit = detail.unit?.trim();
    final qtyText = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toString();
    return '${detail.rawName} '
        '${unit == null || unit.isEmpty ? qtyText : '$qtyText $unit'}';
  }

  static String _shortNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
}

/// HTML .mini-tag 配色（prototype.css 1175-1177）：
/// hit=绿（--green-soft/--green-ink）、have=蓝（--blue-soft/#3D4B5C）。
const _tagHitBg = Color(0xFFDDE7DC);
const _tagHitFg = Color(0xFF33513C);
const _tagHitBorder = Color(0x66476B52); // rgba(71,107,82,.4)

const _tagHaveBg = Color(0xFFE3E9ED);
const _tagHaveFg = Color(0xFF3D4B5C);
const _tagHaveBorder = Color(0x736E8697); // rgba(110,134,151,.45)

/// 缺失标签：项目负责人指定使用灰色（覆盖原型琥珀 .mini-tag.miss）。
const _tagMissBg = Color(0xFFE9E8E3);
const _tagMissFg = Color(0xFF5F645F);
const _tagMissBorder = Color(0x735F645F);

/// 替代（MAYBE）标签：黄色（琥珀系），表达“替代 菜谱食材→库存食材”。
const _tagSubBg = Color(0xFFF3EBD6);
const _tagSubFg = Color(0xFF75602C);
const _tagSubBorder = Color(0x73B08D4F); // rgba(176,141,79,.45)

/// 规格不符（NO）标签：沿用既有红色系（HTML 无对应变体）。
const _tagNoBg = Color(0x1AA9654F);
const _tagNoFg = AppColors.red;
const _tagNoBorder = Color(0x73A9654F);

/// HTML .mini-tag：浅底 + 深字 + 1px 描边的小标签。
class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.label,
    required this.bg,
    required this.fg,
    required this.border,
  });

  final String label;
  final Color bg;
  final Color fg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1.2,
        ),
      ),
    );
  }
}

/// 「更多缺失」折叠面板（1:1 复刻原型 `details.fold`）。
///
/// 原型（app.js UI-016）：
/// ```html
/// <details class="fold mb12">
///   <summary>… 更多缺失（缺 3 样以上 · 2）</summary>
///   <div class="fold-body">
///     <p>宫保鸡丁 — 缺 鸡腿、花生、干辣椒、葱（4 样）</p>
///     <p class="tiny">缺失超过 2 样默认折叠，不虚假标记为「能做」。</p>
///   </div>
/// </details>
/// ```
/// `details.fold`：pxc-sm 切角 + `--px-line`(line2 1.5px) 描边 + card 底；
/// summary 可点击（more 图标 + 标题 + 展开箭头），展开后显示 fold-body。
class _FoldableMore extends StatefulWidget {
  const _FoldableMore({
    required this.results,
    required this.totalCount,
    required this.onOpenRecipe,
  });

  /// 缺失超过 2 样的菜谱（全部，展开时展示）。
  final List<RecipeRecommendation> results;
  final int totalCount;
  final Future<void> Function(Recipe recipe) onOpenRecipe;

  @override
  State<_FoldableMore> createState() => _FoldableMoreState();
}

class _FoldableMoreState extends State<_FoldableMore> {
  /// 默认折叠（与原型 `<details>` 行为一致），点击 summary 展开/收起。
  var _open = false;

  void _toggle() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 12),
      child: ClipPath(
        clipper: const PixelCutClipper(cut: PixelCut.sm),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            // details.fold：--px-line = line2 1.5px 描边。
            border: Border.all(color: AppColors.line2, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // summary：more 图标 + 标题 + 箭头，整行可点。
              InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.more_horiz_rounded,
                        size: 15,
                        color: AppColors.ink2,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '更多缺失（缺 3 样以上 · ${widget.totalCount}）',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      Icon(
                        _open
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
              ),
              if (_open) ...<Widget>[
                // details.fold[open] summary：底部 1.5px 分隔线。
                Container(height: 1.5, color: AppColors.line),
                // fold-body：每个缺失菜谱一行。
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final r in widget.results) ...<Widget>[
                        InkWell(
                          onTap: () => widget.onOpenRecipe(r.recipe),
                          child: Text(
                            '${r.recipe.title} — 缺 '
                            '${r.missing.join('、')}（${r.missingCount} 样）',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.ink2,
                                  height: 1.7,
                                ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        '缺失超过 2 样默认折叠，不虚假标记为「能做」。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.ink3,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
