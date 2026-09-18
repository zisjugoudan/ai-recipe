import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/inventory/inventory_batch.dart';
import 'package:ai_recipe/features/fridge/fridge_page.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/fridge/fridge_batch_edit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_backend_harness.dart';

void main() {
  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
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
        body: FridgePage(
          backend: harness.root.backend,
          onDataChanged: () {},
          onOpenRecipe: (_) async {},
        ),
      ),
    );
  }

  testWidgets('empty fridge shows empty state', (tester) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    expect(find.text('冰箱还是空的'), findsOneWidget);
    expect(find.byKey(const Key('addFirstInventoryBatchButton')), findsOneWidget);
  });

  testWidgets('shows aggregated batch in zone card', (tester) async {
    final harness = await createHarness(tester);
    await harness.root.backend.createInventoryBatch(
      const InventoryBatchInput(
        ingredientName: '番茄',
        quantity: 2,
        unit: '个',
        zone: InventoryZone.chilled,
      ),
    );
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    expect(find.text('冷藏区'), findsWidgets);
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('可用批次'), findsOneWidget);
  });

  testWidgets('batch editor saves a new batch and refreshes fridge',
      (tester) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addFirstInventoryBatchButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('batchNameField')), '鸡蛋');
    await tester.enterText(
      find.byKey(const Key('batchQuantityField')),
      '6',
    );
    await tester.tap(find.byKey(const Key('saveInventoryBatchButton')));
    await tester.pumpAndSettle();
    expect(find.text('鸡蛋'), findsOneWidget);
    final batches = await harness.root.backend.listInventoryBatches();
    expect(batches.single.ingredientName, '鸡蛋');
  });

  testWidgets('batch editor deletes batch in edit mode', (tester) async {
    final harness = await createHarness(tester);

    // 新增态不显示删除按钮。
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAiRecipeTheme(),
        home: FridgeBatchEditPage(backend: harness.root.backend),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('deleteInventoryBatchButton')),
      findsNothing,
    );

    // 已有批次进入编辑态：显示删除按钮。
    await harness.root.backend.createInventoryBatch(
      const InventoryBatchInput(
        ingredientName: '番茄',
        quantity: 2,
        unit: '个',
        zone: InventoryZone.chilled,
      ),
    );
    final batch = (await harness.root.backend.listInventoryBatches()).single;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAiRecipeTheme(),
        home: FridgeBatchEditPage(
          backend: harness.root.backend,
          batch: batch,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('deleteInventoryBatchButton')),
      findsOneWidget,
    );

    // 取消确认：批次保留。
    await tester.tap(find.byKey(const Key('deleteInventoryBatchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await harness.root.backend.listInventoryBatches(), hasLength(1));

    // 确认删除：批次被移除，页面返回。
    await tester.tap(find.byKey(const Key('deleteInventoryBatchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(await harness.root.backend.listInventoryBatches(), isEmpty);
  });

  testWidgets('recommendation matches published recipe by selected ingredients',
      (tester) async {
    final harness = await createHarness(tester);
    await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '番茄炒蛋',
        status: RecipeStatus.published,
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(name: '番茄', quantity: '2 个'),
          RecipeIngredientInput(name: '鸡蛋', quantity: '3 枚'),
        ],
      ),
    );
    await harness.root.backend.createInventoryBatch(
      const InventoryBatchInput(
        ingredientName: '番茄',
        quantity: 2,
        unit: '个',
        zone: InventoryZone.chilled,
      ),
    );
    await harness.root.backend.createInventoryBatch(
      const InventoryBatchInput(
        ingredientName: '鸡蛋',
        quantity: 6,
        unit: '枚',
        zone: InventoryZone.chilled,
      ),
    );
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();
    // 切到推荐 tab，选择番茄，运行推荐。
    await tester.tap(find.text('推荐'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('runRecommendationButton')));
    await tester.pumpAndSettle();
    expect(find.text('番茄炒蛋'), findsWidgets);
    expect(find.textContaining('已选命中'), findsWidgets);
  });
}
