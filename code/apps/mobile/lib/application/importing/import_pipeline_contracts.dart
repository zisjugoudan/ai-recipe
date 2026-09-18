import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';

/// 导入流水线进度回调。
///
/// - `stage`：当前处理阶段（fetching/extracting/ocr/transcribing/generating）。
/// - `progress`：0~1 单调不减的进度值。
/// - `detail`（可选）：运行中实时展示的当前操作说明，例如“已获取到正文”、
///   “正在识别第 2/3 张图片”、“识别为 3 份独立菜谱，正在生成第 1/3 份草稿”、
///   “正在生成草稿《麻婆豆腐》”。仅展示用，不影响进度校验；不传则保留上次详情。
typedef ImportPipelineProgressCallback =
    Future<void> Function(ImportTaskStage stage, double progress,
        [String? detail]);

typedef ImportRecipeDraftDiscarder =
    Future<void> Function({required String recipeId, required String sourceId});

class ImportRecipeDraftResult {
  ImportRecipeDraftResult({
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
  }) : recipeId = _requireText(recipeId, 'recipeId'),
       additionalRecipeIds =
           _normalizeAdditionalIds(recipeId, additionalRecipeIds);

  /// 主草稿 ID（任务 `resultRecipeId` 关联的草稿）。
  final String recipeId;

  /// 附加草稿 ID（多图“每张图独立菜谱”时一次导入产出多个草稿，IMAGE-002）。
  final List<String> additionalRecipeIds;

  /// 本次导入产出的全部草稿 ID（主草稿 + 附加草稿，顺序稳定）。
  List<String> get allRecipeIds =>
      <String>[recipeId, ...additionalRecipeIds];

  static List<String> _normalizeAdditionalIds(
    String primary,
    List<String> additional,
  ) {
    final result = <String>[];
    for (final id in additional) {
      final normalized = id.trim();
      if (normalized.isEmpty || normalized == primary) continue;
      if (result.contains(normalized)) continue;
      result.add(normalized);
    }
    return List<String>.unmodifiable(result);
  }
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
