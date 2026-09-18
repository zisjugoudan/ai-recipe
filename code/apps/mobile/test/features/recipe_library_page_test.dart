import 'dart:math' as math;

import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/library/recipe_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Widget wrap(TestBackendHarness harness) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: Scaffold(
        body: RecipeLibraryPage(
          backend: harness.root.backend,
          onAddRecipe: () {},
          onOpenRecipeId: (_) {},
          onDataChanged: () {},
        ),
      ),
    );
  }

  Future<void> openCreateDialog(WidgetTester tester) async {
    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createCategoryNameField')), findsOneWidget);
  }

  Future<void> submitCreate(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('confirmCreateCategoryButton')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'BUG-001 creates a category without exceptions and shows feedback',
    (tester) async {
      final harness = await createHarness(tester);
      await tester.pumpWidget(wrap(harness));
      await tester.pumpAndSettle();

      await openCreateDialog(tester);
      await tester.enterText(
        find.byKey(const Key('createCategoryNameField')),
        '快手晚餐',
      );
      await submitCreate(tester);

      // Dialog 关闭动画期间不再访问已释放的输入控制器。
      expect(tester.takeException(), isNull);
      // 新分类无需重启即可出现在筛选 Chip 中。
      expect(find.text('快手晚餐'), findsOneWidget);
      expect(find.text('分类已创建。'), findsOneWidget);
      final categories = await harness.root.backend.listCategories();
      expect(categories, hasLength(1));
      expect(categories.single.name, '快手晚餐');
    },
  );

  testWidgets('BUG-001 empty and whitespace names are rejected with stable error', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    await openCreateDialog(tester);
    await submitCreate(tester);
    expect(find.text('请输入分类名称。'), findsOneWidget);
    expect(find.byKey(const Key('confirmCreateCategoryButton')), findsOneWidget);
    expect(await harness.root.backend.listCategories(), isEmpty);

    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      '   ',
    );
    await submitCreate(tester);
    expect(find.text('请输入分类名称。'), findsOneWidget);
    expect(await harness.root.backend.listCategories(), isEmpty);
  });

  testWidgets('BUG-001 duplicate names are rejected without creating duplicates', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await harness.root.backend.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      '家常菜',
    );
    await submitCreate(tester);
    expect(find.text('已存在同名分类。'), findsOneWidget);

    // 大小写与首尾空白不敏感。
    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      ' 家常菜 ',
    );
    await submitCreate(tester);
    expect(find.text('已存在同名分类。'), findsOneWidget);
    expect(await harness.root.backend.listCategories(), hasLength(1));
  });

  testWidgets('BUG-001 over-length names are safely limited and do not crash', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      '很长的分类名称' * 5, // 35 个字符，TextField maxLength 会截断到 30
    );
    await submitCreate(tester);

    expect(tester.takeException(), isNull);
    final categories = await harness.root.backend.listCategories();
    expect(categories, hasLength(1));
    expect(categories.single.name.length, lessThanOrEqualTo(30));
  });

  testWidgets('BUG-001 rapid repeated submit only creates one category', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    await openCreateDialog(tester);
    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      '一菜一汤',
    );
    await tester.tap(find.byKey(const Key('confirmCreateCategoryButton')));
    await tester.pump();
    // 第一次点击后对话框已同步提交并开始退场；第二次点击必然命中退场中的
    // 对话框而被安全忽略（验证防重复提交与无害性），因此 warnIfMissed 关闭。
    await tester.tap(
      find.byKey(const Key('confirmCreateCategoryButton')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final categories = await harness.root.backend.listCategories();
    expect(categories, hasLength(1));
    expect(categories.single.name, '一菜一汤');
  });

  testWidgets('BUG-001 selected category filters recipes correctly', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final category = await harness.root.backend.createCategory(
      const RecipeCategoryInput(name: '快手', sortOrder: 0),
    );
    await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '快手面',
        status: RecipeStatus.published,
        categoryIds: <String>[category.id],
      ),
    );
    await harness.root.backend.createRecipe(
      RecipeDraftInput(title: '慢炖汤', status: RecipeStatus.published),
    );
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    expect(find.text('快手面'), findsOneWidget);
    expect(find.text('慢炖汤'), findsOneWidget);

    await tester.tap(find.text('快手'));
    await tester.pumpAndSettle();

    expect(find.text('快手面'), findsOneWidget);
    expect(find.text('慢炖汤'), findsNothing);
  });

  test('BUG-001 chip label colors are explicit for every state', () {
    final theme = buildAiRecipeTheme();
    final labelStyle = theme.chipTheme.labelStyle!;
    // 显式设置，不依赖 Material 自动推导。
    expect(labelStyle.color, AppColors.greenInk);
    // 主题 labelStyle 是静态 TextStyle，三态解析结果保持一致。
    for (final states in <Set<WidgetState>>{
      const <WidgetState>{},
      const <WidgetState>{WidgetState.selected},
      const <WidgetState>{WidgetState.disabled},
    }) {
      final resolved = WidgetStateProperty.resolveAs<Color?>(
        labelStyle.color,
        states,
      );
      expect(resolved, AppColors.greenInk);
    }
    // WCAG AA：正文与各 Chip 背景的对比度均不低于 4.5:1。
    // 候选背景：未选中（卡片底 card）、选中（浅绿底 greenSoft）、
    // 禁用（卡片底 card）；纸张米白 paper 作为页面底色一并校验。
    for (final background in <Color>{
      AppColors.paper,
      AppColors.card,
      AppColors.greenSoft,
    }) {
      final ratio = _contrastRatio(AppColors.greenInk, background);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'greenInk 与 $background 对比度 ${ratio.toStringAsFixed(2)}:1 应 ≥ 4.5:1');
    }
  });
}

/// 计算两个颜色之间的 WCAG 对比度（4.5:1 为 AA 标准下限）。
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 计算颜色的相对亮度（sRGB 线性化）。
/// 注意：Flutter 3.38 的 Color.r/g/b 返回 0.0-1.0 的 double，无需再除以 255。
double _relativeLuminance(Color c) {
  double channel(double s) {
    return s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}
