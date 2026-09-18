import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/multimodal_llm_provider.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';
import 'image_request_compressor.dart';
import 'import_pipeline_contracts.dart';

/// 多模态 LLM 图片识别：把配图交给多模态 AI，**忠实转录图片中的全部文字**
/// （菜名、配料、步骤、用量），与正文整合后交给 LLM 生成草稿（ADR-0029）。
///
/// 多模态不再扮演“视觉观察器”：不翻译、不总结、不推测画面，避免把画面推测
/// 伪装成作者明确给出的用量或时间。转录文本与 OCR 原文同属文字证据
/// （[ImportTextFragmentSourceType.ocr]），并保留 `sourceMediaOrder` 供按图分组。
class MultimodalImageEnrichingImportContentProcessor
    implements ImportContentProcessor {
  MultimodalImageEnrichingImportContentProcessor({
    required MultimodalLlmProvider provider,
    required LlmConnectionConfig config,
    required String apiKey,
    required OcrRemoteImageStager stager,
    required ImportContentProcessor downstream,
    this.maxImages = 9,
    this.concurrency = 2,
    ImageRequestCompressor imageCompressor = const ImageRequestCompressor(),
  }) : _provider = provider,
       _config = config,
       _apiKey = apiKey,
       _stager = stager,
       _downstream = downstream,
       _imageCompressor = imageCompressor {
    if (maxImages <= 0) {
      throw ArgumentError.value(maxImages, 'maxImages', 'must be positive');
    }
    if (concurrency <= 0) {
      throw ArgumentError.value(concurrency, 'concurrency', 'must be positive');
    }
  }

  /// 多模态转录固定提示词：忠实转录图片中的文字，不翻译、不总结、不推测画面。
  ///
  /// 多图链接“每张图独立菜谱还是多图合成一个菜谱”由纯文本 LLM 分组判断
  /// （IMAGE-002），这里只保证文字证据完整。
  ///
  /// 语言约束（项目负责人反馈“识别时 LLM 会私自改语言”）：显式要求输出语言
  /// 与图片文字完全一致，禁止翻译或改用其他语言。
  static const String defaultPrompt =
      '请忠实转录这张图片中的所有文字，包括菜名、配料与用量、做法步骤，'
      '尽量保留原文的顺序、标点和分行结构。'
      '只输出图片中实际出现的文字，不要翻译、不要总结、不要补充画面中不存在的内容。'
      '必须保持与图片文字完全相同的语言输出，禁止翻译，禁止改用其他语言：'
      '图片是中文就输出中文、是日文就输出日文、是英文就输出英文，'
      '不要因为提示词语言而改变输出语言。'
      '如果图片中没有文字，只输出"（图片没有文字）"。';

  final MultimodalLlmProvider _provider;
  final LlmConnectionConfig _config;
  final String _apiKey;
  final OcrRemoteImageStager _stager;
  final ImportContentProcessor _downstream;
  final ImageRequestCompressor _imageCompressor;
  final int maxImages;

  /// 下载/识别并发数（P0-2）：图片 1 下载完立即识别，图片 2 同时下载，形成流水线。
  final int concurrency;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    print("开始处理图片识别");
    if (!content.warnings.contains(ImportContentWarning.requiresOcr)) {
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }
    print("图片识别开始");

    final images = content.media
        .where((media) => media.kind == ImportMediaKind.image)
        .take(maxImages)
        .toList(growable: false);
    if (images.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片识别需要至少一张图片。',
        retryable: false,
      );
    }

    await onProgress(
      ImportTaskStage.ocr,
      0.35,
      '正在识别 ${images.length} 张图片中的文字',
    );
    final seen = <String>{
      if (content.title case final value?) value.trim(),
      if (content.description case final value?) value.trim(),
      ...content.textFragments.map((fragment) => fragment.text.trim()),
    }..remove('');
    final fragments = <ImportTextFragment>[];
    var nextOrder = content.textFragments.fold<int>(
      -1,
      (largest, fragment) =>
          fragment.order > largest ? fragment.order : largest,
    );
    var hadEmptyResult = false;
    var failedRecognition = 0;

    // 有限并发流水线（P0-2）：下载/识别并发进行，单张失败不拖垮整批；
    // 识别结果按原图顺序收纳，供后续分组与段落顺序保持一致。
    final recognitions = await _runConcurrent<_RecognitionOutcome?>(
      images.length,
      concurrency: concurrency,
      task: (index) => _recognizeOutcome(images[index], cancellationToken),
    );

    for (var index = 0; index < recognitions.length; index += 1) {
      cancellationToken?.throwIfCancelled();
      final media = images[index];
      final outcome = recognitions[index];
      if (outcome == null) {
        // 单张识别失败：记录为部分失败，其余图片继续。
        failedRecognition += 1;
      } else {
        final text = outcome.text.trim();
        // 转录语义下“图片没有文字”与空文本等价：不产生证据，只标记部分内容。
        if (text.isEmpty ||
            text == '（图片没有文字）' ||
            !seen.add(text)) {
          hadEmptyResult = true;
        } else {
          // 多模态识别成功，产生文字证据。
          nextOrder += 1;
          fragments.add(
            ImportTextFragment(
              kind: ImportTextFragmentKind.body,
              text: text,
              order: nextOrder,
              sourceMediaOrder: media.order,
              sourceProvider: outcome.providerId,
              // 多模态转录的文字与 OCR 原文同属文字证据（ADR-0029），
              // 保留 sourceMediaOrder 供“每图独立/多图合成”分组。
              sourceType: ImportTextFragmentSourceType.ocr,
            ),
          );
        }
      }
      await onProgress(
        ImportTaskStage.ocr,
        0.35 + (0.25 * (index + 1) / images.length),
        '正在识别第 ${index + 1}/${images.length} 张图片',
      );
    }

    if (fragments.isEmpty) {
      if (failedRecognition == images.length) {
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.ocrFailed,
          message: '所有图片识别失败，请检查图片后重试。',
          retryable: true,
        );
      }
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片中没有提取到可用的内容。',
        retryable: false,
      );
    }

    final warnings = content.warnings.toSet()
      ..remove(ImportContentWarning.requiresOcr)
      ..remove(ImportContentWarning.missingText);
    if (hadEmptyResult ||
        failedRecognition > 0 ||
        content.media
                .where((item) => item.kind == ImportMediaKind.image)
                .length >
            images.length) {
      warnings.add(ImportContentWarning.partialContent);
    }

    final enriched = ImportContent(
      source: content.source,
      resolvedUrl: content.resolvedUrl,
      contentType: content.contentType,
      title: content.title,
      description: content.description,
      authorName: content.authorName,
      publishedAt: content.publishedAt,
      capturedAt: content.capturedAt,
      textFragments: <ImportTextFragment>[
        ...content.textFragments,
        ...fragments,
      ],
      media: content.media,
      warnings: warnings,
    );
    return _downstream.process(
      enriched,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
  }

  /// 把 http 图片地址升级为 https（其余地址原样返回）。
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

  /// 单张图片：安全暂存下载/校验 → 读取字节 → 压缩重编码 → 多模态识别。
  Future<MultimodalRecognitionResult> _recognize(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    StagedOcrImage? staged;
    try {
      staged = await _stager.stage(input, cancellationToken: cancellationToken);
      cancellationToken?.throwIfCancelled();
      final localAssetId = staged.input.localAssetId;
      if (localAssetId == null || localAssetId.isEmpty) {
        throw const OcrProviderException(
          kind: OcrProviderErrorKind.invalidInput,
          message: '图片暂存结果无效。',
        );
      }
      final bytes = await File(localAssetId).readAsBytes();
      // 识别前压缩重编码（P0-3）：降低上传体积与 Provider 解码开销；压缩失败
      // 或没有收益时保留原图，不影响识别。原图本体不改动，仍用于封面保存。
      final compressed = _imageCompressor.compress(
        bytes: bytes,
        byteLength: bytes.length,
      );
      final uploadBytes = compressed?.bytes ?? bytes;
      final uploadMime = compressed?.mimeType ?? staged.input.mimeType;
      final uploadWidth = compressed?.width ?? staged.input.width;
      final uploadHeight = compressed?.height ?? staged.input.height;
      final validationError = _provider.validateImageBytes(
        bytes: uploadBytes,
        mimeType: uploadMime,
      );
      if (validationError != null) {
        throw const ImportPipelineException(
          code: ImportTaskErrorCode.ocrFailed,
          message: '图片无法用于多模态识别，请检查图片后重试。',
          retryable: false,
        );
      }
      // 多模态识别
      final started = DateTime.now();
      final result = await _provider.recognizeImage(
        config: _config,
        apiKey: _apiKey,
        input: MultimodalImageInput(
          bytes: uploadBytes,
          mimeType: uploadMime,
          width: uploadWidth,
          height: uploadHeight,
          order: staged.input.order,
        ),
        prompt: defaultPrompt,
        cancellationToken: cancellationToken == null
            ? null
            : _ImportTokenAsLlmToken(cancellationToken),
      );
      // 诊断：记录单张图片转录耗时，用于区分“最后识别超时”是转录慢还是生成慢。
      debugPrint(
        '[AIRecipe][Recognize] 单图识别耗时=${DateTime.now().difference(started).inMilliseconds}ms '
        'order=${staged.input.order} uploadBytes=${uploadBytes.length}',
      );
      return result;
    } on ImportOperationCancelledException {
      rethrow;
    } on ImportPipelineException {
      rethrow;
    } on OcrProviderException catch (error) {
      throw _mapStagerError(error);
    } on LlmProviderException catch (error) {
      throw _mapProviderError(error);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片识别失败，请稍后重试。',
        retryable: true,
      );
    } finally {
      await staged?.dispose();
    }
  }

  /// 并发识别单张图片，并把“非取消”的失败折叠为 null（部分失败不拖垮整批）；
  /// 取消错误原样上抛，保证整批立即终止。
  Future<_RecognitionOutcome?> _recognizeOutcome(
    ImportMediaReference media,
    ImportCancellationToken? cancellationToken,
  ) async {
    try {
      final recognition = await _recognize(
        OcrImageInput(
          // 平台可能返回 http 图片地址，安全暂存层要求 HTTPS，统一升级。
          remoteUrl: _secureImageUrl(media.remoteUrl),
          localAssetId: media.localAssetId,
          mimeType: media.mimeType,
          width: media.width,
          height: media.height,
          order: media.order,
        ),
        cancellationToken,
      );
      return _RecognitionOutcome(
        text: recognition.text,
        providerId: recognition.providerId,
      );
    } on ImportPipelineException catch (error) {
      if (error.code == ImportTaskErrorCode.cancelled) rethrow;
      // 非取消的导入失败：单张失败不计为零文本，留待结果循环统一标记部分内容。
      return null;
    }
  }

  /// 以 [concurrency] 并发执行 [count] 个任务，结果按下标顺序返回。
  ///
  /// 任一任务抛出异常（如取消）时，其余任务尽快停止，并把首个异常上抛。
  Future<List<T?>> _runConcurrent<T>(
    int count, {
    required int concurrency,
    required Future<T?> Function(int index) task,
  }) async {
    final results = List<T?>.filled(count, null);
    var nextIndex = 0;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> worker() async {
      while (firstError == null) {
        final index = nextIndex;
        if (index >= count) return;
        nextIndex += 1;
        try {
          results[index] = await task(index);
        } catch (error, stack) {
          firstError = error;
          firstStack = stack;
          return;
        }
      }
    }

    final active = math.min(concurrency, count);
    await Future.wait(List<Future<void>>.generate(active, (_) => worker()));
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
    return results;
  }
  // 映射 OcrProviderException 为 ImportPipelineException
  static ImportPipelineException _mapStagerError(OcrProviderException error) {
    return switch (error.kind) {
      OcrProviderErrorKind.cancelled => const ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: '图片识别已取消。',
        retryable: false,
      ),
      OcrProviderErrorKind.invalidInput => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片无法用于识别，请检查图片后重试。',
        retryable: false,
      ),
      OcrProviderErrorKind.networkUnavailable => const ImportPipelineException(
        code: ImportTaskErrorCode.networkUnavailable,
        message: '无法获取图片内容，请检查网络后重试。',
        retryable: true,
      ),
      OcrProviderErrorKind.timeout => const ImportPipelineException(
        code: ImportTaskErrorCode.timeout,
        message: '获取图片内容超时，请稍后重试。',
        retryable: true,
      ),
      _ => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '获取图片内容失败，请稍后重试。',
        retryable: true,
      ),
    };
  }

  static ImportPipelineException _mapProviderError(LlmProviderException error) {
    return switch (error.kind) {
      LlmProviderErrorKind.cancelled => const ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: '图片识别已取消。',
        retryable: false,
      ),
      LlmProviderErrorKind.unauthorized => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '多模态识别身份验证失败，请检查图片识别 LLM 的 API Key。',
        retryable: false,
      ),
      LlmProviderErrorKind.invalidConfiguration ||
      LlmProviderErrorKind.badRequest ||
      LlmProviderErrorKind.payloadTooLarge ||
      LlmProviderErrorKind.unsupportedMediaType => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片请求与图片识别 LLM 协议不兼容，请检查 API 地址、图片大小和模型。',
        retryable: false,
      ),
      LlmProviderErrorKind.notFound ||
      LlmProviderErrorKind.methodNotAllowed => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '没有找到对应的多模态模型或接口地址。',
        retryable: false,
      ),
      LlmProviderErrorKind.rateLimited => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '多模态识别请求过于频繁或额度不足，请稍后重试。',
        retryable: true,
      ),
      LlmProviderErrorKind.timeout ||
      LlmProviderErrorKind.providerGatewayTimeout ||
      LlmProviderErrorKind.firstByteDeadline ||
      LlmProviderErrorKind.bodyIdleDeadline ||
      LlmProviderErrorKind.streamNotTerminated => const ImportPipelineException(
        code: ImportTaskErrorCode.timeout,
        message: '多模态识别超时，请在识图引擎设置中调大「请求超时」后重试。',
        retryable: true,
      ),
      LlmProviderErrorKind.network => const ImportPipelineException(
        code: ImportTaskErrorCode.networkUnavailable,
        message: '无法连接多模态识别服务，请检查网络后重试。',
        retryable: true,
      ),
      LlmProviderErrorKind.server ||
      LlmProviderErrorKind.modelBusy => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '多模态识别服务暂时不可用，请稍后重试。',
        retryable: true,
      ),
      LlmProviderErrorKind.invalidResponse ||
      LlmProviderErrorKind.imageNotObserved => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '多模态识别服务返回了无法识别的响应。',
        retryable: false,
      ),
      LlmProviderErrorKind.textCapabilityUnconfirmed =>
        const ImportPipelineException(
          code: ImportTaskErrorCode.ocrFailed,
          message: '当前模型不支持图片识别，请更换支持图片输入的模型。',
          retryable: false,
        ),
      LlmProviderErrorKind.unknown => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片识别暂时失败，请稍后重试。',
        retryable: true,
      ),
    };
  }
}

/// 单张图片识别结果（仅保留后续需要的字段）。
class _RecognitionOutcome {
  _RecognitionOutcome({required this.text, required this.providerId});

  final String text;
  final String providerId;
}

/// 把导入链路取消令牌桥接为 LLM 取消令牌。
///
/// 两套领域令牌结构一致但互不相关，多模态识别复用导入的取消语义
/// （取消时抛 [LlmProviderException.cancelled]，由外层统一映射）。
class _ImportTokenAsLlmToken implements LlmCancellationToken {
  _ImportTokenAsLlmToken(this._inner);

  final ImportCancellationToken _inner;

  @override
  bool get isCancelled => _inner.isCancelled;

  @override
  Future<void> get whenCancelled => _inner.whenCancelled;

  @override
  void cancel() => _inner.cancel();

  @override
  void throwIfCancelled() => _inner.throwIfCancelled();
}
