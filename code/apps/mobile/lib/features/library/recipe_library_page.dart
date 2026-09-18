import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/recipe/default_recipe_categories.dart';
import '../../application/recipe/recipe_library_commands.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/create_category_dialog.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../../shared/widgets/recipe_card.dart';

/// 菜谱库页（解决方案.md 第一~四节）。
///
/// - 使用 [RecipeSummary] 摘要分页查询，不再读取完整聚合（消除 N+1）；
/// - SliverGrid + 滚动到底自动加载下一页（虚拟化，只构建屏幕附近卡片）；
/// - 排序在 SQL 中完成（keyset pagination），不再前端全量排序。
class RecipeLibraryPage extends StatefulWidget {
  const RecipeLibraryPage({
    super.key,
    required this.backend,
    required this.onAddRecipe,
    required this.onOpenRecipeId,
    required this.onDataChanged,
    this.onOpenTrash,
    this.refreshToken = 0,
  });

  final AiRecipeBackendFacade backend;
  final VoidCallback onAddRecipe;

  /// 打开菜谱详情：只传 id，详情页内部按需加载完整聚合。
  final ValueChanged<String> onOpenRecipeId;
  final VoidCallback onDataChanged;
  final VoidCallback? onOpenTrash;
  final int refreshToken;

  @override
  State<RecipeLibraryPage> createState() => _RecipeLibraryPageState();
}

class _RecipeLibraryPageState extends State<RecipeLibraryPage> {
  static const int _pageSize = 40;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  String? _selectedCategoryId;
  bool _favoriteOnly = false;
  RecipeSort _sort = RecipeSort.updated;

  // ---- 分页状态（摘要查询 + keyset pagination）----
  List<RecipeSummary> _recipes = const <RecipeSummary>[];
  List<RecipeCategory> _categories = const <RecipeCategory>[];
  int? _totalCount;
  bool _hasMore = false;
  RecipeCursor? _cursor;
  bool _initialLoading = true;
  bool _initialError = false;
  bool _loadingMore = false;
  int _loadGeneration = 0;

  /// 长按选择模式（菜谱库批量操作）：长按卡片进入，点按卡片切换选中。
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};
  bool _batchBusy = false;

  /// 收藏乐观更新覆盖：id → 目标收藏状态，优先于菜谱数据展示，避免等待后端。
  final Map<String, bool> _favoriteOverrides = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void didUpdateWidget(covariant RecipeLibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动接近底部时加载下一页（虚拟化 + 增量分页）。
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      unawaited(_loadMore());
    }
  }

  /// 当前筛选条件（搜索词 / 分类 / 收藏）。
  ({String? query, String? categoryId, bool? favorite}) get _filters => (
    query: _searchController.text,
    categoryId: _selectedCategoryId,
    favorite: _favoriteOnly ? true : null,
  );

  /// 重新加载第一页：已有数据时保持旧列表顶替显示，不闪整页加载动画。
  Future<void> _loadFirstPage() async {
    final generation = ++_loadGeneration;
    final filters = _filters;
    setState(() {
      _initialLoading = _recipes.isEmpty;
      _initialError = false;
    });
    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        widget.backend.listRecipeSummaries(
          query: filters.query,
          categoryId: filters.categoryId,
          favorite: filters.favorite,
          sort: _sort,
          limit: _pageSize,
        ),
        widget.backend.listCategories(),
        widget.backend.countRecipes(
          query: filters.query,
          categoryId: filters.categoryId,
          favorite: filters.favorite,
        ),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      final page = results[0] as RecipeSummaryPage;
      setState(() {
        _recipes = page.items;
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _categories = results[1] as List<RecipeCategory>;
        _totalCount = results[2] as int;
        _initialLoading = false;
        _initialError = false;
        // 筛选/刷新后退出选择模式，避免选中项与列表不一致。
        _selectionMode = false;
        _selectedIds.clear();
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _initialLoading = false;
        // 已有数据时保留旧列表；无数据时展示错误态。
        if (_recipes.isEmpty) _initialError = true;
      });
    }
  }

  /// 加载下一页并追加。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _cursor == null) return;
    final generation = _loadGeneration;
    final filters = _filters;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.backend.listRecipeSummaries(
        query: filters.query,
        categoryId: filters.categoryId,
        favorite: filters.favorite,
        sort: _sort,
        limit: _pageSize,
        after: _cursor,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _recipes = <RecipeSummary>[..._recipes, ...page.items];
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _reload() => _loadFirstPage();

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  void _clearSearch() {
    _searchController.clear();
    _reload();
  }

  Future<void> _toggleFavorite(RecipeSummary recipe, bool value) async {
    // 乐观更新：本地立即切换收藏图标，不触发整页刷新/加载动画。
    setState(() => _favoriteOverrides[recipe.id] = value);
    try {
      await widget.backend.setRecipeFavorite(recipe.id, value);
      widget.onDataChanged();
    } catch (_) {
      // 失败回滚为原状态。
      if (mounted) {
        setState(() => _favoriteOverrides.remove(recipe.id));
        _showMessage('收藏状态保存失败，请稍后重试。');
      }
    }
  }

  Future<void> _createCategory(List<RecipeCategory> categories) async {
    // 输入控制器与校验由 CreateCategoryDialog 自持，避免关闭动画期间访问
    // 已释放控制器，并防止空名称、同名分类、超长名称与快速重复提交。
    final name = await CreateCategoryDialog.show(
      context,
      existingNames: categories.map((item) => item.name).toList(),
    );
    if (name == null || !mounted) return;
    try {
      final maxOrder = categories.fold<int>(
        -1,
        (value, item) => item.sortOrder > value ? item.sortOrder : value,
      );
      await widget.backend.createCategory(
        RecipeCategoryInput(name: name, sortOrder: maxOrder + 1),
      );
      if (!mounted) return;
      widget.onDataChanged();
      _reload();
      _showMessage('分类已创建。');
    } on AiRecipeBackendException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('分类创建失败，请稍后重试。');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 长按某个菜谱卡片：进入选择模式并选中该项。
  void _enterSelection(String recipeId) {
    if (_batchBusy) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(recipeId);
    });
  }

  /// 选择模式下点按卡片切换选中；取消全部选中后自动退出选择模式。
  void _toggleSelection(String recipeId) {
    setState(() {
      if (!_selectedIds.remove(recipeId)) {
        _selectedIds.add(recipeId);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 批量删除所选菜谱（移入回收站）。
  Future<void> _deleteSelected() async {
    if (_batchBusy || _selectedIds.isEmpty) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '删除所选 ${_selectedIds.length} 道菜谱？',
      message: '菜谱将移入回收站，可在回收站恢复。',
      confirmLabel: '删除',
      confirmColor: AppColors.red,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batchBusy = true);
    try {
      for (final id in _selectedIds.toList()) {
        await widget.backend.softDeleteRecipe(id);
      }
      widget.onDataChanged();
      _exitSelection();
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('菜谱删除失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  /// 批量收藏所选菜谱。
  Future<void> _favoriteSelected() async {
    if (_batchBusy || _selectedIds.isEmpty) return;
    setState(() => _batchBusy = true);
    try {
      for (final id in _selectedIds.toList()) {
        await widget.backend.setRecipeFavorite(id, true);
      }
      widget.onDataChanged();
      _exitSelection();
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('收藏失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: <Widget>[
          CustomScrollView(
            controller: _scrollController,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: <Widget>[
              SliverToBoxAdapter(child: _buildHeader()),
              if (_initialError && _recipes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(
                    message: '菜谱库暂时无法读取。',
                    onRetry: _reload,
                  ),
                )
              else if (_initialLoading && _recipes.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppLoadingState(label: '正在翻阅菜谱库…'),
                )
              else if (_recipes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: _searchController.text.isEmpty
                        ? Icons.menu_book_outlined
                        : Icons.search_off_rounded,
                    title: _searchController.text.isEmpty
                        ? '还没有菜谱'
                        : '没有找到匹配的菜谱',
                    message: _searchController.text.isEmpty
                        ? '从链接导入，或手动写下第一道菜。'
                        : '换个关键词，或切换到其他分类试试。',
                    actionLabel: _searchController.text.isEmpty
                        ? '添加菜谱'
                        : null,
                    onAction: _searchController.text.isEmpty
                        ? widget.onAddRecipe
                        : null,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  sliver: SliverGrid(
                    // 虚拟化网格：只构建屏幕附近的卡片（解决方案.md 第四节）。
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 11,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 232,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildCard(_recipes[index]),
                      childCount: _recipes.length,
                    ),
                  ),
                ),
              // 加载更多 / 已全部加载 的页脚。
              if (_recipes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: _loadingMore
                          ? const PixelLoader(size: 5)
                          : Text(
                              _hasMore ? '下拉加载更多…' : '已加载全部 $totalLabel',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.ink3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: _buildTrashRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 112)),
            ],
          ),
          if (_selectionMode)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PixelBottomActionBar(
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _batchBusy || _selectedIds.isEmpty
                            ? null
                            : _favoriteSelected,
                        icon: const Icon(Icons.favorite_border_rounded, size: 17),
                        label: const Text('加入收藏'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red,
                        ),
                        onPressed: _batchBusy || _selectedIds.isEmpty
                            ? null
                            : _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded, size: 17),
                        label: Text('删除所选 (${_selectedIds.length})'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get totalLabel =>
      _totalCount == null ? '' : '· 共 $_totalCount 道';

  /// 页头（标题/搜索/排序/筛选），只构建一次，网格滚动时保持。
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppPageHeader(
            eyebrow: _selectionMode ? null : '我的菜谱库',
            title: _selectionMode ? '已选择 ${_selectedIds.length} 项' : '菜谱库',
            subtitle: _selectionMode
                ? '点按切换选择，或点"取消"退出'
                : _initialLoading && _recipes.isEmpty
                ? '正在翻阅收藏…'
                : '共 ${_totalCount ?? 0} 道菜谱',
            trailing: _selectionMode
                ? OutlinedButton.icon(
                    onPressed: _batchBusy ? null : _exitSelection,
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('取消'),
                  )
                : OutlinedButton.icon(
                    onPressed: _initialLoading ? null : () => _createCategory(_categories),
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 17,
                    ),
                    label: const Text('新建分类'),
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索菜谱',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<RecipeSort>(
                  initialValue: _sort,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 13,
                    ),
                  ),
                  items: const <DropdownMenuItem<RecipeSort>>[
                    DropdownMenuItem(
                      value: RecipeSort.updated,
                      child: Text('最近更新'),
                    ),
                    DropdownMenuItem(
                      value: RecipeSort.created,
                      child: Text('创建时间'),
                    ),
                    DropdownMenuItem(
                      value: RecipeSort.title,
                      child: Text('名称排序'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _sort) return;
                    _sort = value;
                    _reload();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('全部'),
                  selected:
                      _selectedCategoryId == null && !_favoriteOnly,
                  onSelected: (_) {
                    _selectedCategoryId = null;
                    _favoriteOnly = false;
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  avatar: const Icon(
                    Icons.favorite_rounded,
                    size: 15,
                  ),
                  label: const Text('收藏'),
                  selected: _favoriteOnly,
                  onSelected: (_) {
                    _favoriteOnly = !_favoriteOnly;
                    _reload();
                  },
                ),
                ..._categories.map(
                  (category) {
                    final iconAsset = categoryIconAsset(category.id);
                    return Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: ChoiceChip(
                        avatar: iconAsset != null
                            ? Image.asset(
                                iconAsset,
                                width: 15,
                                height: 15,
                                fit: BoxFit.contain,
                              )
                            : null,
                        label: Text(category.name),
                        selected: _selectedCategoryId == category.id,
                        onSelected: (_) {
                          _selectedCategoryId = category.id;
                          _favoriteOnly = false;
                          _reload();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 17),
        ],
      ),
    );
  }

  /// 单个网格卡片（摘要数据 + 乐观收藏 + 长按选择）。
  Widget _buildCard(RecipeSummary summary) {
    return RecipeSummaryCard(
      summary: summary,
      grid: true,
      selected: _selectionMode && _selectedIds.contains(summary.id),
      // 乐观更新：本地立即反映收藏状态。
      favoriteOverride: _favoriteOverrides[summary.id],
      onTap: () {
        if (_selectionMode) {
          // 选择模式下：点按切换选中。
          _toggleSelection(summary.id);
        } else {
          widget.onOpenRecipeId(summary.id);
        }
      },
      // 长按进入选择模式。
      onLongPress: () => _enterSelection(summary.id),
      onFavoriteChanged: _selectionMode
          ? null
          : (value) => _toggleFavorite(summary, value),
    );
  }

  Widget _buildTrashRow() {
    if (widget.onOpenTrash == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: PixelRowTile(
        icon: Icons.delete_outline_rounded,
        iconColor: AppColors.red,
        iconBackground: AppColors.redSoft,
        title: '回收站',
        subtitle: '恢复误删的菜谱，或永久清理本地数据',
        trailing: const PixelBadge(label: '本地'),
        onTap: widget.onOpenTrash,
      ),
    );
  }
}
