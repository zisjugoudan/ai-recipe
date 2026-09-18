import 'package:sqflite/sqflite.dart';

import '../domain/cooking/cooking_session.dart';
import 'local/app_database.dart';

class SqliteCookingRepository implements CookingRepository {
  const SqliteCookingRepository(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<void> upsertSession(CookingSession session) async {
    final database = await _appDatabase.database;
    await database.transaction((transaction) async {
      await transaction.insert(
        'cooking_sessions',
        _sessionRow(session),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await transaction.delete(
        'cooking_timers',
        where: 'session_id = ?',
        whereArgs: <Object?>[session.id],
      );
      for (final timer in session.timers) {
        await transaction.insert(
          'cooking_timers',
          _timerRow(session.id, timer),
        );
      }
    });
  }

  @override
  Future<CookingSession?> getSessionById(String id) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'cooking_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(database, rows.single);
  }

  @override
  Future<CookingSession?> getActiveSessionForRecipe(String recipeId) async {
    final database = await _appDatabase.database;
    final rows = await database.query(
      'cooking_sessions',
      where: 'recipe_id = ? AND status = ?',
      whereArgs: <Object?>[recipeId, CookingSessionStatus.active.name],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(database, rows.single);
  }

  @override
  Future<void> deleteSession(String id) async {
    final database = await _appDatabase.database;
    await database.delete(
      'cooking_sessions',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  static Map<String, Object?> _sessionRow(CookingSession session) =>
      <String, Object?>{
        'id': session.id,
        'recipe_id': session.recipeId,
        'current_step_index': session.currentStepIndex,
        'status': session.status.name,
        'started_at': _timestamp(session.startedAt),
        'updated_at': _timestamp(session.updatedAt),
        'completed_at': _optionalTimestamp(session.completedAt),
      };

  static Map<String, Object?> _timerRow(String sessionId, CookingTimer timer) =>
      <String, Object?>{
        'id': timer.id,
        'session_id': sessionId,
        'label': timer.label,
        'duration_seconds': timer.durationSeconds,
        'state': timer.state.name,
        'ends_at': _optionalTimestamp(timer.endsAt),
        'paused_remaining_seconds': timer.pausedRemainingSeconds,
        'created_at': _timestamp(timer.createdAt),
        'updated_at': _timestamp(timer.updatedAt),
        'completed_at': _optionalTimestamp(timer.completedAt),
      };

  static Future<CookingSession> _fromRow(
    DatabaseExecutor database,
    Map<String, Object?> row,
  ) async {
    final timerRows = await database.query(
      'cooking_timers',
      where: 'session_id = ?',
      whereArgs: <Object?>[row['id']],
      orderBy: 'created_at ASC',
    );
    return CookingSession(
      id: row['id']! as String,
      recipeId: row['recipe_id']! as String,
      currentStepIndex: row['current_step_index']! as int,
      status: CookingSessionStatus.values.byName(row['status']! as String),
      startedAt: _dateTime(row['started_at']! as int),
      updatedAt: _dateTime(row['updated_at']! as int),
      completedAt: _optionalDateTime(row['completed_at'] as int?),
      timers: timerRows
          .map(
            (timerRow) => CookingTimer(
              id: timerRow['id']! as String,
              label: timerRow['label']! as String,
              durationSeconds: timerRow['duration_seconds']! as int,
              state: CookingTimerState.values.byName(
                timerRow['state']! as String,
              ),
              endsAt: _optionalDateTime(timerRow['ends_at'] as int?),
              pausedRemainingSeconds:
                  timerRow['paused_remaining_seconds'] as int?,
              createdAt: _dateTime(timerRow['created_at']! as int),
              updatedAt: _dateTime(timerRow['updated_at']! as int),
              completedAt: _optionalDateTime(timerRow['completed_at'] as int?),
            ),
          )
          .toList(),
    );
  }

  static int _timestamp(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  static int? _optionalTimestamp(DateTime? value) =>
      value?.toUtc().millisecondsSinceEpoch;

  static DateTime _dateTime(int value) =>
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);

  static DateTime? _optionalDateTime(int? value) =>
      value == null ? null : _dateTime(value);
}
