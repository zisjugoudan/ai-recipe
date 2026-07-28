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

enum ImportMediaKind { image, video, audio }

enum ImportContentWarning {
  missingTitle,
  missingText,
  missingMedia,
  partialContent,
  requiresOcr,
  requiresAsr,
  redirected,
}

class ImportTextFragment {
  ImportTextFragment({
    required this.kind,
    required String text,
    required this.order,
  }) : text = _requireText(text, 'text') {
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be zero or greater');
    }
  }

  final ImportTextFragmentKind kind;
  final String text;
  final int order;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'text': text,
    'order': order,
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
