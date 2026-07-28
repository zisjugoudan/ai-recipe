import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_import_task_repository.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteImportTaskRepository repository;
  final createdAt = DateTime.utc(2026, 7, 28, 12);

  ImportTask task({
    required String id,
    String url = 'https://v.douyin.com/example/',
    int maxAttempts = 3,
  }) {
    return ImportTask.queued(
      id: id,
      source: ImportSourceLink.parse(url),
      now: createdAt,
      maxAttempts: maxAttempts,
    );
  }

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_import_sqlite_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'imports.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteImportTaskRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('persists all failure and retry fields after reopening', () async {
    final failedAt = createdAt.add(const Duration(minutes: 2));
    final failed = task(id: 'task-persist')
        .start(createdAt.add(const Duration(minutes: 1)))
        .advance(
          nextStage: ImportTaskStage.transcribing,
          nextProgress: 0.55,
          now: createdAt.add(const Duration(seconds: 90)),
        )
        .fail(
          code: ImportTaskErrorCode.networkUnavailable,
          message: 'network offline',
          canRetry: true,
          nextRetryAt: failedAt.add(const Duration(minutes: 10)),
          now: failedAt,
        );
    await repository.upsertTask(failed);

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteImportTaskRepository(appDatabase);

    final loaded = await repository.getTaskById('task-persist');

    expect(loaded, isNotNull);
    expect(loaded!.sourcePlatform, ImportSourcePlatform.douyin);
    expect(loaded.status, ImportTaskStatus.failed);
    expect(loaded.stage, ImportTaskStage.failed);
    expect(loaded.progress, 0.55);
    expect(loaded.errorCode, ImportTaskErrorCode.networkUnavailable);
    expect(loaded.errorMessage, 'network offline');
    expect(loaded.retryable, isTrue);
    expect(loaded.startedAt, createdAt.add(const Duration(minutes: 1)));
    expect(loaded.nextRetryAt, failedAt.add(const Duration(minutes: 10)));
    expect(loaded.localVersion, 4);
  });

  test(
    'lists only due recoverable tasks and excludes soft deleted tasks',
    () async {
      final recoveryAt = createdAt.add(const Duration(minutes: 10));
      final queued = task(id: 'task-queued');
      final running = task(
        id: 'task-running',
      ).start(createdAt.add(const Duration(minutes: 1)));
      final dueFailure = task(id: 'task-due').fail(
        code: ImportTaskErrorCode.timeout,
        canRetry: true,
        nextRetryAt: recoveryAt,
        now: createdAt.add(const Duration(minutes: 1)),
      );
      final futureFailure = task(id: 'task-future').fail(
        code: ImportTaskErrorCode.timeout,
        canRetry: true,
        nextRetryAt: recoveryAt.add(const Duration(minutes: 1)),
        now: createdAt.add(const Duration(minutes: 1)),
      );
      final nonRetryable = task(id: 'task-terminal-failure').fail(
        code: ImportTaskErrorCode.authorizationRequired,
        canRetry: false,
        now: createdAt.add(const Duration(minutes: 1)),
      );
      for (final value in <ImportTask>[
        queued,
        running,
        dueFailure,
        futureFailure,
        nonRetryable,
      ]) {
        await repository.upsertTask(value);
      }
      await repository.softDeleteTask(
        queued.id,
        createdAt.add(const Duration(minutes: 2)),
      );

      final recoverable = await repository.listRecoverableTasks(recoveryAt);

      expect(recoverable.map((value) => value.id).toSet(), <String>{
        'task-running',
        'task-due',
      });
      expect(await repository.getTaskById(queued.id), isNull);
      final deleted = await repository.getTaskById(
        queued.id,
        includeDeleted: true,
      );
      expect(deleted!.deletedAt, createdAt.add(const Duration(minutes: 2)));
      expect(deleted.localVersion, 2);
    },
  );

  test('filters status lists and permanently deletes tasks', () async {
    await repository.upsertTask(task(id: 'task-list-queued'));
    await repository.upsertTask(
      task(
        id: 'task-list-cancelled',
      ).cancel(createdAt.add(const Duration(minutes: 1))),
    );

    final cancelled = await repository.listTasks(
      statuses: const <ImportTaskStatus>{ImportTaskStatus.cancelled},
    );
    expect(cancelled.map((value) => value.id), <String>['task-list-cancelled']);

    await repository.permanentlyDeleteTask('task-list-cancelled');
    expect(
      await repository.getTaskById('task-list-cancelled', includeDeleted: true),
      isNull,
    );
  });

  test('migrates a v1 database to v2 without losing recipe rows', () async {
    await appDatabase.close();
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE recipes (
              id TEXT PRIMARY KEY NOT NULL,
              user_id TEXT,
              title TEXT NOT NULL,
              description TEXT,
              cover_image TEXT,
              servings INTEGER,
              prep_time_minutes INTEGER,
              cook_time_minutes INTEGER,
              total_time_minutes INTEGER,
              difficulty TEXT NOT NULL,
              notes TEXT,
              favorite INTEGER NOT NULL DEFAULT 0,
              status TEXT NOT NULL,
              source_id TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              local_version INTEGER NOT NULL,
              deleted_at INTEGER
            )
          ''');
        },
      ),
    );
    await legacy.insert('recipes', <String, Object?>{
      'id': 'legacy-recipe',
      'title': '旧版菜谱',
      'difficulty': 'easy',
      'favorite': 0,
      'status': 'draft',
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': createdAt.millisecondsSinceEpoch,
      'local_version': 1,
    });
    await legacy.close();

    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final migrated = await appDatabase.database;
    final recipeRows = await migrated.query(
      'recipes',
      where: 'id = ?',
      whereArgs: <Object?>['legacy-recipe'],
    );
    final importTable = await migrated.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: <Object?>['table', 'import_tasks'],
    );
    final versionRows = await migrated.rawQuery('PRAGMA user_version');

    expect(recipeRows.single['title'], '旧版菜谱');
    expect(importTable, hasLength(1));
    expect(versionRows.single['user_version'], 2);

    repository = SqliteImportTaskRepository(appDatabase);
    await repository.upsertTask(task(id: 'task-after-migration'));
    expect(await repository.getTaskById('task-after-migration'), isNotNull);
  });
}
