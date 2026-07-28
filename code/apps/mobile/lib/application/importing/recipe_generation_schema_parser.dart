import 'dart:convert';

import '../../domain/recipe/recipe.dart';

class RecipeGenerationSchemaException implements Exception {
  const RecipeGenerationSchemaException(this.message);

  final String message;

  @override
  String toString() => 'RecipeGenerationSchemaException: $message';
}

class GeneratedIngredientDraft {
  const GeneratedIngredientDraft({
    required this.name,
    this.groupName,
    this.quantity,
    this.unit,
    required this.optional,
    this.preparation,
    required this.substitutes,
    this.confidence,
  });

  final String name;
  final String? groupName;
  final String? quantity;
  final String? unit;
  final bool optional;
  final String? preparation;
  final List<String> substitutes;
  final double? confidence;
}

class GeneratedRecipeStepDraft {
  const GeneratedRecipeStepDraft({
    required this.description,
    this.durationSeconds,
    this.temperature,
    this.heatLevel,
    this.cookware,
    this.tips,
    this.confidence,
  });

  final String description;
  final int? durationSeconds;
  final String? temperature;
  final String? heatLevel;
  final String? cookware;
  final String? tips;
  final double? confidence;
}

class GeneratedRecipeDraft {
  const GeneratedRecipeDraft({
    required this.title,
    this.description,
    this.servings,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.totalTimeMinutes,
    required this.difficulty,
    this.notes,
    required this.ingredients,
    required this.steps,
  });

  final String title;
  final String? description;
  final int? servings;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final int? totalTimeMinutes;
  final RecipeDifficulty difficulty;
  final String? notes;
  final List<GeneratedIngredientDraft> ingredients;
  final List<GeneratedRecipeStepDraft> steps;
}

class RecipeGenerationSchemaParser {
  const RecipeGenerationSchemaParser();

  static const Set<String> _rootKeys = <String>{
    'schemaVersion',
    'title',
    'description',
    'servings',
    'prepTimeMinutes',
    'cookTimeMinutes',
    'totalTimeMinutes',
    'difficulty',
    'notes',
    'ingredients',
    'steps',
  };
  static const Set<String> _ingredientKeys = <String>{
    'groupName',
    'name',
    'quantity',
    'unit',
    'optional',
    'preparation',
    'substitutes',
    'confidence',
  };
  static const Set<String> _stepKeys = <String>{
    'description',
    'durationSeconds',
    'temperature',
    'heatLevel',
    'cookware',
    'tips',
    'confidence',
  };

  GeneratedRecipeDraft parse(String responseText) {
    final payload = _extractJsonPayload(responseText);
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      throw const RecipeGenerationSchemaException('AI 返回内容不是有效的 JSON。');
    }
    final root = _asObject(decoded, '根对象');
    _rejectUnknownKeys(root, _rootKeys, '根对象');
    if (_requiredInt(root, 'schemaVersion', min: 1, max: 1) != 1) {
      throw const RecipeGenerationSchemaException('Schema 版本不受支持。');
    }

    final ingredientsRaw = _requiredList(
      root,
      'ingredients',
      minItems: 1,
      maxItems: 200,
    );
    final stepsRaw = _requiredList(root, 'steps', minItems: 1, maxItems: 100);

    return GeneratedRecipeDraft(
      title: _requiredString(root, 'title', maxLength: 200),
      description: _optionalString(root, 'description', maxLength: 4000),
      servings: _optionalInt(root, 'servings', min: 0, max: 1000),
      prepTimeMinutes: _optionalInt(
        root,
        'prepTimeMinutes',
        min: 0,
        max: 10080,
      ),
      cookTimeMinutes: _optionalInt(
        root,
        'cookTimeMinutes',
        min: 0,
        max: 10080,
      ),
      totalTimeMinutes: _optionalInt(
        root,
        'totalTimeMinutes',
        min: 0,
        max: 20160,
      ),
      difficulty: _difficulty(root['difficulty']),
      notes: _optionalString(root, 'notes', maxLength: 4000),
      ingredients: List<GeneratedIngredientDraft>.unmodifiable(
        ingredientsRaw.indexed.map((entry) {
          final item = _asObject(entry.$2, '食材 ${entry.$1 + 1}');
          _rejectUnknownKeys(item, _ingredientKeys, '食材 ${entry.$1 + 1}');
          return GeneratedIngredientDraft(
            groupName: _optionalString(item, 'groupName', maxLength: 100),
            name: _requiredString(item, 'name', maxLength: 200),
            quantity: _optionalString(item, 'quantity', maxLength: 100),
            unit: _optionalString(item, 'unit', maxLength: 50),
            optional: _optionalBool(item, 'optional') ?? false,
            preparation: _optionalString(item, 'preparation', maxLength: 500),
            substitutes: _optionalStringList(
              item,
              'substitutes',
              maxItems: 20,
              maxLength: 200,
            ),
            confidence: _optionalConfidence(item, 'confidence'),
          );
        }),
      ),
      steps: List<GeneratedRecipeStepDraft>.unmodifiable(
        stepsRaw.indexed.map((entry) {
          final item = _asObject(entry.$2, '步骤 ${entry.$1 + 1}');
          _rejectUnknownKeys(item, _stepKeys, '步骤 ${entry.$1 + 1}');
          return GeneratedRecipeStepDraft(
            description: _requiredString(item, 'description', maxLength: 4000),
            durationSeconds: _optionalInt(
              item,
              'durationSeconds',
              min: 0,
              max: 86400,
            ),
            temperature: _optionalString(item, 'temperature', maxLength: 100),
            heatLevel: _optionalString(item, 'heatLevel', maxLength: 100),
            cookware: _optionalString(item, 'cookware', maxLength: 200),
            tips: _optionalString(item, 'tips', maxLength: 1000),
            confidence: _optionalConfidence(item, 'confidence'),
          );
        }),
      ),
    );
  }

  String _extractJsonPayload(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const RecipeGenerationSchemaException('AI 返回了空内容。');
    }
    if (!trimmed.startsWith('```')) {
      return trimmed;
    }
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (match == null) {
      throw const RecipeGenerationSchemaException('JSON 代码块格式无效。');
    }
    final payload = match.group(1)?.trim() ?? '';
    if (payload.isEmpty) {
      throw const RecipeGenerationSchemaException('JSON 代码块为空。');
    }
    return payload;
  }

  static Map<String, Object?> _asObject(Object? value, String label) {
    if (value is! Map) {
      throw RecipeGenerationSchemaException('$label必须是对象。');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw RecipeGenerationSchemaException('$label包含无效字段名。');
      }
      result[entry.key! as String] = entry.value;
    }
    return result;
  }

  static void _rejectUnknownKeys(
    Map<String, Object?> object,
    Set<String> allowed,
    String label,
  ) {
    final unknown = object.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw RecipeGenerationSchemaException('$label包含未允许字段：${unknown.first}。');
    }
  }

  static String _requiredString(
    Map<String, Object?> object,
    String key, {
    required int maxLength,
  }) {
    if (!object.containsKey(key) || object[key] is! String) {
      throw RecipeGenerationSchemaException('$key 必须是字符串。');
    }
    final value = (object[key]! as String).trim();
    if (value.isEmpty || value.length > maxLength) {
      throw RecipeGenerationSchemaException('$key 长度无效。');
    }
    return value;
  }

  static String? _optionalString(
    Map<String, Object?> object,
    String key, {
    required int maxLength,
  }) {
    if (!object.containsKey(key) || object[key] == null) {
      return null;
    }
    if (object[key] is! String) {
      throw RecipeGenerationSchemaException('$key 必须是字符串或 null。');
    }
    final value = (object[key]! as String).trim();
    if (value.length > maxLength) {
      throw RecipeGenerationSchemaException('$key 过长。');
    }
    return value.isEmpty ? null : value;
  }

  static int _requiredInt(
    Map<String, Object?> object,
    String key, {
    required int min,
    required int max,
  }) {
    final value = object[key];
    if (!object.containsKey(key) ||
        value is! int ||
        value < min ||
        value > max) {
      throw RecipeGenerationSchemaException('$key 必须是 $min 到 $max 的整数。');
    }
    return value;
  }

  static int? _optionalInt(
    Map<String, Object?> object,
    String key, {
    required int min,
    required int max,
  }) {
    if (!object.containsKey(key) || object[key] == null) {
      return null;
    }
    final value = object[key];
    if (value is! int || value < min || value > max) {
      throw RecipeGenerationSchemaException('$key 必须是 $min 到 $max 的整数或 null。');
    }
    return value;
  }

  static bool? _optionalBool(Map<String, Object?> object, String key) {
    if (!object.containsKey(key) || object[key] == null) {
      return null;
    }
    final value = object[key];
    if (value is! bool) {
      throw RecipeGenerationSchemaException('$key 必须是布尔值或 null。');
    }
    return value;
  }

  static List<Object?> _requiredList(
    Map<String, Object?> object,
    String key, {
    required int minItems,
    required int maxItems,
  }) {
    final value = object[key];
    if (!object.containsKey(key) || value is! List) {
      throw RecipeGenerationSchemaException('$key 必须是数组。');
    }
    if (value.length < minItems || value.length > maxItems) {
      throw RecipeGenerationSchemaException('$key 数量无效。');
    }
    return List<Object?>.from(value);
  }

  static List<String> _optionalStringList(
    Map<String, Object?> object,
    String key, {
    required int maxItems,
    required int maxLength,
  }) {
    if (!object.containsKey(key) || object[key] == null) {
      return const <String>[];
    }
    final value = object[key];
    if (value is! List || value.length > maxItems) {
      throw RecipeGenerationSchemaException('$key 必须是有效字符串数组。');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String) {
        throw RecipeGenerationSchemaException('$key 必须是字符串数组。');
      }
      final normalized = item.trim();
      if (normalized.isEmpty || normalized.length > maxLength) {
        throw RecipeGenerationSchemaException('$key 包含无效文本。');
      }
      result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }

  static double? _optionalConfidence(Map<String, Object?> object, String key) {
    if (!object.containsKey(key) || object[key] == null) {
      return null;
    }
    final value = object[key];
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      throw RecipeGenerationSchemaException('$key 必须是 0 到 1 的数字或 null。');
    }
    return value.toDouble();
  }

  static RecipeDifficulty _difficulty(Object? value) {
    if (value == null) {
      return RecipeDifficulty.unspecified;
    }
    if (value is! String) {
      throw const RecipeGenerationSchemaException('difficulty 格式无效。');
    }
    try {
      return RecipeDifficulty.fromWireName(value);
    } on FormatException {
      throw const RecipeGenerationSchemaException('difficulty 值无效。');
    }
  }
}
