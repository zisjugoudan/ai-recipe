import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/application/recipe/recipe_library_commands.dart';
import 'package:ai_recipe/domain/cooking/cooking_session.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/features/recipe/recipe_detail_page.dart';
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

  Future<Recipe> seedRecipe(TestBackendHarness harness) async {
    final category = await harness.root.backend.createCategory(
      const RecipeCategoryInput(name: '下饭菜', sortOrder: 0),
    );
    return harness.root.backend.createRecipe(
      RecipeDraftInput(
        title: '宫保鸡丁',
        description: '香辣酸甜的家常版本',
        servings: 3,
        prepTimeMinutes: 12,
        cookTimeMinutes: 10,
        totalTimeMinutes: 22,
        difficulty: RecipeDifficulty.medium,
        categoryIds: <String>[category.id],
        tags: const <String>['川味', '快手'],
        notes: '花生最后放，保持酥脆。',
        ingredients: <RecipeIngredientInput>[
          RecipeIngredientInput(
            name: '鸡胸肉',
            quantity: '300',
            unit: '克',
            preparation: '切丁',
          ),
          RecipeIngredientInput(
            name: '花生米',
            quantity: '50',
            unit: '克',
            optional: true,
          ),
        ],
        steps: const <RecipeStepInput>[
          RecipeStepInput(
            description: '鸡丁腌制十分钟',
            durationSeconds: 600,
            cookware: '大碗',
          ),
          RecipeStepInput(
            description: '大火翻炒至断生',
            durationSeconds: 180,
            temperature: '200℃',
            heatLevel: '大火',
            tips: '不要久炒',
          ),
        ],
      ),
    );
  }

  Widget wrap(
    TestBackendHarness harness,
    Recipe recipe, {
    required VoidCallback onDataChanged,
  }) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      initialRoute: '/detail',
      routes: <String, WidgetBuilder>{
        '/': (context) => const Scaffold(body: Text('菜谱库')),
        '/detail': (context) => RecipeDetailPage(
          backend: harness.root.backend,
          recipeId: recipe.id,
          onDataChanged: onDataChanged,
        ),
      },
    );
  }

  testWidgets('renders metadata, ingredients, steps and prepares cooking', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var changed = 0;

    await tester.pumpWidget(
      wrap(harness, recipe, onDataChanged: () => changed += 1),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipeDetailTitle')), findsOneWidget);
    expect(find.text('宫保鸡丁'), findsOneWidget);
    expect(find.text('3 人份'), findsOneWidget);
    expect(find.text('中等难度'), findsOneWidget);
    expect(find.text('下饭菜'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('鸡胸肉'), 350);
    expect(find.text('处理：切丁'), findsOneWidget);
    expect(find.text('花生米（可选）'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('大火翻炒至断生'), 350);
    expect(find.textContaining('200℃'), findsOneWidget);
    expect(find.text('提示：不要久炒'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('startCookingButton')),
      350,
    );
    await tester.tap(find.byKey(const Key('startCookingButton')));
    await tester.pumpAndSettle();

    expect(harness.cookingRepository.sessions, hasLength(1));
    expect(find.byKey(const Key('currentCookingStepText')), findsOneWidget);

    await tester.tap(find.byKey(const Key('exitCookingButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmExitCookingButton')));
    await tester.pumpAndSettle();

    final session = harness.cookingRepository.sessions.values.single;
    expect(session.status, CookingSessionStatus.active);
    expect(find.byKey(const Key('startCookingButton')), findsOneWidget);
    expect(changed, 0);
  });

  testWidgets('favorites, opens editor and soft deletes after confirmation', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final recipe = await seedRecipe(harness);
    var changed = 0;

    await tester.pumpWidget(
      wrap(harness, recipe, onDataChanged: () => changed += 1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    expect((await harness.root.backend.getRecipe(recipe.id)).favorite, isTrue);
    expect(changed, 1);

    await tester.scrollUntilVisible(
      find.byKey(const Key('editRecipeButton')),
      400,
    );
    await tester.tap(find.byKey(const Key('editRecipeButton')));
    await tester.pumpAndSettle();
    expect(find.text('编辑菜谱'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('deleteRecipeButton')));
    await tester.pumpAndSettle();
    expect(find.text('移到回收站？'), findsOneWidget);

    await tester.tap(find.byKey(const Key('confirmSoftDeleteRecipe')));
    await tester.pumpAndSettle();

    final deleted = await harness.root.backend.getRecipe(
      recipe.id,
      includeDeleted: true,
    );
    expect(deleted.deletedAt, isNotNull);
    expect(changed, 2);
    expect(find.text('菜谱库'), findsOneWidget);
  });
}
