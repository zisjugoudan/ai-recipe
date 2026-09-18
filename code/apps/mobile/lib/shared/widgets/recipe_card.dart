import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../domain/recipe/recipe.dart';
import 'pixel_ui.dart';

class RecipeCard extends StatelessWidget {
  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.onLongPress,
    this.onFavoriteChanged,
    this.favoriteOverride,
    this.selected = false,
    this.compact = false,
    this.grid = false,
  });

  final Recipe recipe;
  final VoidCallback? onTap;

  /// 长按回调（选择模式入口，与 [onTap] 由同一 InkWell 处理，互斥且稳定）。
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 外部收藏状态覆盖（乐观更新用）：非空时优先于 [Recipe.favorite] 展示。
  final bool? favoriteOverride;

  /// 选择模式下选中态：绿色描边 + 对勾角标。
  final bool selected;
  final bool compact;
  final bool grid;

  @override
  Widget build(BuildContext context) {
    if (grid) return _buildGridCard(context);
    final metadata = _metadata(recipe);
    final effectiveFavorite = favoriteOverride ?? recipe.favorite;
    return PixelSurface(
      cut: 8,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? AppColors.greenDeep : AppColors.line2,
      borderWidth: selected ? 2 : 1.5,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _coverBox(context, size: compact ? 58 : 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (recipe.sourceId != null) ...<Widget>[
                    const PixelBadge(
                      label: '链接导入',
                      icon: Icons.link_rounded,
                      tone: PixelNoticeTone.green,
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    recipe.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  if (recipe.description?.trim().isNotEmpty ??
                      false) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      recipe.description!,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (metadata.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      metadata.join(' · '),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (recipe.tags.isNotEmpty && !compact) ...<Widget>[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: recipe.tags
                          .take(3)
                          .map((tag) => PixelBadge(label: tag))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...<Widget>[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenDeep,
                size: 20,
              ),
            ],
            if (onFavoriteChanged != null)
              _FavoriteButton(
                favorite: effectiveFavorite,
                onPressed: () => onFavoriteChanged!(!effectiveFavorite),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context) {
    final metadata = _metadata(recipe);
    final effectiveFavorite = favoriteOverride ?? recipe.favorite;
    return PixelSurface(
      cut: 7,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? AppColors.greenDeep : AppColors.line2,
      borderWidth: selected ? 2 : 1.5,
      padding: EdgeInsets.zero,
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _gridCover(),
                    ),
                    if (recipe.sourceId != null && !selected)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: PixelBadge(
                          label: 'AI 导入',
                          icon: Icons.auto_awesome_rounded,
                          tone: PixelNoticeTone.green,
                        ),
                      ),
                    if (onFavoriteChanged != null)
                      Positioned(
                        right: 5,
                        top: 5,
                        child: _FavoriteButton(
                          favorite: effectiveFavorite,
                          onPressed: () => onFavoriteChanged!(!effectiveFavorite),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line2)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      recipe.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      metadata.isEmpty ? '打开查看制作方法' : metadata.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.ink3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (recipe.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      PixelBadge(label: recipe.tags.first),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 选择模式：半透明绿色覆盖 + 右上角对勾角标。
          if (selected) ...<Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.greenDeep.withValues(alpha: .06),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: PixelSurface(
                cut: 3,
                elevation: 0,
                color: AppColors.greenDeep,
                borderColor: AppColors.greenDeep,
                borderWidth: 1.5,
                child: const SizedBox.square(
                  dimension: 20,
                  child: Icon(Icons.check_rounded, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 列表卡片左侧封面：有图显示真实图片，无图回退像素图标。
  Widget _coverBox(BuildContext context, {required double size}) {
    final cover = recipe.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return PixelSurface(
        cut: 4,
        elevation: 0,
        color: _coverColor(recipe.id),
        borderColor: AppColors.line2,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            _coverIcon(recipe.title),
            color: AppColors.greenDeep,
            size: size * 0.5,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: _coverImage(cover),
      ),
    );
  }

  /// 网格卡片顶部封面区：有图显示真实图片，无图回退像素图标。
  Widget _gridCover() {
    final cover = recipe.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return ColoredBox(
        color: _coverColor(recipe.id),
        child: Center(
          child: Icon(_coverIcon(recipe.title), color: AppColors.greenDeep, size: 48),
        ),
      );
    }
    return _coverImage(cover);
  }

  Widget _coverImage(String cover) {
    return Image.file(
      File(cover),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: _coverColor(recipe.id),
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.ink3, size: 30),
        ),
      ),
    );
  }

  static List<String> _metadata(Recipe recipe) => <String>[
    if (recipe.totalTimeMinutes != null) '${recipe.totalTimeMinutes} 分钟',
    if (recipe.servings != null) '${recipe.servings} 人份',
    if (recipe.ingredients.isNotEmpty) '${recipe.ingredients.length} 种食材',
  ];

  static Color _coverColor(String seed) {
    final colors = <Color>[
      AppColors.greenSoft,
      AppColors.amberSoft,
      AppColors.blueSoft,
      AppColors.redSoft,
    ];
    return colors[seed.hashCode.abs() % colors.length];
  }

  static IconData _coverIcon(String title) {
    if (title.contains('面') || title.contains('粉')) {
      return Icons.ramen_dining_rounded;
    }
    if (title.contains('汤')) return Icons.soup_kitchen_rounded;
    if (title.contains('饭')) return Icons.rice_bowl_rounded;
    return Icons.restaurant_rounded;
  }
}

/// 菜谱列表摘要卡片（解决方案.md 第一节）。
///
/// 列表页只展示卡片所需字段（标题/封面/收藏/时间/难度/食材数/标签），
/// 不携带完整聚合，配合 `RecipeSummary` 分页查询与虚拟化网格使用。
/// 视觉与 [RecipeCard] 一致（列表/网格两种形态）。
class RecipeSummaryCard extends StatelessWidget {
  const RecipeSummaryCard({
    super.key,
    required this.summary,
    this.onTap,
    this.onLongPress,
    this.onFavoriteChanged,
    this.favoriteOverride,
    this.selected = false,
    this.compact = false,
    this.grid = false,
    this.tile = false,
  });

  final RecipeSummary summary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFavoriteChanged;

  /// 外部收藏状态覆盖（乐观更新用）：非空时优先于 [RecipeSummary.favorite]。
  final bool? favoriteOverride;
  final bool selected;
  final bool compact;
  final bool grid;

  /// 横排小卡片（首页"最近浏览"用）：正方形封面 + 标题 + 所需时间等元数据。
  final bool tile;

  @override
  Widget build(BuildContext context) {
    if (grid) return _buildGridCard(context);
    if (tile) return _buildTileCard(context);
    final metadata = _metadata(summary);
    final effectiveFavorite = favoriteOverride ?? summary.favorite;
    return PixelSurface(
      cut: 8,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? AppColors.greenDeep : AppColors.line2,
      borderWidth: selected ? 2 : 1.5,
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _coverBox(context, size: compact ? 58 : 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.3,
                    ),
                  ),
                  if (metadata.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      metadata.join(' · '),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.ink3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (summary.tags.isNotEmpty && !compact) ...<Widget>[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: summary.tags
                          .take(3)
                          .map((tag) => PixelBadge(label: tag))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...<Widget>[
              const SizedBox(width: 8),
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenDeep,
                size: 20,
              ),
            ],
            if (onFavoriteChanged != null)
              _FavoriteButton(
                favorite: effectiveFavorite,
                onPressed: () => onFavoriteChanged!(!effectiveFavorite),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(BuildContext context) {
    final metadata = _metadata(summary);
    final effectiveFavorite = favoriteOverride ?? summary.favorite;
    return PixelSurface(
      cut: 7,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? AppColors.greenDeep : AppColors.line2,
      borderWidth: selected ? 2 : 1.5,
      padding: EdgeInsets.zero,
      child: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(child: _gridCover()),
                    if (summary.sourceId != null && !selected)
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: PixelBadge(
                          label: 'AI 导入',
                          icon: Icons.auto_awesome_rounded,
                          tone: PixelNoticeTone.green,
                        ),
                      ),
                    if (onFavoriteChanged != null)
                      Positioned(
                        right: 5,
                        top: 5,
                        child: _FavoriteButton(
                          favorite: effectiveFavorite,
                          onPressed: () => onFavoriteChanged!(!effectiveFavorite),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.line2)),
                ),
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      metadata.isEmpty ? '打开查看制作方法' : metadata.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.ink3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (summary.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      PixelBadge(label: summary.tags.first),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 选择模式：半透明绿色覆盖 + 右上角对勾角标。
          if (selected) ...<Widget>[
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.greenDeep.withValues(alpha: .06),
              ),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: PixelSurface(
                cut: 3,
                elevation: 0,
                color: AppColors.greenDeep,
                borderColor: AppColors.greenDeep,
                borderWidth: 1.5,
                child: const SizedBox.square(
                  dimension: 20,
                  child: Icon(Icons.check_rounded, size: 15, color: Colors.white),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _coverBox(BuildContext context, {required double size}) {
    final cover = summary.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return PixelSurface(
        cut: 4,
        elevation: 0,
        color: _coverColor(summary.id),
        borderColor: AppColors.line2,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            _coverIcon(summary.title),
            color: AppColors.greenDeep,
            size: size * 0.5,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: _coverImage(cover),
      ),
    );
  }

  /// 横排小卡片（首页"最近浏览"用）：正方形封面在上，标题与所需时间等元数据在下。
  ///
  /// 外部用横向 [ListView] + 固定宽度 [SizedBox] 包裹，封面由
  /// [AspectRatio] 保证 1:1 正方形（项目负责人要求）。
  Widget _buildTileCard(BuildContext context) {
    final metadata = _metadata(summary);
    return PixelSurface(
      cut: 7,
      onTap: onTap,
      onLongPress: onLongPress,
      borderColor: selected ? AppColors.greenDeep : AppColors.line2,
      borderWidth: selected ? 2 : 1.5,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 正方形封面：宽度跟随卡片（AspectRatio 1:1），四周留一点边距。
          Padding(
            //padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: AspectRatio(aspectRatio: 1, child: _tileCover()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  summary.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                // 所需时间 · 人份 · 食材数等信息。
                Text(
                  metadata.isEmpty ? '打开查看制作方法' : metadata.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 横排卡片封面：无图回退色块+图标，有图本地文件填充。
  Widget _tileCover() {
    final cover = summary.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return ColoredBox(
        color: _coverColor(summary.id),
        child: Center(
          child: Icon(
            _coverIcon(summary.title),
            color: AppColors.greenDeep,
            size: 42,
          ),
        ),
      );
    }
    return _coverImage(cover);
  }

  Widget _gridCover() {
    final cover = summary.coverImage;
    if (cover == null || cover.trim().isEmpty) {
      return ColoredBox(
        color: _coverColor(summary.id),
        child: Center(
          child: Icon(
            _coverIcon(summary.title),
            color: AppColors.greenDeep,
            size: 48,
          ),
        ),
      );
    }
    return _coverImage(cover);
  }

  Widget _coverImage(String cover) {
    return Image.file(
      File(cover),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: _coverColor(summary.id),
        child: const Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.ink3, size: 30),
        ),
      ),
    );
  }

  static List<String> _metadata(RecipeSummary summary) => <String>[
    if (summary.totalTimeMinutes != null) '${summary.totalTimeMinutes} 分钟',
    if (summary.servings != null) '${summary.servings} 人份',
    if (summary.ingredientCount > 0) '${summary.ingredientCount} 种食材',
  ];

  /// 无封面时的底色（与 [RecipeCard] 保持一致，按 id 稳定取色）。
  static Color _coverColor(String seed) {
    final colors = <Color>[
      AppColors.greenSoft,
      AppColors.amberSoft,
      AppColors.blueSoft,
      AppColors.redSoft,
    ];
    return colors[seed.hashCode.abs() % colors.length];
  }

  /// 无封面时的回退图标（与 [RecipeCard] 保持一致，按菜名映射）。
  static IconData _coverIcon(String title) {
    if (title.contains('面') || title.contains('粉')) {
      return Icons.ramen_dining_rounded;
    }
    if (title.contains('汤')) return Icons.soup_kitchen_rounded;
    if (title.contains('饭')) return Icons.rice_bowl_rounded;
    return Icons.restaurant_rounded;
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.favorite, required this.onPressed});

  final bool favorite;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: favorite ? '取消收藏' : '收藏',
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: AppColors.card.withValues(alpha: .9),
      side: const BorderSide(color: AppColors.line2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
    ),
    onPressed: onPressed,
    icon: Icon(
      favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: 19,
      color: favorite ? AppColors.red : AppColors.ink2,
    ),
  );
}
