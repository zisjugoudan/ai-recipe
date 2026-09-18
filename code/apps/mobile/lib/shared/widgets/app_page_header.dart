import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import 'pixel_ui.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.eyebrow,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (eyebrow != null) ...<Widget>[
                PxLabel(eyebrow!),
                const SizedBox(height: 4),
              ],
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.ink2),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

class AppSectionTitle extends StatelessWidget {
  const AppSectionTitle({
    super.key,
    required this.title,
    this.caption,
    this.action,
  });

  final String title;
  final String? caption;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(width: 7, height: 7, color: AppColors.greenDeep),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .2,
                ),
              ),
              if (caption != null)
                Text(caption!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        action ?? const SizedBox.shrink(),
      ],
    );
  }
}
