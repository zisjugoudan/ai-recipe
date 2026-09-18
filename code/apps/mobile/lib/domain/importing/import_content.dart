import 'import_task.dart';

enum ImportContentType { article, imageGallery, video, mixed, unknown }

enum ImportTextFragmentKind {
  title,
  description,
  body,
  caption,
  altText,
  metadata,
}

/// 文本证据的来源类型（BUG-006，ADR-0028：OCR 与多模态作为独立证据生产者）。
///
/// 结构化菜谱 LLM 只消费经过来源标注的证据；OCR 只负责忠实文字提取，
/// 多模态只负责视觉观察，不互相伪装。
enum ImportTextFragmentSourceType {
  /// 作者明确正文、配料表与平台原始字幕。
  authorText,

  /// 本地/云端 OCR 原文（含坐标、顺序、语言、置信度）。
  ocr,

  /// 平台字幕（未转写）。
  subtitle,

  /// ASR 转写。
  asr,

  /// 多模态 LLM 视觉观察（菜品、食材外观、动作、器具、步骤场景）。
  visionObservation,

  /// 结构化生成阶段允许的模型推断。
  inference,
}

enum ImportMediaKind { image, video, audio }

enum ImportContentWarning {
  missingTitle,
  missingText,
  missingMedia,
  partialContent,
  requiresOcr,
  requiresAsr,
  redirected,

  /// 自动融合中多模态视觉观察失败（OCR 结果已保留）。
  visionIncomplete,

  /// 自动融合中 OCR 文字提取失败（多模态视觉观察已保留）。
  ocrIncomplete,
}

class ImportTextFragment {
  ImportTextFragment({
    required this.kind,
    required String text,
    required this.order,
    this.confidence,
    this.sourceMediaOrder,
    String? sourceProvider,
    String? sourceLanguage,
    this.sourceStartMs,
    this.sourceEndMs,
    String? speakerLabel,
    this.sourceType = ImportTextFragmentSourceType.authorText,
  }) : text = _requireText(text, 'text'),
       sourceProvider = _optionalText(sourceProvider),
       sourceLanguage = _optionalText(sourceLanguage),
       speakerLabel = _optionalText(speakerLabel) {
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be zero or greater');
    }
    if (confidence != null && (confidence! < 0 || confidence! > 1)) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'must be between zero and one',
      );
    }
    if (sourceMediaOrder != null && sourceMediaOrder! < 0) {
      throw ArgumentError.value(
        sourceMediaOrder,
        'sourceMediaOrder',
        'must be zero or greater',
      );
    }
    if ((sourceStartMs == null) != (sourceEndMs == null)) {
      throw ArgumentError(
        'sourceStartMs and sourceEndMs must be provided together.',
      );
    }
    if (sourceStartMs != null && sourceStartMs! < 0) {
      throw ArgumentError.value(
        sourceStartMs,
        'sourceStartMs',
        'must be zero or greater',
      );
    }
    if (sourceEndMs != null && sourceEndMs! <= sourceStartMs!) {
      throw ArgumentError.value(
        sourceEndMs,
        'sourceEndMs',
        'must be greater than sourceStartMs',
      );
    }
  }

  final ImportTextFragmentKind kind;
  final String text;
  final int order;
  final double? confidence;
  final int? sourceMediaOrder;
  final String? sourceProvider;
  final String? sourceLanguage;
  final int? sourceStartMs;
  final int? sourceEndMs;
  final String? speakerLabel;

  /// 证据来源类型（默认作者正文；OCR/多模态处理器显式标记）。
  final ImportTextFragmentSourceType sourceType;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'text': text,
    'order': order,
    'confidence': confidence,
    'sourceMediaOrder': sourceMediaOrder,
    'sourceProvider': sourceProvider,
    'sourceLanguage': sourceLanguage,
    'sourceStartMs': sourceStartMs,
    'sourceEndMs': sourceEndMs,
    'speakerLabel': speakerLabel,
    'sourceType': sourceType.name,
  };
}

class ImportMediaReference {
  ImportMediaReference({
    required this.kind,
    String? remoteUrl,
    String? localAssetId,
    String? mimeType,
    this.width,
    this.height,
    this.durationMs,
    required this.order,
  }) : remoteUrl = _optionalHttpUrl(remoteUrl, 'remoteUrl'),
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
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'must be zero or greater',
      );
    }
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be zero or greater');
    }
  }

  final ImportMediaKind kind;
  final String? remoteUrl;
  final String? localAssetId;
  final String? mimeType;
  final int? width;
  final int? height;
  final int? durationMs;
  final int order;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'remoteUrl': remoteUrl,
    'localAssetId': localAssetId,
    'mimeType': mimeType,
    'width': width,
    'height': height,
    'durationMs': durationMs,
    'order': order,
  };
}

class ImportContent {
  ImportContent({
    required this.source,
    required String resolvedUrl,
    required this.contentType,
    String? title,
    String? description,
    String? authorName,
    DateTime? publishedAt,
    required DateTime capturedAt,
    Iterable<ImportTextFragment> textFragments = const [],
    Iterable<ImportMediaReference> media = const [],
    Iterable<ImportContentWarning> warnings = const [],
  }) : resolvedUrl = _requireHttpUrl(resolvedUrl, 'resolvedUrl'),
       title = _optionalText(title),
       description = _optionalText(description),
       authorName = _optionalText(authorName),
       publishedAt = publishedAt?.toUtc(),
       capturedAt = capturedAt.toUtc(),
       textFragments = List<ImportTextFragment>.unmodifiable(
         textFragments.toList()..sort((a, b) => a.order.compareTo(b.order)),
       ),
       media = List<ImportMediaReference>.unmodifiable(
         media.toList()..sort((a, b) => a.order.compareTo(b.order)),
       ),
       warnings = Set<ImportContentWarning>.unmodifiable(warnings) {
    final hasText =
        this.title != null ||
        this.description != null ||
        this.textFragments.isNotEmpty;
    if (!hasText && this.media.isEmpty) {
      throw ArgumentError('Import content must include text or media.');
    }
  }

  static const int schemaVersion = 1;

  final ImportSourceLink source;
  final String resolvedUrl;
  final ImportContentType contentType;
  final String? title;
  final String? description;
  final String? authorName;
  final DateTime? publishedAt;
  final DateTime capturedAt;
  final List<ImportTextFragment> textFragments;
  final List<ImportMediaReference> media;
  final Set<ImportContentWarning> warnings;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'sourceUrl': source.sourceUrl,
    'normalizedUrl': source.normalizedUrl,
    'sourcePlatform': source.platform.name,
    'resolvedUrl': resolvedUrl,
    'contentType': contentType.name,
    'title': title,
    'description': description,
    'authorName': authorName,
    'publishedAt': publishedAt?.toIso8601String(),
    'capturedAt': capturedAt.toIso8601String(),
    'textFragments': textFragments.map((item) => item.toJson()).toList(),
    'media': media.map((item) => item.toJson()).toList(),
    'warnings': warnings.map((warning) => warning.name).toList()..sort(),
  };

  /// 从 [toJson] 的输出反序列化出原始内容证据，用于把证据持久化到本地后恢复。
  factory ImportContent.fromJson(Map<String, Object?> json) {
    final capturedAt = DateTime.parse(json['capturedAt']! as String).toUtc();
    return ImportContent(
      source: ImportSourceLink(
        sourceUrl: json['sourceUrl']! as String,
        normalizedUrl: (json['normalizedUrl'] as String?) ??
            json['sourceUrl']! as String,
        platform: ImportSourcePlatform.values.byName(
          json['sourcePlatform']! as String,
        ),
      ),
      resolvedUrl: json['resolvedUrl']! as String,
      contentType: ImportContentType.values.byName(
        json['contentType']! as String,
      ),
      title: json['title'] as String?,
      description: json['description'] as String?,
      authorName: json['authorName'] as String?,
      publishedAt: json['publishedAt'] == null
          ? null
          : DateTime.parse(json['publishedAt']! as String),
      capturedAt: capturedAt,
      textFragments: (json['textFragments'] as List<Object?>? ?? const [])
          .map((item) {
            final map = item! as Map<String, Object?>;
            return ImportTextFragment(
              kind: ImportTextFragmentKind.values.byName(
                map['kind']! as String,
              ),
              text: map['text']! as String,
              order: map['order']! as int,
              confidence: map['confidence'] as double?,
              sourceMediaOrder: map['sourceMediaOrder'] as int?,
              sourceProvider: map['sourceProvider'] as String?,
              sourceLanguage: map['sourceLanguage'] as String?,
              sourceStartMs: map['sourceStartMs'] as int?,
              sourceEndMs: map['sourceEndMs'] as int?,
              speakerLabel: map['speakerLabel'] as String?,
              sourceType: ImportTextFragmentSourceType.values.byName(
                (map['sourceType'] as String?) ??
                    ImportTextFragmentSourceType.authorText.name,
              ),
            );
          })
          .toList(),
      media: (json['media'] as List<Object?>? ?? const [])
          .map((item) {
            final map = item! as Map<String, Object?>;
            return ImportMediaReference(
              kind: ImportMediaKind.values.byName(map['kind']! as String),
              remoteUrl: map['remoteUrl'] as String?,
              localAssetId: map['localAssetId'] as String?,
              mimeType: map['mimeType'] as String?,
              width: map['width'] as int?,
              height: map['height'] as int?,
              durationMs: map['durationMs'] as int?,
              order: map['order']! as int,
            );
          })
          .toList(),
      warnings: (json['warnings'] as List<Object?>? ?? const [])
          .map((name) => ImportContentWarning.values.byName(name! as String))
          .toSet(),
    );
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
  if (value == null) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String _requireHttpUrl(String value, String name) {
  final normalized = _requireText(value, name);
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    throw ArgumentError.value(value, name, '$name must be an HTTP(S) URL');
  }
  return uri.toString();
}

String? _optionalHttpUrl(String? value, String name) {
  final normalized = _optionalText(value);
  return normalized == null ? null : _requireHttpUrl(normalized, name);
}
