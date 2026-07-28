import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  static const int schemaVersion = 2;
  static const String defaultFileName = 'ai_recipe.db';

  final DatabaseFactory _factory;
  final String? _databasePath;
  Future<Database>? _openingDatabase;

  Future<Database> get database {
    return _openingDatabase ??= _open();
  }

  Future<Database> _open() async {
    final resolvedPath =
        _databasePath ??
        path.join(await _factory.getDatabasesPath(), defaultFileName);
    return _factory.openDatabase(
      resolvedPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
  }

  Future<void> close() async {
    final openingDatabase = _openingDatabase;
    _openingDatabase = null;
    if (openingDatabase != null) {
      await (await openingDatabase).close();
    }
  }

  static Future<void> _createSchema(Database database, int version) async {
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
        FOREIGN KEY (category_id) REFERENCES recipe_categories(id) ON DELETE CASCADE
      )
    ''');

    await database.execute(
      'CREATE INDEX idx_recipes_updated_at ON recipes(updated_at DESC)',
    );
    await database.execute(
      'CREATE INDEX idx_recipes_deleted_at ON recipes(deleted_at)',
    );
    await database.execute(
      'CREATE INDEX idx_ingredients_recipe_sort '
      'ON ingredients(recipe_id, sort_order)',
    );
    await database.execute(
      'CREATE INDEX idx_steps_recipe_number '
      'ON recipe_steps(recipe_id, step_number)',
    );
    await database.execute(
      'CREATE INDEX idx_categories_sort '
      'ON recipe_categories(sort_order, name)',
    );
    await _createImportTaskSchema(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createImportTaskSchema(database);
    }
  }

  static Future<void> _createImportTaskSchema(Database database) async {
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
    await database.execute(
      'CREATE INDEX idx_import_tasks_status_updated '
      'ON import_tasks(status, updated_at)',
    );
    await database.execute(
      'CREATE INDEX idx_import_tasks_recovery '
      'ON import_tasks(status, retryable, next_retry_at)',
    );
    await database.execute(
      'CREATE INDEX idx_import_tasks_deleted_at '
      'ON import_tasks(deleted_at)',
    );
  }
}
