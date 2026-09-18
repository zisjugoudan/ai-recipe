import 'import_content.dart';
import 'import_task.dart';

class ImportTaskWriteConflictException implements Exception {
  const ImportTaskWriteConflictException({
    required this.id,
    required this.expectedLocalVersion,
    this.actualLocalVersion,
  });

  final String id;
  final int? expectedLocalVersion;
  final int? actualLocalVersion;

  @override
  String toString() {
    return 'ImportTaskWriteConflictException('
        'id: $id, expectedLocalVersion: $expectedLocalVersion, '
        'actualLocalVersion: $actualLocalVersion)';
  }
}

abstract interface class ImportTaskRepository {
  Future<void> upsertTask(
    ImportTask task, {
    int? expectedLocalVersion,
  });

  Future<ImportTask?> getTaskById(String id, {bool includeDeleted = false});

  Future<List<ImportTask>> listTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  });

  Future<List<ImportTask>> listRecoverableTasks(DateTime now);

  Future<void> softDeleteTask(String id, DateTime deletedAt);

  Future<void> permanentlyDeleteTask(String id);

  /// 保存导入任务的原始内容证据（可被"原始内容依据"面板展示与复制）。
  Future<void> saveImportEvidence(String taskId, ImportContent content);

  /// 读取导入任务持久化的原始内容证据；没有则返回 null。
  Future<ImportContent?> loadImportEvidence(String taskId);
}
