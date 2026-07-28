enum AsrProviderKind { localPlugin, cloudApi }

enum AsrMediaKind { audio, video }

class AsrMediaInput {
  AsrMediaInput({
    required this.kind,
    String? remoteUrl,
    String? localAssetId,
    String? mimeType,
    this.durationMs,
    String? languageHint,
    required this.order,
  }) : remoteUrl = _optionalHttpsUrl(remoteUrl, 'remoteUrl'),
       localAssetId = _optionalText(localAssetId),
       mimeType = _optionalText(mimeType),
       languageHint = _optionalText(languageHint) {
    if (this.remoteUrl == null && this.localAssetId == null) {
      throw ArgumentError('Either remoteUrl or localAssetId is required.');
    }
    if (durationMs != null && durationMs! <= 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'must be greater than zero',
      );
    }
    if (order < 0) {
      throw ArgumentError.value(order, 'order', 'must be zero or greater');
    }
    final normalizedMime = this.mimeType?.toLowerCase();
    if (normalizedMime != null) {
      final expectedPrefix = kind == AsrMediaKind.audio ? 'audio/' : 'video/';
      if (!normalizedMime.startsWith(expectedPrefix)) {
        throw ArgumentError.value(
          mimeType,
          'mimeType',
          'must match the ASR media kind',
        );
      }
    }
  }

  final AsrMediaKind kind;
  final String? remoteUrl;
  final String? localAssetId;
  final String? mimeType;
  final int? durationMs;
  final String? languageHint;
  final int order;
}

class AsrTranscriptSegment {
  AsrTranscriptSegment({
    required String text,
    required this.startMs,
    required this.endMs,
    this.confidence,
    String? speakerLabel,
  }) : text = _requireText(text, 'text'),
       speakerLabel = _optionalText(speakerLabel) {
    if (startMs < 0) {
      throw ArgumentError.value(startMs, 'startMs', 'must be zero or greater');
    }
    if (endMs <= startMs) {
      throw ArgumentError.value(endMs, 'endMs', 'must be greater than startMs');
    }
    if (confidence != null && (confidence! < 0 || confidence! > 1)) {
      throw ArgumentError.value(
        confidence,
        'confidence',
        'must be between zero and one',
      );
    }
  }

  final String text;
  final int startMs;
  final int endMs;
  final double? confidence;
  final String? speakerLabel;
}

class AsrTranscript {
  AsrTranscript({
    required String providerId,
    required String modelVersion,
    required String language,
    Iterable<AsrTranscriptSegment> segments = const <AsrTranscriptSegment>[],
    this.durationMs,
    this.processingDurationMs,
  }) : providerId = _requireText(providerId, 'providerId'),
       modelVersion = _requireText(modelVersion, 'modelVersion'),
       language = _requireText(language, 'language'),
       segments = List<AsrTranscriptSegment>.unmodifiable(
         segments.toList()..sort((a, b) {
           final start = a.startMs.compareTo(b.startMs);
           return start != 0 ? start : a.endMs.compareTo(b.endMs);
         }),
       ) {
    if (durationMs != null && durationMs! < 0) {
      throw ArgumentError.value(
        durationMs,
        'durationMs',
        'must be zero or greater',
      );
    }
    if (processingDurationMs != null && processingDurationMs! < 0) {
      throw ArgumentError.value(
        processingDurationMs,
        'processingDurationMs',
        'must be zero or greater',
      );
    }
    if (durationMs != null &&
        this.segments.any((item) => item.endMs > durationMs!)) {
      throw ArgumentError('Transcript segments must fit within durationMs.');
    }
  }

  final String providerId;
  final String modelVersion;
  final String language;
  final List<AsrTranscriptSegment> segments;
  final int? durationMs;
  final int? processingDurationMs;

  String get fullText => segments.map((segment) => segment.text).join('\n');

  double? get averageConfidence {
    final values = segments
        .map((segment) => segment.confidence)
        .whereType<double>()
        .toList(growable: false);
    if (values.isEmpty) {
      return null;
    }
    return values.reduce((a, b) => a + b) / values.length;
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
