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
  final createdAt = DateTime.utc(2026, 7, 30, 8);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_database_v3_migration_test_',
    );
    databasePath = path.join(temporaryDirectory.path, 'legacy.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'migrates v1 recipe data to v3 and enables local business tables',
    () async {
      await _createLegacyDatabase(
        databasePath: databasePath,
        version: 1,
        createdAt: createdAt,
      );

      final database = await appDatabase.database;

      expect(await _userVersion(database), AppDatabase.schemaVersion);
      expect(await _foreignKeysEnabled(database), isTrue);
      expect(
        await _tableNames(database, const <String>{
          'import_tasks',
          'recipe_recent_views',
          'local_app_settings',
          'cooking_sessions',
          'cooking_timers',
        }),
        <String>{
          'import_tasks',
          'recipe_recent_views',
          'local_app_settings',
          'cooking_sessions',
          'cooking_timers',
        },
      );

      final recipe = (await database.query(
        'recipes',
        where: 'id = ?',
        whereArgs: const <Object?>['recipe-legacy'],
      )).single;
      expect(recipe['title'], 'Legacy recipe');
      expect(recipe['tags_json'], '[]');

      expect(await _rowCount(database, 'recipe_categories'), 1);
      expect(await _rowCount(database, 'ingredients'), 1);
      expect(await _rowCount(database, 'recipe_steps'), 1);
      expect(await _rowCount(database, 'recipe_category_relations'), 1);

      await database.insert('recipe_recent_views', <String, Object?>{
        'recipe_id': 'recipe-legacy',
        'viewed_at': createdAt.millisecondsSinceEpoch,
      });
      await database.insert('cooking_sessions', <String, Object?>{
        'id': 'session-legacy',
        'recipe_id': 'recipe-legacy',
        'current_step_index': 0,
        'status': 'active',
        'started_at': createdAt.millisecondsSinceEpoch,
        'updated_at': createdAt.millisecondsSinceEpoch,
      });
      await database.insert('cooking_timers', <String, Object?>{
        'id': 'timer-legacy',
        'session_id': 'session-legacy',
        'label': 'Timer',
        'duration_seconds': 60,
        'state': 'running',
        'ends_at': createdAt
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': createdAt.millisecondsSinceEpoch,
      });

      await database.delete(
        'recipes',
        where: 'id = ?',
        whereArgs: const <Object?>['recipe-legacy'],
      );

      expect(await _rowCount(database, 'ingredients'), 0);
      expect(await _rowCount(database, 'recipe_steps'), 0);
      expect(await _rowCount(database, 'recipe_category_relations'), 0);
      expect(await _rowCount(database, 'recipe_recent_views'), 0);
      expect(await _rowCount(database, 'cooking_sessions'), 0);
      expect(await _rowCount(database, 'cooking_timers'), 0);
      expect(await _rowCount(database, 'recipe_categories'), 1);
    },
  );

  test('migrates v2 recipe and import task data to v3 without loss', () async {
    await _createLegacyDatabase(
      databasePath: databasePath,
      version: 2,
      createdAt: createdAt,
    );

    final database = await appDatabase.database;

    expect(await _userVersion(database), AppDatabase.schemaVersion);
    final recipe = (await database.query(
      'recipes',
      where: 'id = ?',
      whereArgs: const <Object?>['recipe-legacy'],
    )).single;
    final importTask = (await database.query(
      'import_tasks',
      where: 'id = ?',
      whereArgs: const <Object?>['task-legacy'],
    )).single;

    expect(recipe['title'], 'Legacy recipe');
    expect(recipe['tags_json'], '[]');
    expect(importTask['source_platform'], ImportSourcePlatform.douyin.name);
    expect(importTask['status'], ImportTaskStatus.failed.name);
    expect(importTask['stage'], ImportTaskStage.failed.name);
    expect(
      importTask['error_code'],
      ImportTaskErrorCode.networkUnavailable.name,
    );
    expect(importTask['retryable'], 1);
    expect(
      await _tableNames(database, const <String>{
        'recipe_recent_views',
        'local_app_settings',
        'cooking_sessions',
        'cooking_timers',
      }),
      <String>{
        'recipe_recent_views',
        'local_app_settings',
        'cooking_sessions',
        'cooking_timers',
      },
    );
  });

  test('migrates v2 data to v12 and allows web platform import tasks', () async {
    await _createLegacyDatabase(
      databasePath: databasePath,
      version: 2,
      createdAt: createdAt,
    );

    final database = await appDatabase.database;

    // v12 迁移后 schema 版本为最新，且旧 douyin 任务数据不丢失。
    expect(await _userVersion(database), AppDatabase.schemaVersion);
    final legacyTask = (await database.query(
      'import_tasks',
      where: 'id = ?',
      whereArgs: const <Object?>['task-legacy'],
    )).single;
    expect(legacyTask['source_platform'], ImportSourcePlatform.douyin.name);
    // v9 之后新增的列在迁移后用默认值兜底，不丢列结构。
    expect(legacyTask['additional_result_recipe_ids'], '[]');

    // 关键修复点：迁移后允许插入 source_platform = 'web' 的任务
    // （拍照选图/剪贴板占位 URL 解析后的平台值），经 repository 真实路径写入。
    final repository = SqliteImportTaskRepository(appDatabase);
    final webTask = ImportTask.queued(
      id: 'task-web',
      source: ImportSourceLink.parse('https://local-image/capture'),
      now: createdAt,
      maxAttempts: 1,
    );
    await repository.upsertTask(webTask);

    // 再次读取确认已持久化，且平台值可完整解析回 web。
    final restored = await repository.getTaskById('task-web');
    expect(restored, isNotNull);
    expect(restored!.sourcePlatform, ImportSourcePlatform.web);
    expect(restored.localVersion, 1);
  });
}

Future<void> _createLegacyDatabase({
  required String databasePath,
  required int version,
  required DateTime createdAt,
}) async {
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(
      version: version,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, _) async {
        await _createLegacyRecipeSchema(database);
        if (version >= 2) {
          await _createLegacyImportTaskSchema(database);
        }
      },
    ),
  );

  await database.insert('recipe_categories', <String, Object?>{
    'id': 'category-legacy',
    'name': 'Legacy category',
    'sort_order': 0,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': createdAt.millisecondsSinceEpoch,
    'local_version': 1,
  });
  await database.insert('recipes', <String, Object?>{
    'id': 'recipe-legacy',
    'title': 'Legacy recipe',
    'difficulty': 'easy',
    'favorite': 1,
    'status': 'draft',
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': createdAt.millisecondsSinceEpoch,
    'local_version': 1,
  });
  await database.insert('ingredients', <String, Object?>{
    'id': 'ingredient-legacy',
    'recipe_id': 'recipe-legacy',
    'name': 'Ingredient',
    'optional': 0,
    'substitutes_json': '[]',
    'sort_order': 0,
  });
  await database.insert('recipe_steps', <String, Object?>{
    'id': 'step-legacy',
    'recipe_id': 'recipe-legacy',
    'step_number': 1,
    'description': 'Cook it',
  });
  await database.insert('recipe_category_relations', <String, Object?>{
    'recipe_id': 'recipe-legacy',
    'category_id': 'category-legacy',
  });

  if (version >= 2) {
    await database.insert('import_tasks', <String, Object?>{
      'id': 'task-legacy',
      'source_url': 'https://v.douyin.com/legacy/',
      'normalized_url': 'https://v.douyin.com/legacy',
      'source_platform': ImportSourcePlatform.douyin.name,
      'status': ImportTaskStatus.failed.name,
      'stage': ImportTaskStage.failed.name,
      'progress': 0.65,
      'attempt': 2,
      'max_attempts': 3,
      'error_code': ImportTaskErrorCode.networkUnavailable.name,
      'error_message': 'offline',
      'retryable': 1,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': createdAt.millisecondsSinceEpoch,
      'local_version': 2,
    });
  }

  await database.close();
}

Future<void> _createLegacyRecipeSchema(Database database) async {
  await database.execute('''
    CREATE TABLE recipe_categories (
      id TEXT PRIMARY KEY NOT NULL,
      user_id TEXT,
      name TEXT NOT NULL,
      cover_image TEXT,
      sort_order INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      local_version INTEGER NOT NULL,
      deleted_at INTEGER
    )
  ''');
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
  await database.execute('''
    CREATE TABLE ingredients (
      id TEXT PRIMARY KEY NOT NULL,
      recipe_id TEXT NOT NULL,
      group_name TEXT,
      name TEXT NOT NULL,
      quantity TEXT,
      unit TEXT,
      optional INTEGER NOT NULL DEFAULT 0,
      preparation TEXT,
      substitutes_json TEXT NOT NULL DEFAULT '[]',
      sort_order INTEGER NOT NULL,
      confidence REAL,
      FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
    )
  ''');
  await database.execute('''
    CREATE TABLE recipe_steps (
      id TEXT PRIMARY KEY NOT NULL,
      recipe_id TEXT NOT NULL,
      step_number INTEGER NOT NULL,
      description TEXT NOT NULL,
      duration_seconds INTEGER,
      temperature TEXT,
      heat_level TEXT,
      cookware TEXT,
      tips TEXT,
      media_url TEXT,
      confidence REAL,
      FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
      UNIQUE (recipe_id, step_number)
    )
  ''');
  await database.execute('''
    CREATE TABLE recipe_category_relations (
      recipe_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      PRIMARY KEY (recipe_id, category_id),
      FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE,
      FOREIGN KEY (category_id) REFERENCES recipe_categories(id)
        ON DELETE CASCADE
    )
  ''');
}

Future<void> _createLegacyImportTaskSchema(Database database) async {
  await database.execute('''
    CREATE TABLE import_tasks (
      id TEXT PRIMARY KEY NOT NULL,
      source_url TEXT NOT NULL,
      normalized_url TEXT NOT NULL,
      source_platform TEXT NOT NULL
        CHECK (source_platform IN ('xiaohongshu', 'douyin')),
      status TEXT NOT NULL
        CHECK (status IN (
          'queued', 'running', 'needsReview',
          'completed', 'failed', 'cancelled'
        )),
      stage TEXT NOT NULL
        CHECK (stage IN (
          'queued', 'fetching', 'extracting', 'ocr', 'transcribing',
          'generating', 'review', 'completed', 'failed', 'cancelled'
        )),
      progress REAL NOT NULL CHECK (progress >= 0 AND progress <= 1),
      attempt INTEGER NOT NULL CHECK (attempt >= 1),
      max_attempts INTEGER NOT NULL CHECK (max_attempts >= attempt),
      error_code TEXT,
      error_message TEXT,
      retryable INTEGER NOT NULL DEFAULT 0 CHECK (retryable IN (0, 1)),
      result_recipe_id TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      started_at INTEGER,
      completed_at INTEGER,
      cancelled_at INTEGER,
      next_retry_at INTEGER,
      local_version INTEGER NOT NULL CHECK (local_version >= 1),
      deleted_at INTEGER
    )
  ''');
}

Future<int> _userVersion(Database database) async {
  final rows = await database.rawQuery('PRAGMA user_version');
  return rows.single['user_version']! as int;
}

Future<bool> _foreignKeysEnabled(Database database) async {
  final rows = await database.rawQuery('PRAGMA foreign_keys');
  return rows.single['foreign_keys'] == 1;
}

Future<Set<String>> _tableNames(
  Database database,
  Set<String> expectedNames,
) async {
  final placeholders = List<String>.filled(expectedNames.length, '?').join(',');
  final rows = await database.rawQuery(
    'SELECT name FROM sqlite_master WHERE type = ? AND name IN ($placeholders)',
    <Object?>['table', ...expectedNames],
  );
  return rows.map((row) => row['name']! as String).toSet();
}

Future<int> _rowCount(Database database, String table) async {
  final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM $table');
  return rows.single['count']! as int;
}
