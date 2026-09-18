import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/ocr/ocr_models.dart';
import '../../domain/ocr/ocr_provider.dart';
import '../../domain/ocr/ocr_provider_exception.dart';
import 'import_pipeline_contracts.dart';

class OcrEnrichingImportContentProcessor implements ImportContentProcessor {
  OcrEnrichingImportContentProcessor({
    required OcrProvider provider,
    required ImportContentProcessor downstream,
    this.maxImages = 20,
  }) : _provider = provider,
       _downstream = downstream {
    if (maxImages <= 0) {
      throw ArgumentError.value(maxImages, 'maxImages', 'must be positive');
    }
  }

  final OcrProvider _provider;
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
        message: '图片文字识别需要至少一张图片。',
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
    var hadEmptyResult = false;

    for (var index = 0; index < images.length; index += 1) {
      cancellationToken?.throwIfCancelled();
      final media = images[index];
      final document = await _recognize(
        OcrImageInput(
          // 小红书等平台可能返回 http 图片地址，安全暂存层要求 HTTPS，
          // 识别前统一升级为 https。
          remoteUrl: _secureImageUrl(media.remoteUrl),
          localAssetId: media.localAssetId,
          mimeType: media.mimeType,
          width: media.width,
          height: media.height,
          order: media.order,
        ),
        cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      final text = document.fullText.trim();
      if (text.isEmpty || !seen.add(text)) {
        hadEmptyResult = true;
      } else {
        nextOrder += 1;
        fragments.add(
          ImportTextFragment(
            kind: ImportTextFragmentKind.body,
            text: text,
            order: nextOrder,
            confidence: document.averageConfidence,
            sourceMediaOrder: media.order,
            sourceProvider: document.providerId,
          ),
        );
      }
      await onProgress(
        ImportTaskStage.ocr,
        0.35 + (0.25 * (index + 1) / images.length),
      );
    }

    if (fragments.isEmpty) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片中没有识别到可用的文字。',
        retryable: false,
      );
    }

    final warnings = content.warnings.toSet()
      ..remove(ImportContentWarning.requiresOcr)
      ..remove(ImportContentWarning.missingText);
    if (hadEmptyResult ||
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
  ///
  /// 小红书等平台的图片地址可能是 `http://`，而远程图片安全暂存层要求
  /// HTTPS-only；统一升级后再识别，避免图片因协议被拒。
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

  Future<OcrDocument> _recognize(
    OcrImageInput input,
    ImportCancellationToken? cancellationToken,
  ) async {
    try {
      return await _provider.recognize(
        input,
        cancellationToken: cancellationToken,
      );
    } on ImportOperationCancelledException {
      rethrow;
    } on OcrProviderException catch (error) {
      throw _mapProviderError(error);
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片文字识别失败，请稍后重试。',
        retryable: true,
      );
    }
  }

  /// 把 OCR Provider 错误映射为稳定中文文案。
  ///
  /// 常见失败路径（模型未安装、识别不可用、图片无效）使用固定可操作文案；
  /// 网络/超时等临时错误保持可重试，具体 message 已由 Provider 中文化。
  static ImportPipelineException _mapProviderError(OcrProviderException error) {
    return switch (error.kind) {
      OcrProviderErrorKind.cancelled => const ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: '图片文字识别已取消。',
        retryable: false,
      ),
      OcrProviderErrorKind.modelNotInstalled => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '本地 OCR 模型尚未安装，请先在 OCR 设置中安装模型包。',
        retryable: false,
      ),
      OcrProviderErrorKind.unavailable => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '本地 OCR 当前不可用，请检查 OCR 设置后重试。',
        retryable: false,
      ),
      OcrProviderErrorKind.invalidInput => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片无法用于文字识别，请检查图片后重试。',
        retryable: false,
      ),
      OcrProviderErrorKind.invalidResponse => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片内容无效，无法完成文字识别。',
        retryable: false,
      ),
      OcrProviderErrorKind.inferenceFailed => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片文字识别失败，请稍后重试。',
        retryable: true,
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
      OcrProviderErrorKind.rateLimited ||
      OcrProviderErrorKind.unknown => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片文字识别暂时失败，请稍后重试。',
        retryable: true,
      ),
      OcrProviderErrorKind.unauthorized => const ImportPipelineException(
        code: ImportTaskErrorCode.ocrFailed,
        message: '图片来源未授权，暂时无法识别。',
        retryable: false,
      ),
    };
  }
}
