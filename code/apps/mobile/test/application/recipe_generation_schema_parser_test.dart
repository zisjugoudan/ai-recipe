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

  test('tolerates LLM field-name casing differences, e.g. heatlevel', () {
    // 回归：LLM 有时把 heatLevel 输出成 heatlevel（全小写），
    // 之前会被当作未知字段拒绝，导致整份菜谱解析失败。
    final mixedCase = validRecipeGenerationJson
        .replaceFirst('"heatLevel": "中火"', '"heatlevel": "中火"')
        .replaceFirst('"durationSeconds": 180', '"durationseconds": 180')
        .replaceFirst('"schemaVersion": 1', '"schemaVersion": 1');

    final result = parser.parse(mixedCase);

    expect(result.steps.single.heatLevel, '中火');
    expect(result.steps.single.durationSeconds, 180);
  });

  test('extracts one JSON object surrounded by ordinary model prose', () {
    for (final response in <String>[
      '当然，以下是菜谱：\n$validRecipeGenerationJson',
      '$validRecipeGenerationJson\n以上内容可直接用于菜谱。',
      '当然，以下是菜谱：\n```json\n$validRecipeGenerationJson\n```\n请确认。',
      '<think>Check fields before returning the final answer.</think>\n'
          '当然，以下是菜谱：\n'
          '$validRecipeGenerationJson',
    ]) {
      expect(parser.parse(response).title, '番茄炒蛋');
    }
  });

  test('ignores braces and escaped quotes inside JSON strings', () {
    final wrappedText = validRecipeGenerationJson.replaceFirst(
      '"description": "家常快手菜"',
      r'"description": "说明包含 {花括号} 和 \"引号\""',
    );

    final result = parser.parse('结果如下：\n$wrappedText\n完成。');

    expect(result.description, '说明包含 {花括号} 和 "引号"');
  });

  test('rejects multiple, fenced and incomplete JSON candidates', () {
    for (final response in <String>[
      '$validRecipeGenerationJson\n$validRecipeGenerationJson',
      '```json\n$validRecipeGenerationJson\n```\n'
          '```json\n$validRecipeGenerationJson\n```',
      '$validRecipeGenerationJson\n{',
      '}\n$validRecipeGenerationJson',
      '```json\n$validRecipeGenerationJson',
      '```json\n说明\n$validRecipeGenerationJson\n```',
    ]) {
      expect(
        () => parser.parse(response),
        throwsA(isA<RecipeGenerationSchemaException>()),
      );
    }
  });

  test('rejects malformed, repeated and oversized reasoning wrappers', () {
    for (final response in <String>[
      '<think>unfinished\n$validRecipeGenerationJson',
      '<think>outer <think>inner</think></think>\n'
          '$validRecipeGenerationJson',
      '<think>first</think>\n<think>second</think>\n'
          '$validRecipeGenerationJson',
      '$validRecipeGenerationJson\n</think>',
    ]) {
      expect(
        () => parser.parse(response),
        throwsA(isA<RecipeGenerationSchemaException>()),
      );
    }

    const limitedParser = RecipeGenerationSchemaParser(
      maxResponseCharacters: 2048,
      maxReasoningCharacters: 8,
    );
    expect(
      () => limitedParser.parse(
        '<think>123456789</think>\n$validRecipeGenerationJson',
      ),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
    expect(
      () => const RecipeGenerationSchemaParser(
        maxResponseCharacters: 32,
        maxReasoningCharacters: 8,
      ).parse(validRecipeGenerationJson),
      throwsA(isA<RecipeGenerationSchemaException>()),
    );
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

  test('rejects missing fields, truncated JSON and invalid types', () {
    final missingTitle = validRecipeGenerationJson.replaceFirst(
      '  "title": "番茄炒蛋",\n',
      '',
    );
    final wrongIngredientsType = validRecipeGenerationJson.replaceFirst(
      '"ingredients": [',
      '"ingredients": "not-an-array", "ignored": [',
    );
    final decimalServings = validRecipeGenerationJson.replaceFirst(
      '"servings": 2',
      '"servings": 2.5',
    );
    final numericQuantity = validRecipeGenerationJson.replaceFirst(
      '"quantity": "2"',
      '"quantity": 2',
    );
    final truncated = validRecipeGenerationJson.substring(
      0,
      validRecipeGenerationJson.length - 4,
    );

    for (final response in <String>[
      missingTitle,
      wrongIngredientsType,
      decimalServings,
      numericQuantity,
      truncated,
    ]) {
      expect(
        () => parser.parse(response),
        throwsA(isA<RecipeGenerationSchemaException>()),
      );
    }
  });
}
