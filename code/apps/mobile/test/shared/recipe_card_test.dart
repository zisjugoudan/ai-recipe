import 'package:ai_recipe/app/app_theme.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:ai_recipe/shared/widgets/recipe_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Recipe buildRecipe({bool favorite = false}) {
    final now = DateTime.utc(2026, 7, 30);
    return Recipe(
      id: 'recipe-card-test',
      title:
          '\u8d85\u957f\u83dc\u540d\u7528\u4e8e\u9a8c\u8bc1\u79fb\u52a8\u7aef\u83dc\u8c31\u5361\u7247\u5728\u72ed\u7a84\u5c4f\u5e55\u4e0a\u4e0d\u4f1a\u6ea2\u51fa',
      description:
          '\u4e00\u9053\u9002\u5408\u5bb6\u5ead\u5236\u4f5c\u7684\u6d4b\u8bd5\u83dc\u3002',
      servings: 2,
      totalTimeMinutes: 35,
      favorite: favorite,
      ingredients: <Ingredient>[
        Ingredient(
          id: 'ingredient-1',
          name: '\u897f\u7ea2\u67ff',
          sortOrder: 0,
        ),
        Ingredient(id: 'ingredient-2', name: '\u9e21\u86cb', sortOrder: 1),
      ],
      tags: const <String>['\u5feb\u624b', '\u5bb6\u5e38'],
      createdAt: now,
      updatedAt: now,
    );
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: buildAiRecipeTheme(),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }

  testWidgets('renders metadata and handles a long title', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(RecipeCard(recipe: buildRecipe())));

    expect(find.textContaining('35 \u5206\u949f'), findsOneWidget);
    expect(find.textContaining('2 \u4eba\u4efd'), findsOneWidget);
    expect(find.textContaining('2 \u79cd\u98df\u6750'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invokes favorite and card callbacks', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? favoriteValue;
    var tapCount = 0;

    await tester.pumpWidget(
      wrap(
        RecipeCard(
          recipe: buildRecipe(favorite: true),
          onTap: () => tapCount++,
          onFavoriteChanged: (value) => favoriteValue = value,
        ),
      ),
    );

    await tester.tap(find.byTooltip('\u53d6\u6d88\u6536\u85cf'));
    await tester.pump();
    expect(favoriteValue, isFalse);

    await tester.tap(find.textContaining('\u8d85\u957f\u83dc\u540d'));
    await tester.pump();
    expect(tapCount, 1);
  });
}
