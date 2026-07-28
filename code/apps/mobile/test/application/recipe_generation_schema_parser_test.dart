import 'package:ai_recipe/application/importing/recipe_generation_schema_parser.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_recipe_generation_dependencies.dart';

void main() {
  const parser = RecipeGenerationSchemaParser();

  test('parses a valid pure JSON recipe', () {
    final result = parser.parse(validRecipeGenerationJson);

    expect(result.title, '番茄炒蛋');
    expect(result.difficulty, RecipeDifficulty.easy);
    expect(result.ingredients.single.name, '番茄');
    expect(result.ingredients.single.confidence, 0.95);
    expect(result.steps.single.durationSeconds, 180);
  });

  test('parses a single fenced JSON block', () {
    final result = parser.parse('```json\n$validRecipeGenerationJson\n```');

    expect(result.title, '番茄炒蛋');
  });

  test('rejects model-controlled local fields', () {
    final invalid = validRecipeGenerationJson.replaceFirst(
      '"schemaVersion": 1,',
      '"schemaVersion": 1, "id": "model-id",',
    );

    expect(
      () => parser.parse(invalid),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
  });

  test('rejects invalid confidence and empty required arrays', () {
    final invalidConfidence = validRecipeGenerationJson.replaceFirst(
      '"confidence": 0.95',
      '"confidence": 1.5',
    );
    final emptyIngredients = validRecipeGenerationJson.replaceFirst(
      RegExp(r'"ingredients": \[[\s\S]*?\],\n  "steps"'),
      '"ingredients": [],\n  "steps"',
    );

    expect(
      () => parser.parse(invalidConfidence),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
    expect(
      () => parser.parse(emptyIngredients),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
  });

  test('rejects commentary around JSON and invalid numeric types', () {
    final decimalServings = validRecipeGenerationJson.replaceFirst(
      '"servings": 2',
      '"servings": 2.5',
    );

    expect(
      () => parser.parse('Here is the recipe: $validRecipeGenerationJson'),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
    expect(
      () => parser.parse(decimalServings),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
  });
}
