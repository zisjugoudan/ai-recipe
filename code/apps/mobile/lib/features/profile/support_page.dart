import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 「支持我们」赞赏页。
///
/// 展示微信 / 支付宝收款码与感谢语；点击收款码可全屏放大预览
/// （支持双指缩放），方便用户保存或扫码。收款码资产打包自
/// `design/assets/收款码/`（微信.jpg、支付宝.jpg）。
class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  /// 收款码资产清单（asset 路径 + 平台名 + 展示用宽高比）。
  static const List<({String asset, String label, double aspectRatio})>
      _qrCodes = <({String asset, String label, double aspectRatio})>[
    (
      asset: 'assets/payment/wechat_qr.jpg',
      label: '微信赞赏',
      // 源图 1213×1213 正方形。
      aspectRatio: 1,
    ),
    (
      asset: 'assets/payment/alipay_qr.jpg',
      label: '支付宝赞赏',
      // 源图 1260×1890 竖版。
      aspectRatio: 2 / 3,
    ),
  ];

  /// 打开收款码全屏预览（黑底 + 双指缩放 + 左右滑动切换）。
  void _openPreview(BuildContext context, int initialIndex) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SupportQrPreview(
          images: _qrCodes.map((code) => code.asset).toList(),
          labels: _qrCodes.map((code) => code.label).toList(),
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 独立路由页面必须自带 Scaffold 提供 Material 上下文，
    // 否则内部 InkWell 等组件会报 "No Material widget found"。
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 112),
          children: <Widget>[
          const AppPageHeader(
            eyebrow: '支持我们',
            title: '感谢你的支持',
            subtitle: '如果这款软件帮到了你，欢迎扫码赞赏，持续维护离不开你。',
          ),
          const SizedBox(height: 16),
          // 感谢语卡片：说明赞赏自愿、用途与不赞赏也无妨。
          PixelSurface(
            cut: PixelCut.lg,
            color: AppColors.card,
            padding: const EdgeInsets.all(16),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '感谢使用巴食',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '很荣幸能成为你下厨路上的小帮手。如果你喜欢这款软件，'
                  '愿意请我们喝一杯咖啡，可以扫描下方任意收款码。'
                  '赞赏完全自愿，不赞赏也完全没关系，软件的核心功能永远免费使用。',
                  style: TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const AppSectionTitle(title: '扫码赞赏'),
          const SizedBox(height: 10),
          // 两张收款码卡片：点击进入全屏预览。
          for (var index = 0; index < _qrCodes.length; index++) ...[
            _QrCodeCard(
              key: Key('supportQrCodeCard-$index'),
              asset: _qrCodes[index].asset,
              label: _qrCodes[index].label,
              aspectRatio: _qrCodes[index].aspectRatio,
              onTap: () => _openPreview(context, index),
            ),
            if (index < _qrCodes.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 18),
          // 底部提示：隐私说明与感谢。
          const PixelSurface(
            cut: PixelCut.sm,
            color: AppColors.greenSofter,
            padding: EdgeInsets.all(12),
            child: Text(
              '提示：赞赏金额与次数完全由你决定，不会影响任何功能的使用。'
              '你的支持是我们持续打磨这款软件的最大动力。',
              style: TextStyle(fontSize: 12, height: 1.6, color: AppColors.greenInk),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// 单张收款码卡片：缩略图 + 平台标签，点击可放大预览。
class _QrCodeCard extends StatelessWidget {
  const _QrCodeCard({
    super.key,
    required this.asset,
    required this.label,
    required this.aspectRatio,
    required this.onTap,
  });

  final String asset;
  final String label;
  final double aspectRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: PixelCut.sm,
      color: AppColors.card,
      padding: const EdgeInsets.all(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 收款码缩略图：按源图比例展示，点击放大。
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.asset(
                  asset,
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
            Row(
              children: <Widget>[
                Icon(
                  label.startsWith('微信') ? Icons.wechat : Icons.account_balance_wallet_outlined,
                  size: 16,
                  color: AppColors.greenDeep,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                const Text(
                  '点击放大',
                  style: TextStyle(fontSize: 11, color: AppColors.ink3),
                ),
                const Icon(
                  Icons.zoom_in_rounded,
                  size: 14,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 收款码全屏预览：黑底 + 左右滑动切换 + 双指缩放（参考
/// 菜谱详情的 `_FullscreenImageGallery` 交互模式，使用 asset 图片）。
class _SupportQrPreview extends StatefulWidget {
  const _SupportQrPreview({
    required this.images,
    required this.labels,
    required this.initialIndex,
  });

  final List<String> images;
  final List<String> labels;
  final int initialIndex;

  @override
  State<_SupportQrPreview> createState() => _SupportQrPreviewState();
}

class _SupportQrPreviewState extends State<_SupportQrPreview> {
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
      backgroundColor: Colors.black.withValues(alpha: .92),
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 全屏轮播：左右滑动切换收款码，双指缩放查看细节。
            PageView.builder(
              key: const Key('supportQrPreview'),
              controller: _controller,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Image.asset(
                    widget.images[index],
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
            // 底部：平台标签 + 页码。
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
                    '${widget.labels[_page]} · ${_page + 1} / ${widget.images.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      letterSpacing: 1,
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
