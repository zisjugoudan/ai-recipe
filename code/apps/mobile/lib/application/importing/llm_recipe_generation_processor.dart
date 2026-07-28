import 'dart:async';

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/recipe/recipe.dart';
import '../../domain/recipe/recipe_repository.dart';
import 'import_pipeline_contracts.dart';
import 'recipe_generation_prompt.dart';
import 'recipe_generation_schema_parser.dart';

typedef RecipeDraftIdGenerator = String Function();
typedef RecipeGenerationClock = DateTime Function();

class LlmRecipeGenerationProcessor implements ImportContentProcessor {
  LlmRecipeGenerationProcessor({
    required LlmProvider provider,
    required LlmConnectionConfig config,
    required String apiKey,
    required RecipeRepository recipeRepository,
    required RecipeDraftIdGenerator idGenerator,
    required RecipeGenerationClock clock,
    String? userId,
    RecipeGenerationPromptBuilder promptBuilder =
        const RecipeGenerationPromptBuilder(),
    RecipeGenerationSchemaParser schemaParser =
        const RecipeGenerationSchemaParser(),
  }) : _provider = provider,
       _config = config,
       _apiKey = apiKey,
       _recipeRepository = recipeRepository,
       _idGenerator = idGenerator,
       _clock = clock,
       _userId = _normalizeUserId(userId),
       _promptBuilder = promptBuilder,
       _schemaParser = schemaParser;

  final LlmProvider _provider;
  final LlmConnectionConfig _config;
  final String _apiKey;
  final RecipeRepository _recipeRepository;
  final RecipeDraftIdGenerator _idGenerator;
  final RecipeGenerationClock _clock;
  final String? _userId;
  final RecipeGenerationPromptBuilder _promptBuilder;
  final RecipeGenerationSchemaParser _schemaParser;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final prompt = _promptBuilder.build(content);
    final requiresMediaExtraction =
        content.warnings.contains(ImportContentWarning.requiresOcr) ||
        content.warnings.contains(ImportContentWarning.requiresAsr);
    if (!prompt.hasUsableText ||
        (!prompt.hasSubstantiveText && requiresMediaExtraction)) {
      throw _missingTextError(content);
    }

    await onProgress(ImportTaskStage.generating, 0.65);
    cancellationToken?.throwIfCancelled();

    final llmCancellationToken = LlmCancellationToken();
    if (cancellationToken != null) {
      unawaited(
        cancellationToken.whenCancelled.then((_) {
          llmCancellationToken.cancel();
        }),
      );
    }

    final responseText = await _generate(
      prompt,
      cancellationToken: llmCancellationToken,
    );
    cancellationToken?.throwIfCancelled();

    final GeneratedRecipeDraft generated;
    try {
      generated = _schemaParser.parse(responseText);
    } on RecipeGenerationSchemaException {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.schemaInvalid,
        message: 'AI 返回的菜谱结构无效，请重试或手动编辑。',
        retryable: false,
      );
    }

    await onProgress(ImportTaskStage.generating, 0.88);
    cancellationToken?.throwIfCancelled();

    await onProgress(ImportTaskStage.generating, 0.9);
    cancellationToken?.throwIfCancelled();

    final recipe = _buildRecipe(content, generated);
    try {
      await _recipeRepository.upsertRecipe(recipe);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.storageFailure,
        message: '菜谱草稿保存失败，请稍后重试。',
        retryable: true,
      );
    }

    return ImportRecipeDraftResult(recipeId: recipe.id);
  }

  Future<String> _generate(
    RecipeGenerationPrompt prompt, {
    required LlmCancellationToken cancellationToken,
  }) async {
    try {
      final result = await _provider.generate(
        config: _config,
        apiKey: _apiKey,
        request: prompt.request,
        cancellationToken: cancellationToken,
      );
      return result.text;
    } on LlmProviderException catch (error) {
      throw _mapLlmError(error.kind);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.llmFailed,
        message: 'AI 服务调用失败，请稍后重试。',
        retryable: true,
      );
    }
  }

  Recipe _buildRecipe(ImportContent content, GeneratedRecipeDraft generated) {
    try {
      final now = _clock().toUtc();
      return Recipe(
        id: _nextId(),
        userId: _userId,
        title: generated.title,
        description: generated.description,
        coverImage: _coverImage(content),
        servings: generated.servings,
        prepTimeMinutes: generated.prepTimeMinutes,
        cookTimeMinutes: generated.cookTimeMinutes,
        totalTimeMinutes: generated.totalTimeMinutes,
        difficulty: generated.difficulty,
        notes: generated.notes,
        favorite: false,
        status: RecipeStatus.draft,
        sourceId: content.source.normalizedUrl,
        ingredients: generated.ingredients.indexed.map((entry) {
          final item = entry.$2;
          return Ingredient(
            id: _nextId(),
            groupName: item.groupName,
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            optional: item.optional,
            preparation: item.preparation,
            substitutes: item.substitutes,
            sortOrder: entry.$1,
            confidence: item.confidence,
          );
        }).toList(),
        steps: generated.steps.indexed.map((entry) {
          final item = entry.$2;
          return RecipeStep(
            id: _nextId(),
            stepNumber: entry.$1 + 1,
            description: item.description,
            durationSeconds: item.durationSeconds,
            temperature: item.temperature,
            heatLevel: item.heatLevel,
            cookware: item.cookware,
            tips: item.tips,
            confidence: item.confidence,
          );
        }).toList(),
        categoryIds: const <String>[],
        createdAt: now,
        updatedAt: now,
        localVersion: 1,
      );
    } on ImportPipelineException {
      rethrow;
    } on FormatException {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.schemaInvalid,
        message: 'AI 返回的菜谱字段不符合本地规则。',
        retryable: false,
      );
    } on ArgumentError {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.schemaInvalid,
        message: 'AI 返回的菜谱字段不符合本地规则。',
        retryable: false,
      );
    }
  }

  String _nextId() {
    final value = _idGenerator().trim();
    if (value.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.storageFailure,
        message: '无法生成本地菜谱标识。',
        retryable: true,
      );
    }
    return value;
  }

  static String? _normalizeUserId(String? userId) {
    final normalized = userId?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static String? _coverImage(ImportContent content) {
    for (final media in content.media) {
      if (media.kind == ImportMediaKind.image && media.remoteUrl != null) {
        return media.remoteUrl;
      }
    }
    return null;
  }

  static ImportPipelineException _missingTextError(ImportContent content) {
    if (content.warnings.contains(ImportContentWarning.requiresOcr)) {
      return const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '当前内容需要先完成图片文字识别。',
        retryable: false,
      );
    }
    if (content.warnings.contains(ImportContentWarning.requiresAsr)) {
      return const ImportPipelineException(
        code: ImportTaskErrorCode.asrFailed,
        message: '当前内容需要先完成视频语音识别。',
        retryable: false,
      );
    }
    return const ImportPipelineException(
      code: ImportTaskErrorCode.extractionFailed,
      message: '没有可用于生成菜谱的文本。',
      retryable: false,
    );
  }

  static ImportPipelineException _mapLlmError(LlmProviderErrorKind kind) {
    switch (kind) {
      case LlmProviderErrorKind.timeout:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.timeout,
          message: 'AI 服务响应超时，请稍后重试。',
          retryable: true,
        );
      case LlmProviderErrorKind.cancelled:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.cancelled,
          message: '导入已取消。',
          retryable: false,
        );
      case LlmProviderErrorKind.network:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.networkUnavailable,
          message: '无法连接 AI 服务，请检查网络和 API 地址。',
          retryable: true,
        );
      case LlmProviderErrorKind.rateLimited:
      case LlmProviderErrorKind.server:
      case LlmProviderErrorKind.unknown:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'AI 服务暂时不可用，请稍后重试。',
          retryable: true,
        );
      case LlmProviderErrorKind.invalidConfiguration:
      case LlmProviderErrorKind.unauthorized:
      case LlmProviderErrorKind.notFound:
      case LlmProviderErrorKind.invalidResponse:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'AI 服务配置或响应无效，请检查设置。',
          retryable: false,
        );
    }
  }
}
