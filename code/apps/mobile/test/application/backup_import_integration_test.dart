import 'dart:convert';
import 'dart:io';

import 'package:ai_recipe/application/backup/backup_export_use_cases.dart';
import 'package:ai_recipe/application/backup/backup_import_use_cases.dart';
import 'package:ai_recipe/data/backup/device_backup_archive_reader.dart';
import 'package:ai_recipe/data/backup/device_backup_archive_writer.dart';
import 'package:ai_recipe/data/backup/device_backup_import_media_writer.dart';
import 'package:ai_recipe/data/backup/sqlite_backup_import_repository.dart';
import 'package:ai_recipe/data/backup/sqlite_backup_snapshot_repository.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/data/sqlite_recipe_repository.dart';
import 'package:ai_recipe/domain/backup/backup_cancellation_token.dart';
import 'package:ai_recipe/domain/backup/backup_errors.dart';
import 'package:ai_recipe/domain/backup/backup_import_plan.dart';
import 'package:ai_recipe/domain/backup/backup_import_repository.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 测试专用取消令牌：在第 [cancelAt] 次检查时自我取消。
///
/// 用于确定性模拟「执行中途（清库后、写入前）用户取消或失败」，
/// 避免依赖时序（Future.delayed）造成测试不稳定。
class _SelfCancellingToken extends BackupCancellationToken {
  _SelfCancellingToken({required this.cancelAt});

  /// 第几次 [throwIfCancelled] 检查时触发自我取消。
  final int cancelAt;
  int _checks = 0;

  @override
  void throwIfCancelled() {
    _checks += 1;
    if (_checks >= cancelAt) {
      cancel();
    }
    super.throwIfCancelled();
  }
}

/// 导入流水线集成测试（BACKUP-004/005）：真实 SQLite + 真实 ZIP 读写器。
///
/// 复现项目负责人反馈的「替换恢复后什么数据都没有」场景：
/// 创建备份 → 替换导入 → 重新读取菜谱库，验证数据真实落库并可读。
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late String mediaDirectory;
  late String outputDirectory;
  late String stagingDirectory;
  late String coverRoot;
  late DateTime now;

  /// 生成唯一图片文件并返回其路径。
  Future<String> writeImageFile(String name, List<int> bytes) async {
    final file = File(path.join(mediaDirectory, name));
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 预置：空分类 1 个 + 正式菜谱 1 个（封面 + 2 张画廊图）+ 软删除菜谱 1 个。
  Future<void> seedDatabase() async {
    final database = await appDatabase.database;
    final nowMs = now.toUtc().millisecondsSinceEpoch;
    await database.insert('recipe_categories', <String, Object?>{
      'id': 'cat-empty',
      'user_id': null,
      'name': '空分类',
      'cover_image': null,
      'sort_order': 0,
      'created_at': nowMs,
      'updated_at': nowMs,
      'local_version': 1,
      'deleted_at': null,
    });

    final coverBytes = utf8.encode('cover-bytes');
    final galleryABytes = utf8.encode('gallery-a-bytes');
    final coverPath = await writeImageFile('cover.jpg', coverBytes);
    final galleryAPath = await writeImageFile('gallery-a.jpg', galleryABytes);

    await database.insert('recipe_categories', <String, Object?>{
      'id': 'cat-published',
      'user_id': null,
      'name': '家常菜',
      'cover_image': null,
      'sort_order': 1,
      'created_at': nowMs,
      'updated_at': nowMs,
      'local_version': 1,
      'deleted_at': null,
    });

    await database.insert('recipes', <String, Object?>{
      'id': 'recipe-published',
      'user_id': null,
      'title': '番茄炒蛋',
      'description': '家常',
      'cover_image': coverPath,
      'servings': 2,
      'prep_time_minutes': 5,
      'cook_time_minutes': 10,
      'total_time_minutes': 15,
      'difficulty': 'easy',
      'notes': '少盐',
      'favorite': 1,
      'status': 'published',
      'source_id': null,
      'tags_json': jsonEncode(<String>['快手菜']),
      'created_at': nowMs,
      'updated_at': nowMs,
      'local_version': 3,
      'deleted_at': null,
    });
    await database.insert('recipe_category_relations', <String, Object?>{
      'recipe_id': 'recipe-published',
      'category_id': 'cat-published',
    });
    await database.insert('recipe_images', <String, Object?>{
      'recipe_id': 'recipe-published',
      'image_path': galleryAPath,
      'sort_order': 0,
    });
    await database.insert('ingredients', <String, Object?>{
      'id': 'ing-1',
      'recipe_id': 'recipe-published',
      'group_name': '主料',
      'name': '番茄',
      'quantity': '2',
      'unit': '个',
      'optional': 0,
      'preparation': '切块',
      'substitutes_json': '[]',
      'sort_order': 0,
      'confidence': 0.9,
      'base_concept_id': null,
      'base_concept_name': null,
      'cut': 'sliced',
      'fat_level': null,
      'form': null,
      'processing': null,
      'spec_confidence': null,
      'spec_source': 'user',
    });
    await database.insert('recipe_steps', <String, Object?>{
      'id': 'step-1',
      'recipe_id': 'recipe-published',
      'step_number': 1,
      'description': '翻炒',
      'duration_seconds': 60,
      'temperature': null,
      'heat_level': '中火',
      'cookware': '炒锅',
      'tips': null,
      'media_url': null,
      'confidence': 0.95,
    });

    // 回收站软删除菜谱（无图片）。
    await database.insert('recipes', <String, Object?>{
      'id': 'recipe-trashed',
      'user_id': null,
      'title': '已删除菜谱',
      'description': null,
      'cover_image': null,
      'servings': null,
      'prep_time_minutes': null,
      'cook_time_minutes': null,
      'total_time_minutes': null,
      'difficulty': 'medium',
      'notes': null,
      'favorite': 0,
      'status': 'published',
      'source_id': null,
      'tags_json': '[]',
      'created_at': nowMs,
      'updated_at': nowMs,
      'local_version': 1,
      'deleted_at': nowMs,
    });
  }

  /// 大数据 seed：生成 [total] 道菜谱（一半软删除回收站，各带封面 +
  /// 2 张画廊图 + 2 食材 + 2 步骤），复现用户「两千多条」规模场景。
  Future<void> seedLargeDatabase(int total) async {
    final database = await appDatabase.database;
    final nowMs = now.toUtc().millisecondsSinceEpoch;
    for (var i = 0; i < total; i++) {
      final trashed = i % 2 == 0;
      final id = 'recipe-large-$i';
      final coverPath = await writeImageFile(
        'cover-$i.jpg',
        utf8.encode('cover-$i-bytes'),
      );
      final galleryAPath = await writeImageFile(
        'gallery-$i-a.jpg',
        utf8.encode('gallery-$i-a-bytes'),
      );
      final galleryBPath = await writeImageFile(
        'gallery-$i-b.jpg',
        utf8.encode('gallery-$i-b-bytes'),
      );
      await database.insert('recipes', <String, Object?>{
        'id': id,
        'user_id': null,
        'title': '大菜谱 $i',
        'description': '描述 $i',
        'cover_image': coverPath,
        'servings': 2,
        'prep_time_minutes': 5,
        'cook_time_minutes': 10,
        'total_time_minutes': 15,
        'difficulty': 'easy',
        'notes': '备注 $i',
        'favorite': 0,
        'status': 'published',
        'source_id': null,
        'tags_json': jsonEncode(<String>['标签$i']),
        'created_at': nowMs,
        'updated_at': nowMs,
        'local_version': 1,
        'deleted_at': trashed ? nowMs : null,
      });
      await database.insert('recipe_images', <String, Object?>{
        'recipe_id': id,
        'image_path': galleryAPath,
        'sort_order': 0,
      });
      await database.insert('recipe_images', <String, Object?>{
        'recipe_id': id,
        'image_path': galleryBPath,
        'sort_order': 1,
      });
      await database.insert('ingredients', <String, Object?>{
        'id': 'ing-large-$i-0',
        'recipe_id': id,
        'group_name': '主料',
        'name': '食材$i-A',
        'quantity': '1',
        'unit': '个',
        'optional': 0,
        'preparation': null,
        'substitutes_json': '[]',
        'sort_order': 0,
        'confidence': 0.9,
        'base_concept_id': null,
        'base_concept_name': null,
        'cut': null,
        'fat_level': null,
        'form': null,
        'processing': null,
        'spec_confidence': null,
        'spec_source': 'user',
      });
      await database.insert('ingredients', <String, Object?>{
        'id': 'ing-large-$i-1',
        'recipe_id': id,
        'group_name': null,
        'name': '食材$i-B',
        'quantity': '2',
        'unit': '克',
        'optional': 1,
        'preparation': '切末',
        'substitutes_json': '["替代品"]',
        'sort_order': 1,
        'confidence': 0.8,
        'base_concept_id': null,
        'base_concept_name': null,
        'cut': 'sliced',
        'fat_level': 'low',
        'form': 'fresh',
        'processing': null,
        'spec_confidence': null,
        'spec_source': 'user',
      });
      await database.insert('recipe_steps', <String, Object?>{
        'id': 'step-large-$i-0',
        'recipe_id': id,
        'step_number': 1,
        'description': '步骤$i-1',
        'duration_seconds': 60,
        'temperature': null,
        'heat_level': null,
        'cookware': null,
        'tips': null,
        'media_url': null,
        'confidence': 0.9,
      });
      await database.insert('recipe_steps', <String, Object?>{
        'id': 'step-large-$i-1',
        'recipe_id': id,
        'step_number': 2,
        'description': '步骤$i-2',
        'duration_seconds': 120,
        'temperature': '180',
        'heat_level': '中火',
        'cookware': '炒锅',
        'tips': '小心烫',
        'media_url': null,
        'confidence': 0.9,
      });
    }
  }

  BackupExportUseCases buildExportUseCases() {
    return BackupExportUseCases(
      snapshotRepository: SqliteBackupSnapshotRepository(appDatabase),
      archiveWriter: DeviceBackupArchiveWriter(),
      outputDirectoryProvider: () async => outputDirectory,
      clock: () => now,
      appVersion: '1.0.0-test',
    );
  }

  BackupImportUseCases buildImportUseCases() {
    var id = 0;
    return BackupImportUseCases(
      archiveReader: DeviceBackupArchiveReader(),
      preflightRepository: SqliteBackupImportRepository(
        appDatabase,
        coverRootProvider: () async => Directory(coverRoot),
      ),
      commitRepository: SqliteBackupImportRepository(
        appDatabase,
        coverRootProvider: () async => Directory(coverRoot),
      ),
      mediaWriter: DeviceBackupImportMediaWriter(
        coverRootProvider: () async => Directory(coverRoot),
      ),
      exportUseCases: buildExportUseCases(),
      stagingDirectoryProvider: () async => stagingDirectory,
      idGenerator: () => 'import-${id += 1}',
    );
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_backup_import_',
    );
    databasePath = path.join(temporaryDirectory.path, 'backup.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    mediaDirectory = path.join(temporaryDirectory.path, 'media');
    outputDirectory = path.join(temporaryDirectory.path, 'backups');
    stagingDirectory = path.join(temporaryDirectory.path, 'staging');
    coverRoot = path.join(temporaryDirectory.path, 'covers');
    now = DateTime.utc(2026, 8, 7, 8);
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test('替换恢复：创建备份 → 替换导入 → 菜谱/分类/媒体真实落库可读', () async {
    await seedDatabase();

    // 1. 创建备份。
    final backup = await buildExportUseCases().createFullBackup();
    expect(backup.statistics.recipeTotal, 2);
    expect(File(backup.filePath).existsSync(), isTrue);

    // 2. 模拟替换：先清空当前库（替换模式内部也会做，这里显式清库以
    //    验证「清库后写入」路径，等价于用户库中已无数据再导入）。
    await SqliteBackupImportRepository(
      appDatabase,
      coverRootProvider: () async => Directory(coverRoot),
    ).clearLibrary();

    final importUseCases = buildImportUseCases();

    // 3. 预检：备份含 2 道菜谱（1 正式 + 1 软删除）。当前库已清空，
    //    与备份无任何相同记录，全部为新增。
    final preview = await importUseCases.previewImport(
      sourcePath: backup.filePath,
    );
    expect(preview.plan.addRecipes, 2);
    expect(preview.plan.addCategories, 2);
    expect(preview.plan.compatible, isTrue);

    // 4. 替换执行（用户选择「替换恢复」）。
    final result = await importUseCases.executeImport(
      sessionId: preview.sessionId,
      plan: preview.plan.copyWith(mode: BackupImportMode.replace),
    );
    expect(result.mode, BackupImportMode.replace);
    expect(result.writtenRecipes, 2);
    expect(result.writtenCategories, 2);
    expect(result.rollbackBackupPath, isNotNull);
    expect(File(result.rollbackBackupPath!).existsSync(), isTrue);

    // 5. 通过真实菜谱库仓库读取：正式列表 1 道、回收站 1 道、分类 2 个。
    final recipeRepository = SqliteRecipeRepository(appDatabase);
    final page = await recipeRepository.listRecipeSummaries();
    expect(page.items, hasLength(1));
    expect(page.items.single.title, '番茄炒蛋');
    final trash = await recipeRepository.listTrashSummaries();
    expect(trash, hasLength(1));
    expect(trash.single.title, '已删除菜谱');
    final categories = await recipeRepository.listCategories(
      includeDeleted: true,
    );
    expect(categories, hasLength(2));

    // 6. 完整读取正式菜谱：食材、步骤、图片、分类关系全部还原。
    final full = await recipeRepository.getRecipeById('recipe-published');
    expect(full, isNotNull);
    expect(full!.ingredients, hasLength(1));
    expect(full.ingredients.single.name, '番茄');
    expect(full.steps, hasLength(1));
    expect(full.steps.single.description, '翻炒');
    expect(full.images, hasLength(1));
    expect(full.coverImage, isNotNull);
    expect(
      File(full.coverImage!).existsSync(),
      isTrue,
      reason: '导入后封面媒体文件应真实落盘',
    );
    expect(full.categoryIds, <String>['cat-published']);
  });

  test('合并导入：备份与当前库相同记录全部跳过、不丢现有数据', () async {
    await seedDatabase();

    final backup = await buildExportUseCases().createFullBackup();

    final importUseCases = buildImportUseCases();

    final preview = await importUseCases.previewImport(
      sourcePath: backup.filePath,
    );
    // 当前库与备份完全一致：同 UUID 同内容全部跳过。
    expect(preview.plan.addRecipes, 0);
    expect(preview.plan.skipRecipes, 2);
    expect(preview.plan.skippedRecipeIds, <String>[
      'recipe-published',
      'recipe-trashed',
    ]);

    final result = await importUseCases.executeImport(
      sessionId: preview.sessionId,
      plan: preview.plan, // 默认 merge
    );
    // 回归：相同记录不得被当作新增写入（BACKUP-005 bug）。
    expect(result.writtenRecipes, 0);
    expect(result.writtenCategories, 0);

    // 现有数据完整保留。
    final recipeRepository = SqliteRecipeRepository(appDatabase);
    final page = await recipeRepository.listRecipeSummaries();
    expect(page.items, hasLength(1));
    expect(page.items.single.title, '番茄炒蛋');
  });

  test(
    '替换恢复（大数据）：120 道菜谱含回收站 + 图片，替换后全部真实落库',
    () async {
      await seedLargeDatabase(120);

      // 1. 创建备份（含软删除与图片）。
      final backup = await buildExportUseCases().createFullBackup();
      expect(backup.statistics.recipeTotal, 120);
      expect(backup.statistics.recipeByStatus['trashed'], 60);

      // 2. 模拟替换：先清空当前库。
      await SqliteBackupImportRepository(
        appDatabase,
        coverRootProvider: () async => Directory(coverRoot),
      ).clearLibrary();

      final importUseCases = buildImportUseCases();

      // 3. 预检：全部为新增。
      final preview = await importUseCases.previewImport(
        sourcePath: backup.filePath,
      );
      expect(preview.plan.addRecipes, 120);
      expect(preview.plan.compatible, isTrue);
      expect(preview.plan.mediaTotal, greaterThanOrEqualTo(120));

      // 4. 替换执行（用户选择「替换恢复」）。
      final result = await importUseCases.executeImport(
        sessionId: preview.sessionId,
        plan: preview.plan.copyWith(mode: BackupImportMode.replace),
      );
      expect(result.writtenRecipes, 120);
      expect(result.rollbackBackupPath, isNotNull);

      // 5. 读取验证：正式 60 道、回收站 60 道、封面图片落盘。
      final recipeRepository = SqliteRecipeRepository(appDatabase);
      final page = await recipeRepository.listRecipeSummaries(limit: 200);
      expect(page.items, hasLength(60));
      final trash = await recipeRepository.listTrashSummaries();
      expect(trash, hasLength(60));
      final full = await recipeRepository.getRecipeById('recipe-large-1');
      expect(full, isNotNull);
      expect(full!.coverImage, isNotNull);
      expect(File(full.coverImage!).existsSync(), isTrue);
      expect(full.images, hasLength(2));
      expect(full.ingredients, hasLength(2));
      expect(full.steps, hasLength(2));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    '替换执行中取消（模拟中断）：单事务保证清库后、写入前失败时原库完整保留',
    () async {
      await seedDatabase();

      // 1. 从当前库创建备份，并读取备份记录（与预检/执行同一数据源）。
      final backup = await buildExportUseCases().createFullBackup();
      final staged = await DeviceBackupArchiveReader().stage(
        BackupArchiveStageRequest(
          sourcePath: backup.filePath,
          sessionId: 'cancel-replace-test',
          stagingDirectory: stagingDirectory,
        ),
      );

      // 2. 媒体准备正常完成（对应替换流水线的 preparingMedia 阶段）。
      final mediaResult = await DeviceBackupImportMediaWriter(
        coverRootProvider: () async => Directory(coverRoot),
      ).stageMediaToCoverStorage(
        recipes: staged.recipes,
        categories: staged.categories,
        stagedMedia: staged.mediaEntries,
      );

      // 3. 取消点：applyImport 事务内第 3 次检查（清库 delete 完成后、
      //    写入第一条记录前）——确定性模拟用户取消或写入中途失败。
      //    事务整体回滚，原库必须完整保留（BACKUP-005 核心保证）。
      final token = _SelfCancellingToken(cancelAt: 3);
      await expectLater(
        SqliteBackupImportRepository(
          appDatabase,
          coverRootProvider: () async => Directory(coverRoot),
        ).applyImport(
          recipes: staged.recipes,
          categories: staged.categories,
          recipeMediaPaths: mediaResult.recipeMediaPaths,
          categoryCoverPaths: mediaResult.categoryCoverPaths,
          token: token,
          clearExisting: true,
        ),
        throwsA(isA<BackupOperationCancelledException>()),
      );

      // 4. 原库完整保留：正式 1、回收站 1、分类 2、封面与画廊文件仍在。
      final recipeRepository = SqliteRecipeRepository(appDatabase);
      final page = await recipeRepository.listRecipeSummaries();
      expect(page.items, hasLength(1));
      expect(page.items.single.title, '番茄炒蛋');
      final trash = await recipeRepository.listTrashSummaries();
      expect(trash, hasLength(1));
      final categories = await recipeRepository.listCategories(
        includeDeleted: true,
      );
      expect(categories, hasLength(2));
      final full = await recipeRepository.getRecipeById('recipe-published');
      expect(full, isNotNull);
      expect(full!.coverImage, isNotNull);
      expect(File(full.coverImage!).existsSync(), isTrue,
          reason: '替换取消后原库封面媒体文件必须保留');
      expect(full.images, hasLength(1));
      expect(File(full.images.single).existsSync(), isTrue,
          reason: '替换取消后原库画廊媒体文件必须保留');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('替换导入取消安全：executeImport 收到取消令牌时原库不受影响', () async {
    await seedDatabase();

    final backup = await buildExportUseCases().createFullBackup();
    final importUseCases = buildImportUseCases();

    final preview = await importUseCases.previewImport(
      sourcePath: backup.filePath,
    );
    // 当前库与备份完全一致：预检全部标记跳过（替换模式仍会执行写入）。
    expect(preview.plan.addRecipes, 0);
    expect(preview.plan.skipRecipes, 2);

    // 预取消：用户在任何修改发生前中断，必须抛取消异常且不误伤原库。
    final token = BackupCancellationToken()..cancel();
    await expectLater(
      importUseCases.executeImport(
        sessionId: preview.sessionId,
        plan: preview.plan.copyWith(mode: BackupImportMode.replace),
        token: token,
      ),
      throwsA(isA<BackupOperationCancelledException>()),
    );

    // 原库完整保留：正式 1、回收站 1、分类 2。
    final recipeRepository = SqliteRecipeRepository(appDatabase);
    final page = await recipeRepository.listRecipeSummaries();
    expect(page.items, hasLength(1));
    expect(page.items.single.title, '番茄炒蛋');
    final trash = await recipeRepository.listTrashSummaries();
    expect(trash, hasLength(1));
    final categories = await recipeRepository.listCategories(
      includeDeleted: true,
    );
    expect(categories, hasLength(2));
  });

  test('导入进度逐步上报：预检与替换执行阶段进度条实时前进', () async {
    await seedLargeDatabase(60);

    final backup = await buildExportUseCases().createFullBackup();
    final importUseCases = buildImportUseCases();

    // 预检阶段：staging（解压/解析/媒体校验）应上报带总量的进度，
    // 存在中间值且最终到达 100%，供预检页进度条实时前进。
    final previewEvents = <BackupImportProgress>[];
    final preview = await importUseCases.previewImport(
      sourcePath: backup.filePath,
      onProgress: previewEvents.add,
    );
    expect(preview.plan.compatible, isTrue);
    final previewMeasurable = previewEvents
        .where((event) => event.total > 0)
        .toList();
    expect(previewMeasurable, isNotEmpty);
    expect(
      previewMeasurable.any(
        (event) => event.fraction > 0 && event.fraction < 1,
      ),
      isTrue,
      reason: '预检阶段应出现中间进度，而不是只有 0 和 100%',
    );
    expect(previewMeasurable.last.fraction, 1.0);

    // 执行阶段（替换）：创建回滚备份/媒体准备/写库同样逐步上报。
    final executeEvents = <BackupImportProgress>[];
    final result = await importUseCases.executeImport(
      sessionId: preview.sessionId,
      plan: preview.plan.copyWith(mode: BackupImportMode.replace),
      onProgress: executeEvents.add,
    );
    expect(result.writtenRecipes, 60);

    // 有明确总量的阶段内 fraction 单调不减；存在中间值且最终到达 100%。
    final measurable = executeEvents
        .where((event) => event.total > 0)
        .toList();
    expect(measurable, isNotEmpty);
    expect(
      measurable.any((event) => event.fraction > 0 && event.fraction < 1),
      isTrue,
      reason: '执行阶段应出现中间进度，而不是进度一直 0 然后突然成功',
    );
    expect(measurable.last.fraction, 1.0);
    for (final stage in BackupImportStage.values) {
      final stageEvents = measurable
          .where((event) => event.stage == stage)
          .toList();
      for (var i = 1; i < stageEvents.length; i++) {
        expect(
          stageEvents[i].fraction,
          greaterThanOrEqualTo(stageEvents[i - 1].fraction),
          reason: '${stage.name} 阶段进度必须单调不减',
        );
      }
    }
  });
}
