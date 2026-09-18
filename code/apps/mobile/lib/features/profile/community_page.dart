import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 「加入交流群」页。
///
/// 展示交流群二维码海报（源图 `design/assets/交流群.jpg`），点击可全屏
/// 放大预览（支持双指缩放），方便保存后长按识别或用QQ 扫一扫进群。
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  /// 群二维码海报 asset 路径（竖版 1352×2405 原图）。
  static const String _groupPoster = 'assets/community/qq_group.jpg';

  /// 打开群二维码全屏预览（黑底 + 双指缩放）。
  void _openPreview(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const _GroupPosterPreview(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 112),
          children: <Widget>[
            const AppPageHeader(
              eyebrow: '加入交流群',
              title: '一起聊下厨那些事',
              subtitle: '使用 QQ 扫一扫下面的二维码，欢迎来群里交流菜谱、分享心得。',
            ),
            const SizedBox(height: 16),
            // 引导卡片：说明进群方式与能获得什么。
            const PixelSurface(
              cut: PixelCut.lg,
              color: AppColors.card,
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '为什么加入交流群？',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '在群里你可以：和其他使用者交流做菜心得、反馈使用建议、'
                    '第一时间了解新版本动态，也可以把希望支持的菜谱类型告诉我们。'
                    '我们很期待听到你的声音。',
                    style: TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.ink2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const AppSectionTitle(title: '群二维码'),
            const SizedBox(height: 10),
            // 群二维码海报卡片：点击放大预览。
            PixelSurface(
              cut: PixelCut.sm,
              color: AppColors.card,
              padding: const EdgeInsets.all(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _openPreview(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 竖版海报：按源图比例展示，点击放大。
                    AspectRatio(
                      aspectRatio: 1352 / 2405,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.asset(
                          _groupPoster,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.ink3,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      children: <Widget>[
                        Icon(
                          Icons.forum_outlined,
                          size: 16,
                          color: AppColors.greenDeep,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '进群方式',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '点击放大',
                          style: TextStyle(fontSize: 11, color: AppColors.ink3),
                        ),
                        Icon(
                          Icons.zoom_in_rounded,
                          size: 14,
                          color: AppColors.ink3,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            // 底部提示：进群注意事项。
            const PixelSurface(
              cut: PixelCut.sm,
              color: AppColors.greenSofter,
              padding: EdgeInsets.all(12),
              child: Text(
               
                '在 QQ 里可直接长按图片识别二维码。进群请遵守群规，友善交流。',
                style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.greenInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 群二维码全屏预览：黑底 + 双指缩放，方便保存后识别。
class _GroupPosterPreview extends StatelessWidget {
  const _GroupPosterPreview();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: .92),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 全屏海报：双指缩放查看细节。
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.asset(
                  CommunityPage._groupPoster,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 48,
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
            // 底部引导文字（BoxDecoration 非 const，故外层不能加 const）。
            Positioned(
              left: 0,
              right: 0,
              bottom: 18,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: const Text(
                    '保存图片 → QQ 扫一扫识别',
                    style: TextStyle(fontSize: 12, color: Colors.white, letterSpacing: 1),
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
