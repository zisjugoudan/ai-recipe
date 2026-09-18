import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/recipe/recipe_edit_page.dart';
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

  Widget wrap(TestBackendHarness harness, {Recipe? recipe}) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: RecipeEditPage(
        backend: harness.root.backend,
        initialRecipe: recipe,
      ),
    );
  }

  Widget wrapWithLauncher(TestBackendHarness harness) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('openRecipeEditorButton'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => RecipeEditPage(backend: harness.root.backend),
                ),
              ),
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openEditor(
    WidgetTester tester,
    TestBackendHarness harness,
  ) async {
    await tester.pumpWidget(wrapWithLauncher(harness));
    await tester.tap(find.byKey(const Key('openRecipeEditorButton')));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeEditPage), findsOneWidget);
  }

  testWidgets(
    'new recipe validates title and saves dynamic ingredients/steps',
    (tester) async {
      final harness = await createHarness(tester);
      await tester.pumpWidget(wrap(harness));
      await tester.pumpAndSettle();

      expect(find.text('新建菜谱'), findsOneWidget);
      expect(find.text('基础信息'), findsOneWidget);
      expect(find.text('分类与状态'), findsOneWidget);
      expect(find.text('所需食材'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saveRecipeButton')));
      await tester.pump();
      expect(find.text('请输入菜名'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('recipeTitleField')), '青椒炒肉');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('ingredientsSectionTitle')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipeIngredientNameField-0')),
        '青椒',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipeIngredientQuantityField-0')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipeIngredientUnitField-0')),
        '个',
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('stepsSectionTitle')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipeStepDescriptionField-0')),
        '大火快速翻炒',
      );
      await tester.tap(find.text('添加').last);
      await tester.pump();
      expect(find.text('步骤 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('saveRecipeButton')));
      await tester.pumpAndSettle();

      final recipes = await harness.root.backend.listRecipes();
      expect(recipes, hasLength(1));
      expect(recipes.single.title, '青椒炒肉');
      expect(recipes.single.ingredients.single.name, '青椒');
      expect(recipes.single.ingredients.single.quantity, '2');
      expect(recipes.single.steps.single.description, '大火快速翻炒');
    },
  );

  testWidgets('editing fills existing values and preserves child ids', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final category = await harness.root.backend.createCategory(
      const RecipeCategoryInput(name: '家常菜', sortOrder: 0),
    );
    final original = await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '番茄炒蛋',
        description: '酸甜下饭',
        servings: 2,
        prepTimeMinutes: 5,
        cookTimeMinutes: 8,
        totalTimeMinutes: 13,
        difficulty: RecipeDifficulty.easy,
        favorite: true,
        status: RecipeStatus.draft,
        categoryIds: <String>[category.id],
        tags: const <String>['快手', '家常'],
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(
            id: 'ingredient-existing',
            name: '番茄',
            quantity: '2',
            unit: '个',
          ),
        ],
        steps: const <RecipeStepInput>[
          RecipeStepInput(
            id: 'step-existing',
            description: '先炒鸡蛋',
            durationSeconds: 90,
          ),
        ],
      ),
    );

    await tester.pumpWidget(wrap(harness, recipe: original));
    await tester.pumpAndSettle();

    expect(find.text('编辑菜谱'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('家常菜'), findsOneWidget);
    expect(find.text('快手，家常'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recipeTitleField')),
      '番茄炒蛋升级版',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveRecipeButton')));
    await tester.pumpAndSettle();

    final updated = await harness.root.backend.getRecipe(original.id);
    expect(updated.title, '番茄炒蛋升级版');
    expect(updated.favorite, isTrue);
    expect(updated.status, RecipeStatus.draft);
    expect(updated.categoryIds, <String>[category.id]);
    expect(updated.ingredients.single.id, original.ingredients.single.id);
    expect(updated.steps.single.id, original.steps.single.id);
    expect(updated.steps.single.durationSeconds, 90);
  });

  testWidgets('unsaved app bar back keeps input or discards and exits', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await openEditor(tester, harness);

    await tester.enterText(find.byKey(const Key('recipeTitleField')), '保留的菜名');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('未保存的修改'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keepEditingRecipeButton')));
    await tester.pumpAndSettle();

    expect(find.text('未保存的修改'), findsNothing);
    expect(find.text('保留的菜名'), findsOneWidget);
    expect(find.byType(RecipeEditPage), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discardRecipeChangesButton')));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeEditPage), findsNothing);
    expect(find.byKey(const Key('openRecipeEditorButton')), findsOneWidget);
  });

  testWidgets('bottom cancel uses the same unsaved changes confirmation', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await openEditor(tester, harness);

    await tester.enterText(
      find.byKey(const Key('recipeTitleField')),
      '准备取消的菜名',
    );
    await tester.tap(find.byKey(const Key('cancelRecipeEditButton')));
    await tester.pumpAndSettle();

    expect(find.text('未保存的修改'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discardRecipeChangesButton')));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeEditPage), findsNothing);
    expect(find.byKey(const Key('openRecipeEditorButton')), findsOneWidget);
  });

  testWidgets('BUG-001 category creation from editor is stable and selects it', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    // 点击分类区末尾的“新建”chip 打开共享分类创建对话框。
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createCategoryNameField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('createCategoryNameField')),
      '下饭菜',
    );
    await tester.tap(find.byKey(const Key('confirmCreateCategoryButton')));
    await tester.pumpAndSettle();

    // 关闭动画期间不再访问已释放控制器，且新分类被选中。
    expect(tester.takeException(), isNull);
    expect(find.text('下饭菜'), findsOneWidget);
    final categories = await harness.root.backend.listCategories();
    expect(categories, hasLength(1));
    expect(categories.single.name, '下饭菜');
  });

  testWidgets('save failure preserves input and dirty exit protection', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await openEditor(tester, harness);

    await tester.enterText(
      find.byKey(const Key('recipeTitleField')),
      '保存失败仍保留',
    );
    harness.recipeRepository.error = StateError('write failed');

    await tester.tap(find.byKey(const Key('saveRecipeButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('菜谱库暂时不可用，请稍后重试'), findsOneWidget);
    expect(find.text('保存失败仍保留'), findsOneWidget);
    expect(find.byType(RecipeEditPage), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('未保存的修改'), findsOneWidget);
  });

  testWidgets('cover image editor shows empty hint and multi-pick button', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    expect(find.text('封面图片'), findsOneWidget);
    expect(find.textContaining('还没有封面图'), findsOneWidget);
    expect(
      find.byKey(const Key('addRecipeCoverImagesButton')),
      findsOneWidget,
    );
  });

  testWidgets('cover image editor renders existing images with cover badge', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '多图菜谱',
        images: const <String>['/tmp/cover-1.jpg', '/tmp/cover-2.jpg'],
        ingredients: const <RecipeIngredientInput>[],
        steps: const <RecipeStepInput>[],
      ),
    );

    await tester.pumpWidget(wrap(harness, recipe: recipe));
    await tester.pumpAndSettle();

    // 首图标记“封面”，两张图都有删除入口。
    expect(find.text('封面'), findsOneWidget);
    expect(
      find.byKey(const Key('removeRecipeCoverImage-/tmp/cover-1.jpg')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('removeRecipeCoverImage-/tmp/cover-2.jpg')),
      findsOneWidget,
    );
  });

  testWidgets('groups ingredients by AI group name and renders drag lists', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '分组菜谱',
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(
            id: 'group-1',
            name: '鸡腿肉',
            groupName: '主料',
            quantity: '500',
            unit: 'g',
          ),
          RecipeIngredientInput(
            id: 'group-2',
            name: '盐',
            groupName: '调料',
            quantity: '1',
            unit: '勺',
          ),
          RecipeIngredientInput(
            id: 'group-3',
            name: '生抽',
            groupName: '调料',
            quantity: '2',
            unit: '勺',
          ),
        ],
        steps: const <RecipeStepInput>[
          RecipeStepInput(id: 'step-1', description: '切肉'),
          RecipeStepInput(id: 'step-2', description: '炒制'),
        ],
      ),
    );
    await tester.pumpWidget(wrap(harness, recipe: recipe));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('ingredientsSectionTitle')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // AI 分组（主料/调料）分段展示：主料一次、调料连续两项合并为一次标题。
    expect(find.text('主料'), findsOneWidget);
    expect(find.text('调料'), findsOneWidget);
    // 食材与步骤列表均可拖拽排序。
    expect(
      find.byKey(const Key('recipeIngredientsReorderList')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recipeStepsReorderList')), findsOneWidget);
  });

  testWidgets('allows adding and editing ingredient group on editor', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    await tester.pumpWidget(wrap(harness));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('ingredientsSectionTitle')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 分组输入框常显，可输入自定义分组。
    final groupField = find.byKey(
      const ValueKey('recipeIngredientGroupField-0'),
    );
    expect(groupField, findsOneWidget);
    await tester.enterText(groupField, '腌料');
    await tester.pump();

    // 点常用分组 chip 快捷填入。
    await tester.tap(find.text('调料').last);
    await tester.pump();
    final field = tester.widget<TextFormField>(groupField);
    expect(field.controller!.text, '调料');

    // 保存后分组写入菜谱。
    await tester.enterText(find.byKey(const Key('recipeTitleField')), '分组菜');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('saveRecipeButton')));
    await tester.pumpAndSettle();
    final recipes = await harness.root.backend.listRecipes();
    expect(recipes.single.ingredients.single.groupName, '调料');
  });
}
