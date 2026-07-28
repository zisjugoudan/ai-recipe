import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';

typedef ImportPipelineProgressCallback =
    Future<void> Function(ImportTaskStage stage, double progress);

class ImportRecipeDraftResult {
  ImportRecipeDraftResult({required String recipeId})
    : recipeId = _requireText(recipeId, 'recipeId');

  final String recipeId;
}

class ImportPipelineException implements Exception {
  const ImportPipelineException({
    required this.code,
    required this.message,
    required this.retryable,
  });

  final ImportTaskErrorCode code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'ImportPipelineException(${code.name}): $message';
}

abstract interface class ImportContentProcessor {
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  });
}

String _requireText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name must not be blank');
  }
  return normalized;
}
