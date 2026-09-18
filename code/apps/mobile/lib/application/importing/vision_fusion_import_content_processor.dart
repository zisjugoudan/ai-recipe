import 'dart:io';

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/llm/llm_cancellation_token.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/multimodal_llm_provider.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import '../../domain/ocr/ocr_remote_image_stager.dart';
import 'import_pipeline_contracts.dart';

/// OCR 与多模态 LLM 视觉观察的自动融合处理器（BUG-006，ADR-0028）。
///
/// 替代原先"多模态失败后再 OCR"的串行二选一语义：两路**独立执行、分别结算**，
/// 任一路成功都保留：
/// - OCR 负责忠实文字提取（[ImportTextFragmentSourceType.ocr]）；
/// - 多模态负责视觉观察（[ImportTextFragmentSourceType.visionObservation]）；
/// - 两路都成功时按来源合并证据（重复文本去重，不互相覆盖）；
/// - 一路失败时保留另一路，并写入 [ImportContentWarning.visionIncomplete] 或
///   [ImportContentWarning.ocrIncomplete]；
/// - 两路都失败但有正文/字幕时基于已有证据继续；
/// - 两路都失败且无任何证据时不生成空草稿，抛错引导重选图片/粘贴正文。
class VisionFusionImportContentProcessor implements ImportContentProcessor {
  VisionFusionImportContentProcessor({
    required OcrProvider ocrProvider,
    required MultimodalLlmProvider multimodalProvider,
    required LlmConnectionConfig multimodalConfig,
    required String multimodalApiKey,
    required OcrRemoteImageStager stager,
    required ImportContentProcessor downstream,
    this.maxImages = 9,
  }) : _ocrProvider = ocrProvider,
       _multimodalProvider = multimodalProvider,
       _multimodalConfig = multimodalConfig,
       _multimodalApiKey = multimodalApiKey,
       _stager = stager,
       _downstream = downstream {
    if (maxImages <= 0) {
      throw ArgumentError.value(maxImages, 'maxImages', 'must be positive');
    }
  }

  /// 多模态视觉观察固定提示词：只描述画面，不编造作者未给出的用量/时间。
  static const String visionObservationPrompt =
      '请观察这张图片并输出与菜谱相关的视觉信息：菜品的名称与外观、'
      '可见的食材及其状态、烹饪动作、使用的器具、步骤场景。'
      '请用简洁的条目化文字输出；不确定的内容请标注"不确定"。'
      '如果图片与菜谱无关，只输出"（图片与菜谱无关）"。'
      '不要编造图片中没有的内容，不要把推测写成作者明确给出的用量或时间。';

  final OcrProvider _ocrProvider;
  final MultimodalLlmProvider _multimodalProvider;
  final LlmConnectionConfig _multimodalConfig;
  final String _multimodalApiKey;
  final OcrRemoteImageStager _stager;
  final ImportContentProcessor _downstream;
  final int maxImages;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    if (!content.warnings.contains(ImportContentWarning.requiresOcr)) {
      return _downstream.process(
        content,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
    }

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

    await onProgress(ImportTaskStage.ocr, 0.35);
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
    var ocrSucceeded = false;
    var visionSucceeded = false;
    var ocrFailedCount = 0;
    var visionFailedCount = 0;
    var hadEmptyResult = false;

    for (var index = 0; index < images.length; index += 1) {
      cancellationToken?.throwIfCancelled();
      final media = images[index];
      final input = OcrImageInput(
        remoteUrl: _secureImageUrl(media.remoteUrl),
        localAssetId: media.localAssetId,
        mimeType: media.mimeType,
        width: media.width,
        height: media.height,
        order: media.order,
      );

      // 两路独立执行：OCR 失败不影响多模态，反之亦然。
      final ocrResult = await _tryOcr(
        input,
        cancellationToken,
      );
      if (ocrResult != null) {
        ocrSucceeded = true;
        final text = ocrResult.fullText.trim();
        if (text.isEmpty || !seen.add(text)) {
          hadEmptyResult = true;
        } else {
          nextOrder += 1;
          fragments.add(
            ImportTextFragment(
              kind: ImportTextFragmentKind.body,
              text: text,
              order: nextOrder,
              confidence: ocrResult.averageConfidence,
              sourceMediaOrder: media.order,
              sourceProvider: ocrResult.providerId,
              sourceType: ImportTextFragmentSourceType.ocr,
            ),
          );
        }
      } else {
        ocrFailedCount += 1;
      }

      final visionResult = await _tryVision(
        input,
        cancellationToken,
      );
      if (visionResult != null) {
        visionSucceeded = true;
        final text = visionResult.text.trim();
        if (text.isEmpty ||
            text == '（图片与菜谱无关）' ||
            !seen.add(text)) {
          hadEmptyResult = true;
        } else {
          nextOrder += 1;
          fragments.add(
            ImportTextFragment(
              kind: ImportTextFragmentKind.body,
              text: text,
              order: nextOrder,
              sourceMediaOrder: media.order,
              sourceProvider: visionResult.providerId,
              sourceType: ImportTextFragmentSourceType.visionObservation,
            ),
          );
        }
      } else {
        visionFailedCount += 1;
      }

      await onProgress(
        ImportTaskStage.ocr,
        0.35 + (0.25 * (index + 1) / images.length),
      );
    }

    final warnings = content.warnings.toSet()
      ..remove(ImportContentWarning.requiresOcr)
      ..remove(ImportContentWarning.missingText);
    if (ocrSucceeded && visionFailedCount > 0) {
      warnings.add(ImportContentWarning.visionIncomplete);
    }
    if (visionSucceeded && ocrFailedCount > 0) {
      warnings.add(ImportContentWarning.ocrIncomplete);
    }
    if (hadEmptyResult ||
        ocrFailedCount > 0 ||
        visionFailedCount > 0 ||
        content.media
                .where((item) => item.kind == ImportMediaKind.image)
                .length >
            images.length) {
      warnings.add(ImportContentWarning.partialContent);
    }

    // 两路都失败且无任何可用证据：不生成空草稿。
    if (fragments.isEmpty && !_hasOtherEvidence(content)) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片文字识别与视觉观察均未完成，没有可用的内容。'
            '请重新选择图片、粘贴正文或手动创建菜谱。',
        retryable: false,
      );
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

  /// 除图片识别之外是否还有作者正文/字幕等独立证据。
  static bool _hasOtherEvidence(ImportContent content) {
    if (content.title?.trim().isNotEmpty == true) return true;
    if (content.description?.trim().isNotEmpty == true) return true;
    if (content.textFragments.any(
      (fragment) => fragment.sourceType == ImportTextFragmentSourceType.authorText,
    )) {
      return true;
    }
    return false;
  }

  /// OCR 一路：失败返回 null（不抛出，保持另一路继续）。
  Future<OcrDocument?> _tryOcr(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    try {
      return await _ocrProvider.recognize(
        input,
        cancellationToken: cancellationToken,
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on ImportPipelineException {
      rethrow;
    } on OcrProviderException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 多模态一路：失败返回 null（不抛出，保持另一路继续）。
  Future<MultimodalRecognitionResult?> _tryVision(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    StagedOcrImage? staged;
    try {
      staged = await _stager.stage(
        input,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      final localAssetId = staged.input.localAssetId;
      if (localAssetId == null || localAssetId.isEmpty) {
        return null;
      }
      final bytes = await File(localAssetId).readAsBytes();
      final validationError = _multimodalProvider.validateImageBytes(
        bytes: bytes,
        mimeType: staged.input.mimeType,
      );
      if (validationError != null) {
        return null;
      }
      return await _multimodalProvider.recognizeImage(
        config: _multimodalConfig,
        apiKey: _multimodalApiKey,
        input: MultimodalImageInput(
          bytes: bytes,
          mimeType: staged.input.mimeType,
          width: staged.input.width,
          height: staged.input.height,
          order: staged.input.order,
        ),
        prompt: visionObservationPrompt,
        cancellationToken: cancellationToken == null
            ? null
            : _ImportTokenAsLlmToken(cancellationToken),
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on ImportPipelineException {
      rethrow;
    } on OcrProviderException {
      return null;
    } on LlmProviderException {
      return null;
    } catch (_) {
      return null;
    } finally {
      await staged?.dispose();
    }
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
}

/// 把导入链路取消令牌桥接为 LLM 取消令牌。
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
