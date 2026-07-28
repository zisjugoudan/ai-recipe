enum OcrModelPackageErrorKind {
  invalidPackage,
  incompatiblePlatform,
  incompatibleAppVersion,
  untrustedDownloadHost,
  unsupportedFileType,
  downloadFailed,
  sizeMismatch,
  checksumMismatch,
  healthCheckFailed,
  storageUnavailable,
  insufficientStorage,
  cancelled,
  unknown,
}

class OcrModelPackageException implements Exception {
  const OcrModelPackageException({required this.kind, required this.message});

  final OcrModelPackageErrorKind kind;
  final String message;

  @override
  String toString() => 'OcrModelPackageException(${kind.name}): $message';
}
