import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/recipe/recipe_detail_use_cases.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import '../cooking/cooking_mode_page.dart';
import 'recipe_edit_page.dart';

class RecipeDetailPage extends StatefulWidget {
  const RecipeDetailPage({
    super.key,
    required this.backend,
    required this.recipeId,
    required this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final String recipeId;
  final VoidCallback onDataChanged;

  @override
  State<RecipeDetailPage> createState() => _RecipeDetailPageState();
}

class _RecipeDetailPageState extends State<RecipeDetailPage> {
  late Future<RecipeDetailSnapshot> _detail;
  var _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.backend.openRecipeDetail(widget.recipeId);
  }

  void _reload({bool recordView = false}) {
    setState(() {
      _detail = widget.backend.openRecipeDetail(
        widget.recipeId,
        recordView: recordView,
      );
    });
  }

  Future<void> _toggleFavorite(Recipe recipe) async {
    await _runAction(() async {
      await widget.backend.setRecipeFavorite(recipe.id, !recipe.favorite);
      widget.onDataChanged();
      _reload();
    });
  }

  Future<void> _edit(Recipe recipe) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) =>
            RecipeEditPage(backend: widget.backend, initialRecipe: recipe),
      ),
    );
    if (changed == true && mounted) {
      widget.onDataChanged();
      _reload();
    }
  }

  /// 打开分享底部弹层：选择「分享为图片」或「其他方式」。
  ///
  /// 两个入口目前均为预留占位（项目负责人要求），真实分享能力后续接入；
  /// 因此不需要走 [_runAction]（没有后台操作）。
  Future<void> _share(Recipe recipe) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _ShareSheet(recipe: recipe),
    );
  }

  Future<void> _startCooking(Recipe recipe) async {
    await _runAction(() async {
      final session = await widget.backend.startOrResumeCooking(recipe.id);
      if (!mounted) return;
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => CookingModePage(
            backend: widget.backend,
            recipeId: recipe.id,
            sessionId: session.id,
          ),
        ),
      );
      if (!mounted) return;
      if (completed == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本次烹饪已完成，辛苦了。')));
      }
    });
  }

  Future<void> _delete(Recipe recipe) async {
    final confirmed = await showPixelConfirm(
      context: context,
      title: '移到回收站？',
      message: '“${recipe.title}”会从菜谱库隐藏，你仍可以在回收站恢复。',
      confirmLabel: '移到回收站',
      confirmKey: const Key('confirmSoftDeleteRecipe'),
    );
    if (confirmed != true) return;
    await _runAction(() async {
      await widget.backend.softDeleteRecipe(recipe.id);
      widget.onDataChanged();
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } on AiRecipeBackendException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RecipeDetailSnapshot>(
      future: _detail,
      builder: (context, state) {
        if (state.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            appBar: PixelPageAppBar(title: '菜谱详情', eyebrow: '菜谱详情'),
            body: AppLoadingState(label: '正在读取菜谱…'),
          );
        }
        if (state.hasError) {
          return Scaffold(
            appBar: const PixelPageAppBar(
              title: '菜谱详情',
              eyebrow: '菜谱详情',
            ),
            body: AppErrorState(
              message: '菜谱详情暂时无法读取。',
              onRetry: () => _reload(recordView: true),
            ),
          );
        }

        final snapshot = state.requireData;
        final recipe = snapshot.recipe;
        return Scaffold(
          appBar: PixelPageAppBar(
            title: '菜谱详情',
            eyebrow: '菜谱详情',
            actions: <Widget>[
              IconButton(
                tooltip: recipe.favorite ? '取消收藏' : '收藏',
                onPressed: _actionBusy ? null : () => _toggleFavorite(recipe),
                icon: Icon(
                  recipe.favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: recipe.favorite ? AppColors.red : AppColors.ink2,
                  size: 20,
                ),
              ),
              PopupMenuButton<_RecipeDetailMenuAction>(
                tooltip: '更多操作',
                enabled: !_actionBusy,
                onSelected: (action) {
                  switch (action) {
                    case _RecipeDetailMenuAction.edit:
                      _edit(recipe);
                    case _RecipeDetailMenuAction.share:
                      _share(recipe);
                    case _RecipeDetailMenuAction.delete:
                      _delete(recipe);
                  }
                },
                itemBuilder: (context) =>
                    const <PopupMenuEntry<_RecipeDetailMenuAction>>[
                      PopupMenuItem(
                        value: _RecipeDetailMenuAction.edit,
                        child: Text('编辑菜谱'),
                      ),
                      PopupMenuItem(
                        value: _RecipeDetailMenuAction.share,
                        child: Text('分享菜谱'),
                      ),
                      PopupMenuItem(
                        value: _RecipeDetailMenuAction.delete,
                        child: Text('移到回收站'),
                      ),
                    ],
              ),
            ],
          ),
          body: _RecipeDetailContent(snapshot: snapshot),
          bottomNavigationBar: PixelBottomActionBar(
            child: Row(
              children: <Widget>[
                _PixelActionButton(
                  key: const Key('editRecipeButton'),
                  tooltip: '编辑菜谱',
                  icon: Icons.edit_outlined,
                  onPressed: _actionBusy ? null : () => _edit(recipe),
                ),
                const SizedBox(width: 8),
                _PixelActionButton(
                  key: const Key('shareRecipeButton'),
                  tooltip: '分享菜谱',
                  icon: Icons.ios_share_rounded,
                  onPressed: _actionBusy ? null : () => _share(recipe),
                ),
                const SizedBox(width: 8),
                _PixelActionButton(
                  key: const Key('deleteRecipeButton'),
                  tooltip: '移到回收站',
                  icon: Icons.delete_outline_rounded,
                  color: AppColors.red,
                  onPressed: _actionBusy ? null : () => _delete(recipe),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('startCookingButton'),
                    onPressed: _actionBusy ? null : () => _startCooking(recipe),
                    icon: _actionBusy
                        ? const PixelLoader(size: 3, color: Colors.white)
                        : const Icon(Icons.local_fire_department_rounded),
                    label: const Text('开始烹饪'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum _RecipeDetailMenuAction { edit, share, delete }

/// 分享底部弹层：列出「分享为图片」「其他方式」两个入口。
///
/// 两个入口目前都是预留占位（点击提示即将上线，项目负责人要求），
/// 真实分享能力（渲染图片、系统分享等）后续再接入。
class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    // 预留入口的点击反馈：关闭弹层并提示即将上线。
    void comingSoon() {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该分享方式即将上线，敬请期待。')));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题行：分享图标 + 菜谱名。
            Row(
              children: <Widget>[
                const Icon(
                  Icons.ios_share_rounded,
                  color: AppColors.greenDeep,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '分享「${recipe.title}」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ShareOptionTile(
              icon: Icons.image_outlined,
              title: '分享为图片',
              subtitle: '把菜谱生成一张图片',
              onTap: comingSoon,
            ),
            const SizedBox(height: 8),
            _ShareOptionTile(
              icon: Icons.more_horiz_rounded,
              title: '其他方式',
              subtitle: '系统分享、链接分享等（预留）',
              onTap: comingSoon,
            ),
          ],
        ),
      ),
    );
  }
}

/// 分享弹层里的单个选项行（像素风可点面板）。
class _ShareOptionTile extends StatelessWidget {
  const _ShareOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 6,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.greenDeep, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.ink3,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.ink3, size: 18),
        ],
      ),
    );
  }
}

class _RecipeDetailContent extends StatelessWidget {
  const _RecipeDetailContent({required this.snapshot});

  final RecipeDetailSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final recipe = snapshot.recipe;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _RecipeHero(title: recipe.title, images: recipe.images),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                recipe.title,
                key: const Key('recipeDetailTitle'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                  height: 1.25,
                ),
              ),
              if (_hasText(recipe.description)) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  recipe.description!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AppColors.ink2,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  ...snapshot.categories.map(
                    (category) => PixelBadge(
                      label: category.name,
                      icon: Icons.folder_outlined,
                      tone: PixelNoticeTone.green,
                    ),
                  ),
                  ...recipe.tags.map(
                    (tag) => PixelBadge(label: tag, icon: Icons.tag_rounded),
                  ),
                  if (recipe.servings != null)
                    PixelBadge(
                      label: '${recipe.servings} 人份',
                      icon: Icons.people_outline_rounded,
                    ),
                  if (recipe.totalTimeMinutes != null)
                    PixelBadge(
                      label: '${recipe.totalTimeMinutes} 分钟',
                      icon: Icons.schedule_rounded,
                    ),
                  if (recipe.difficulty != RecipeDifficulty.unspecified)
                    PixelBadge(
                      label: '${_difficultyLabel(recipe.difficulty)}难度',
                    ),
                ],
              ),
              if (snapshot.sourceImportTask case final source?) ...<Widget>[
                const SizedBox(height: 10),
                _ImportSourceLine(task: source),
              ],
              const SizedBox(height: 24),
              _SectionTitle(title: '食材', count: recipe.ingredients.length),
              const SizedBox(height: 9),
              if (recipe.ingredients.isEmpty)
                const _EmptySection(message: '尚未添加食材。')
              else
                _IngredientList(ingredients: recipe.ingredients),
              const SizedBox(height: 24),
              _SectionTitle(title: '步骤', count: recipe.steps.length),
              const SizedBox(height: 9),
              if (recipe.steps.isEmpty)
                const _EmptySection(message: '尚未添加步骤。')
              else
                ...recipe.steps.map((step) => _StepCard(step: step)),
              if (_hasText(recipe.notes)) ...<Widget>[
                const SizedBox(height: 2),
                PixelNotice(
                  title: '小贴士',
                  message: recipe.notes,
                  tone: PixelNoticeTone.green,
                  icon: Icons.lightbulb_outline_rounded,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeHero extends StatefulWidget {
  const _RecipeHero({required this.title, required this.images});

  final String title;
  final List<String> images;

  @override
  State<_RecipeHero> createState() => _RecipeHeroState();
}

class _RecipeHeroState extends State<_RecipeHero> {
  var _page = 0;

  /// 点击图片打开像素风全屏查看器（初始页 = 当前页，可左右滑动切换）。
  Future<void> _openGallery(int index) async {
    if (widget.images.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImageGallery(
          images: widget.images,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    if (images.isEmpty) {
      return _buildPixelHero();
    }
    return SizedBox(
      height: 168,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          PageView.builder(
            key: const Key('recipeCoverCarousel'),
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _page = index),
            itemBuilder: (context, index) => GestureDetector(
              // 点击放大查看，支持左右滑动切换（像素风全屏查看器）。
              onTap: () => _openGallery(index),
              child: Image.file(
                File(images[index]),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: AppColors.card2,
                  child: const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.ink3,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List<Widget>.generate(images.length, (index) {
                  final active = index == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? AppColors.greenDeep : Colors.white70,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPixelHero() {
    return Container(
      height: 168,
      decoration: const BoxDecoration(
        color: AppColors.card2,
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: CustomPaint(painter: const _PixelKitchenGridPainter()),
          ),
          CustomPaint(
            size: const Size(174, 132),
            painter: _PixelDishPainter(widget.title),
          ),
        ],
      ),
    );
  }
}

/// 像素风全屏图片查看器：深色背景 + 左右滑动切换 + 双指缩放，
/// 顶部像素风关闭按钮、底部像素页码，与整体 UI 风格一致。
class _FullscreenImageGallery extends StatefulWidget {
  const _FullscreenImageGallery({
    required this.images,
    required this.initialIndex,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final PageController _controller;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialIndex.clamp(0, widget.images.length - 1);
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .88),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 全屏轮播：左右滑动切换图片，双指缩放查看细节。
            PageView.builder(
              key: const Key('fullscreenImageGallery'),
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => InteractiveViewer(
                maxScale: 4,
                child: Center(
                  child: Image.file(
                    File(widget.images[index]),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white38,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            // 顶部关闭按钮（像素风 icon-btn）。
            Positioned(
              top: 8,
              left: 8,
              child: PixelIconBtn(
                icon: Icons.close_rounded,
                size: 34,
                iconSize: 18,
                tooltip: '关闭',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            // 底部页码（像素 monospace 风格）。
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Text(
                    '${_page + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelKitchenGridPainter extends CustomPainter {
  const _PixelKitchenGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.line2.withValues(alpha: .32);
    const step = 18.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PixelDishPainter extends CustomPainter {
  const _PixelDishPainter(this.title);

  final String title;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = AppColors.greenDeep;
    final green = Paint()..color = AppColors.green;
    final bowl = Paint()..color = const Color(0xFFF7E4B1);
    final broth = Paint()..color = const Color(0xFFD87447);
    final red = Paint()..color = const Color(0xFFC9573F);
    final cream = Paint()..color = AppColors.paper;
    final shadow = Paint()..color = AppColors.ink.withValues(alpha: .12);

    canvas.drawRect(const Rect.fromLTWH(29, 107, 116, 7), shadow);
    canvas.drawRect(const Rect.fromLTWH(34, 55, 106, 45), bowl);
    canvas.drawRect(const Rect.fromLTWH(43, 96, 88, 9), bowl);
    canvas.drawRect(const Rect.fromLTWH(48, 101, 78, 7), dark);
    canvas.drawRect(const Rect.fromLTWH(40, 50, 94, 14), dark);
    canvas.drawRect(const Rect.fromLTWH(46, 54, 82, 10), broth);

    final noodleLike = title.contains('面') || title.contains('粉');
    final soupLike = title.contains('汤') || title.contains('羹');
    if (noodleLike) {
      for (var i = 0; i < 5; i++) {
        canvas.drawRect(
          Rect.fromLTWH(55 + i * 13, 61 + (i % 2) * 5, 8, 27),
          cream,
        );
      }
      canvas.drawRect(const Rect.fromLTWH(49, 70, 73, 5), green);
    } else if (soupLike) {
      canvas.drawRect(const Rect.fromLTWH(48, 62, 75, 22), broth);
      canvas.drawRect(const Rect.fromLTWH(60, 66, 19, 12), green);
      canvas.drawRect(const Rect.fromLTWH(91, 70, 22, 10), cream);
    } else {
      canvas.drawRect(const Rect.fromLTWH(51, 62, 27, 19), red);
      canvas.drawRect(const Rect.fromLTWH(82, 59, 33, 23), red);
      canvas.drawRect(const Rect.fromLTWH(66, 78, 37, 15), broth);
      canvas.drawRect(const Rect.fromLTWH(58, 58, 8, 7), green);
      canvas.drawRect(const Rect.fromLTWH(103, 55, 8, 7), green);
    }

    canvas.drawRect(const Rect.fromLTWH(63, 22, 7, 18), dark);
    canvas.drawRect(const Rect.fromLTWH(70, 13, 7, 16), dark);
    canvas.drawRect(const Rect.fromLTWH(96, 27, 7, 14), dark);
    canvas.drawRect(const Rect.fromLTWH(103, 17, 7, 17), dark);
  }

  @override
  bool shouldRepaint(_PixelDishPainter oldDelegate) =>
      oldDelegate.title != title;
}

class _IngredientList extends StatelessWidget {
  const _IngredientList({required this.ingredients});

  final List<Ingredient> ingredients;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Ingredient>>{};
    for (final ingredient in ingredients) {
      final group = _hasText(ingredient.groupName)
          ? ingredient.groupName!.trim()
          : '食材';
      groups.putIfAbsent(group, () => <Ingredient>[]).add(ingredient);
    }
    return Column(
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PixelSurface(
                cut: 6,
                elevation: 1,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (groups.length > 1) ...<Widget>[
                      PxLabel(entry.key, color: AppColors.greenDeep),
                      const SizedBox(height: 5),
                    ],
                    ...entry.value.map(
                      (ingredient) => _IngredientRow(ingredient: ingredient),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient});

  final Ingredient ingredient;

  @override
  Widget build(BuildContext context) {
    final amount = <String?>[
      ingredient.quantity,
      ingredient.unit,
    ].where((part) => _hasText(part)).join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 15,
            height: 15,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: ingredient.optional
                  ? AppColors.paper2
                  : AppColors.greenSofter,
              border: Border.all(
                color: ingredient.optional ? AppColors.line2 : AppColors.green,
              ),
            ),
            child: ingredient.optional
                ? null
                : const Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: AppColors.greenDeep,
                  ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        '${ingredient.name}${ingredient.optional ? '（可选）' : ''}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_hasText(ingredient.preparation))
                  Text(
                    '处理：${ingredient.preparation}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.ink3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            amount,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final RecipeStep step;

  @override
  Widget build(BuildContext context) {
    final details = <({IconData icon, String label})>[
      if (step.durationSeconds != null)
        (
          icon: Icons.schedule_rounded,
          label: _durationLabel(step.durationSeconds!),
        ),
      if (_hasText(step.temperature))
        (icon: Icons.thermostat_rounded, label: step.temperature!),
      if (_hasText(step.heatLevel))
        (icon: Icons.local_fire_department_rounded, label: step.heatLevel!),
      if (_hasText(step.cookware))
        (icon: Icons.soup_kitchen_rounded, label: step.cookware!),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PixelSurface(
        cut: 6,
        elevation: 1,
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipPath(
              clipper: const PixelCutClipper(cut: 4),
              child: SizedBox.square(
                dimension: 34,
                child: ColoredBox(
                  color: AppColors.greenDeep,
                  child: Center(
                    child: Text(
                      '${step.stepNumber}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    step.description,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.55,
                    ),
                  ),
                  if (details.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: details
                          .map(
                            (detail) => PixelBadge(
                              label: detail.label,
                              icon: detail.icon,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  if (_hasText(step.tips)) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '提示：${step.tips}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.greenInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportSourceLine extends StatelessWidget {
  const _ImportSourceLine({required this.task});

  final ImportTask task;

  @override
  Widget build(BuildContext context) {
    final platform = switch (task.sourcePlatform) {
      ImportSourcePlatform.xiaohongshu => '小红书',
      ImportSourcePlatform.douyin => '抖音',
      ImportSourcePlatform.web => '网页',
    };
    return Row(
      children: <Widget>[
        const Icon(Icons.link_rounded, size: 13, color: AppColors.ink3),
        const SizedBox(width: 5),
        Expanded(
          child: InkWell(
            // 点击来源链接复制到剪贴板。
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: task.normalizedUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('来源链接已复制到剪贴板'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text(
              '来源：$platform · ${_importStatusLabel(task.status)} · ${task.normalizedUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppColors.ink3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(width: 4, height: 17, color: AppColors.green),
        const SizedBox(width: 8),
        Text(
          count == null ? title : '$title · $count',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
          ),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 5,
      elevation: 0,
      color: AppColors.card2,
      padding: const EdgeInsets.all(16),
      child: Text(message, style: const TextStyle(color: AppColors.ink3)),
    );
  }
}

class _PixelActionButton extends StatelessWidget {
  const _PixelActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color = AppColors.ink2,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 44,
        child: PixelSurface(
          cut: 5,
          elevation: onPressed == null ? 0 : 2,
          color: onPressed == null ? AppColors.paper2 : AppColors.card,
          onTap: onPressed,
          child: Icon(
            icon,
            size: 19,
            color: onPressed == null ? AppColors.ink3 : color,
          ),
        ),
      ),
    );
  }
}

bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

String _difficultyLabel(RecipeDifficulty value) => switch (value) {
  RecipeDifficulty.unspecified => '未设置',
  RecipeDifficulty.easy => '简单',
  RecipeDifficulty.medium => '中等',
  RecipeDifficulty.hard => '困难',
};

String _durationLabel(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return remaining == 0 ? '$minutes 分钟' : '$minutes 分 $remaining 秒';
}

String _importStatusLabel(ImportTaskStatus status) => switch (status) {
  ImportTaskStatus.queued => '等待处理',
  ImportTaskStatus.running => '处理中',
  ImportTaskStatus.needsReview => '待确认',
  ImportTaskStatus.completed => '已完成',
  ImportTaskStatus.failed => '失败',
  ImportTaskStatus.cancelled => '已取消',
};
