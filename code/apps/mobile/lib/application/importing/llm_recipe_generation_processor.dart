import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';
import '../../domain/recipe/recipe.dart';
import '../../domain/recipe/recipe_cover_image_storer.dart';
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
    RecipeCoverImageStorer? coverImageStorer,
    OcrRemoteImageStager? remoteCoverImageStager,
    this.maxCoverImages = 9,
  }) : _provider = provider,
       _config = config,
       _apiKey = apiKey,
       _recipeRepository = recipeRepository,
       _idGenerator = idGenerator,
       _clock = clock,
       _userId = _normalizeUserId(userId),
       _promptBuilder = promptBuilder,
       _schemaParser = schemaParser,
       _coverImageStorer = coverImageStorer,
       _remoteCoverImageStager = remoteCoverImageStager {
    if (maxCoverImages <= 0) {
      throw ArgumentError.value(
        maxCoverImages,
        'maxCoverImages',
        'must be positive',
      );
    }
  }

  final LlmProvider _provider;
  final LlmConnectionConfig _config;
  final String _apiKey;
  final RecipeRepository _recipeRepository;
  final RecipeDraftIdGenerator _idGenerator;
  final RecipeGenerationClock _clock;
  final String? _userId;
  final RecipeGenerationPromptBuilder _promptBuilder;
  final RecipeGenerationSchemaParser _schemaParser;
  final RecipeCoverImageStorer? _coverImageStorer;
  final OcrRemoteImageStager? _remoteCoverImageStager;
  final int maxCoverImages;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    // 深度思考开关（PERF-001）：最终结构化生成跟随用户设置（config.reasoningMode）。
    final prompt = _promptBuilder.build(
      content,
      reasoningMode: _config.reasoningMode,
    );
    final requiresMediaExtraction =
        content.warnings.contains(ImportContentWarning.requiresOcr) ||
        content.warnings.contains(ImportContentWarning.requiresAsr);
    if (!prompt.hasUsableText ||
        (!prompt.hasSubstantiveText && requiresMediaExtraction)) {
      throw _missingTextError(content);
    }

    await onProgress(
      ImportTaskStage.generating,
      0.65,
      '正在整理识别到的内容，生成菜谱草稿',
    );
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
    } on RecipeGenerationSchemaException catch (error) {
      // 诊断：输出具体 Schema 校验原因与截断的 AI 响应（脱敏，≤2000 字符），
      // 便于定位 LLM 输出到底是字段缺失、多余还是格式问题。
      debugPrint(
        '[AIRecipe][Schema] AI JSON 校验失败：${error.message} '
        '响应片段=${_clip(responseText, 2000)}',
      );
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.schemaInvalid,
        message: 'AI 返回的 JSON 不符合菜谱规则，请重新导入或手动编辑。',
        retryable: false,
      );
    }

    await onProgress(
      ImportTaskStage.generating,
      0.88,
      'AI 已返回草稿，正在校验菜谱格式',
    );
    cancellationToken?.throwIfCancelled();

    await onProgress(
      ImportTaskStage.generating,
      0.9,
      '草稿《${generated.title}》已生成，正在保存',
    );
    cancellationToken?.throwIfCancelled();

    var recipe = _buildRecipe(content, generated);
    // 下载公开内容配图到菜谱私有封面目录（IMPORT-006）。
    if (_coverImageStorer != null && _remoteCoverImageStager != null) {
      recipe = await _attachCoverImages(
        recipe,
        content,
        cancellationToken,
      );
    }
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
    // 诊断：记录最终结构化生成的耗时与模式，用于定位“最后识别超时”
    // 到底是多模态转录慢、还是最终 LLM 生成慢。
    final started = _clock();
    try {
      final result = await _provider.generate(
        config: _config,
        apiKey: _apiKey,
        request: prompt.request,
        cancellationToken: cancellationToken,
      );
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      debugPrint(
        '[AIRecipe][Generate] 最终结构化生成耗时=${elapsedMs}ms '
        'sourceChars=${prompt.sourceCharacterCount} '
        'reasoningMode=${prompt.request.reasoningMode?.name ?? _config.reasoningMode.name}',
      );
      return result.text;
    } on LlmProviderException catch (error) {
      debugPrint(
        '[AIRecipe][Generate] 最终结构化生成失败 kind=${error.kind.name} '
        '耗时=${DateTime.now().difference(started).inMilliseconds}ms',
      );
      throw _mapLlmError(error.kind);
    } catch (_) {
      debugPrint(
        '[AIRecipe][Generate] 最终结构化生成异常 '
        '耗时=${DateTime.now().difference(started).inMilliseconds}ms',
      );
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
        coverImage: null,
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

  /// 下载公开内容（小红书/抖音）配图到菜谱私有封面目录（IMPORT-006）。
  ///
  /// 只处理带远程地址的图片，最多保存 [maxCoverImages] 张；远程图片经安全
  /// 暂存下载并校验后复制到 `recipe_covers/<recipeId>/<index>.<ext>`。单张
  /// 图片失败时 best-effort 跳过，不阻塞草稿生成；全部失败时草稿保持原样。
  Future<Recipe> _attachCoverImages(
    Recipe recipe,
    ImportContent content,
    ImportCancellationToken? cancellationToken,
  ) async {
    final images = content.media
        .where(
          (media) =>
              media.kind == ImportMediaKind.image &&
              (media.remoteUrl != null || media.localAssetId != null),
        )
        .take(maxCoverImages)
        .toList(growable: false);
    if (images.isEmpty) return recipe;

    final staged = <String>[];
    var failed = 0;
    for (final entry in images.indexed) {
      cancellationToken?.throwIfCancelled();
      final media = entry.$2;
      StagedOcrImage? remote;
      try {
        if (media.localAssetId != null) {
          // WebView 浏览器会话已下载到本地的图片：直接复制到封面目录，
          // 不经过远程下载（避免客户端直连被 CDN 拒绝）。
          final localPath = await _coverImageStorer!.copyIn(
            sourcePath: media.localAssetId!,
            containerId: recipe.id,
            index: entry.$1,
          );
          staged.add(localPath);
          continue;
        }
        remote = await _remoteCoverImageStager!.stage(
          OcrImageInput(
            // 小红书等平台可能返回 http 图片地址，安全暂存层要求 HTTPS，
            // 下载前统一升级为 https。
            remoteUrl: _secureImageUrl(media.remoteUrl),
            mimeType: media.mimeType,
            width: media.width,
            height: media.height,
            order: media.order,
          ),
          cancellationToken: cancellationToken,
        );
        final localPath = await _coverImageStorer!.copyIn(
          sourcePath: remote.input.localAssetId!,
          containerId: recipe.id,
          index: entry.$1,
        );
        staged.add(localPath);
      } on ImportOperationCancelledException {
        rethrow;
      } catch (error) {
        // best-effort：单张图片下载或落盘失败跳过，不阻塞草稿生成；
        // 同时输出脱敏调试摘要，便于定位真实下载失败原因。
        failed += 1;
        final detail = switch (error) {
          // statusCode 用于区分 CDN 拒绝（403/404）与客户端解析失败。
          OcrProviderException e =>
            'OcrProviderException(${e.kind.name} status=${e.statusCode})',
          _ => error.runtimeType.toString(),
        };
        debugPrint(
          '[AIRecipe][CoverImage] 配图下载失败 index=${entry.$1} '
          'url=${_clip(media.remoteUrl ?? '', 320)} error=$detail',
        );
      } finally {
        await remote?.dispose();
      }
    }
    if (failed == images.length) {
      debugPrint(
        '[AIRecipe][CoverImage] 全部 ${images.length} 张配图下载失败，'
        '草稿无本地封面',
      );
    }
    if (staged.isEmpty) return recipe;

    return Recipe(
      id: recipe.id,
      userId: recipe.userId,
      title: recipe.title,
      description: recipe.description,
      coverImage: staged.first,
      images: staged,
      servings: recipe.servings,
      prepTimeMinutes: recipe.prepTimeMinutes,
      cookTimeMinutes: recipe.cookTimeMinutes,
      totalTimeMinutes: recipe.totalTimeMinutes,
      difficulty: recipe.difficulty,
      notes: recipe.notes,
      favorite: recipe.favorite,
      status: recipe.status,
      sourceId: recipe.sourceId,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      categoryIds: recipe.categoryIds,
      tags: recipe.tags,
      createdAt: recipe.createdAt,
      updatedAt: recipe.updatedAt,
      localVersion: recipe.localVersion,
      deletedAt: recipe.deletedAt,
    );
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

  /// 截断调试输出中的 URL，避免完整地址与查询参数进入日志。
  static String _clip(String value, int maxLength) =>
      value.length <= maxLength ? value : '${value.substring(0, maxLength)}…';

  /// 把 http 图片地址升级为 https（其余地址原样返回）。
  ///
  /// 小红书等平台的配图地址可能是 `http://`，而远程图片安全暂存层要求
  /// HTTPS-only；统一升级后再下载，避免整批图片因协议被拒。
  static String? _secureImageUrl(String? url) {
    if (url == null) return null;
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.scheme.toLowerCase() == 'http' &&
        uri.hasAuthority) {
      return uri.replace(scheme: 'https').toString();
    }
    return url;
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
      case LlmProviderErrorKind.providerGatewayTimeout:
      case LlmProviderErrorKind.firstByteDeadline:
      case LlmProviderErrorKind.bodyIdleDeadline:
      case LlmProviderErrorKind.streamNotTerminated:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.timeout,
          message: 'AI 服务响应超时，请在 LLM/识图引擎设置中调大「请求超时」后重试。',
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
      case LlmProviderErrorKind.modelBusy:
      case LlmProviderErrorKind.unknown:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'AI 服务暂时不可用，请稍后重试。',
          retryable: true,
        );
      case LlmProviderErrorKind.invalidConfiguration:
      case LlmProviderErrorKind.badRequest:
      case LlmProviderErrorKind.methodNotAllowed:
      case LlmProviderErrorKind.payloadTooLarge:
      case LlmProviderErrorKind.unsupportedMediaType:
      case LlmProviderErrorKind.unauthorized:
      case LlmProviderErrorKind.notFound:
      case LlmProviderErrorKind.invalidResponse:
      case LlmProviderErrorKind.imageNotObserved:
      case LlmProviderErrorKind.textCapabilityUnconfirmed:
        return const ImportPipelineException(
          code: ImportTaskErrorCode.llmFailed,
          message: 'AI 服务配置或响应无效，请检查设置。',
          retryable: false,
        );
    }
  }
}
