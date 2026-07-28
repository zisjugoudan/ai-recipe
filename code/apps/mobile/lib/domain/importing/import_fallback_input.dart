import 'import_task.dart';

enum ImportFallbackInputKind { pastedText, localImage, localVideo }

class ImportFallbackInput {
  ImportFallbackInput._({
    required this.source,
    required this.kind,
    this.text,
    this.localAssetId,
    this.mimeType,
    required DateTime capturedAt,
  }) : capturedAt = capturedAt.toUtc();

  factory ImportFallbackInput.pastedText({
    required ImportSourceLink source,
    required String text,
    required DateTime capturedAt,
  }) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be empty');
    }
    return ImportFallbackInput._(
      source: source,
      kind: ImportFallbackInputKind.pastedText,
      text: normalized,
      capturedAt: capturedAt,
    );
  }

  factory ImportFallbackInput.localImage({
    required ImportSourceLink source,
    required String localAssetId,
    String? mimeType,
    required DateTime capturedAt,
  }) => ImportFallbackInput._localMedia(
    source: source,
    kind: ImportFallbackInputKind.localImage,
    localAssetId: localAssetId,
    mimeType: mimeType,
    requiredMimePrefix: 'image/',
    capturedAt: capturedAt,
  );

  factory ImportFallbackInput.localVideo({
    required ImportSourceLink source,
    required String localAssetId,
    String? mimeType,
    required DateTime capturedAt,
  }) => ImportFallbackInput._localMedia(
    source: source,
    kind: ImportFallbackInputKind.localVideo,
    localAssetId: localAssetId,
    mimeType: mimeType,
    requiredMimePrefix: 'video/',
    capturedAt: capturedAt,
  );

  factory ImportFallbackInput._localMedia({
    required ImportSourceLink source,
    required ImportFallbackInputKind kind,
    required String localAssetId,
    required String requiredMimePrefix,
    String? mimeType,
    required DateTime capturedAt,
  }) {
    final normalizedAssetId = localAssetId.trim();
    final normalizedMimeType = mimeType?.trim().toLowerCase();
    if (normalizedAssetId.isEmpty) {
      throw ArgumentError.value(
        localAssetId,
        'localAssetId',
        'must not be empty',
      );
    }
    if (normalizedMimeType != null &&
        normalizedMimeType.isNotEmpty &&
        !normalizedMimeType.startsWith(requiredMimePrefix)) {
      throw ArgumentError.value(
        mimeType,
        'mimeType',
        'must start with $requiredMimePrefix',
      );
    }
    return ImportFallbackInput._(
      source: source,
      kind: kind,
      localAssetId: normalizedAssetId,
      mimeType: normalizedMimeType == null || normalizedMimeType.isEmpty
          ? null
          : normalizedMimeType,
      capturedAt: capturedAt,
    );
  }

  final ImportSourceLink source;
  final ImportFallbackInputKind kind;
  final String? text;
  final String? localAssetId;
  final String? mimeType;
  final DateTime capturedAt;
}
