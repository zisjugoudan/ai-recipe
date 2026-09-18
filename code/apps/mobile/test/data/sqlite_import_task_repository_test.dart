import 'dart:io';

import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_import_task_repository.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/importing/import_task_repository.dart';
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

  Future<void> persistTaskHistory(
    ImportTask initial,
    List<ImportTask> updates,
  ) async {
    await repository.upsertTask(initial);
    var previous = initial;
    for (final update in updates) {
      await repository.upsertTask(
        update,
        expectedLocalVersion: previous.localVersion,
      );
      previous = update;
    }
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
    final queued = task(id: 'task-persist');
    final running = queued.start(createdAt.add(const Duration(minutes: 1)));
    final transcribing = running.advance(
      nextStage: ImportTaskStage.transcribing,
      nextProgress: 0.55,
      now: createdAt.add(const Duration(seconds: 90)),
    );
    final failed = transcribing.fail(
      code: ImportTaskErrorCode.networkUnavailable,
      message: 'network offline',
      canRetry: true,
      nextRetryAt: failedAt.add(const Duration(minutes: 10)),
      now: failedAt,
    );
    await persistTaskHistory(queued, <ImportTask>[
      running,
      transcribing,
      failed,
    ]);

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
      final runningQueued = task(id: 'task-running');
      final running = runningQueued.start(
        createdAt.add(const Duration(minutes: 1)),
      );
      final dueQueued = task(id: 'task-due');
      final dueFailure = dueQueued.fail(
        code: ImportTaskErrorCode.timeout,
        canRetry: true,
        nextRetryAt: recoveryAt,
        now: createdAt.add(const Duration(minutes: 1)),
      );
      final futureQueued = task(id: 'task-future');
      final futureFailure = futureQueued.fail(
        code: ImportTaskErrorCode.timeout,
        canRetry: true,
        nextRetryAt: recoveryAt.add(const Duration(minutes: 1)),
        now: createdAt.add(const Duration(minutes: 1)),
      );
      final nonRetryableQueued = task(id: 'task-terminal-failure');
      final nonRetryable = nonRetryableQueued.fail(
        code: ImportTaskErrorCode.authorizationRequired,
        canRetry: false,
        now: createdAt.add(const Duration(minutes: 1)),
      );
      await repository.upsertTask(queued);
      await persistTaskHistory(runningQueued, <ImportTask>[running]);
      await persistTaskHistory(dueQueued, <ImportTask>[dueFailure]);
      await persistTaskHistory(futureQueued, <ImportTask>[futureFailure]);
      await persistTaskHistory(nonRetryableQueued, <ImportTask>[nonRetryable]);
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
    final cancellable = task(id: 'task-list-cancelled');
    final cancelledTask = cancellable.cancel(
      createdAt.add(const Duration(minutes: 1)),
    );
    await persistTaskHistory(cancellable, <ImportTask>[cancelledTask]);

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

  test('stale worker writes cannot overwrite persisted cancellation', () async {
    final queued = task(id: 'task-cancel-race');
    final running = queued.start(createdAt.add(const Duration(seconds: 10)));
    final generating = running.advance(
      nextStage: ImportTaskStage.generating,
      nextProgress: 0.9,
      now: createdAt.add(const Duration(seconds: 20)),
    );
    final cancelled = generating.cancel(
      createdAt.add(const Duration(seconds: 30)),
    );
    await persistTaskHistory(queued, <ImportTask>[
      running,
      generating,
      cancelled,
    ]);

    final staleFailure = generating.fail(
      code: ImportTaskErrorCode.schemaInvalid,
      message: 'late schema failure',
      canRetry: false,
      now: createdAt.add(const Duration(seconds: 40)),
    );
    final staleReview = generating.markNeedsReview(
      recipeId: 'late-recipe',
      now: createdAt.add(const Duration(seconds: 40)),
    );

    await expectLater(
      repository.upsertTask(
        staleFailure,
        expectedLocalVersion: generating.localVersion,
      ),
      throwsA(isA<ImportTaskWriteConflictException>()),
    );
    await expectLater(
      repository.upsertTask(
        staleReview,
        expectedLocalVersion: generating.localVersion,
      ),
      throwsA(isA<ImportTaskWriteConflictException>()),
    );

    await appDatabase.close();
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    repository = SqliteImportTaskRepository(appDatabase);

    final reopened = await repository.getTaskById(queued.id);
    expect(reopened!.status, ImportTaskStatus.cancelled);
    expect(reopened.errorCode, isNull);
    await expectLater(
      repository.upsertTask(queued),
      throwsA(isA<ImportTaskWriteConflictException>()),
    );
    expect(
      (await repository.getTaskById(queued.id))!.status,
      ImportTaskStatus.cancelled,
    );
  });

  test('migrates a v1 database to v3 without losing recipe rows', () async {
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
    expect(versionRows.single['user_version'], AppDatabase.schemaVersion);

    repository = SqliteImportTaskRepository(appDatabase);
    await repository.upsertTask(task(id: 'task-after-migration'));
    expect(await repository.getTaskById('task-after-migration'), isNotNull);
  });
}
