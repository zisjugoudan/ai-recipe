import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 欢迎页。
///
/// 视觉按 UI-WELCOME-001 重设计：像素风品牌标题、漂浮食材元素、
/// 立体相框插画、带尾巴的像素气泡副标题，并保留登录/游客/隐私说明。
class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.onContinueAsGuest,
    required this.onLogin,
    required this.onRetry,
    this.busy = false,
    this.errorMessage,
  });

  final Future<void> Function() onContinueAsGuest;
  final VoidCallback onLogin;
  final VoidCallback onRetry;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _WelcomeHero(),
                  const SizedBox(height: 22),
                  const _FeatureRow(
                    icon: Icons.link_rounded,
                    title: '链接一键导入',
                    detail: 'AI 把图文 / 视频整理成结构化菜谱，确认后才保存',
                  ),
                  const SizedBox(height: 12),
                  const _FeatureRow(
                    icon: Icons.key_rounded,
                    title: '不登录也能用 AI',
                    detail: '支持自定义 LLM API，Key 只加密保存在本机',
                  ),
                  const SizedBox(height: 12),
                  const _FeatureRow(
                    icon: Icons.shield_outlined,
                    title: '隐私优先',
                    detail: '游客数据仅保存在本机，可一键禁止任何上传',
                  ),
                  if (errorMessage != null) ...<Widget>[
                    const SizedBox(height: 16),
                    PixelNotice(
                      title: errorMessage!,
                      message: '本地空间准备失败，请重试。',
                      icon: Icons.warning_amber_rounded,
                      tone: PixelNoticeTone.red,
                      trailing: TextButton(
                        key: const Key('welcomeRetryButton'),
                        onPressed: onRetry,
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    key: const Key('welcomeLoginButton'),
                    onPressed: busy ? null : onLogin,
                    icon: const Icon(Icons.person_outline_rounded, size: 19),
                    label: const Text('登录 / 注册'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('welcomeGuestButton'),
                    onPressed: busy ? null : () => onContinueAsGuest(),
                    icon: busy
                        ? const PixelLoader(size: 6)
                        : const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(busy ? '正在准备本地空间…' : '游客继续，先逛逛'),
                  ),
                  const SizedBox(height: 18),
                  const _PrivacyPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 欢迎页顶部视觉区：响应式品牌构图 → 插画相框 → 说明气泡。
class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final sectionGap = (width * .025).clamp(8.0, 14.0).toDouble();
        final bubbleOverlap = (width * .018).clamp(5.0, 9.0).toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const _FloatingTitle(),
            SizedBox(height: sectionGap),
            const _PixelBevelFrame(key: Key('welcomeCoverFrame')),
            Transform.translate(
              offset: Offset(0, -bubbleOverlap),
              child: const FractionallySizedBox(
                widthFactor: .82,
                child: _PixelSpeechBubble(
                  key: Key('welcomeSubtitleBubble'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 像素风品牌标题，周围环绕漂浮食材元素。
///
/// 五个装饰的锚点、宽度和浮动幅度都以当前容器为基准计算，
/// 不绑定某一台手机的屏幕像素坐标；平板上再通过最大高度限制避免失控放大。
class _FloatingTitle extends StatelessWidget {
  const _FloatingTitle();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final height = (width * .34).clamp(118.0, 172.0).toDouble();
        final amplitude = (width * .009).clamp(2.5, 4.5).toDouble();

        return SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: <Widget>[
              const Positioned.fill(
                child: Align(
                  alignment: FractionalOffset(.5, .5),
                  child: FractionallySizedBox(
                    widthFactor: .31,
                    child: _PixelBrandTitle(),
                  ),
                ),
              ),
              _ResponsiveFloatingAsset(
                asset: 'assets/welcome/float_hat.png',
                anchor: const FractionalOffset(.035, .18),
                widthFactor: .075,
                amplitude: amplitude * .78,
              ),
              _ResponsiveFloatingAsset(
                asset: 'assets/welcome/float_carrot.png',
                anchor: const FractionalOffset(.06, .76),
                widthFactor: .082,
                amplitude: amplitude,
              ),
              _ResponsiveFloatingAsset(
                asset: 'assets/welcome/float_tomato.png',
                anchor: const FractionalOffset(.22, .31),
                widthFactor: .078,
                amplitude: amplitude * .82,
              ),
              _ResponsiveFloatingAsset(
                asset: 'assets/welcome/float_chili.png',
                anchor: const FractionalOffset(.86, .2),
                widthFactor: .084,
                amplitude: amplitude * .82,
              ),
              _ResponsiveFloatingAsset(
                asset: 'assets/welcome/float_leaf.png',
                anchor: const FractionalOffset(.93, .73),
                widthFactor: .066,
                amplitude: amplitude,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResponsiveFloatingAsset extends StatelessWidget {
  const _ResponsiveFloatingAsset({
    required this.asset,
    required this.anchor,
    required this.widthFactor,
    required this.amplitude,
  });

  final String asset;
  final FractionalOffset anchor;
  final double widthFactor;
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: anchor,
        child: FractionallySizedBox(
          widthFactor: widthFactor,
          child: PixelFloat(
            amplitude: amplitude,
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 品牌标题「巴食」——使用项目内置的像素字体（Fusion Pixel）渲染，
/// 替代此前的波纹扩散动画与手工点阵绘制；保留右下立体阴影与副标。
class _PixelBrandTitle extends StatelessWidget {
  const _PixelBrandTitle();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 240.0;
        // 等宽汉字宽≈字号；「巴食」两字共约 2×字号，按容器宽度取字号
        final brandSize = (width * .46).clamp(40.0, 68.0).toDouble();
        final labelGap = (width * .05).clamp(4.0, 7.0).toDouble();
        final labelSize = (width * .09).clamp(9.0, 12.0).toDouble();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Semantics(
              key: const Key('welcomeBrandSemantics'),
              label: '巴食',
              image: true,
              child: Text(
                '巴食',
                key: const Key('welcomeTitle'),
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: brandSize,
                  height: 1.1,
                  letterSpacing: 2,
                  color: AppColors.greenDeep,
                  fontFamily: 'FusionPixel',
                  // 右下偏移硬阴影，保留像素字立体感
                  shadows: const <Shadow>[
                    Shadow(
                      color: AppColors.ink,
                      offset: Offset(3, 3),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: labelGap),
            Text(
              '拾味 · AI 菜谱',
              maxLines: 1,
              style: TextStyle(
                fontSize: labelSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: AppColors.ink2,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 主插画像素立体相框。
///
/// 层次由外到内为：右下投影、墨绿轮廓、深绿框体、浅色框带、
/// 上左高光 / 下右压暗、内侧墨绿压边；框厚随容器宽度轻微缩放。
class _PixelBevelFrame extends StatelessWidget {
  const _PixelBevelFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final unit = (width * .0115).clamp(3.2, 5.6).toDouble();
        final shadowOffset = unit * .9;
        final imageInset = unit * 3.15;

        return AspectRatio(
          aspectRatio: 16 / 10,
          child: CustomPaint(
            painter: _WelcomeFramePainter(
              unit: unit,
              shadowOffset: shadowOffset,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                imageInset,
                imageInset,
                imageInset + shadowOffset,
                imageInset + shadowOffset,
              ),
              child: ClipPath(
                clipper: PixelCutClipper(cut: unit * .72),
                child: Image.asset(
                  'assets/welcome/cover.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeFramePainter extends CustomPainter {
  const _WelcomeFramePainter({
    required this.unit,
    required this.shadowOffset,
  });

  final double unit;
  final double shadowOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(
      0,
      0,
      size.width - shadowOffset,
      size.height - shadowOffset,
    );
    final cut = unit * 1.15;

    canvas.drawPath(
      _cutRectPath(outer.shift(Offset(shadowOffset, shadowOffset)), cut),
      Paint()..color = AppColors.greenInk.withValues(alpha: .62),
    );
    canvas.drawPath(
      _cutRectPath(outer, cut),
      Paint()..color = AppColors.greenInk,
    );

    final body = outer.deflate(unit * .62);
    canvas.drawPath(
      _cutRectPath(body, cut * .82),
      Paint()..color = AppColors.greenDeep,
    );

    final face = outer.deflate(unit * 1.42);
    final facePath = _cutRectPath(face, cut * .58);
    canvas.drawPath(facePath, Paint()..color = AppColors.greenSoft);

    canvas.save();
    canvas.clipPath(facePath);
    final highlight = Paint()..color = AppColors.card;
    final shade = Paint()..color = AppColors.greenDeep.withValues(alpha: .72);
    canvas.drawRect(
      Rect.fromLTWH(face.left, face.top, face.width, unit * .72),
      highlight,
    );
    canvas.drawRect(
      Rect.fromLTWH(face.left, face.top, unit * .72, face.height),
      highlight,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        face.left,
        face.bottom - unit * .78,
        face.width,
        unit * .78,
      ),
      shade,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        face.right - unit * .78,
        face.top,
        unit * .78,
        face.height,
      ),
      shade,
    );
    canvas.restore();

    final inner = outer.deflate(unit * 2.55);
    canvas.drawPath(
      _cutRectPath(inner, cut * .38),
      Paint()..color = AppColors.greenInk,
    );
    final innerHighlight = inner.deflate(unit * .38);
    canvas.drawPath(
      _cutRectPath(innerHighlight, cut * .28),
      Paint()..color = AppColors.paper2,
    );
  }

  Path _cutRectPath(Rect rect, double cut) {
    return PixelCutClipper(cut: cut).getClip(rect.size).shift(rect.topLeft);
  }

  @override
  bool shouldRepaint(_WelcomeFramePainter oldDelegate) =>
      oldDelegate.unit != unit || oldDelegate.shadowOffset != shadowOffset;
}

/// 插画下方的像素说明气泡，顶部尾巴向上连接主插画。
class _PixelSpeechBubble extends StatelessWidget {
  const _PixelSpeechBubble({super.key});

  @override
  Widget build(BuildContext context) {
    const subtitle = '把小红书 / 抖音上的菜谱，收进你的口袋厨房';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 280.0;
        final tailWidth = (width * .045).clamp(11.0, 15.0).toDouble();
        final tailHeight = (width * .032).clamp(8.0, 11.0).toDouble();
        final horizontal = (width * .055).clamp(13.0, 18.0).toDouble();

        return CustomPaint(
          painter: _SpeechBubblePainter(
            backgroundColor: AppColors.card,
            borderColor: AppColors.ink,
            borderWidth: 1.5,
            tailWidth: tailWidth,
            tailHeight: tailHeight,
            tailPosition: .28,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              tailHeight + 8,
              horizontal + 18,
              12,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                const Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const Positioned(
                  right: -13,
                  bottom: -2,
                  child: Text(
                    '♥',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1,
                      color: AppColors.red,
                    ),
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

class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.borderWidth,
    required this.tailWidth,
    required this.tailHeight,
    required this.tailPosition,
  });

  final Color backgroundColor;
  final Color borderColor;
  final double borderWidth;
  final double tailWidth;
  final double tailHeight;
  final double tailPosition;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyTop = tailHeight;
    const corner = 5.0;
    final tailCenter = size.width * tailPosition;
    final tailHalf = tailWidth / 2;
    final path = Path()
      ..moveTo(corner, bodyTop)
      ..lineTo(tailCenter - tailHalf, bodyTop)
      ..lineTo(tailCenter, 0)
      ..lineTo(tailCenter + tailHalf, bodyTop)
      ..lineTo(size.width - corner, bodyTop)
      ..lineTo(size.width, bodyTop + corner)
      ..lineTo(size.width, size.height - corner)
      ..lineTo(size.width - corner, size.height)
      ..lineTo(corner, size.height)
      ..lineTo(0, size.height - corner)
      ..lineTo(0, bodyTop + corner)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill
        ..isAntiAlias = false,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth * 2
        ..strokeJoin = StrokeJoin.miter
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_SpeechBubblePainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.borderWidth != borderWidth ||
      oldDelegate.tailWidth != tailWidth ||
      oldDelegate.tailHeight != tailHeight ||
      oldDelegate.tailPosition != tailPosition;
}
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        PixelSurface(
          cut: 3,
          elevation: 0,
          color: AppColors.greenSofter,
          borderColor: AppColors.greenDeep.withValues(alpha: .3),
          child: SizedBox.square(
            dimension: 34,
            child: Icon(icon, size: 17, color: AppColors.greenDeep),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.ink3,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();
  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: 4,
      elevation: 0,
      color: AppColors.card2,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: const ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 14, vertical: 1),
          childrenPadding: EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            Icons.shield_outlined,
            size: 17,
            color: AppColors.greenDeep,
          ),
          title: Text(
            '隐私说明（游客模式数据仅保存在本机）',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
          children: <Widget>[
            Text(
              '游客模式下，菜谱、分类、LLM API Key 等数据仅保存在本机。登录并开启云同步后，本地游客数据按"合并不覆盖"同步；自定义 LLM API 请求由设备直接发往你配置的服务商。你可以在「我的 → 隐私与上传设置」中禁止图片上传。',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.ink2,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

