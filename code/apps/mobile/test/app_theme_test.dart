import 'package:ai_recipe/app/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme keeps the HTML prototype color tokens', () {
    final theme = buildAiRecipeTheme();

    // Scaffold 透明，纸张背景 #F3F1E9 + 圆点由 MaterialApp.builder 提供。
    expect(theme.scaffoldBackgroundColor, Colors.transparent);
    expect(theme.colorScheme.primary, AppColors.greenDeep);
    expect(theme.colorScheme.surface, AppColors.card);
    expect(theme.colorScheme.error, AppColors.red);
    expect(theme.useMaterial3, isTrue);
  });
}
