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
  const RecipeGenerationSchemaParser({
    this.maxResponseCharacters = 262144,
    this.maxReasoningCharacters = 65536,
  }) : assert(maxResponseCharacters > 0),
       assert(maxReasoningCharacters >= 0),
       assert(maxReasoningCharacters < maxResponseCharacters);

  final int maxResponseCharacters;
  final int maxReasoningCharacters;

  // 注意：字段名一律使用小写，配合 _asObject 中的键小写归一化，
  // 以容忍 LLM 输出不同大小写（如 heatlevel / heatLevel）导致解析失败。
  static const Set<String> _rootKeys = <String>{
    'schemaversion',
    'title',
    'description',
    'servings',
    'preptimeminutes',
    'cooktimeminutes',
    'totaltimeminutes',
    'difficulty',
    'notes',
    'ingredients',
    'steps',
  };
  static const Set<String> _ingredientKeys = <String>{
    'groupname',
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
    'durationseconds',
    'temperature',
    'heatlevel',
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
    if (_requiredInt(root, 'schemaversion', min: 1, max: 1) != 1) {
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
        'preptimeminutes',
        min: 0,
        max: 10080,
      ),
      cookTimeMinutes: _optionalInt(
        root,
        'cooktimeminutes',
        min: 0,
        max: 10080,
      ),
      totalTimeMinutes: _optionalInt(
        root,
        'totaltimeminutes',
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
            groupName: _optionalString(item, 'groupname', maxLength: 100),
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
              'durationseconds',
              min: 0,
              max: 86400,
            ),
            temperature: _optionalString(item, 'temperature', maxLength: 100),
            heatLevel: _optionalString(item, 'heatlevel', maxLength: 100),
            cookware: _optionalString(item, 'cookware', maxLength: 200),
            tips: _optionalString(item, 'tips', maxLength: 1000),
            confidence: _optionalConfidence(item, 'confidence'),
          );
        }),
      ),
    );
  }

  String _extractJsonPayload(String value) {
    if (value.length > maxResponseCharacters) {
      throw const RecipeGenerationSchemaException('AI 返回内容超过大小限制。');
    }

    var normalized = value.trim();
    if (normalized.isEmpty) {
      throw const RecipeGenerationSchemaException('AI 返回了空内容。');
    }

    normalized = _removeReasoningPrefix(normalized);
    return _extractUniqueJsonObject(normalized);
  }

  String _removeReasoningPrefix(String value) {
    final openTag = RegExp(r'<think>', caseSensitive: false);
    final closeTag = RegExp(r'</think>', caseSensitive: false);
    final firstOpen = openTag.firstMatch(value);
    final firstClose = closeTag.firstMatch(value);

    if (firstOpen == null) {
      if (firstClose != null) {
        throw const RecipeGenerationSchemaException('AI 推理包装格式无效。');
      }
      return value;
    }
    if (firstOpen.start != 0 || firstClose == null) {
      throw const RecipeGenerationSchemaException('AI 推理包装未完整闭合。');
    }
    if (firstClose.start < firstOpen.end) {
      throw const RecipeGenerationSchemaException('AI 推理包装格式无效。');
    }

    final reasoning = value.substring(firstOpen.end, firstClose.start);
    if (reasoning.length > maxReasoningCharacters) {
      throw const RecipeGenerationSchemaException('AI 推理包装超过大小限制。');
    }
    if (openTag.hasMatch(reasoning) || closeTag.hasMatch(reasoning)) {
      throw const RecipeGenerationSchemaException('AI 推理包装存在嵌套。');
    }

    final remainder = value.substring(firstClose.end).trim();
    if (remainder.isEmpty) {
      throw const RecipeGenerationSchemaException('AI 推理包装后缺少 JSON。');
    }
    if (openTag.hasMatch(remainder) || closeTag.hasMatch(remainder)) {
      throw const RecipeGenerationSchemaException('AI 推理包装重复。');
    }
    return remainder;
  }

  String _extractUniqueJsonObject(String value) {
    final fences = RegExp(r'```').allMatches(value).toList(growable: false);
    int? fencedContentStart;
    int? fencedContentEnd;
    if (fences.isNotEmpty) {
      if (fences.length != 2) {
        throw const RecipeGenerationSchemaException('JSON 代码块数量无效。');
      }
      final openingFence = fences.first;
      final closingFence = fences.last;
      final headerEnd = value.indexOf('\n', openingFence.end);
      if (headerEnd < 0 || headerEnd >= closingFence.start) {
        throw const RecipeGenerationSchemaException('JSON 代码块格式无效。');
      }
      final language = value
          .substring(openingFence.end, headerEnd)
          .trim()
          .toLowerCase();
      if (language.isNotEmpty && language != 'json') {
        throw const RecipeGenerationSchemaException('JSON 代码块语言无效。');
      }
      fencedContentStart = headerEnd + 1;
      fencedContentEnd = closingFence.start;
    }

    var depth = 0;
    var inString = false;
    var escaping = false;
    var objectStart = -1;
    var objectEnd = -1;

    for (var index = 0; index < value.length; index += 1) {
      final character = value[index];
      if (depth == 0) {
        if (character == '{') {
          if (objectEnd >= 0) {
            throw const RecipeGenerationSchemaException('AI 返回了多个 JSON 对象。');
          }
          objectStart = index;
          depth = 1;
        } else if (character == '}') {
          throw const RecipeGenerationSchemaException('JSON 对象花括号不平衡。');
        }
        continue;
      }

      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (character == '\\') {
          escaping = true;
        } else if (character == '"') {
          inString = false;
        }
        continue;
      }

      if (character == '"') {
        inString = true;
      } else if (character == '{') {
        depth += 1;
      } else if (character == '}') {
        depth -= 1;
        if (depth == 0) {
          objectEnd = index + 1;
        }
      }
    }

    if (depth != 0 || inString || escaping) {
      throw const RecipeGenerationSchemaException('JSON 对象未完整闭合。');
    }
    if (objectStart < 0 || objectEnd < 0) {
      throw const RecipeGenerationSchemaException('AI 返回内容中缺少 JSON 对象。');
    }

    if (fencedContentStart != null && fencedContentEnd != null) {
      if (objectStart < fencedContentStart || objectEnd > fencedContentEnd) {
        throw const RecipeGenerationSchemaException('JSON 对象不在代码块内。');
      }
      final beforeObject = value
          .substring(fencedContentStart, objectStart)
          .trim();
      final afterObject = value.substring(objectEnd, fencedContentEnd).trim();
      if (beforeObject.isNotEmpty || afterObject.isNotEmpty) {
        throw const RecipeGenerationSchemaException('JSON 代码块包含额外内容。');
      }
    }

    return value.substring(objectStart, objectEnd);
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
      // 键统一转为小写，容忍 LLM 输出大小写不一致的字段名。
      result[(entry.key! as String).toLowerCase()] = entry.value;
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
