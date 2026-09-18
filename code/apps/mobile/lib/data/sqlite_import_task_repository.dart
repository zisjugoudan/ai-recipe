import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/importing/import_content.dart';
import '../domain/importing/import_task.dart';
import '../domain/importing/import_task_repository.dart';
import 'local/app_database.dart';

class SqliteImportTaskRepository implements ImportTaskRepository {
  const SqliteImportTaskRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> upsertTask(ImportTask task, {int? expectedLocalVersion}) async {
    final database = await _appDatabase.database;
    await database.transaction((transaction) async {
      if (expectedLocalVersion == null) {
        try {
          await transaction.insert(
            'import_tasks',
            _taskToRow(task),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          return;
        } on DatabaseException {
          final actualLocalVersion = await _readLocalVersion(
            transaction,
            task.id,
          );
          if (actualLocalVersion != null) {
            throw ImportTaskWriteConflictException(
              id: task.id,
              expectedLocalVersion: null,
              actualLocalVersion: actualLocalVersion,
            );
          }
          rethrow;
        }
      }

      if (task.localVersion != expectedLocalVersion + 1) {
        throw ArgumentError.value(
          task.localVersion,
          'task.localVersion',
          'must be exactly one greater than expectedLocalVersion',
        );
      }
      final changed = await transaction.update(
        'import_tasks',
        _taskToRow(task),
        where: 'id = ? AND local_version = ?',
        whereArgs: <Object?>[task.id, expectedLocalVersion],
      );
      if (changed == 0) {
        throw ImportTaskWriteConflictException(
          id: task.id,
          expectedLocalVersion: expectedLocalVersion,
          actualLocalVersion: await _readLocalVersion(transaction, task.id),
        );
      }
    });
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
    // 一并清理持久化的原始内容证据，避免残留。
    await database.delete(
      'import_task_evidence',
      where: 'task_id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> saveImportEvidence(String taskId, ImportContent content) async {
    final database = await _appDatabase.database;
    await database.insert(
      'import_task_evidence',
      <String, Object?>{
        'task_id': taskId,
        'evidence_json': jsonEncode(content.toJson()),
        'updated_at': _toEpoch(content.capturedAt),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<ImportContent?> loadImportEvidence(String taskId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'import_task_evidence',
      columns: const <String>['evidence_json'],
      where: 'task_id = ?',
      whereArgs: <Object?>[taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.single['evidence_json']! as String;
    return ImportContent.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  static Future<int?> _readLocalVersion(
    DatabaseExecutor database,
    String id,
  ) async {
    final rows = await database.query(
      'import_tasks',
      columns: const <String>['local_version'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['local_version']! as int;
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
      'additional_result_recipe_ids':
          jsonEncode(task.additionalResultRecipeIds),
      'progress_detail': task.progressDetail,
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
      additionalResultRecipeIds: _decodeAdditionalIds(
        row['additional_result_recipe_ids'] as String?,
      ),
      progressDetail: row['progress_detail'] as String?,
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

  /// 解码附加草稿 ID 列（JSON 数组；异常/空值回退为空列表）。
  static List<String> _decodeAdditionalIds(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return decoded
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
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
