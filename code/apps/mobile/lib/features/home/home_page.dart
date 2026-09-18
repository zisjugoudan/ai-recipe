import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/home/home_use_cases.dart';
import '../../application/recipe/default_recipe_categories.dart';
import '../../domain/importing/import_task.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../../shared/widgets/recipe_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.backend,
    required this.onOpenLibrary,
    required this.onOpenImportTask,
    required this.onOpenImportTasks,
    required this.onQuickLinkImport,
    required this.onQuickClipboardImport,
    required this.onQuickImageImport,
    required this.onQuickManualCreate,
    required this.onOpenRecipe,
    this.refreshToken = 0,
  });
  final AiRecipeBackendFacade backend;
  final VoidCallback onOpenLibrary;
  final Future<void> Function(ImportTask task) onOpenImportTask;
  /// 打开未完成导入任务列表。
  final VoidCallback onOpenImportTasks;
  /// 快速导入：粘贴链接。
  final VoidCallback onQuickLinkImport;
  /// 快速导入：剪贴板。
  final VoidCallback onQuickClipboardImport;
  /// 快速导入：拍照选图（本地 OCR）。
  final VoidCallback onQuickImageImport;
  /// 快速导入：手动创建。
  final VoidCallback onQuickManualCreate;

  /// 打开菜谱详情：只传 id（首页只持有摘要，详情页按需加载完整聚合）。
  final ValueChanged<String> onOpenRecipe;
  final int refreshToken;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<HomeSnapshot> _snapshot;
  @override
  void initState() {
    super.initState();
    _snapshot = widget.backend.loadHome();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _reload();
  }

  void _reload() {
    setState(() {
      _snapshot = widget.backend.loadHome();
    });
  }

  /// 首页眉题：中文日期，如“8月2日 周六”。
  static String _todayLabel() {
    final now = DateTime.now();
    const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
    return '${now.month}月${now.day}日 周${weekdays[now.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _snapshot;
        },
        child: FutureBuilder<HomeSnapshot>(
          future: _snapshot,
          builder: (context, state) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 112),
                sliver: SliverList.list(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              PxLabel(_todayLabel()),
                              const SizedBox(height: 3),
                              const Text(
                                '晚上好，今天吃什么？',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PixelBadge(
                          label: '游客',
                          tone: PixelNoticeTone.green,
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    if (state.connectionState == ConnectionState.waiting)
                      const SizedBox(height: 420, child: AppLoadingState())
                    else if (state.hasError)
                      AppErrorState(message: '首页内容暂时无法读取。', onRetry: _reload)
                    else
                      _HomeContent(
                        snapshot: state.requireData,
                        onOpenLibrary: widget.onOpenLibrary,
                        onOpenImportTask: widget.onOpenImportTask,
                        onOpenImportTasks: widget.onOpenImportTasks,
                        onQuickLinkImport: widget.onQuickLinkImport,
                        onQuickClipboardImport: widget.onQuickClipboardImport,
                        onQuickImageImport: widget.onQuickImageImport,
                        onQuickManualCreate: widget.onQuickManualCreate,
                        onOpenRecipe: widget.onOpenRecipe,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.snapshot,
    required this.onOpenLibrary,
    required this.onOpenImportTask,
    required this.onOpenImportTasks,
    required this.onQuickLinkImport,
    required this.onQuickClipboardImport,
    required this.onQuickImageImport,
    required this.onQuickManualCreate,
    required this.onOpenRecipe,
  });
  final HomeSnapshot snapshot;
  final VoidCallback onOpenLibrary;
  final Future<void> Function(ImportTask task) onOpenImportTask;
  final VoidCallback onOpenImportTasks;
  final VoidCallback onQuickLinkImport;
  final VoidCallback onQuickClipboardImport;
  final VoidCallback onQuickImageImport;
  final VoidCallback onQuickManualCreate;

  /// 打开菜谱详情：只传 id（首页只持有摘要，详情页按需加载完整聚合）。
  final ValueChanged<String> onOpenRecipe;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (snapshot.unfinishedImportTasks.isNotEmpty) ...<Widget>[
          PixelNotice(
            title: '有 ${snapshot.unfinishedImportTasks.length} 个未完成的导入',
            message: '解析进行中或等待确认，点这里继续处理',
            icon: Icons.timer_outlined,
            tone: PixelNoticeTone.amber,
            trailing: const Icon(Icons.chevron_right_rounded, size: 18),
            onTap: onOpenImportTasks,
          ),
          const SizedBox(height: 14),
        ],
        const PxLabel('快速导入'),
        const SizedBox(height: 10),
        // HTML .quick-grid：一行 4 个 quick-btn（竖排图标块 + 文字）。
        Row(
          children: <Widget>[
            Expanded(
              child: _QuickButton(
                icon: Image.asset(
                  'assets/icon/home/quick/链接导入.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
                label: '粘贴链接',
                onTap: onQuickLinkImport,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickButton(
                icon: Image.asset(
                  'assets/icon/home/quick/视频识别.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
                label: '剪贴板',
                onTap: onQuickClipboardImport,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickButton(
                icon: Image.asset(
                  'assets/icon/home/quick/图片识别.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
                label: '拍照选图',
                onTap: onQuickImageImport,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickButton(
                icon: Image.asset(
                  'assets/icon/home/quick/手动记账.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                ),
                label: '手动创建',
                onTap: onQuickManualCreate,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        AppSectionTitle(
          title: '分类',
          
          action: TextButton(
            onPressed: onOpenLibrary,
            child: const Text('更多分类 ›'),
          ),
        ),
        const SizedBox(height: 9),
        if (snapshot.categories.isEmpty)
          AppEmptyState(
            icon: Icons.category_outlined,
            title: '先建立你的第一个分类',
            message: '例如「快手晚餐」「空气炸锅」或「周末甜点」。',
            actionLabel: '去菜谱库创建',
            onAction: onOpenLibrary,
          )
        else
          SizedBox(
            height: 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final summary = snapshot.categories[index];
                final iconAsset = categoryIconAsset(summary.category.id);
                return PixelSurface(
                  cut: 4,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 11,
                  ),
                  child: SizedBox(
                    width: 112,
                    child: Row(
                      children: <Widget>[
                        if (iconAsset != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Image.asset(
                              iconAsset,
                              width: 22,
                              height: 22,
                              fit: BoxFit.contain,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                summary.category.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${summary.recipeCount} 道菜',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 22),
        AppSectionTitle(
          title: '最近浏览',
          action: TextButton(
            onPressed: onOpenLibrary,
            child: const Text('全部菜谱 ›'),
          ),
        ),
        const SizedBox(height: 9),
        if (snapshot.recentRecipes.isEmpty)
          AppEmptyState(
            icon: Icons.menu_book_outlined,
            title: '你的菜谱库还是空的',
            message: '导入一个链接，或手动添加一道熟悉的菜。',
            actionLabel: '添加菜谱',
            onAction: onQuickLinkImport,
          )
        else
          // 最近浏览：横排滚动的小卡片（正方形封面 + 标题 + 所需时间等信息）。
          SizedBox(
            height: 205,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.recentRecipes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final recipe = snapshot.recentRecipes[index];
                return SizedBox(
                  width: 132,
                  child: RecipeSummaryCard(
                    summary: recipe,
                    tile: true,
                    onTap: () => onOpenRecipe(recipe.id),
                  ),
                );
              },
            ),
          ),
        if (snapshot.favoriteRecipes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 15),
          const AppSectionTitle(title: '我的收藏'),
          const SizedBox(height: 9),
          ...snapshot.favoriteRecipes
              .take(3)
              .map(
                (recipe) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: RecipeSummaryCard(
                    summary: recipe,
                    compact: true,
                    onTap: () => onOpenRecipe(recipe.id),
                  ),
                ),
              ),
        ],
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Widget icon;
  final String label;
  final VoidCallback onTap;

  /// HTML .quick-btn：card 底 + pxc-sm 切角 + 墨色 1.5px inset 描边
  /// （与右下角"添加菜谱"按钮的描边一致），竖排 36×36 图标块 + 文字。
  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: PixelCut.sm,
      elevation: 0,
      color: AppColors.card,
      borderColor: AppColors.ink,
      borderWidth: 1.5,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // .qb-ic：36×36 green-softer 图标块 + pxc-xs 切角。
            ClipPath(
              clipper: PixelCutClipper(cut: PixelCut.xs),
              child: SizedBox.square(
                dimension: 36,
                child: ColoredBox(
                  color: AppColors.greenSofter,
                  // 支持传入 Widget 图标（asset 图片或 Icon）。
                  child: Center(child: icon),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
