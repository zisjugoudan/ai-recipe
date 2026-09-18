enum OcrProviderKind { localPlugin, cloudApi }

/// OCR 设置页"测试 OCR"的一次识别结果（识别文本 + 耗时等）。
class OcrTestResult {
  const OcrTestResult({
    required this.text,
    required this.modelVersion,
    required this.language,
    required this.blockCount,
    this.durationMs,
    this.averageConfidence,
  });

  /// 识别出的全文（按阅读顺序拼接，多行用换行分隔）。
  final String text;

  final String modelVersion;
  final String language;

  /// 识别出的文本块数量。
  final int blockCount;

  /// 识别耗时（毫秒，运行时未回传时为 null）。
  final int? durationMs;

  /// 平均置信度 0..1（无文本块时为 null）。
  final double? averageConfidence;
}

class OcrImageInput {
  OcrImageInput({
    String? remoteUrl,
    String? localAssetId,
    String? mimeType,
    this.width,
    this.height,
    required this.order,
  }) : remoteUrl = _optionalHttpsUrl(remoteUrl, 'remoteUrl'),
       localAssetId = _optionalText(localAssetId),
       mimeType = _optionalText(mimeType) {
    if (this.remoteUrl == null && this.localAssetId == null) {
      throw ArgumentError('Either remoteUrl or localAssetId is required.');
    }
    if (width != null && width! <= 0) {
      throw ArgumentError.value(width, 'width', 'must be greater than zero');
    }
    if (height != null && height! <= 0) {
      throw ArgumentError.value(height, 'height', 'must be greater than zero');
    }
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be zero or greater');
    }
  }

  final String? remoteUrl;
  final String? localAssetId;
  final String? mimeType;
  final int? width;
  final int? height;
  final int order;
}

class OcrPoint {
  OcrPoint({required this.x, required this.y}) {
    if (x < 0 || x > 1 || y < 0 || y > 1) {
      throw ArgumentError(
        'OCR point coordinates must be between zero and one.',
      );
    }
  }

  final double x;
  final double y;
}

class OcrTextBlock {
  OcrTextBlock({
    required String text,
    required this.confidence,
    required this.readingOrder,
    this.pageIndex = 0,
    Iterable<OcrPoint>? polygon,
  }) : text = _requireText(text, 'text'),
       polygon = polygon == null ? null : List<OcrPoint>.unmodifiable(polygon) {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'must be between zero and one',
      );
    }
    if (readingOrder < 0) {
      throw ArgumentError.value(
        readingOrder,
        'readingOrder',
        'must be zero or greater',
      );
    }
    if (pageIndex < 0) {
      throw ArgumentError.value(
        pageIndex,
        'pageIndex',
        'must be zero or greater',
      );
    }
    if (this.polygon != null && this.polygon!.length != 4) {
      throw ArgumentError.value(
        this.polygon,
        'polygon',
        'must contain exactly four normalized points',
      );
    }
  }

  final String text;
  final double confidence;
  final int readingOrder;
  final int pageIndex;
  final List<OcrPoint>? polygon;
}

class OcrDocument {
  OcrDocument({
    required String providerId,
    required String modelVersion,
    required String language,
    Iterable<OcrTextBlock> blocks = const <OcrTextBlock>[],
    this.durationMs,
  }) : providerId = _requireText(providerId, 'providerId'),
       modelVersion = _requireText(modelVersion, 'modelVersion'),
       language = _requireText(language, 'language'),
       blocks = List<OcrTextBlock>.unmodifiable(
         blocks.toList()..sort((a, b) {
           final page = a.pageIndex.compareTo(b.pageIndex);
           return page != 0 ? page : a.readingOrder.compareTo(b.readingOrder);
         }),
       ) {
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'must be zero or greater',
      );
    }
  }

  final String providerId;
  final String modelVersion;
  final String language;
  final List<OcrTextBlock> blocks;
  final int? durationMs;

  String get fullText => blocks.map((block) => block.text).join('\n');

  double? get averageConfidence {
    if (blocks.isEmpty) {
      return null;
    }
    final total = blocks.fold<double>(
      0,
      (sum, block) => sum + block.confidence,
    );
    return total / blocks.length;
  }
}

String _requireText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be blank');
  }
  return normalized;
}

String? _optionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _optionalHttpsUrl(String? value, String name) {
  final normalized = _optionalText(value);
  if (normalized == null) {
    return null;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw ArgumentError.value(value, name, '$name must be an HTTPS URL');
  }
  return uri.toString();
}
