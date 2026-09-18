import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _databasePath = databasePath;

  static const int schemaVersion = 13;
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
        tags_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        local_version INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await _createRecipeImagesSchema(database);

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
        base_concept_id TEXT,
        base_concept_name TEXT,
        cut TEXT,
        fat_level TEXT,
        form TEXT,
        processing TEXT,
        spec_confidence REAL,
        spec_source TEXT NOT NULL DEFAULT 'unknown',
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
    await _addPerformanceIndexes(database);
    await _createImportTaskSchema(database);
    await _createLocalBusinessSchema(database);
    await _createInventorySchema(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _createImportTaskSchema(database);
    }
    if (oldVersion < 3) {
      await database.execute(
        "ALTER TABLE recipes ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'",
      );
      await _createLocalBusinessSchema(database);
    }
    if (oldVersion < 4) {
      await _createRecipeImagesSchema(database);
    }
    if (oldVersion < 5) {
      await _createInventorySchema(database);
    }
    if (oldVersion < 6) {
      await _addSpecColumns(database);
    }
    if (oldVersion < 7) {
      await _addInventorySortOrderColumn(database);
    }
    if (oldVersion < 8) {
      await _addImageRecognitionModeColumn(database);
    }
    if (oldVersion < 9) {
      await _addAdditionalResultRecipeIdsColumn(database);
    }
    if (oldVersion < 10) {
      await _addPerformanceIndexes(database);
    }
    if (oldVersion < 11) {
      await _addProgressDetailColumn(database);
    }
    if (oldVersion < 12) {
      await _rebuildImportTasksTable(database);
    }
    if (oldVersion < 13) {
      await _createImportTaskEvidenceSchema(database);
    }
  }

  /// schema v10（解决方案.md 第五节）：为列表分页与推荐匹配补充复合索引。
  ///
  /// 消除 N+1 之后，让剩余的摘要分页 / 收藏过滤 / 推荐批量查询
  /// 也能走索引，而不是在数据量增大后全表扫描。全部 IF NOT EXISTS，幂等。
  static Future<void> _addPerformanceIndexes(Database database) async {
    // 列表默认排序：status + updated_at + id（keyset 分页同键续读）。
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipes_status_updated_id '
      'ON recipes(status, updated_at DESC, id DESC)',
    );
    // 收藏过滤 + 分页。
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipes_favorite_updated_id '
      'ON recipes(favorite, updated_at DESC, id DESC)',
    );
    // 食材按基础概念反查菜谱（推荐候选筛选）。
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_ingredients_base_recipe '
      'ON ingredients(base_concept_id, recipe_id)',
    );
    // 分类反向查询（分类筛选 EXISTS 子查询）。
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_relations_category_recipe '
      'ON recipe_category_relations(category_id, recipe_id)',
    );
  }

  /// schema v11（IMAGE-002 优化）：导入任务新增进度详情列，运行中实时展示
  /// 当前操作说明（如“正在识别第 2/3 张图片”“正在生成第 1/3 份草稿”）。
  static Future<void> _addProgressDetailColumn(Database database) async {
    await _addColumnsIfMissing(
      database,
      'import_tasks',
      const <String>{'progress_detail'},
      const <String, String>{'progress_detail': 'TEXT'},
    );
  }

  /// schema v12（IMPORT-011 修复）：放宽 import_tasks.source_platform 的
  /// CHECK 约束，允许 'web'。
  ///
  /// 背景：本地图片/文本导入（拍照选图、剪贴板）与通用网页导入使用占位
  /// URL，经 [ImportSourceLink.parse] 解析后平台值均为 web。旧约束只允许
  /// 'xiaohongshu'/'douyin'，导致创建任务时违反约束而失败。
  ///
  /// SQLite 不支持 ALTER COLUMN 修改 CHECK 约束，只能重建整表：
  /// 建新表（含 'web'）→ 按实际存在的列复制数据 → 删旧表 → 重命名 → 重建索引。
  /// import_tasks 无外键依赖关系，删除重建是安全的。
  static Future<void> _rebuildImportTasksTable(Database database) async {
    const newTable = 'import_tasks_new';
    // 失败重试时先清理残留的临时表，保证幂等。
    await database.execute('DROP TABLE IF EXISTS $newTable');

    // 1. 用新 schema（含 'web'）创建临时表，暂不建索引。
    await _createImportTaskTable(database, newTable);

    // 2. 复制数据：只复制旧表实际存在的列（老版本可能缺 v9/v11 新增列），
    //    缺失列由新表 DEFAULT/NULL 兜底；列名来自白名单交集，无注入风险。
    const allColumns = <String>{
      'id', 'source_url', 'normalized_url', 'source_platform', 'status',
      'stage', 'progress', 'attempt', 'max_attempts', 'error_code',
      'error_message', 'retryable', 'result_recipe_id',
      'additional_result_recipe_ids', 'progress_detail', 'created_at',
      'updated_at', 'started_at', 'completed_at', 'cancelled_at',
      'next_retry_at', 'local_version', 'deleted_at',
    };
    final oldColumns = (await database.rawQuery('PRAGMA table_info(import_tasks)'))
        .map((row) => row['name']! as String)
        .toSet();
    final columnList = allColumns.intersection(oldColumns).join(', ');
    await database.execute(
      'INSERT INTO $newTable ($columnList) '
      'SELECT $columnList FROM import_tasks',
    );

    // 3. 删除旧表（旧索引随表一起删除）并重命名新表。
    await database.execute('DROP TABLE import_tasks');
    await database.execute('ALTER TABLE $newTable RENAME TO import_tasks');

    // 4. 重建索引，与 _createImportTaskSchema 保持一致。
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

  /// schema v9（IMAGE-002，ADR-0029）：导入任务支持关联多个菜谱草稿
  /// （多图“每张图独立菜谱”一次导入产出多个草稿），JSON 数组列。
  static Future<void> _addAdditionalResultRecipeIdsColumn(
    Database database,
  ) async {
    await _addColumnsIfMissing(
      database,
      'import_tasks',
      const <String>{'additional_result_recipe_ids'},
      const <String, String>{
        "additional_result_recipe_ids": "TEXT NOT NULL DEFAULT '[]'",
      },
    );
  }

  /// schema v8（IMAGE-001）：本地设置新增图片识别方式列（识图引擎）。
  static Future<void> _addImageRecognitionModeColumn(Database database) async {
    await _addColumnsIfMissing(
      database,
      'local_app_settings',
      const <String>{'image_recognition_mode'},
      const <String, String>{
        "image_recognition_mode": "TEXT NOT NULL DEFAULT 'auto'",
      },
    );
  }

  /// schema v7：库存批次增加分区内排序权重列（长按拖动排序用）。
  static Future<void> _addInventorySortOrderColumn(Database database) async {
    await _addColumnsIfMissing(
      database,
      'inventory_batches',
      const <String>{'sort_order'},
      const <String, String>{'sort_order': 'INTEGER NOT NULL DEFAULT 0'},
    );
  }

  /// schema v6（ADR-0022）：给既有表补充食材规格列。
  ///
  /// SQLite 的 ADD COLUMN 不支持 IF NOT EXISTS，先读 PRAGMA table_info
  /// 只添加缺失的列，保证迁移幂等。
  static Future<void> _addSpecColumns(Database database) async {
    final ingredientColumns = <String>{
      'base_concept_id',
      'base_concept_name',
      'cut',
      'fat_level',
      'form',
      'processing',
      'spec_confidence',
      'spec_source',
    };
    final batchColumns = <String>{
      'base_concept_id',
      'base_concept_name',
      'cut',
      'fat_level',
      'form',
      'processing',
      'spec_source',
    };
    await _addColumnsIfMissing(
      database,
      'ingredients',
      ingredientColumns,
      <String, String>{
        'base_concept_id': 'TEXT',
        'base_concept_name': 'TEXT',
        'cut': 'TEXT',
        'fat_level': 'TEXT',
        'form': 'TEXT',
        'processing': 'TEXT',
        'spec_confidence': 'REAL',
        "spec_source": "TEXT NOT NULL DEFAULT 'unknown'",
      },
    );
    await _addColumnsIfMissing(
      database,
      'inventory_batches',
      batchColumns,
      <String, String>{
        'base_concept_id': 'TEXT',
        'base_concept_name': 'TEXT',
        'cut': 'TEXT',
        'fat_level': 'TEXT',
        'form': 'TEXT',
        'processing': 'TEXT',
        "spec_source": "TEXT NOT NULL DEFAULT 'unknown'",
      },
    );
  }

  static Future<void> _addColumnsIfMissing(
    Database database,
    String table,
    Set<String> expectedColumns,
    Map<String, String> definitions,
  ) async {
    final rows = await database.rawQuery('PRAGMA table_info($table)');
    final existing = rows.map((row) => row['name'] as String).toSet();
    for (final column in expectedColumns) {
      if (existing.contains(column)) continue;
      await database.execute(
        'ALTER TABLE $table ADD COLUMN $column ${definitions[column]}',
      );
    }
  }

  /// 创建冰箱库存批次与变更记录表（schema v5，FRIDGE-002/003）。
  static Future<void> _createInventorySchema(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_batches (
        id TEXT PRIMARY KEY NOT NULL,
        ingredient_name TEXT NOT NULL,
        normalized_ingredient_name TEXT,
        quantity REAL,
        unit TEXT,
        category TEXT,
        storage_location TEXT NOT NULL
          CHECK (storage_location IN (
            'chilled', 'frozen', 'roomTemperature', 'other'
          )),
        purchased_at INTEGER,
        expires_at INTEGER,
        note TEXT,
        base_concept_id TEXT,
        base_concept_name TEXT,
        cut TEXT,
        fat_level TEXT,
        form TEXT,
        processing TEXT,
        spec_source TEXT NOT NULL DEFAULT 'unknown',
        sort_order INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL
          CHECK (status IN ('available', 'usedUp', 'discarded')),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        local_version INTEGER NOT NULL CHECK (local_version >= 1),
        deleted_at INTEGER
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_batches_zone_status '
      'ON inventory_batches(storage_location, status, expires_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_batches_name '
      'ON inventory_batches(ingredient_name, status)',
    );

    await database.execute('''
      CREATE TABLE IF NOT EXISTS inventory_changes (
        id TEXT PRIMARY KEY NOT NULL,
        batch_id TEXT NOT NULL,
        change_type TEXT NOT NULL
          CHECK (change_type IN ('create', 'adjust', 'consume', 'usedUp', 'discard')),
        quantity_delta REAL,
        unit TEXT,
        related_recipe_id TEXT,
        confirmed_by_user INTEGER NOT NULL DEFAULT 0
          CHECK (confirmed_by_user IN (0, 1)),
        created_at INTEGER NOT NULL,
        FOREIGN KEY (batch_id) REFERENCES inventory_batches(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_changes_batch_time '
      'ON inventory_changes(batch_id, created_at)',
    );
  }

  /// 创建菜谱封面图片表（schema v4）。
  ///
  /// 一张菜谱可有多张封面图，按 sort_order 排列；图片存储在应用私有目录，
  /// 表中保存的是相对私有目录的文件路径。
  static Future<void> _createRecipeImagesSchema(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS recipe_images (
        recipe_id TEXT NOT NULL,
        image_path TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (recipe_id, sort_order),
        FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipe_images_recipe '
      'ON recipe_images(recipe_id, sort_order ASC)',
    );
  }

  /// 创建导入任务表（schema v2 引入，v12 放宽平台约束）。
  ///
  /// [tableName] 允许迁移时以临时表名重建；索引由调用方单独创建，
  /// 避免临时表与旧表产生同名索引冲突。
  static Future<void> _createImportTaskTable(
    Database database,
    String tableName,
  ) async {
    await database.execute('''
      CREATE TABLE $tableName (
        id TEXT PRIMARY KEY NOT NULL,
        source_url TEXT NOT NULL,
        normalized_url TEXT NOT NULL,
        source_platform TEXT NOT NULL
          CHECK (source_platform IN ('xiaohongshu', 'douyin', 'web')),
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
        additional_result_recipe_ids TEXT NOT NULL DEFAULT '[]',
        progress_detail TEXT,
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

  static Future<void> _createImportTaskSchema(Database database) async {
    await _createImportTaskTable(database, 'import_tasks');
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
    await _createImportTaskEvidenceSchema(database);
  }

  /// schema v13：原始内容依据持久化表（"原始内容依据"面板展示与复制）。
  ///
  /// 独立成表（task_id 主键），避免改动 import_tasks 主表结构与既有备份/哈希。
  static Future<void> _createImportTaskEvidenceSchema(
    Database database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS import_task_evidence (
        task_id TEXT PRIMARY KEY NOT NULL,
        evidence_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  static Future<void> _createLocalBusinessSchema(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS recipe_recent_views (
        recipe_id TEXT PRIMARY KEY NOT NULL,
        viewed_at INTEGER NOT NULL,
        FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_recipe_recent_views_time '
      'ON recipe_recent_views(viewed_at DESC)',
    );

    await database.execute('''
      CREATE TABLE IF NOT EXISTS local_app_settings (
        id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
        record_recipe_history INTEGER NOT NULL DEFAULT 1
          CHECK (record_recipe_history IN (0, 1)),
        allow_text_upload INTEGER NOT NULL DEFAULT 1
          CHECK (allow_text_upload IN (0, 1)),
        allow_image_upload INTEGER NOT NULL DEFAULT 0
          CHECK (allow_image_upload IN (0, 1)),
        allow_video_upload INTEGER NOT NULL DEFAULT 0
          CHECK (allow_video_upload IN (0, 1)),
        image_recognition_mode TEXT NOT NULL DEFAULT 'auto',
        updated_at INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS cooking_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        recipe_id TEXT NOT NULL,
        current_step_index INTEGER NOT NULL DEFAULT 0
          CHECK (current_step_index >= 0),
        status TEXT NOT NULL CHECK (status IN ('active', 'completed')),
        started_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY (recipe_id) REFERENCES recipes(id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cooking_sessions_recipe_status '
      'ON cooking_sessions(recipe_id, status, updated_at DESC)',
    );

    await database.execute('''
      CREATE TABLE IF NOT EXISTS cooking_timers (
        id TEXT PRIMARY KEY NOT NULL,
        session_id TEXT NOT NULL,
        label TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL CHECK (duration_seconds > 0),
        state TEXT NOT NULL
          CHECK (state IN ('running', 'paused', 'completed')),
        ends_at INTEGER,
        paused_remaining_seconds INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        FOREIGN KEY (session_id) REFERENCES cooking_sessions(id)
          ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cooking_timers_session '
      'ON cooking_timers(session_id, created_at ASC)',
    );
  }
}
