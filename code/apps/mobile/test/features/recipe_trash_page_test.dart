import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/features/trash/recipe_trash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_backend_harness.dart';

void main() {
  // TestBackendHarness 构造组合根时会通过全局 databaseFactory 创建
  // AppDatabase，并构造 DeviceMultimodalLlmConfigRepository（依赖
  // SharedPreferencesAsync），因此先初始化 sqlite FFI 与内存偏好存储。
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<TestBackendHarness> createHarness(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    // 系统"减少动态"（PixelFloat 等装饰动画静止直达终态），
    // 避免空状态浮动动画让 pumpAndSettle 永不结束。
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = TestBackendHarness();
    addTearDown(() async {
      await harness.close();
      await tester.binding.setSurfaceSize(null);
    });
    return harness;
  }

  Widget wrap(TestBackendHarness harness, VoidCallback onDataChanged) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: RecipeTrashPage(
        backend: harness.root.backend,
        onDataChanged: onDataChanged,
      ),
    );
  }

  Future<String> seedDeleted(TestBackendHarness harness, String title) async {
    final recipe = await harness.root.backend.createRecipe(
      RecipeDraftInput(title: title),
    );
    await harness.root.backend.softDeleteRecipe(recipe.id);
    return recipe.id;
  }

  testWidgets('shows empty state', (tester) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness, () {}));
    await tester.pumpAndSettle();

    expect(find.text('回收站是空的'), findsOneWidget);
    expect(find.text('从菜谱详情删除的菜谱会暂存在这里。'), findsOneWidget);
  });

  testWidgets('restores a deleted recipe', (tester) async {
    final harness = await createHarness(tester);
    final recipeId = await seedDeleted(harness, '待恢复菜谱');
    var changed = 0;

    await tester.pumpWidget(wrap(harness, () => changed += 1));
    await tester.pumpAndSettle();

    expect(find.text('待恢复菜谱'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('restoreRecipe-$recipeId')));
    await tester.pumpAndSettle();

    expect((await harness.root.backend.getRecipe(recipeId)).deletedAt, isNull);
    expect(changed, 1);
    expect(find.text('回收站是空的'), findsOneWidget);
  });

  testWidgets('permanent deletion and empty trash require confirmation', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final firstId = await seedDeleted(harness, '永久删除测试');
    await seedDeleted(harness, '批量清空测试');
    var changed = 0;

    await tester.pumpWidget(wrap(harness, () => changed += 1));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('permanentlyDeleteRecipe-$firstId')));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsOneWidget);
    expect(find.text('“永久删除测试”删除后无法恢复。'), findsOneWidget);
    expect(
      await harness.root.backend.getRecipe(firstId, includeDeleted: true),
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('confirmPermanentDeleteRecipe')));
    await tester.pumpAndSettle();
    expect(harness.recipeRepository.recipes.containsKey(firstId), isFalse);
    expect(changed, 1);

    await tester.tap(find.byKey(const Key('emptyRecipeTrashButton')));
    await tester.pumpAndSettle();
    expect(find.text('清空回收站？'), findsOneWidget);
    expect(find.text('将永久删除 1 道菜谱，此操作无法撤销。'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmEmptyRecipeTrash')));
    await tester.pumpAndSettle();
    expect(harness.recipeRepository.recipes, isEmpty);
    expect(changed, 2);
    expect(find.text('回收站是空的'), findsOneWidget);
  });
}
