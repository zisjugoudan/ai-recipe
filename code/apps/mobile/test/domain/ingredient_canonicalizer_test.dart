import 'package:ai_recipe/domain/ingredient/ingredient_canonicalizer.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final canonicalizer = IngredientCanonicalizer();

  group('canonicalize', () {
    test('maps aliases to the same canonical id', () {
      final tomato = canonicalizer.canonicalize('西红柿');
      expect(tomato.canonicalIngredientId, 'ingredient.tomato');
      expect(tomato.canonicalName, '番茄');
      expect(tomato.matchType, IngredientMatchType.alias);

      final exact = canonicalizer.canonicalize('番茄');
      expect(exact.matchType, IngredientMatchType.exact);
      expect(exact.canonicalIngredientId, 'ingredient.tomato');

      final variant = canonicalizer.canonicalize('蕃茄');
      expect(variant.canonicalIngredientId, 'ingredient.tomato');
    });

    test('normalizes format: brackets, full-width, quantity suffix', () {
      final withBrackets = canonicalizer.canonicalize('西红柿（新鲜）');
      expect(withBrackets.normalizedName, '西红柿');
      expect(withBrackets.canonicalIngredientId, 'ingredient.tomato');

      final withQuantity = canonicalizer.canonicalize('西红柿 2 个');
      expect(withQuantity.normalizedName, '西红柿');

      final halfWidth = canonicalizer.canonicalize('西红柿(新鲜)');
      expect(halfWidth.normalizedName, '西红柿');
    });

    test('unknown names keep raw name with unknown match type', () {
      final unknown = canonicalizer.canonicalize('小番茄');
      expect(unknown.matchType, IngredientMatchType.unknown);
      expect(unknown.isKnown, isFalse);
      expect(unknown.normalizedName, '小番茄');
    });

    test('similar-but-different ingredients are not the same', () {
      // ADR-0021：相近食材不默认等价。
      expect(canonicalizer.isSameIngredient('番茄', '小番茄'), isFalse);
      expect(canonicalizer.isSameIngredient('鸡蛋', '鸡蛋液'), isFalse);
      expect(canonicalizer.isSameIngredient('白菜', '娃娃菜'), isFalse);
      expect(canonicalizer.isSameIngredient('猪肉', '五花肉'), isFalse);
      expect(canonicalizer.isSameIngredient('辣椒', '小米椒'), isFalse);
    });

    test('spec entries resolve base concept and facets (ADR-0022)', () {
      final lean = canonicalizer.canonicalize('精瘦肉');
      expect(lean.canonicalIngredientId, 'ingredient.pork');
      expect(lean.canonicalName, '猪肉');
      expect(lean.fatLevel, IngredientFatLevel.veryLean);
      expect(lean.matchType, IngredientMatchType.spec);
      expect(lean.specSource, IngredientSpecSource.localRule);

      final belly = canonicalizer.canonicalize('五花肉');
      expect(belly.canonicalIngredientId, 'ingredient.pork');
      expect(belly.cut, IngredientCut.belly);
      expect(belly.fatLevel, IngredientFatLevel.mixed);

      final mince = canonicalizer.canonicalize('肉末');
      expect(mince.canonicalIngredientId, 'ingredient.meat');
      expect(mince.form, IngredientForm.minced);

      final pork = canonicalizer.canonicalize('猪肉');
      expect(pork.canonicalIngredientId, 'ingredient.pork');
      expect(pork.hasNoFacets, isTrue);
    });

    test('suggestions list same-base spec candidates for progressive entry',
        () {
      final options = canonicalizer.specSuggestionsFor('猪肉');
      final labels = options.map((entry) => entry.name).toSet();
      expect(labels, containsAll(<String>['精瘦肉', '五花肉', '半肥半瘦']));

      expect(canonicalizer.specSuggestionsFor('小番茄'), isEmpty);
    });

    test('family concepts resolve to family base ids (ADR-0023)', () {
      final chili = canonicalizer.canonicalize('辣椒');
      expect(chili.canonicalIngredientId, 'ingredient.capsicum');
      expect(familyOf(chili.canonicalIngredientId), IngredientFamily.capsicum);

      final greenPepper = canonicalizer.canonicalize('青椒');
      expect(
        familyOf(greenPepper.canonicalIngredientId),
        IngredientFamily.capsicum,
      );
      expect(greenPepper.processing, IngredientProcessing.fresh);

      final mushroom = canonicalizer.canonicalize('香菇');
      expect(
        familyOf(mushroom.canonicalIngredientId),
        IngredientFamily.mushroom,
      );

      final bass = canonicalizer.canonicalize('鲈鱼');
      expect(familyOf(bass.canonicalIngredientId), IngredientFamily.fish);

      final pakchoi = canonicalizer.canonicalize('小白菜');
      expect(
        familyOf(pakchoi.canonicalIngredientId),
        IngredientFamily.leafyVegetable,
      );
    });

    test('family match: 辣椒 vs 青椒 is MAYBE, 干辣椒 vs 青椒 is NO',
        () {
      final chili = canonicalizer.canonicalize('辣椒').spec;
      final greenPepper = canonicalizer.canonicalize('青椒').spec;
      final driedChili = canonicalizer.canonicalize('干辣椒').spec;

      final maybe = matchIngredientSpec(
        stock: chili,
        requirement: greenPepper,
      );
      expect(maybe.verdict, IngredientMatchVerdict.maybe);

      final no = matchIngredientSpec(
        stock: driedChili,
        requirement: greenPepper,
      );
      expect(no.verdict, IngredientMatchVerdict.no);
    });
  });
}
