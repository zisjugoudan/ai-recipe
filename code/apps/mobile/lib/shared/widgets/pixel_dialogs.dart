import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'pixel_ui.dart';

/// 像素风通用确认弹窗：取消 + 确认按钮。
///
/// 容器样式与全局像素弹窗基准（`_PasteTextDialog`）一致：透明 Dialog +
/// [PixelSurface]（大缺角切角 + 墨色描边 + 硬投影），标题/正文/按钮均沿用
/// 像素主题。危险操作可通过 [confirmColor]（如 [AppColors.red]）表达。
class PixelConfirmDialog extends StatelessWidget {
  const PixelConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.confirmKey,
    this.cancelKey,
    this.confirmColor,
  });

  final String title;

  /// 弹窗正文，支持换行。
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final Key? confirmKey;
  final Key? cancelKey;

  /// 确认按钮背景色；为空时使用主题默认（绿色系）。
  final Color? confirmColor;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: PixelSurface(
        cut: PixelCut.lg,
        elevation: 2,
        color: AppColors.card,
        borderColor: AppColors.ink,
        borderWidth: 1.5,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  key: cancelKey,
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(cancelLabel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: confirmKey,
                  style: confirmColor == null
                      ? null
                      : FilledButton.styleFrom(backgroundColor: confirmColor),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出像素风确认弹窗，返回用户是否确认（返回键/遮罩关闭时返回 null）。
Future<bool?> showPixelConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  Key? confirmKey,
  Key? cancelKey,
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => PixelConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmKey: confirmKey,
      cancelKey: cancelKey,
      confirmColor: confirmColor,
    ),
  );
}

/// 像素风信息弹窗：仅一个确认按钮，用于不可操作的提示。
class PixelInfoDialog extends StatelessWidget {
  const PixelInfoDialog({
    super.key,
    required this.title,
    required this.message,
    this.okLabel = '知道了',
    this.okKey,
  });

  final String title;
  final String message;
  final String okLabel;
  final Key? okKey;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: PixelSurface(
        cut: PixelCut.lg,
        elevation: 2,
        color: AppColors.card,
        borderColor: AppColors.ink,
        borderWidth: 1.5,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.ink2,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                FilledButton(
                  key: okKey,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(okLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出像素风信息弹窗。
Future<void> showPixelInfo({
  required BuildContext context,
  Key? key,
  required String title,
  required String message,
  String okLabel = '知道了',
  Key? okKey,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => PixelInfoDialog(
      key: key,
      title: title,
      message: message,
      okLabel: okLabel,
      okKey: okKey,
    ),
  );
}
