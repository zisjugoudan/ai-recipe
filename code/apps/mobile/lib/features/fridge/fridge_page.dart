import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/ingredient/ingredient_canonicalizer.dart';
import '../../domain/inventory/inventory_batch.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import 'fridge_batch_edit_page.dart';
import 'fridge_recommendation_view.dart';

/// 冰箱页（FRIDGE-002/RECO-001）：轻拟物分区库存 + 选择食材推荐 二级切换。
class FridgePage extends StatefulWidget {
  const FridgePage({
    super.key,
    required this.backend,
    required this.onDataChanged,
    required this.onOpenRecipe,
    this.refreshToken = 0,
  });

  final AiRecipeBackendFacade backend;
  final VoidCallback onDataChanged;
  final Future<void> Function(Recipe recipe) onOpenRecipe;
  final int refreshToken;

  @override
  State<FridgePage> createState() => _FridgePageState();
}

class _FridgePageState extends State<FridgePage> {
  var _tab = 0; // 0=库存，1=推荐

  /// 本页数据变更计数：批次新增/编辑/删除保存返回后递增，
  /// 让 _InventoryView 立即重载（不依赖 AppShell 的 refreshToken 链路）。
  var _localRefresh = 0;

  @override
  void didUpdateWidget(covariant FridgePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(() {});
    }
  }

  Future<void> _openBatchEditor({InventoryZone? zone, InventoryBatch? batch}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => FridgeBatchEditPage(
          backend: widget.backend,
          initialZone: zone,
          batch: batch,
        ),
      ),
    );
    if (changed == true && mounted) {
      // 保存成功：本地立即刷新库存视图，并通知外部数据已变化。
      setState(() => _localRefresh++);
      widget.onDataChanged();
    }
  }

  Future<void> _confirmBatchAction(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: title,
      message: message,
    );
    if (confirmed != true || !mounted) return;
    try {
      await action();
      widget.onDataChanged();
      if (mounted) setState(() => _localRefresh++);
    } on AiRecipeBackendException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 透明露出全局纸张背景 #F3F1E9（HTML body 一致）。
      backgroundColor: Colors.transparent,
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              key: const Key('addInventoryBatchFab'),
              tooltip: '添加食材',
              onPressed: () => _openBatchEditor(),
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            // HTML UI-014 顶部：.seg 二级切换（库存/推荐）。
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: PixelSeg(
                tabs: const <String>['库存', '推荐'],
                index: _tab,
                onChanged: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(
              child: _tab == 0
                  ? _InventoryView(
                      backend: widget.backend,
                      refreshToken: widget.refreshToken + _localRefresh,
                      onOpenBatchEditor: _openBatchEditor,
                      onConfirmAction: _confirmBatchAction,
                      onOpenRecommendation: () => setState(() => _tab = 1),
                      onDataChanged: widget.onDataChanged,
                    )
                  : FridgeRecommendationView(
                      backend: widget.backend,
                      refreshToken: widget.refreshToken,
                      onOpenRecipe: widget.onOpenRecipe,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 库存筛选类型。
enum _InventoryFilter { all, soon, expired, unknown, chilled, frozen, room, other }

/// 拖拽移动的动画类型：只有跨冷冻区边界才播放逐格动画。
enum _FrostKind {
  /// 不播放颜色动画（同区排序、非冷冻区之间移动）。
  none,

  /// 非冷冻区 → 冷冻区：正常→冰冻，逐格出现。
  freezeIn,

  /// 冷冻区 → 非冷冻区：冰冻→正常，逐格消失。
  thawOut,
}

/// 一次拖拽的唯一到达事件。
///
/// 只在“最终目标接收 + 库存移动保存成功 + 目标 chip 挂载”之后生成一次，
/// 由目标 chip 消费后立即从待处理集合移除；长按、拖动经过、无效释放、
/// 同区排序、页面重建都不会产生该事件。
class _ArrivalEvent {
  const _ArrivalEvent({
    required this.dragSessionId,
    required this.moveEventId,
    required this.stableItemId,
    required this.kind,
  });

  /// 标识一次完整长按拖拽会话（一次性消费防重复提交）。
  final String dragSessionId;

  /// 单调递增的提交序号，同一会话/页面内全局唯一。
  final int moveEventId;

  /// 被移动聚合项的稳定身份（批次 ID 集合，见 stableId）。
  final String stableItemId;

  final _FrostKind kind;
}

/// 库存视图：摘要、临期提醒、筛选、分区卡片（聚合展开批次）。
class _InventoryView extends StatefulWidget {
  const _InventoryView({
    required this.backend,
    required this.refreshToken,
    required this.onOpenBatchEditor,
    required this.onConfirmAction,
    required this.onOpenRecommendation,
    required this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final int refreshToken;
  final Future<void> Function({InventoryZone? zone, InventoryBatch? batch})
  onOpenBatchEditor;
  final Future<void> Function(
    String title,
    String message,
    Future<void> Function() action,
  )
  onConfirmAction;
  final VoidCallback onOpenRecommendation;

  /// 库存数据变化后通知外部刷新（拖拽排序/跨区移动持久化后调用）。
  final VoidCallback onDataChanged;

  @override
  State<_InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<_InventoryView> {
  var _filter = _InventoryFilter.all;
  final _queryController = TextEditingController();
  var _query = '';
  late Future<(InventorySummary, List<AggregatedInventoryItem>)> _future;

  /// 加载后的全部库存条目（可变副本）：长按拖动排序/跨区移动后本地更新。
  List<AggregatedInventoryItem>? _allItems;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      // 外部数据已变化（如批次编辑保存日期/分区）：清空本地副本，
      // 让加载结果重新填充，否则 _allItems ??= 会沿用旧缓存导致不刷新。
      _allItems = null;
      _future = _load();
    }
  }

  Future<(InventorySummary, List<AggregatedInventoryItem>)> _load() async {
    final summary = await widget.backend.loadInventorySummary();
    final items = await widget.backend.loadAggregatedInventory();
    return (summary, items);
  }

  /// 单调递增的拖拽提交序号：每个成功提交的移动分配唯一 moveEventId。
  int _moveEventSeq = 0;

  /// 当前进行中的长按拖拽会话 ID（一次完整拖拽唯一，防重复提交）。
  String? _activeDragSession;

  /// 已提交过的拖拽会话 ID：同一会话只允许提交一次。
  String? _committedDragSession;

  /// 保存成功、待目标 chip 消费的到达事件（moveEventId → 事件）。
  /// chip 消费后立即删除，页面重建即清空，不会重播旧动画。
  final Map<int, _ArrivalEvent> _pendingArrivals = <int, _ArrivalEvent>{};

  /// 开始一次长按拖拽：生成唯一会话 ID。
  void _beginDragSession() {
    _activeDragSession = 'drag_${DateTime.now().microsecondsSinceEpoch}';
    _committedDragSession = null;
    debugPrint('[AIRecipe][Fridge][Drag] 开始拖拽 session=$_activeDragSession');
  }

  /// 长按拖放处理（唯一提交入口）：把 [dragged] 移动到目标分区
  /// [targetZone] 的 [insertIndex]（0=最前，items.length=末尾）。
  ///
  /// 流程：判断有效性 → 先持久化 → 保存成功后才更新本地数据并挂载目标 chip，
  /// 再生成唯一到达事件（仅跨冷冻区边界）；保存失败恢复原位并提示，不生成事件。
  Future<void> _applyDrop(
    AggregatedInventoryItem dragged,
    InventoryZone targetZone,
    int insertIndex,
  ) async {
    // 会话级一次性提交守卫：同一拖拽会话只允许提交一次
    // （即使嵌套 DragTarget 意外重复回调，后续调用直接忽略）。
    // 注意：只有"会话已存在且已提交"才拦截；onDragStarted 未触发时
    // _activeDragSession 为 null，此时仍应正常处理拖放，否则会静默失败。
    if (_activeDragSession != null &&
        _committedDragSession == _activeDragSession) {
      debugPrint(
        '[AIRecipe][Fridge][Drag] 会话重复提交被拦截 '
        'session=$_activeDragSession',
      );
      return;
    }
    _committedDragSession = _activeDragSession;
    var current = List<AggregatedInventoryItem>.of(_allItems ?? const []);
    var fromIndex = current.indexWhere(
      (item) => item.stableId == dragged.stableId,
    );
    if (fromIndex < 0) {
      // 数据陈旧（_allItems 被刷新置空或列表已变化）：先重新加载一次，
      // 避免拖放静默失败；仍找不到则放弃（不烧掉会话守卫）。
      debugPrint(
        '[AIRecipe][Fridge][Drag] 本地列表未命中 ${dragged.stableId}，'
        '重新加载后再试',
      );
      try {
        final items = await widget.backend.loadAggregatedInventory();
        _allItems = List<AggregatedInventoryItem>.of(items);
        current = List<AggregatedInventoryItem>.of(items);
        fromIndex = current.indexWhere(
          (item) => item.stableId == dragged.stableId,
        );
      } catch (_) {
        fromIndex = -1;
      }
      if (fromIndex < 0) {
        debugPrint(
          '[AIRecipe][Fridge][Drag] 重载后仍找不到 ${dragged.stableId}，'
          '放弃本次拖放',
        );
        return;
      }
    }
    final moved = current.removeAt(fromIndex);

    // 计算目标分区内插入位置对应的全局下标（与筛选无关，按分区顺序定位）。
    final targetItems = current
        .where((item) => item.zone == targetZone)
        .toList(growable: false);
    var globalIndex = current.length;
    final clamped = insertIndex.clamp(0, targetItems.length);
    if (clamped < targetItems.length) {
      var seen = 0;
      for (var i = 0; i < current.length; i++) {
        if (current[i].zone == targetZone) {
          if (seen == clamped) {
            globalIndex = i;
            break;
          }
          seen++;
        }
      }
    }
    current.insert(
      globalIndex,
      AggregatedInventoryItem(
        ingredientName: moved.ingredientName,
        zone: targetZone,
        batches: moved.batches,
        condition: moved.condition,
      ),
    );

    // 与拖拽前顺序完全一致 → 无效移动（同区原位置放下），不提交、无动画。
    final beforeOrder = (_allItems ?? const <AggregatedInventoryItem>[])
        .map((item) => item.stableId)
        .toList(growable: false);
    final afterOrder = current.map((item) => item.stableId).toList(growable: false);
    if (beforeOrder.length == afterOrder.length &&
        _sameOrder(beforeOrder, afterOrder)) {
      debugPrint(
        '[AIRecipe][Fridge][Drag] 无效移动（顺序未变化）'
        ' ${moved.ingredientName} -> ${targetZone.name}',
      );
      return;
    }

    // 是否跨冷冻区边界：决定动画类型（同区排序/非冷冻互移 = none）。
    final kind = switch ((moved.zone, targetZone)) {
      (InventoryZone.frozen, InventoryZone.frozen) => _FrostKind.none,
      (final source, InventoryZone.frozen) when source != InventoryZone.frozen =>
        _FrostKind.freezeIn,
      (InventoryZone.frozen, final target) when target != InventoryZone.frozen =>
        _FrostKind.thawOut,
      _ => _FrostKind.none,
    };

    // 先持久化：跨区批次改分区；分区内按新顺序重新编号。
    final zoneCounters = <InventoryZone, int>{};
    try {
      for (final item in current) {
        final order = zoneCounters[item.zone] ?? 0;
        for (final batch in item.batches) {
          if (batch.zone != item.zone) {
            await widget.backend.moveInventoryBatchToZone(batch.id, item.zone);
          }
          await widget.backend.reorderInventoryBatch(batch.id, order);
        }
        zoneCounters[item.zone] = order + 1;
      }
    } on AiRecipeBackendException catch (error) {
      // 保存失败：恢复原位置（重新加载持久化数据）+ 中文提示，不生成动画事件。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('移动失败，食材已放回原位置，请重试。'),
          ),
        );
        debugPrint(
          '[AIRecipe][Fridge][Drag] 拖拽保存失败：${error.message}',
        );
      }
      if (mounted) {
        setState(() {
          _allItems = null;
          _future = _load();
        });
      }
      return;
    }

    // 保存成功：更新本地数据并挂载目标 chip，然后生成唯一到达事件。
    debugPrint(
      '[AIRecipe][Fridge][Drag] 移动成功 ${moved.ingredientName} '
      '${moved.zone.name} -> ${targetZone.name} kind=${kind.name}',
    );
    setState(() {
      _allItems = current;
      if (kind != _FrostKind.none) {
        _moveEventSeq++;
        _pendingArrivals[_moveEventSeq] = _ArrivalEvent(
          dragSessionId: _activeDragSession ?? '',
          moveEventId: _moveEventSeq,
          stableItemId: moved.stableId,
          kind: kind,
        );
      }
    });
  }

  /// 按顺序逐一比较两个稳定 ID 列表是否一致。
  static bool _sameOrder(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 目标 chip 消费到达事件后回调：从待处理集合移除（消费即删除）。
  void _consumeArrival(int moveEventId) {
    if (!mounted || !_pendingArrivals.containsKey(moveEventId)) return;
    setState(() => _pendingArrivals.remove(moveEventId));
  }

  void _setFilter(_InventoryFilter filter) {
    setState(() => _filter = filter);
  }

  bool _matches(InventoryItemCondition condition, InventoryZone zone) {
    return switch (_filter) {
      _InventoryFilter.all => true,
      _InventoryFilter.soon => condition == InventoryItemCondition.soonExpiring,
      _InventoryFilter.expired => condition == InventoryItemCondition.expired,
      _InventoryFilter.unknown =>
        condition == InventoryItemCondition.unknownQuantity ||
            condition == InventoryItemCondition.noDate,
      _InventoryFilter.chilled => zone == InventoryZone.chilled,
      _InventoryFilter.frozen => zone == InventoryZone.frozen,
      _InventoryFilter.room => zone == InventoryZone.roomTemperature,
      _InventoryFilter.other => zone == InventoryZone.other,
    };
  }

  /// 搜索命中：名称包含关键词，或与关键词映射到同一标准食材（同义词命中）。
  bool _matchesSearch(
    AggregatedInventoryItem item,
    IngredientCanonicalization? queryCanonical,
    IngredientCanonicalizer canonicalizer,
  ) {
    final name = item.ingredientName;
    if (name.toLowerCase().contains(_query.trim().toLowerCase())) return true;
    final query = queryCanonical;
    if (query == null || !query.isKnown) return false;
    return canonicalizer.canonicalize(name).canonicalIngredientId ==
        query.canonicalIngredientId;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(InventorySummary, List<AggregatedInventoryItem>)>(
      future: _future,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) {
          return const Center(child: PixelLoader(size: 7));
        }
        if (state.hasError) {
          return AppErrorState(
            message: '库存暂时无法读取。',
            onRetry: () => setState(() => _future = _load()),
          );
        }
        final (summary, items) = state.requireData;
        // 首次加载后保存可变副本，供长按拖动排序/跨区移动使用。
        _allItems ??= List<AggregatedInventoryItem>.of(items);
        if (items.isEmpty) {
          return _EmptyFridge(
            onAdd: () => widget.onOpenBatchEditor(),
            onRecommend: widget.onOpenRecommendation,
          );
        }
        // 搜索与推荐共用统一标准化器（ADR-0021 第八节）：输入“西红柿”
        // 能命中库存“番茄”。
        final keyword = _query.trim().toLowerCase();
        final canonicalizer = IngredientCanonicalizer();
        final queryCanonical = keyword.isEmpty
            ? null
            : canonicalizer.canonicalize(_query.trim());
        final filtered = _allItems!
            .where(
              (item) =>
                  _matches(item.condition, item.zone) &&
                  (keyword.isEmpty || _matchesSearch(item, queryCanonical, canonicalizer)),
            )
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 96),
          children: <Widget>[
            _buildHeader(summary, filtered.length),
            const SizedBox(height: 12),
            _buildSearchField(),
            const SizedBox(height: 10),
            _buildFilterRow(),
            const SizedBox(height: 12),
            if (summary.soonExpiring > 0) ...<Widget>[
              PixelNotice(
                title: '${summary.soonExpiring} 样食材临期',
                message: '建议优先消耗临期食材。',
                icon: Icons.timer_outlined,
                tone: PixelNoticeTone.amber,
              ),
              const SizedBox(height: 12),
            ],
            _buildFridgeBox(filtered),
            if (filtered.isEmpty) ...<Widget>[
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  '该筛选下暂时没有食材。',
                  style: TextStyle(color: AppColors.ink3),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 冰箱箱体（CSS .fridge-body）：浅绿底 + pxc-lg 切角 + 2px inset 描边 +
  /// 顶部门缝虚线 + 各分区卡（可折叠）。
  Widget _buildFridgeBox(List<AggregatedInventoryItem> filtered) {
    final zones = <Widget>[];
    for (final zone in InventoryZone.values) {
      final zoneItems = filtered
          .where((item) => item.zone == zone)
          .toList(growable: false);
      // HTML 筛选逻辑：非“全部”筛选时，无匹配食材的分区整体隐藏。
      if (_filter != _InventoryFilter.all && zoneItems.isEmpty) continue;
      zones.add(
        _ZoneCard(
          // 关键：分区卡必须有稳定 key。否则筛选/折叠导致分区卡数量变化时，
          // Flutter 按位置复用 State，冷冻区可能继承冷藏区的 _chipKeys/_open/
          // _dragOver 状态——折叠状态的分区连 DragTarget 都不存在，拖放会静默失效。
          key: ValueKey(zone),
          zone: zone,
          items: zoneItems,
          pendingArrivals: _pendingArrivals,
          showEmptyHint: _filter == _InventoryFilter.all,
          onAdd: () => widget.onOpenBatchEditor(zone: zone),
          onDragStart: _beginDragSession,
          onDropToZone: (dragged, insertIndex) =>
              _applyDrop(dragged, zone, insertIndex),
          onConsumeArrival: _consumeArrival,
          onEditBatch: (batch) => widget.onOpenBatchEditor(batch: batch),
          onUseUp: (batch) => widget.onConfirmAction(
            '标记「${batch.ingredientName}」批次用完？',
            '该批次将不再出现在可用库存中。',
            () => widget.backend.useUpInventoryBatch(batch.id),
          ),
          onDiscard: (batch) => widget.onConfirmAction(
            '丢弃「${batch.ingredientName}」批次？',
            '丢弃后从库存移除，并记录变更。',
            () => widget.backend.discardInventoryBatch(batch.id),
          ),
          onDelete: (batch) => widget.onConfirmAction(
            '删除「${batch.ingredientName}」批次？',
            '删除后无法恢复（永久删除并记录变更）。',
            () => widget.backend.deleteInventoryBatch(batch.id),
          ),
        ),
      );
      zones.add(const SizedBox(height: 10));
    }
    return PixelSurface(
      cut: PixelCut.lg,
      elevation: 0,
      color: const Color(0xFFEBEFEA),
      borderColor: AppColors.line2,
      borderWidth: 2,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // .fridge-door-line：4px 门缝虚线（8px 实 + 6px 空）。
          Container(
            height: 4,
            margin: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
            child: CustomPaint(painter: _DoorLinePainter()),
          ),
          ...zones,
        ],
      ),
    );
  }

  Widget _buildHeader(InventorySummary summary, int kindCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '我的冰箱',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  // HTML .tiny：X 种食材 · Y 个可用批次。
                  Text(
                    '$kindCount 种食材 · ${summary.availableBatches} 个可用批次',
                    style: const TextStyle(fontSize: 11, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            // HTML .ri-tag.ok“去选择食材推荐”按钮。
            InkWell(
              key: const Key('goRecommendationButton'),
              onTap: widget.onOpenRecommendation,
              child: const PixelBadge(
                label: '去选择食材推荐',
                icon: Icons.auto_awesome_outlined,
                tone: PixelNoticeTone.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // .stat-grid.cols4：四列摘要。
        Row(
          children: <Widget>[
            PixelStatCard(
              label: '可用批次',
              value: summary.availableBatches.toString(),
            ),
            PixelStatCard(
              label: '临期',
              value: summary.soonExpiring.toString(),
              color: AppColors.amber,
            ),
            PixelStatCard(
              label: '已过期',
              value: summary.expired.toString(),
              color: AppColors.red,
            ),
            PixelStatCard(
              label: '数量未知',
              value: summary.unknownQuantity.toString(),
              color: AppColors.blue,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      key: const Key('inventorySearchField'),
      controller: _queryController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: '搜索食材名称',
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        isDense: true,
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: '清空',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _queryController.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );
  }

  Widget _buildFilterRow() {
    const filters = <(_InventoryFilter, String)>[
      (_InventoryFilter.all, '全部'),
      (_InventoryFilter.soon, '临期'),
      (_InventoryFilter.expired, '已过期'),
      (_InventoryFilter.unknown, '数量未知'),
      (_InventoryFilter.chilled, '冷藏'),
      (_InventoryFilter.frozen, '冷冻'),
      (_InventoryFilter.room, '常温'),
      (_InventoryFilter.other, '其他'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((entry) {
          final (filter, label) = entry;
          final selected = filter == _filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            // CSS .chip：平直小矩形 + inset 1.5px 描边；active 绿底 +
            // green-deep 描边 + #FDFDFB 白字。
            child: Material(
              color: selected ? AppColors.green : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
                side: BorderSide(
                  color: selected ? AppColors.greenDeep : AppColors.line2,
                  width: 1.5,
                ),
              ),
              child: InkWell(
                onTap: () => _setFilter(filter),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 5,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? const Color(0xFFFDFDFB)
                          : AppColors.ink2,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 空状态（HTML UI-014 空状态）：92px 大图标块 + 标题 + 说明 + 主/次按钮。
class _EmptyFridge extends StatelessWidget {
  const _EmptyFridge({required this.onAdd, required this.onRecommend});

  final VoidCallback onAdd;
  final VoidCallback onRecommend;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PixelFloat(
              amplitude: 5,
              child: PixelSurface(
                cut: PixelCut.lg,
                elevation: 4,
                borderColor: AppColors.line2,
                child: SizedBox.square(
                  dimension: 92,
                  child: Icon(
                    Icons.kitchen_outlined,
                    size: 44,
                    color: AppColors.green,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '冰箱还是空的',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加第一样食材后，就能按库存推荐「现在就能做」的菜，并跟踪临期食材。',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.ink2, fontSize: 12.5, height: 1.7),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('addFirstInventoryBatchButton'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加第一样食材'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRecommend,
              child: const Text('或先去选择食材推荐'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分区卡（CSS .fridge-zone）：可折叠——点击 zone-head 展开/收起。
/// 每个分区只保留一个最终拖放接收者（单一 DragTarget），
/// 食材 chip 只负责静态视觉与插入位置计算，不重复提交移动。
class _ZoneCard extends StatefulWidget {
  const _ZoneCard({
    super.key,
    required this.zone,
    required this.items,
    required this.pendingArrivals,
    required this.showEmptyHint,
    required this.onAdd,
    required this.onDragStart,
    required this.onDropToZone,
    required this.onConsumeArrival,
    required this.onEditBatch,
    required this.onUseUp,
    required this.onDiscard,
    required this.onDelete,
  });

  final InventoryZone zone;
  final List<AggregatedInventoryItem> items;

  /// 保存成功、待目标 chip 消费的到达事件（moveEventId → 事件）。
  final Map<int, _ArrivalEvent> pendingArrivals;

  final bool showEmptyHint;
  final VoidCallback onAdd;

  /// 一次长按拖拽开始时回调（生成唯一拖拽会话）。
  final VoidCallback onDragStart;

  /// 本分区最终接收拖放：[dragged] 移入本分区 [insertIndex] 位置。
  final void Function(AggregatedInventoryItem dragged, int insertIndex)
  onDropToZone;

  /// 目标 chip 消费到达事件后回调（从待处理集合删除）。
  final ValueChanged<int> onConsumeArrival;

  final ValueChanged<InventoryBatch> onEditBatch;
  final ValueChanged<InventoryBatch> onUseUp;
  final ValueChanged<InventoryBatch> onDiscard;
  final ValueChanged<InventoryBatch> onDelete;

  @override
  State<_ZoneCard> createState() => _ZoneCardState();
}

class _ZoneCardState extends State<_ZoneCard> {
  // HTML <details open>：分区默认展开。
  var _open = true;

  /// 每个食材 chip 的 GlobalKey：拖拽指针在分区内移动时据此
  /// 计算插入序号（chip 位置即唯一事实源，不依赖名称）。
  final Map<String, GlobalKey> _chipKeys = <String, GlobalKey>{};

  /// 本分区是否为当前拖拽的可接收高亮目标。
  var _dragOver = false;

  /// 拖拽指针在本分区内的插入序号（0=最前，N=末尾）。
  var _insertIndex = 0;

  static const _zoneMeta = <InventoryZone, (String, String, String)>{
    InventoryZone.chilled: ('冷藏区', '层架', 'assets/icon/home/fridge/冷藏区.png'),
    InventoryZone.frozen: ('冷冻区', '抽屉', 'assets/icon/home/fridge/冷冻区.png'),
    InventoryZone.roomTemperature: ('常温区', '米面粮油', 'assets/icon/home/fridge/常温区.png'),
    InventoryZone.other: ('其他区', '待整理', 'assets/icon/home/fridge/其他区.png'),
  };

  /// 查找匹配某食材的待消费到达事件（按稳定身份，同名多批次不串）。
  _ArrivalEvent? _arrivalFor(AggregatedInventoryItem item) {
    for (final event in widget.pendingArrivals.values) {
      if (event.stableItemId == item.stableId) return event;
    }
    return null;
  }

  /// 拖拽指针移动：根据指针全局坐标与各 chip 中心距离计算插入序号。
  void _onDragMove(DragTargetDetails<AggregatedInventoryItem> details) {
    final offset = details.offset;
    var bestIndex = widget.items.length;
    var bestDist = double.infinity;
    for (var i = 0; i < widget.items.length; i++) {
      final box =
          _chipKeys[widget.items[i].stableId]
              ?.currentContext
              ?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final dist = (offset - center).distance;
      if (dist < bestDist) {
        bestDist = dist;
        // 指针在 chip 中心左侧 → 插到它前面；否则插到它后面。
        bestIndex = offset.dx < center.dx ? i : i + 1;
      }
    }
    bestIndex = bestIndex.clamp(0, widget.items.length);
    if (!_dragOver || bestIndex != _insertIndex) {
      setState(() {
        _dragOver = true;
        _insertIndex = bestIndex;
      });
    }
  }

  /// 指针离开本分区：清除高亮与插入指示（不改变任何数据）。
  void _onDragLeave(AggregatedInventoryItem? data) {
    if (_dragOver) setState(() => _dragOver = false);
  }

  /// 本分区最终接收：提交一次移动（唯一提交入口）。
  void _onZoneAccept(DragTargetDetails<AggregatedInventoryItem> details) {
    final insertIndex = _dragOver ? _insertIndex : widget.items.length;
    _dragOver = false;
    debugPrint(
      '[AIRecipe][Fridge][Drag] 分区接收 ${widget.zone.name} '
      'item=${details.data.ingredientName} insert=$insertIndex',
    );
    widget.onDropToZone(details.data, insertIndex);
  }

  @override
  Widget build(BuildContext context) {
    final (label, kind, icon) = _zoneMeta[widget.zone]!;
    final frozen = widget.zone == InventoryZone.frozen;
    // .zone-head .tiny：层架 · 5 种。
    final subtitle = '$kind · ${widget.items.length} 种';
    return CustomPaint(
      // .fridge-zone：inset 1.5px line2 描边（--px-line）。
      foregroundPainter: const _FridgeInsetBorderPainter(
        color: AppColors.line2,
        width: 1.5,
      ),
      child: DecoratedBox(
        // .zone-frozen：冷冻区浅蓝灰底。
        decoration: BoxDecoration(
          color: frozen ? const Color(0xFFF2F5F6) : AppColors.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // .zone-head：点击展开/收起。
            InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: <Widget>[
                    // .zone-ic：26×26 浅绿图标块 + pxc-xs 切角。
                    // 冰箱区图标改用设计素材（HOME-001）。
                    ClipPath(
                      clipper: const PixelCutClipper(cut: PixelCut.xs),
                      child: SizedBox.square(
                        dimension: 26,
                        child: ColoredBox(
                          color: AppColors.greenSofter,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: Image.asset(
                              icon,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.help_outline_rounded,
                                size: 14,
                                color: AppColors.greenDeep,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                    // .zone-add：放入该区按钮（26×26 icon-btn）。
                    PixelIconBtn(
                      icon: Icons.add_rounded,
                      size: 26,
                      iconSize: 12,
                      tooltip: '放入$label',
                      onTap: widget.onAdd,
                    ),
                    const SizedBox(width: 4),
                    // .agg-arrow：展开时旋转 90°（steps 近似）。
                    AnimatedRotation(
                      turns: _open ? 0.25 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 15,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_open) ...<Widget>[
              // .zone-body：顶部 1.5px inset 分隔线（inset 0 1.5px 0 line）。
              Container(height: 1.5, color: AppColors.line),
              // 单一最终拖放接收者：本分区所有可放置内容（空分区或 chip 网格）。
              DragTarget<AggregatedInventoryItem>(
                onWillAcceptWithDetails: (_) => true,
                onMove: _onDragMove,
                onLeave: _onDragLeave,
                onAcceptWithDetails: _onZoneAccept,
                builder: (context, candidates, rejected) {
                  // 候选高亮是静态反馈：不改数据、不触发动画。
                  final highlighted = candidates.isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        // 拖拽目标区高亮线（仅视觉）。
                        if (highlighted) ...<Widget>[
                          const SizedBox(height: 6),
                          Container(
                            height: 2,
                            color: AppColors.green,
                          ),
                        ],
                        if (widget.items.isEmpty && widget.showEmptyHint)
                          _ZoneEmpty(onAdd: widget.onAdd)
                        else ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 9,
                              runSpacing: 9,
                              children: _buildChipRow(),
                            ),
                          ),
                          // .drawer-handle：冷冻抽屉把手。
                          if (frozen) const _DrawerHandle(),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// chip 行内容：拖拽中在目标插入位置显示指示竖条。
  List<Widget> _buildChipRow() {
    final children = <Widget>[];
    for (var i = 0; i < widget.items.length; i++) {
      if (_dragOver && i == _insertIndex) children.add(_buildInsertIndicator());
      children.add(_buildDraggableChip(widget.items[i]));
    }
    if (_dragOver && _insertIndex >= widget.items.length) {
      children.add(_buildInsertIndicator());
    }
    return children;
  }

  /// 插入位置指示竖条（仅拖拽高亮反馈，不参与数据）。
  Widget _buildInsertIndicator() {
    return Container(
      width: 3,
      height: 38,
      margin: const EdgeInsets.symmetric(vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.greenDeep,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }

  /// 长按可拖动的食材 chip。
  ///
  /// 职责拆分：正式目标 chip（_FoodChip）只在保存成功、目标挂载后消费
  /// 唯一到达事件播放逐格动画；拖拽影子与原位占位使用无动画控制器的
  /// 静态视觉（_FoodChipView），长按/拖动/无效释放绝不触发动画。
  Widget _buildDraggableChip(AggregatedInventoryItem item) {
    // 稳定身份定位 chip 位置（GlobalKey 挂在不变的 Container 上，
    // 拖拽中 childWhenDragging 替换内部不影响位置计算）。
    _chipKeys[item.stableId] ??= GlobalKey();
    final key = _chipKeys[item.stableId]!;
    final arrival = _arrivalFor(item);
    final onTap = item.batchCount == 1
        ? () => widget.onEditBatch(item.batches.first)
        : null;
    final onExpand = item.batchCount > 1
        ? () => _showBatches(context, item)
        : null;
    // 正式目标 chip：仅消费匹配自身稳定身份的到达事件。
    final chip = _FoodChip(
      item: item,
      frozen: item.zone == InventoryZone.frozen,
      pendingArrival: arrival,
      onEventConsumed: widget.onConsumeArrival,
      onTap: onTap,
      onExpandBatches: onExpand,
    );
    // 静态视觉（无 AnimationController、无挂载自动播放、无水波纹）。
    final staticView = _FoodChipView(
      item: item,
      frozen: item.zone == InventoryZone.frozen,
      onTap: onTap,
      onExpandBatches: onExpand,
    );
    return Container(
      key: key,
      child: LongPressDraggable<AggregatedInventoryItem>(
        data: item,
        onDragStarted: widget.onDragStart,
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(opacity: .85, child: staticView),
        ),
        // 原位占位：静态视觉淡显，只维持布局。
        childWhenDragging: Opacity(opacity: .35, child: staticView),
        child: chip,
      ),
    );
  }

  /// 批次状态 → .conf 标签（正常/临期/已过期/未设置日期/数量未知）。
  Widget _conditionTag(InventoryBatch batch) {
    final condition = batch.conditionOn(DateTime.now());
    final (label, tone) = switch (condition) {
      InventoryItemCondition.normal => ('正常', PixelConfTone.ok),
      InventoryItemCondition.soonExpiring => ('临期', PixelConfTone.low),
      InventoryItemCondition.expired => ('已过期', PixelConfTone.exp),
      InventoryItemCondition.noDate => ('未设置日期', PixelConfTone.gray),
      InventoryItemCondition.unknownQuantity => ('数量未知', PixelConfTone.unknown),
    };
    return PixelConfTag(label, tone: tone);
  }

  void _showBatches(BuildContext context, AggregatedInventoryItem item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${item.ingredientName} · ${item.batchCount} 个批次',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              ...item.batches.map((batch) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: _BatchLine(batch: batch)),
                      // HTML .batch-row 状态标签（临期/正常/已过期…）。
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _conditionTag(batch),
                      ),
                      // .batch-row 操作：编辑 / 用完 / 丢弃 / 删除。
                      PixelIconBtn(
                        icon: Icons.edit_outlined,
                        iconSize: 14,
                        tooltip: '编辑批次',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onEditBatch(batch);
                        },
                      ),
                      const SizedBox(width: 6),
                      PixelIconBtn(
                        icon: Icons.check_rounded,
                        iconSize: 14,
                        tooltip: '标记用完',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onUseUp(batch);
                        },
                      ),
                      const SizedBox(width: 6),
                      PixelIconBtn(
                        icon: Icons.delete_outline_rounded,
                        iconSize: 14,
                        tooltip: '标记丢弃',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onDiscard(batch);
                        },
                      ),
                      const SizedBox(width: 6),
                      PixelIconBtn(
                        icon: Icons.close_rounded,
                        iconSize: 14,
                        tooltip: '删除批次',
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          widget.onDelete(batch);
                        },
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

/// 冰冻目标色（冷冻区视觉：浅冰蓝底 + 蓝灰描边/投影 + 冰蓝图标）。
const _frozenBg = Color(0xFFE8EFF3);
const _frozenBorder = Color(0xFF9AB0BE);
const _frozenProjection = Color(0x666E8697);
const _frozenIcon = Color(0xFF5A7A8C);

/// 食材状态变体（HTML .food-chip.soon/.expired/.unknown）：
/// 投影色 / 描边色 / conf 标签 / 透明度。
(Color, Color, String, PixelConfTone, double) _conditionVisual(
  InventoryItemCondition condition,
) {
  return switch (condition) {
    InventoryItemCondition.normal => (
      const Color(0x2936403A),
      AppColors.line2,
      '正常',
      PixelConfTone.ok,
      1.0,
    ),
    InventoryItemCondition.soonExpiring => (
      const Color(0x73B08D4F),
      const Color(0xFFD3B06A),
      '临期',
      PixelConfTone.low,
      1.0,
    ),
    InventoryItemCondition.expired => (
      const Color(0x66AF6859),
      const Color(0xFFC98A7E),
      '已过期',
      PixelConfTone.exp,
      0.7,
    ),
    InventoryItemCondition.noDate => (
      const Color(0x2936403A),
      AppColors.line2,
      '未设置日期',
      PixelConfTone.gray,
      1.0,
    ),
    InventoryItemCondition.unknownQuantity => (
      const Color(0x666E8697),
      const Color(0xFF9AB0BE),
      '数量未知',
      PixelConfTone.unknown,
      1.0,
    ),
  };
}

/// .fc-ic：按常见食材名映射图标，未映射用通用餐具图标。
IconData _foodIcon(String name) {
  if (name.contains('蛋')) return Icons.egg_alt_outlined;
  if (name.contains('奶')) return Icons.local_drink_outlined;
  if (name.contains('肉') ||
      name.contains('鱼') ||
      name.contains('虾') ||
      name.contains('鸡')) {
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
      name.contains('菇')) {
    return Icons.eco_outlined;
  }
  return Icons.restaurant_outlined;
}

/// chip 主体内容（图标 + 名称/数量 + conf 标签）。
/// 静态视图（_FoodChipView）与动画 chip（_FoodChip）复用同一份视觉。
Widget _buildChipContent({
  required AggregatedInventoryItem item,
  required Color iconColor,
  required String confLabel,
  required PixelConfTone confTone,
  VoidCallback? onTap,
}) {
  return InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // .fc-ic：食材小图标。
          Icon(_foodIcon(item.ingredientName), size: 15, color: iconColor),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // .fc-name：名称 + 多批次展开提示。
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.ingredientName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.batchCount > 1) ...<Widget>[
                    const SizedBox(width: 5),
                    Icon(
                      Icons.unfold_more_rounded,
                      size: 11,
                      color: AppColors.ink3,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 1),
              // .fc-qty：数量/日期摘要。
              Text(
                item.summary,
                style: const TextStyle(fontSize: 10, color: AppColors.ink3),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // .conf：状态标签。
          PixelConfTag(confLabel, tone: confTone),
        ],
      ),
    ),
  );
}

/// 静态食材视觉（CSS .food-chip 最终样式）。
///
/// 职责：只负责名称、数量、状态、图标、边框与背景的最终静态样式。
/// 不持有 AnimationController、不接收到达事件、挂载不自动播放、
/// didUpdateWidget 不触发动画、无 InkWell 水波纹之外的任何动效——
/// 用于拖拽影子与原位占位，保证长按时不会因临时 Widget 被创建而播放动画。
class _FoodChipView extends StatelessWidget {
  const _FoodChipView({
    required this.item,
    required this.frozen,
    this.onTap,
    this.onExpandBatches,
  });

  final AggregatedInventoryItem item;

  /// 是否在冷冻区：true 使用冰蓝冰冻样式。
  final bool frozen;

  final VoidCallback? onTap;
  final VoidCallback? onExpandBatches;

  @override
  Widget build(BuildContext context) {
    final (projection, border, confLabel, confTone, opacity) =
        _conditionVisual(item.condition);
    final borderColor = frozen ? _frozenBorder : border;
    final projectionColor = frozen ? _frozenProjection : projection;
    final iconColor = frozen ? _frozenIcon : AppColors.ink2;
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: frozen ? _frozenBg : AppColors.card,
          // .food-chip：底部 3px 硬投影（box-shadow 0 3px 0 …）。
          boxShadow: <BoxShadow>[
            BoxShadow(color: projectionColor, offset: const Offset(0, 3)),
          ],
        ),
        child: CustomPaint(
          // inset 1.5px 描边。
          foregroundPainter: _FridgeInsetBorderPainter(
            color: borderColor,
            width: 1.5,
          ),
          child: _buildChipContent(
            item: item,
            iconColor: iconColor,
            confLabel: confLabel,
            confTone: confTone,
            onTap: onExpandBatches ?? onTap,
          ),
        ),
      ),
    );
  }
}

/// 食材 chip（CSS .food-chip）：card 底 + 底部 3px 硬投影 + inset 1.5px 描边 +
/// 食材图标 + 名称/数量 + conf 状态标签；多批次可展开。
///
/// 正式目标 chip：只在“保存成功 → 目标挂载 → 收到唯一到达事件”后播放
/// 二维逐格冰冻/解冻动画；长按、拖动、无效释放、同区排序均不触发。
class _FoodChip extends StatefulWidget {
  const _FoodChip({
    required this.item,
    required this.frozen,
    this.pendingArrival,
    this.onEventConsumed,
    this.onTap,
    this.onExpandBatches,
  });

  final AggregatedInventoryItem item;

  /// 是否在冷冻区：true 时使用冰蓝色“冰冻”视觉。
  final bool frozen;

  /// 保存成功后的唯一到达事件（匹配本 chip 稳定身份；null=无）。
  final _ArrivalEvent? pendingArrival;

  /// 消费事件后通知父级从待处理集合删除（同一事件只播一次）。
  final ValueChanged<int>? onEventConsumed;

  final VoidCallback? onTap;
  final VoidCallback? onExpandBatches;

  @override
  State<_FoodChip> createState() => _FoodChipState();
}

class _FoodChipState extends State<_FoodChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 动画方向：true=正在冷冻（正常→冰冻，格子逐个出现）；
  /// false=正在解冻（冰冻→正常，格子逆序消失）。
  bool _freezing = true;

  /// 本 State 已消费的到达事件序号（同一事件只播放一次）。
  int? _consumedMoveEventId;

  @override
  void initState() {
    super.initState();
    _freezing = widget.frozen;
    // 静止态 = 动画已完成（progress=1）：冷冻区全冰冻、其他区全正常。
    // 总时长 550ms，配合二维逐格（约 24-36ms/格）呈现一格一格跳变。
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
      value: 1,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 消费唯一到达事件（在 build 内调用，可安全读取 MediaQuery）。
  ///
  /// 只有“保存成功 → 目标 chip 挂载 → 收到本次未消费事件”才播放；
  /// 长按、拖动开始、经过区域、无效释放、同区排序、页面重建都不会走到这里。
  void _maybeConsumeArrival(bool reduceMotion) {
    final event = widget.pendingArrival;
    if (event == null || _consumedMoveEventId == event.moveEventId) return;
    _consumedMoveEventId = event.moveEventId;
    // 帧末通知父级删除事件（消费即删除），避免 build 期间触发父级 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onEventConsumed?.call(event.moveEventId);
    });
    // 减少动态：数据正常提交，但不播放逐格动画（直接最终样式）。
    if (reduceMotion || event.kind == _FrostKind.none) return;
    _freezing = event.kind == _FrostKind.freezeIn;
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    _maybeConsumeArrival(reduceMotion);
    final item = widget.item;
    final (projection, border, confLabel, confTone, opacity) =
        _conditionVisual(item.condition);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // 描边/投影/图标离散切换（不做连续 Color.lerp）：
        // - 冷冻目标：恒为冰冻样式（冷冻在第一个格子出现时一次性切换）。
        // - 非冷冻目标：解冻动画完成（progress==1）后一次性恢复正常样式。
        final bool showFrozenStyle;
        if (widget.frozen) {
          showFrozenStyle = true;
        } else {
          // 解冻方向（_freezing=false）且动画未结束（t<1）时保留冰冻描边；
          // 用 _freezing 判断而非 pendingArrival——事件消费后即被父级删除，
          // 但动画可能仍在播放，必须等最后一个格子消失后才恢复正常样式。
          final thawing = !_freezing && _consumedMoveEventId != null;
          showFrozenStyle = thawing && t < 1.0;
        }
        final borderColor = showFrozenStyle ? _frozenBorder : border;
        final projectionColor = showFrozenStyle ? _frozenProjection : projection;
        final iconColor = showFrozenStyle ? _frozenIcon : AppColors.ink2;
        return Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // .food-chip：底部 3px 硬投影（box-shadow 0 3px 0 …）。
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: projectionColor,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: CustomPaint(
              // 二维独立小格逐格变色（冰核向外扩散，非增长矩形）。
              painter: _FrostGridPainter(
                progress: t,
                freezing: _freezing,
                normalColor: AppColors.card,
                frozenColor: _frozenBg,
              ),
              // inset 1.5px 描边（离散状态色，非渐变）。
              foregroundPainter: _FridgeInsetBorderPainter(
                color: borderColor,
                width: 1.5,
              ),
              child: _buildChipContent(
                item: item,
                iconColor: iconColor,
                confLabel: confLabel,
                confTone: confTone,
                onTap: widget.onExpandBatches ?? widget.onTap,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 二维逐格冰冻/解冻绘制器。
///
/// 把 chip 背景切成 12dp 的二维小格（至少两行），以“图标一侧、垂直居中”
/// 的格子为冰核，按曼哈顿距离由近到远逐个激活；每个动画 tick 只切换
/// 一个完整格子。冷冻=格子逐个出现；解冻=完全相反顺序逐个消失。
/// 禁止增长矩形、整列/整行扫过、透明度渐变。
class _FrostGridPainter extends CustomPainter {
  const _FrostGridPainter({
    required this.progress,
    required this.freezing,
    required this.normalColor,
    required this.frozenColor,
  });

  /// 动画进度 0..1。
  final double progress;

  /// true=正在冷冻（正常→冰冻，格子逐个出现）；
  /// false=正在解冻（冰冻→正常，格子逆序消失）。
  final bool freezing;

  final Color normalColor;
  final Color frozenColor;

  /// 格子 12dp，格子间 1dp 视觉缝隙。
  static const double _cell = 12;
  static const double _gap = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = (size.width / (_cell + _gap)).ceil();
    final rows = (size.height / (_cell + _gap)).ceil();
    final order = _cellOrder(cols, rows);
    final total = order.length;
    // 激活格子数：冷冻 0→total 逐个出现；解冻 total→0 逆序消失。
    final active = freezing
        ? (progress * total).floor()
        : total - (progress * total).floor();
    // 背景底色（正常样式）。
    canvas.drawRect(Offset.zero & size, Paint()..color = normalColor);
    // 激活格子逐个画冰冻色，每个格子内缩 gap/2 形成缝隙。
    final paint = Paint()..color = frozenColor;
    final limit = active.clamp(0, total).toInt();
    for (var i = 0; i < limit; i++) {
      final (r, c) = order[i];
      final rect = Rect.fromLTWH(
        c * (_cell + _gap) + _gap / 2,
        r * (_cell + _gap) + _gap / 2,
        _cell,
        _cell,
      );
      canvas.drawRect(rect, paint);
    }
  }

  /// 冰核扩散顺序：以左上（图标一侧）垂直居中的格子为冰核，
  /// 按曼哈顿距离由近到远排序；同一距离按方向角度固定排序保证稳定。
  static List<(int, int)> _cellOrder(int cols, int rows) {
    final coreR = rows ~/ 2;
    final coreC = 0;
    final cells = <(int, int)>[
      for (var r = 0; r < rows; r++)
        for (var c = 0; c < cols; c++) (r, c),
    ];
    cells.sort((a, b) {
      final da = (a.$1 - coreR).abs() + (a.$2 - coreC).abs();
      final db = (b.$1 - coreR).abs() + (b.$2 - coreC).abs();
      if (da != db) return da.compareTo(db);
      final angleA = math.atan2(
        (a.$1 - coreR).toDouble(),
        (a.$2 - coreC).toDouble(),
      );
      final angleB = math.atan2(
        (b.$1 - coreR).toDouble(),
        (b.$2 - coreC).toDouble(),
      );
      return angleA.compareTo(angleB);
    });
    return cells;
  }

  @override
  bool shouldRepaint(covariant _FrostGridPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.freezing != freezing ||
        oldDelegate.normalColor != normalColor ||
        oldDelegate.frozenColor != frozenColor;
  }
}

/// 门缝虚线（CSS .fridge-door-line：8px 实 + 6px 空）。
class _DoorLinePainter extends CustomPainter {
  const _DoorLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.line2;
    var x = 0.0;
    while (x < size.width) {
      final w = math.min(8, size.width - x).toDouble();
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      x += 14;
    }
  }

  @override
  bool shouldRepaint(_DoorLinePainter oldDelegate) => false;
}

/// 空分区（CSS .zone-empty）：1.5px 虚线框 + 居中提示 + 放入按钮。
class _ZoneEmpty extends StatelessWidget {
  const _ZoneEmpty({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: CustomPaint(
        painter: const _DashedRectPainter(color: AppColors.line2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: <Widget>[
              const Text(
                '这个分区还是空的',
                style: TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('放入这个区域'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 1.5px 虚线矩形框（四边虚线）。
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color, this.dash = 6, this.gap = 4});

  final Color color;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    var x = 0.0;
    while (x < size.width) {
      final end = math.min(x + dash, size.width).toDouble();
      path.moveTo(x, 0);
      path.lineTo(end, 0);
      path.moveTo(x, size.height);
      path.lineTo(end, size.height);
      x += dash + gap;
    }
    var y = 0.0;
    while (y < size.height) {
      final end = math.min(y + dash, size.height).toDouble();
      path.moveTo(0, y);
      path.lineTo(0, end);
      path.moveTo(size.width, y);
      path.lineTo(size.width, end);
      y += dash + gap;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}

/// 冷冻抽屉把手（CSS .drawer-handle：56×6 深色条 + 顶部 2px 内阴影）。
class _DrawerHandle extends StatelessWidget {
  const _DrawerHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 56,
        height: 6,
        margin: const EdgeInsets.only(top: 10),
        decoration: const BoxDecoration(
          color: Color(0x3336403A), // rgba(54,64,58,.20)
          border: Border(
            top: BorderSide(color: Color(0x3836403A), width: 2), // inset 0 2px 0 22%
          ),
        ),
      ),
    );
  }
}

/// 平直矩形 inset 描边带（fridge 局部实现，与共享 _InsetRectBorderPainter 同逻辑）。
class _FridgeInsetBorderPainter extends CustomPainter {
  const _FridgeInsetBorderPainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inner = rect.deflate(width);
    if (inner.width <= 0 || inner.height <= 0) return;
    final band = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect),
      Path()..addRect(inner),
    );
    canvas.drawPath(band, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_FridgeInsetBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}

class _BatchLine extends StatelessWidget {
  const _BatchLine({required this.batch});

  final InventoryBatch batch;

  @override
  Widget build(BuildContext context) {
    final qty = batch.quantity == null
        ? '数量未知'
        : '${_trimNumber(batch.quantity!)} ${batch.unit ?? ''}'.trim();
    final date = batch.expiresAt == null
        ? '未设置日期'
        : '到期 ${_dateLabel(batch.expiresAt!)}';
    return Text(
      '$qty · $date',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  static String _trimNumber(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }

  static String _dateLabel(DateTime time) {
    final local = time.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
