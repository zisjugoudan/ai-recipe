import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

enum PixelNoticeTone { neutral, green, amber, red, blue }

/// 像素阶梯缺角三档（与 prototype.css 的 pxc-lg / pxc-sm / pxc-xs 对齐）。
abstract final class PixelCut {
  /// 大缺角 8px，2px 台阶（卡片/大面板）。
  static const double lg = 8;

  /// 小缺角 4px，2px 台阶（按钮/输入）。
  static const double sm = 4;

  /// 微缺角 3px，3px 台阶（徽标/小方块）。
  static const double xs = 3;
}

/// 像素阶梯缺角裁剪（1:1 复刻 prototype.css 的阶梯多边形）。
///
/// 台阶步长由缺角尺寸推导：8/4 → 2px 双台阶，3 → 3px 单台阶，
/// 其余尺寸按一半取整作为步长，保证缺口永远是阶梯而非斜切。
class PixelCutClipper extends CustomClipper<Path> {
  const PixelCutClipper({this.cut = PixelCut.lg});
  final double cut;

  @override
  Path getClip(Size size) {
    final c = math.min(cut, math.min(size.width, size.height) / 4);
    final s = c <= 3 ? 3.0 : 2.0;
    final n = math.max(1, (c / s).floor());
    final path = Path();

    // 左上角：(0, c) → (c, 0)，水平/垂直交替 2px 台阶。
    path.moveTo(0, c);
    for (var i = 0; i < n; i++) {
      path.lineTo((i + 1) * s, c - i * s);
      path.lineTo((i + 1) * s, c - (i + 1) * s);
    }
    // 顶边 → 右上角 → 右边。
    path.lineTo(size.width - c, 0);
    var x = size.width - c;
    var y = 0.0;
    for (var i = 0; i < n; i++) {
      y += s;
      path.lineTo(x, y);
      x += s;
      path.lineTo(x, y);
    }
    // 右边 → 右下角 → 底边。
    path.lineTo(size.width, size.height - c);
    x = size.width;
    y = size.height - c;
    for (var i = 0; i < n; i++) {
      x -= s;
      path.lineTo(x, y);
      y += s;
      path.lineTo(x, y);
    }
    // 底边 → 左下角 → 左边 → 闭合。
    path.lineTo(c, size.height);
    x = c;
    y = size.height;
    for (var i = 0; i < n; i++) {
      y -= s;
      path.lineTo(x, y);
      x -= s;
      path.lineTo(x, y);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(PixelCutClipper oldClipper) => oldClipper.cut != cut;
}

/// 像素缺角 OutlinedBorder（用于按钮等 Material 控件的全局主题）。
///
/// 与 CSS 的 `clip-path + inset 描边` 对齐：外轮廓是阶梯缺角，
/// 内部绘制 borderSide 描边。
class PixelCutOutlinedBorder extends OutlinedBorder {
  const PixelCutOutlinedBorder({
    this.cut = PixelCut.sm,
    super.side = const BorderSide(color: AppColors.ink, width: 1.5),
  });

  final double cut;

  Path _pathFor(Rect rect) => PixelCutClipper(cut: cut)
      .getClip(rect.size)
      .shift(rect.topLeft);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return PixelCutClipper(cut: cut)
        .getClip(rect.deflate(side.width).size)
        .shift(rect.deflate(side.width).topLeft);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _pathFor(rect);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    if (side.width <= 0) return;
    // 与 _PixelBorderPainter 相同的 inset 描边带：切角外轮廓 − 内缩矩形，
    // 避免沿阶梯路径居中 stroke 在凹角产生 miter 尖刺。
    final innerRect = rect.deflate(side.width);
    if (innerRect.width <= 0 || innerRect.height <= 0) return;
    final bandPath = Path.combine(
      PathOperation.difference,
      _pathFor(rect),
      Path()..addRect(innerRect),
    );
    canvas.drawPath(bandPath, side.toPaint());
  }

  @override
  PixelCutOutlinedBorder copyWith({BorderSide? side}) {
    return PixelCutOutlinedBorder(cut: cut, side: side ?? this.side);
  }

  @override
  ShapeBorder scale(double t) {
    return PixelCutOutlinedBorder(cut: cut, side: side.scale(t));
  }
}

/// 像素缺角 InputBorder（用于输入框的边框，继承 Material InputBorder）。
///
/// 聚焦等状态通过不同 borderSide 颜色/宽度表达（CSS .input:focus）。
class PixelCutInputBorder extends InputBorder {
  const PixelCutInputBorder({
    this.cut = PixelCut.sm,
    super.borderSide = const BorderSide(color: AppColors.line2, width: 1.4),
  });

  final double cut;

  Path _pathFor(Rect rect) => PixelCutClipper(cut: cut)
      .getClip(rect.size)
      .shift(rect.topLeft);

  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return PixelCutClipper(cut: cut)
        .getClip(rect.deflate(borderSide.width).size)
        .shift(rect.deflate(borderSide.width).topLeft);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _pathFor(rect);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    if (borderSide.width <= 0) return;
    // inset 描边带（同 PixelCutOutlinedBorder）：消除凹角 miter 尖刺。
    final innerRect = rect.deflate(borderSide.width);
    if (innerRect.width <= 0 || innerRect.height <= 0) return;
    final bandPath = Path.combine(
      PathOperation.difference,
      _pathFor(rect),
      Path()..addRect(innerRect),
    );
    canvas.drawPath(bandPath, borderSide.toPaint());
  }

  @override
  PixelCutInputBorder copyWith({BorderSide? borderSide}) {
    return PixelCutInputBorder(cut: cut, borderSide: borderSide ?? this.borderSide);
  }

  @override
  ShapeBorder scale(double t) {
    return PixelCutInputBorder(cut: cut, borderSide: borderSide.scale(t));
  }
}

/// 像素虚线分隔（1:1 复刻 CSS 的 repeating-linear-gradient 虚线分隔线）。
class PixelDashedDivider extends StatelessWidget {
  const PixelDashedDivider({
    super.key,
    this.thickness = 2,
    this.color = AppColors.line2,
    this.dash = 6,
    this.gap = 4,
    this.vertical = false,
  });

  final double thickness;
  final Color color;
  final double dash;
  final double gap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(
        color: color,
        dash: dash,
        gap: gap,
        vertical: vertical,
        thickness: thickness,
      ),
      size: vertical
          ? Size(thickness, double.infinity)
          : Size(double.infinity, thickness),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.vertical,
    required this.thickness,
  });

  final Color color;
  final double dash;
  final double gap;
  final bool vertical;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    final step = dash + gap;
    if (vertical) {
      var y = 0.0;
      while (y < size.height) {
        canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, y + dash), paint);
        y += step;
      }
    } else {
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, size.height / 2), Offset(x + dash, size.height / 2), paint);
        x += step;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap ||
      oldDelegate.vertical != vertical ||
      oldDelegate.thickness != thickness;
}

/// 底部导航单个 tab（与 prototype.css .tab 对齐）。
///
/// 支持传入 [Widget]（如 Image.asset）或 [IconData] 作为图标。
typedef PixelTab = ({
  String key,
  Object icon,
  Object selectedIcon,
  String label,
});

/// 像素底部导航（1:1 复刻 prototype.css .tabbar / .tab）。
///
/// 顶部虚线分隔 + 等分 tab；选中项为 greenSofter 底 + 深绿 inset 描边。
/// tab 图标可以是 IconData 或任意 Widget（用于 asset 图片图标）。
class PixelTabBar extends StatelessWidget {
  const PixelTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.tabs,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<PixelTab> tabs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: .96),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const PixelDashedDivider(thickness: 2, color: AppColors.line2),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              children: <Widget>[
                for (var i = 0; i < tabs.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(child: _buildTab(context, i)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, int index) {
    final tab = tabs[index];
    final active = index == selectedIndex;
    final icon = active ? tab.selectedIcon : tab.icon;
    return Material(
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(0)),
      ),
      child: InkWell(
        key: Key(tab.key),
        onTap: () => onSelect(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 21,
                height: 21,
                child: _buildIcon(icon, active: active),
              ),
              const SizedBox(height: 3),
              Text(
                tab.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: active ? AppColors.greenInk : AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Object icon, {required bool active}) {
    if (icon is IconData) {
      return Icon(
        icon,
        size: 21,
        color: active ? AppColors.greenDeep : AppColors.ink3,
      );
    }
    if (icon is Widget) return icon;
    throw ArgumentError('PixelTab icon must be IconData or Widget');
  }
}

/// 分区标题：绿色像素方块 + 硬边投影（prototype.css .sec-title）。
class PixelSectionTitle extends StatelessWidget {
  const PixelSectionTitle(this.text, {super.key, this.more});

  final String text;
  final String? more;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
        children: <Widget>[
          // 9px 绿色方块 + 2px 硬边投影（CSS .sec-title::before
          // box-shadow: 2px 2px 0 rgba(54,64,58,.22)）。
          SizedBox(
            width: 11,
            height: 11,
            child: Stack(
              children: <Widget>[
                Transform.translate(
                  offset: const Offset(2, 2),
                  child: const SizedBox.square(
                    dimension: 9,
                    child: ColoredBox(color: Color(0x3836403A)),
                  ),
                ),
                const SizedBox.square(
                  dimension: 9,
                  child: ColoredBox(color: AppColors.green),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            text,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          if (more != null) ...<Widget>[
            const Spacer(),
            Text(
              more!,
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ],
        ],
      ),
    );
  }
}

/// 像素阶梯浮动动画（复刻 CSS `px-float 2.6s steps(4)`）。
class PixelFloat extends StatefulWidget {
  const PixelFloat({
    super.key,
    required this.child,
    this.amplitude = 4,
  });

  final Widget child;
  final double amplitude;

  @override
  State<PixelFloat> createState() => _PixelFloatState();
}

class _PixelFloatState extends State<PixelFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 系统"减少动态"时直达终态（静态，0 位移）：遵循 UI-002 既定原则
    // "系统减少动态时直达终态"。同时停止 ticker，避免无限动画导致
    // widget 测试 pumpAndSettle 永不结束。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // steps(4) 阶梯位移：0 → -2/3 幅 → 满幅 → 回落。
        final v = _controller.value;
        final double k;
        if (v < .25) {
          k = 0;
        } else if (v < .5) {
          k = .4;
        } else if (v < .75) {
          k = 1;
        } else {
          k = .4;
        }
        return Transform.translate(
          offset: Offset(0, -widget.amplitude * k),
          child: widget.child,
        );
      },
    );
  }
}

class PixelSurface extends StatelessWidget {
  const PixelSurface({
    super.key,
    required this.child,
    this.color = AppColors.card,
    this.borderColor = AppColors.line2,
    this.borderWidth = 1.5,
    this.cut = 8,
    this.padding,
    this.elevation = 2,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final double cut;
  final EdgeInsetsGeometry? padding;
  final double elevation;
  final VoidCallback? onTap;

  /// 长按回调：与 [onTap] 由同一个 InkWell 处理，两者天然互斥
  /// （长按触发时不会同时触发点击），在列表内长按稳定可用。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final content = CustomPaint(
      foregroundPainter: _PixelBorderPainter(
        cut: cut,
        color: borderColor,
        band: borderWidth,
      ),
      child: ColoredBox(
        color: color,
        child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
    final hasGestures = onTap != null || onLongPress != null;
    return PhysicalShape(
      color: Colors.transparent,
      elevation: elevation,
      shadowColor: AppColors.ink.withValues(alpha: .18),
      clipper: PixelCutClipper(cut: cut),
      child: !hasGestures
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                child: content,
              ),
            ),
    );
  }
}

class _PixelBorderPainter extends CustomPainter {
  const _PixelBorderPainter({
    required this.cut,
    required this.color,
    this.band = 1.5,
  });

  final double cut;
  final Color color;
  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    // CSS 原型 `box-shadow: inset 0 0 0 W` 是先画“矩形内缩 W”
    // 的描边带，再被 clip-path 切角裁剪。因此描边带 = 切角外轮廓
    // − 内缩 W 的矩形；若用“内缩切角路径”做差集，角部台阶会错位，
    // 出现粗细不均的波浪边（旧实现）。
    final rect = Offset.zero & size;
    final innerRect = rect.deflate(band);
    if (innerRect.width <= 0 || innerRect.height <= 0) return;
    final outer = PixelCutClipper(cut: cut).getClip(size);
    final bandPath = Path.combine(
      PathOperation.difference,
      outer,
      Path()..addRect(innerRect),
    );
    canvas.drawPath(bandPath, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PixelBorderPainter oldDelegate) =>
      oldDelegate.cut != cut ||
      oldDelegate.color != color ||
      oldDelegate.band != band;
}

class PxLabel extends StatelessWidget {
  const PxLabel(this.text, {super.key, this.color, this.textAlign});
  final String text;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    textAlign: textAlign,
    style: TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      height: 1.25,
      letterSpacing: 2.1,
      fontWeight: FontWeight.w800,
      color: color ?? AppColors.ink3,
    ),
  );
}

class PixelBadge extends StatelessWidget {
  const PixelBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = PixelNoticeTone.neutral,
  });
  final String label;
  final IconData? icon;
  final PixelNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _tone(tone);
    // 描边对齐原型 .ri-tag：ok=green-deep 40%、warn=amber 45%、默认 line，
    // 宽度 1px（inset 0 0 0 1px）。
    final borderColor = switch (tone) {
      PixelNoticeTone.green => AppColors.greenDeep.withValues(alpha: .4),
      PixelNoticeTone.amber => AppColors.amber.withValues(alpha: .45),
      PixelNoticeTone.neutral => AppColors.line,
      PixelNoticeTone.red => AppColors.red.withValues(alpha: .45),
      PixelNoticeTone.blue => AppColors.blue.withValues(alpha: .45),
    };
    return ClipPath(
      clipper: const PixelCutClipper(cut: 3),
      // 原型 .ri-tag：pxc-xs 切角 + `inset 0 0 0 1px` 内缩描边带。
      // 用 inset 带绘制保证切角边缘描边完整（Border.all 居中描边
      // 在切角处会被裁剪缺失）。
      child: CustomPaint(
        foregroundPainter: _InsetRectBorderPainter(color: borderColor, width: 1),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.$2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 12, color: colors.$1),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: colors.$1,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 像素二级切换（CSS .seg / .seg-btn）。
///
/// 容器 card 底 + inset 1.5px 描边（--px-line）+ 4px 内边距；
/// 选中项 green 底 + pxc-xs 切角 + #FDFDFB 白字。
class PixelSeg extends StatelessWidget {
  const PixelSeg({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: const _InsetRectBorderPainter(
        color: AppColors.line2,
        width: 1.5,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: <Widget>[
              for (var i = 0; i < tabs.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 4),
                Expanded(child: _buildButton(context, i)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, int i) {
    final active = i == index;
    return Material(
      color: active ? AppColors.green : Colors.transparent,
      shape: active
          ? const PixelCutOutlinedBorder(cut: PixelCut.xs, side: BorderSide.none)
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(0)),
            ),
      child: InkWell(
        onTap: () => onChanged(i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              tabs[i],
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFFFDFDFB) : AppColors.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 摘要卡（CSS .stat-card）：card 底 + inset 1.5px 描边 + 等宽数字。
class PixelStatCard extends StatelessWidget {
  const PixelStatCard({
    super.key,
    required this.value,
    required this.label,
    this.color = AppColors.greenInk,
    this.expand = true,
  });

  final String value;
  final String label;
  final Color color;

  /// 是否用 [Expanded] 占满父级剩余宽度（默认 true，供 Row 内使用）。
  /// 单独置于 Column/ListView（纵向高度无界）时必须传 false，
  /// 否则会触发 RenderFlex 高度无界异常。
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final card = CustomPaint(
      foregroundPainter: const _InsetRectBorderPainter(
        color: AppColors.line2,
        width: 1.5,
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: AppColors.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: AppColors.ink3),
              ),
            ],
          ),
        ),
      ),
    );
    return expand ? Expanded(child: card) : card;
  }
}

/// 状态标签（CSS .conf / .conf-ok|low|exp|gray|unknown）：
/// pxc-xs 切角 + 10px 粗体 + 各状态前景/背景色。
enum PixelConfTone { ok, low, exp, gray, unknown }

class PixelConfTag extends StatelessWidget {
  const PixelConfTag(this.label, {super.key, this.tone = PixelConfTone.ok});

  final String label;
  final PixelConfTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      PixelConfTone.ok => (AppColors.greenDeep, AppColors.greenSoft),
      PixelConfTone.low => (const Color(0xFF826415), AppColors.amberSoft),
      PixelConfTone.exp => (const Color(0xFF7C3A2E), AppColors.redSoft),
      PixelConfTone.gray => (AppColors.ink2, AppColors.card2),
      PixelConfTone.unknown => (const Color(0xFF3D4B5C), AppColors.blueSoft),
    };
    // 内描边颜色：跟随标签前景色的半透明版本。
    final borderColor = fg.withValues(alpha: .45);
    return ClipPath(
      clipper: const PixelCutClipper(cut: PixelCut.xs),
      // 表面之下再带一层 1px inset 内描边（位于最外层表面边缘内）。
      child: CustomPaint(
        foregroundPainter: _InsetRectBorderPainter(
          color: borderColor,
          width: 1,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: bg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图标按钮（CSS .icon-btn）：pxc-xs 切角 + card 底 + inset 1.5px 描边。
class PixelIconBtn extends StatelessWidget {
  const PixelIconBtn({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 32,
    this.iconSize = 16,
    this.iconColor = AppColors.ink,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      child: ClipPath(
        clipper: const PixelCutClipper(cut: PixelCut.xs),
        child: CustomPaint(
          foregroundPainter: const _InsetRectBorderPainter(
            color: AppColors.line2,
            width: 1.5,
          ),
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class PixelNotice extends StatelessWidget {
  const PixelNotice({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = PixelNoticeTone.neutral,
    this.trailing,
    this.onTap,
  });
  final String title;
  final String? message;
  final IconData icon;
  final PixelNoticeTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _tone(tone);
    // 原型 .notice：pxc-sm 切角 + 左侧 4px 色条（inset 4px 0 0），无全描边。
    return PixelSurface(
      cut: 4,
      elevation: 0,
      color: colors.$2,
      borderColor: Colors.transparent,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(width: 4, child: ColoredBox(color: colors.$1)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 18, color: colors.$1),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (message != null)
                            Text(
                              message!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.ink2,
                                height: 1.45,
                              ),
                            ),
                        ],
                      ),
                    ),
                    trailing ?? const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PixelLoader extends StatefulWidget {
  const PixelLoader({super.key, this.size = 8, this.color = AppColors.green});
  final double size;
  final Color color;

  @override
  State<PixelLoader> createState() => _PixelLoaderState();
}

class _PixelLoaderState extends State<PixelLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final step = (_controller.value * 4).floor();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(4, (index) {
          final up = step == index;
          return Padding(
            padding: EdgeInsets.only(
              right: index == 3 ? 0 : widget.size * .6,
              bottom: up ? widget.size : 0,
            ),
            child: SizedBox.square(
              dimension: widget.size,
              child: ColoredBox(
                color: index.isOdd ? AppColors.greenDeep : widget.color,
              ),
            ),
          );
        }),
      );
    },
  );
}

class PixelPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PixelPageAppBar({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions,
    this.onBack,
  });

  final String title;
  final String? eyebrow;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  /// 原型 .navbar .nb-btn：32×32 切角按钮（pxc-xs）+ card 底 +
  /// inset 1.5px 描边（--px-line）+ 左箭头。
  Widget _buildBackButton(BuildContext context) {
    final canPop = Navigator.of(context).canPop() || onBack != null;
    if (!canPop) return const SizedBox.shrink();
    return Center(
      child: Tooltip(
        message: '返回',
        child: InkWell(
          onTap: onBack ?? () => Navigator.maybePop(context),
          child: ClipPath(
            clipper: const PixelCutClipper(cut: PixelCut.xs),
            child: CustomPaint(
              foregroundPainter: const _InsetRectBorderPainter(
                color: AppColors.line2,
                width: 1.5,
              ),
              child: const SizedBox.square(
                dimension: 32,
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      // 原型 .navbar：card 94% 半透明 + 底部虚线分隔。
      backgroundColor: AppColors.card.withValues(alpha: .94),
      leading: _buildBackButton(context),
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (eyebrow != null) PxLabel(eyebrow!),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
      actions: actions,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(2),
        child: PixelDashedDivider(thickness: 2, color: AppColors.line2),
      ),
    );
  }
}

class PixelRowTile extends StatelessWidget {
  const PixelRowTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor = AppColors.greenDeep,
    this.iconBackground = AppColors.greenSofter,
    this.trailing,
    this.onTap,
    this.tone = PixelNoticeTone.neutral,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color iconColor;
  final Color iconBackground;
  final Widget? trailing;
  final VoidCallback? onTap;
  final PixelNoticeTone tone;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = _tone(tone);
    final tileColor = tone == PixelNoticeTone.neutral
        ? AppColors.card
        : colors.$2;
    // CSS v4 .row-item：平直矩形（无缺角）+ 硬边软阴影。
    // 外框按项目负责人要求采用像素风立体描边：右/下 #000、左/上 #545454。
    final content = Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            // CSS .ri-ic：40×40 浅绿图标块 + pxc-sm 缺角。
            ClipPath(
              clipper: const PixelCutClipper(cut: PixelCut.sm),
              child: SizedBox.square(
                dimension: 40,
                child: ColoredBox(
                  color: iconBackground,
                  child: Icon(icon, size: 18, color: iconColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.ink3,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing ??
              (onTap == null
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.ink3,
                    )),
        ],
      ),
    );
    return CustomPaint(
      // 像素风立体描边：右/下 #000（暗）、左/上 #545454（亮），
      // 宽度 1.5px；内缩绘制与 CSS 视觉一致（无 miter 溢出）。
      foregroundPainter: _BevelBorderPainter(width: 1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tileColor,
          // --px-shadow-soft: drop-shadow(2px 3px 0 rgba(54,64,58,.07))。
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x1236403A),
              offset: Offset(2, 3),
            ),
          ],
        ),
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: content),
              ),
      ),
    );
  }
}

/// 平直矩形的 inset 描边带绘制（外矩形 − 内缩 width 的矩形）。
class _InsetRectBorderPainter extends CustomPainter {
  const _InsetRectBorderPainter({required this.color, required this.width});

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
  bool shouldRepaint(_InsetRectBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.width != width;
}

/// 像素风立体描边（chisel）：左/上亮边 #545454，右/下暗边 #000。
///
/// 项目负责人指定整行条目外框使用该立体边框（右/下 #000、左/上 #545454）。
class _BevelBorderPainter extends CustomPainter {
  const _BevelBorderPainter({required this.width});

  final double width;

  /// 亮边（左上）。
  static const Color _light = Color(0xFF545454);

  /// 暗边（右下）。
  static const Color _dark = Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    final w = width;
    // 亮边：上 + 左（先画）。
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, w),
      Paint()..color = _light,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, size.height),
      Paint()..color = _light,
    );
    // 暗边：右 + 下（后画覆盖角部，左上角保留亮色）。
    canvas.drawRect(
      Rect.fromLTWH(size.width - w, 0, w, size.height),
      Paint()..color = _dark,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - w, size.width, w),
      Paint()..color = _dark,
    );
  }

  @override
  bool shouldRepaint(_BevelBorderPainter oldDelegate) =>
      oldDelegate.width != width;
}

class PixelProgressBar extends StatefulWidget {
  const PixelProgressBar({
    super.key,
    required this.value,
    this.label,
    this.color = AppColors.green,
    this.indeterminate = false,
  });

  final double value;
  final String? label;
  final Color color;

  /// 不确定进度：总数为 0 或阶段无百分比时显示来回滑动的动画条，
  /// 避免「进度停在 0%」让用户误以为卡住（如预检分析、回滚备份收尾）。
  final bool indeterminate;

  @override
  State<PixelProgressBar> createState() => _PixelProgressBarState();
}

class _PixelProgressBarState extends State<PixelProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final indeterminate = widget.indeterminate;
    final safeValue = widget.value.clamp(0, 1).toDouble();
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        ClipPath(
          clipper: const PixelCutClipper(cut: 3),
          child: SizedBox(
            height: 22,
            child: ColoredBox(
              color: AppColors.paper2,
              child: indeterminate
                  ? AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        // 高亮块从左侧滑出到右侧（越界部分被裁剪），
                        // 往复循环，表达「进行中但无明确百分比」。
                        final alignX = (_controller.value * 2 - 1) * 1.5;
                        return Align(
                          alignment: Alignment(alignX, 0),
                          child: FractionallySizedBox(
                            // heightFactor 必须为 1：填充子项是无固有尺寸的
                            // ColoredBox，缺省高度取子项高度为 0，会导致填充条
                            // 不可见而只剩文字。
                            widthFactor: 0.33,
                            heightFactor: 1.0,
                            child: ColoredBox(color: widget.color),
                          ),
                        );
                      },
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: safeValue,
                        heightFactor: 1.0,
                        child: ColoredBox(color: widget.color),
                      ),
                    ),
            ),
          ),
        ),
        Text(
          widget.label ??
              (indeterminate ? '处理中…' : '${(safeValue * 100).round()}%'),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: safeValue > .52 ? Colors.white : AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class PixelBottomActionBar extends StatelessWidget {
  const PixelBottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line2, width: 1.2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x1F36403A),
            offset: Offset(0, -3),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: child,
      ),
    );
  }
}

class PixelFieldLabel extends StatelessWidget {
  const PixelFieldLabel(this.label, {super.key, this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: AppColors.ink2,
            letterSpacing: .4,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w900),
          ),
      ],
    ),
  );
}

(Color, Color) _tone(PixelNoticeTone tone) => switch (tone) {
  // 绿色系背景用 green-soft（原型 .notice.green / .ri-tag.ok 均为
  // var(--green-soft) #DDE7DC，不是更浅的 green-softer）。
  PixelNoticeTone.green => (AppColors.greenDeep, AppColors.greenSoft),
  PixelNoticeTone.amber => (AppColors.amber, AppColors.amberSoft),
  PixelNoticeTone.red => (AppColors.red, AppColors.redSoft),
  PixelNoticeTone.blue => (AppColors.blue, AppColors.blueSoft),
  PixelNoticeTone.neutral => (AppColors.ink2, AppColors.card2),
};
