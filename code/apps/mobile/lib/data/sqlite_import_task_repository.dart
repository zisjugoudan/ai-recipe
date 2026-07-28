import 'package:sqflite/sqflite.dart';

import '../domain/importing/import_task.dart';
import '../domain/importing/import_task_repository.dart';
import 'local/app_database.dart';

class SqliteImportTaskRepository implements ImportTaskRepository {
  const SqliteImportTaskRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> upsertTask(ImportTask task) async {
    final database = await _appDatabase.database;
    await database.insert(
      'import_tasks',
      _taskToRow(task),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<ImportTask?> getTaskById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'import_tasks',
      where: includeDeleted ? 'id = ?' : 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _taskFromRow(rows.single);
  }

  @override
  Future<List<ImportTask>> listTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  }) async {
    if (limit != null && limit < 1) {
      throw ArgumentError.value(limit, 'limit', '必须大于等于 1');
    }
    if (statuses != null && statuses.isEmpty) {
      return const <ImportTask>[];
    }

    final clauses = <String>[];
    final arguments = <Object?>[];
    if (!includeDeleted) {
      clauses.add('deleted_at IS NULL');
    }
    if (statuses != null) {
      clauses.add(
        'status IN (${List.filled(statuses.length, '?').join(', ')})',
      );
      arguments.addAll(statuses.map((status) => status.name));
    }

    final database = await _appDatabase.database;
    final rows = await database.query(
      'import_tasks',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'created_at DESC, id ASC',
      limit: limit,
    );
    return rows.map(_taskFromRow).toList(growable: false);
  }

  @override
  Future<List<ImportTask>> listRecoverableTasks(DateTime now) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'import_tasks',
      where: '''
        deleted_at IS NULL AND (
          status = ? OR
          status = ? OR
          (
            status = ? AND retryable = 1 AND attempt < max_attempts AND
            (next_retry_at IS NULL OR next_retry_at <= ?)
          )
        )
      ''',
      whereArgs: <Object?>[
        ImportTaskStatus.queued.name,
        ImportTaskStatus.running.name,
        ImportTaskStatus.failed.name,
        _toEpoch(now),
      ],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(_taskFromRow).toList(growable: false);
  }

  @override
  Future<void> softDeleteTask(String id, DateTime deletedAt) async {
    final database = await _appDatabase.database;
    final changed = await database.rawUpdate(
      '''
        UPDATE import_tasks
        SET deleted_at = ?, updated_at = ?, local_version = local_version + 1
        WHERE id = ? AND deleted_at IS NULL
      ''',
      <Object?>[_toEpoch(deletedAt), _toEpoch(deletedAt), id],
    );
    _requireChanged(changed, id);
  }

  @override
  Future<void> permanentlyDeleteTask(String id) async {
    final database = await _appDatabase.database;
    final changed = await database.delete(
      'import_tasks',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    _requireChanged(changed, id);
  }

  static Map<String, Object?> _taskToRow(ImportTask task) {
    return <String, Object?>{
      'id': task.id,
      'source_url': task.sourceUrl,
      'normalized_url': task.normalizedUrl,
      'source_platform': task.sourcePlatform.name,
      'status': task.status.name,
      'stage': task.stage.name,
      'progress': task.progress,
      'attempt': task.attempt,
      'max_attempts': task.maxAttempts,
      'error_code': task.errorCode?.name,
      'error_message': task.errorMessage,
      'retryable': task.retryable ? 1 : 0,
      'result_recipe_id': task.resultRecipeId,
      'created_at': _toEpoch(task.createdAt),
      'updated_at': _toEpoch(task.updatedAt),
      'started_at': _nullableToEpoch(task.startedAt),
      'completed_at': _nullableToEpoch(task.completedAt),
      'cancelled_at': _nullableToEpoch(task.cancelledAt),
      'next_retry_at': _nullableToEpoch(task.nextRetryAt),
      'local_version': task.localVersion,
      'deleted_at': _nullableToEpoch(task.deletedAt),
    };
  }

  static ImportTask _taskFromRow(Map<String, Object?> row) {
    return ImportTask(
      id: row['id']! as String,
      sourceUrl: row['source_url']! as String,
      normalizedUrl: row['normalized_url']! as String,
      sourcePlatform: ImportSourcePlatform.values.byName(
        row['source_platform']! as String,
      ),
      status: ImportTaskStatus.values.byName(row['status']! as String),
      stage: ImportTaskStage.values.byName(row['stage']! as String),
      progress: (row['progress']! as num).toDouble(),
      attempt: row['attempt']! as int,
      maxAttempts: row['max_attempts']! as int,
      errorCode: _nullableEnum(
        row['error_code'] as String?,
        ImportTaskErrorCode.values,
      ),
      errorMessage: row['error_message'] as String?,
      retryable: row['retryable']! as int == 1,
      resultRecipeId: row['result_recipe_id'] as String?,
      createdAt: _fromEpoch(row['created_at']! as int),
      updatedAt: _fromEpoch(row['updated_at']! as int),
      startedAt: _nullableFromEpoch(row['started_at'] as int?),
      completedAt: _nullableFromEpoch(row['completed_at'] as int?),
      cancelledAt: _nullableFromEpoch(row['cancelled_at'] as int?),
      nextRetryAt: _nullableFromEpoch(row['next_retry_at'] as int?),
      localVersion: row['local_version']! as int,
      deletedAt: _nullableFromEpoch(row['deleted_at'] as int?),
    );
  }

  static T? _nullableEnum<T extends Enum>(String? name, List<T> values) {
    return name == null ? null : values.byName(name);
  }

  static int _toEpoch(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static int? _nullableToEpoch(DateTime? value) {
    return value == null ? null : _toEpoch(value);
  }

  static DateTime _fromEpoch(int value) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static DateTime? _nullableFromEpoch(int? value) {
    return value == null ? null : _fromEpoch(value);
  }

  static void _requireChanged(int changed, String id) {
    if (changed == 0) {
      throw StateError('导入任务不存在：$id');
    }
  }
}
