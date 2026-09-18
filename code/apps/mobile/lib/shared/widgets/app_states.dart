import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'pixel_ui.dart';

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = '正在整理本地数据…'});
  final String label;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight.isFinite && constraints.maxHeight < 220;
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 32,
              vertical: compact ? 8 : 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const PixelLoader(),
                SizedBox(height: compact ? 10 : 16),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink2,
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

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 1:1 复刻 prototype.css .state-box：92px 大图标块 + 缺角 +
          // 硬边阴影 + 阶梯浮动动画。
          PixelFloat(
            amplitude: 5,
            child: PixelSurface(
              cut: PixelCut.lg,
              elevation: 4,
              borderColor: AppColors.line2,
              child: SizedBox.square(
                dimension: 92,
                child: Icon(icon, color: AppColors.green, size: 42),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.ink2, fontSize: 12.5),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = '\u91cd\u65b0\u52a0\u8f7d',
  });
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => PixelNotice(
    title: '加载失败',
    message: message,
    icon: Icons.error_outline_rounded,
    tone: PixelNoticeTone.red,
    trailing: TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: Text(retryLabel),
      style: TextButton.styleFrom(foregroundColor: AppColors.red),
    ),
  );
}
