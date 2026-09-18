import 'package:flutter/material.dart';

import '../shared/widgets/pixel_ui.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF3F1E9);
  static const paper2 = Color(0xFFEAE7DC);
  static const card = Color(0xFFFCFBF6);
  static const card2 = Color(0xFFF5F2E9);
  static const ink = Color(0xFF36403A);
  static const ink2 = Color(0xFF5F6A63);
  static const ink3 = Color(0xFF8F978F);
  static const green = Color(0xFF5F8F6E);
  static const greenDeep = Color(0xFF476B52);
  static const greenInk = Color(0xFF33513C);
  static const greenSoft = Color(0xFFDDE7DC);
  static const greenSofter = Color(0xFFEDF2EA);
  static const amber = Color(0xFFB08D4F);
  static const amberSoft = Color(0xFFF3EBD6);
  static const red = Color(0xFFAF6859);
  static const redSoft = Color(0xFFF2E2DD);
  static const blue = Color(0xFF6E8697);
  static const blueSoft = Color(0xFFE3E9ED);
  static const line = Color(0xFFDDD8C9);
  static const line2 = Color(0xFFCFC9B6);
  static const cooking = Color(0xFF243B2D);
  static const cookingPanel = Color(0xFF31503B);
}

ThemeData buildAiRecipeTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.green,
        brightness: Brightness.light,
        surface: AppColors.card,
      ).copyWith(
        primary: AppColors.greenDeep,
        onPrimary: Colors.white,
        secondary: AppColors.amber,
        error: AppColors.red,
        surface: AppColors.card,
        onSurface: AppColors.ink,
        outline: AppColors.line2,
      );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 背景纹理由 MaterialApp.builder 的 _PixelPaperBackground 提供，
    // Scaffold 透明以露出纸张圆点纹理（prototype.css body）。
    scaffoldBackgroundColor: Colors.transparent,
    fontFamilyFallback: const <String>[
      'PingFang SC',
      'Microsoft YaHei',
      'Noto Sans CJK SC',
    ],
    splashFactory: InkSparkle.splashFactory,
  );

  final text = base.textTheme
      .copyWith(
        headlineLarge: const TextStyle(
          fontSize: 28,
          height: 1.2,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
        headlineMedium: const TextStyle(
          fontSize: 24,
          height: 1.25,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
        ),
        headlineSmall: const TextStyle(
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w900,
          letterSpacing: .5,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          height: 1.35,
          fontWeight: FontWeight.w900,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          height: 1.4,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: const TextStyle(fontSize: 15, height: 1.65),
        bodyMedium: const TextStyle(fontSize: 14, height: 1.6),
        bodySmall: const TextStyle(
          fontSize: 12,
          height: 1.55,
          color: AppColors.ink2,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        labelMedium: const TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        labelSmall: const TextStyle(
          fontSize: 10.5,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: AppColors.ink3,
        ),
      )
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  // 1:1 复刻 CSS 按钮：阶梯缺角 + 墨色 inset 描边（.btn 项目负责人要求
  // 比原型的 2px 更细，统一为 1.5px）+ 硬边投影（--px-shadow-hard）。
  final pixelButtonShape = const PixelCutOutlinedBorder(
    cut: PixelCut.sm,
    side: BorderSide(color: AppColors.ink, width: 1.5),
  );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.line2, width: 1.2),
        borderRadius: BorderRadius.all(Radius.circular(0)),
      ),
    ),
    // 底部弹层统一像素风：纸张卡片底色 + 像素切角描边，无阴影、无拖拽手柄。
    // 让各处 showModalBottomSheet（导入、冰箱、菜谱分享等）外观一致。
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      showDragHandle: false,
      shape: PixelCutOutlinedBorder(
        cut: PixelCut.sm,
        side: BorderSide(color: AppColors.line2, width: 1.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      hintStyle: const TextStyle(color: AppColors.ink3),
      labelStyle: const TextStyle(
        color: AppColors.ink2,
        fontWeight: FontWeight.w700,
      ),
      // 输入框像素缺角 + inset 描边（CSS .input box-shadow: --px-line 1.5px）。
      border: const PixelCutInputBorder(
        cut: PixelCut.sm,
        borderSide: BorderSide(color: AppColors.line2, width: 1.5),
      ),
      enabledBorder: const PixelCutInputBorder(
        cut: PixelCut.sm,
        borderSide: BorderSide(color: AppColors.line2, width: 1.5),
      ),
      focusedBorder: const PixelCutInputBorder(
        cut: PixelCut.sm,
        borderSide: BorderSide(color: AppColors.greenDeep, width: 2),
      ),
      errorBorder: const PixelCutInputBorder(
        cut: PixelCut.sm,
        borderSide: BorderSide(color: AppColors.red, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        backgroundColor: AppColors.green,
        foregroundColor: const Color(0xFFFDFDFB),
        disabledBackgroundColor: AppColors.line,
        shape: pixelButtonShape,
        elevation: 3,
        shadowColor: const Color(0x3336403A),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: .3,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 46),
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.card,
        shape: pixelButtonShape,
        elevation: 2,
        shadowColor: const Color(0x3336403A),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.greenDeep,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.green,
      foregroundColor: Colors.white,
      elevation: 4,
      // .fab-add：墨色 inset 描边（项目负责人要求 1.5px，比原型 2px 细）。
      shape: PixelCutOutlinedBorder(
        cut: PixelCut.sm,
        side: BorderSide(color: AppColors.ink, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: AppColors.card,
      indicatorColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: states.contains(WidgetState.selected)
              ? AppColors.greenDeep
              : AppColors.ink2,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? AppColors.greenDeep
              : AppColors.ink2,
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.green,
      side: const BorderSide(color: AppColors.line2, width: 1.5),
      // 与 CSS chip 一致：平直矩形（无圆角）。选中态描边 green-deep
      // 需在各 Chip 使用处通过 shape: WidgetStateProperty 提供，
      // ChipThemeData.shape 只接受固定 OutlinedBorder。
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(0)),
      ),
      // BUG-001：分类 Chip 文字前景色显式指定，不依赖 Material 自动推导，
      // 保证纸张米白底/浅绿底上的 WCAG AA 对比度。
      labelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.greenInk,
      ),
      checkmarkColor: AppColors.greenInk,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    dividerColor: AppColors.line,
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.green,
      linearTrackColor: AppColors.paper2,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(0)),
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
