import 'import_task.dart';

abstract interface class ImportTaskRepository {
  Future<void> upsertTask(ImportTask task);

  Future<ImportTask?> getTaskById(String id, {bool includeDeleted = false});

  Future<List<ImportTask>> listTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  });

  Future<List<ImportTask>> listRecoverableTasks(DateTime now);

  Future<void> softDeleteTask(String id, DateTime deletedAt);

  Future<void> permanentlyDeleteTask(String id);
}
