import 'dart:convert';
import 'dart:io';

import 'package:ai_recipe/application/backup/backup_export_use_cases.dart';
import 'package:ai_recipe/data/backup/device_backup_archive_writer.dart';
import 'package:ai_recipe/data/backup/sqlite_backup_snapshot_repository.dart';
import 'package:ai_recipe/data/local/app_database.dart';
import 'package:ai_recipe/domain/backup/backup_archive_constants.dart';
import 'package:ai_recipe/domain/backup/backup_cancellation_token.dart';
import 'package:ai_recipe/domain/backup/backup_errors.dart';
import 'package:ai_recipe/domain/backup/backup_manifest.dart';
import 'package:ai_recipe/domain/backup/backup_records.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 导出流水线集成测试（BACKUP-003）：真实 SQLite + 真实 ZIP 写入器。
///
/// 验证全链路：一致性快照（含软删除与空分类）→ 媒体 SHA-256 去重 →
/// NDJSON 编码 → 媒体索引 → Manifest → 归档写入（重读复核 + 原子发布）。
/// 媒体文件缺失时备份失败并清理半成品，不交付不完整归档。
void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temporaryDirectory;
  late String databasePath;
  late AppDatabase appDatabase;
  late SqliteBackupSnapshotRepository snapshotRepository;
  late DeviceBackupArchiveWriter archiveWriter;
  late String mediaDirectory;
  late String outputDirectory;
  late String backupFilePath;
  late DateTime now;

  /// 生成唯一图片文件并返回其路径。
  Future<String> writeImageFile(String name, List<int> bytes) async {
    final file = File(path.join(mediaDirectory, name));
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 预置：空分类 1 个 + 正式菜谱 1 个（封面 + 2 张画廊图，画廊中一张
  /// 与封面同内容验证去重）+ 草稿菜谱 1 个（回收站软删除）。
  Future<void> seedDatabase() async {
    final database = await appDatabase.database;
    // 空分类。
    await database.insert('recipe_categories', <String, Object?>{
      'id': 'cat-empty',
      'user_id': null,
      'name': '空分类',
      'cover_image': null,
      'sort_order': 0,
      'created_at': now.toUtc().millisecondsSinceEpoch,
      'updated_at': now.toUtc().millisecondsSinceEpoch,
      'local_version': 1,
      'deleted_at': null,
    });

    final coverBytes = utf8.encode('cover-bytes');
    final galleryABytes = utf8.encode('gallery-a-bytes');
    final coverPath = await writeImageFile('cover.jpg', coverBytes);
    final galleryAPath = await writeImageFile('gallery-a.jpg', galleryABytes);
    final galleryBPath = await writeImageFile('gallery-b.jpg', coverBytes);

    // 正式菜谱所属分类（外键级联开启后必须先建分类再建关系）。
    await database.insert('recipe_categories', <String, Object?>{
      'id': 'cat-published',
      'user_id': null,
      'name': '家常菜',
      'cover_image': null,
      'sort_order': 1,
      'created_at': now.toUtc().millisecondsSinceEpoch,
      'updated_at': now.toUtc().millisecondsSinceEpoch,
      'local_version': 1,
      'deleted_at': null,
    });

    // 正式菜谱：封面 + 画廊图（含与封面同内容的 gallery-b）。
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
      'source_id': 'https://example.com/xhs/1',
      'tags_json': jsonEncode(<String>['快手菜']),
      'created_at': now.toUtc().millisecondsSinceEpoch,
      'updated_at': now.toUtc().millisecondsSinceEpoch,
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
    await database.insert('recipe_images', <String, Object?>{
      'recipe_id': 'recipe-published',
      'image_path': galleryBPath,
      'sort_order': 1,
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
      'created_at': now.toUtc().millisecondsSinceEpoch,
      'updated_at': now.toUtc().millisecondsSinceEpoch,
      'local_version': 1,
      'deleted_at': now.toUtc().millisecondsSinceEpoch,
    });
  }

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'ai_recipe_backup_export_',
    );
    databasePath = path.join(temporaryDirectory.path, 'backup.db');
    appDatabase = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    snapshotRepository = SqliteBackupSnapshotRepository(appDatabase);
    archiveWriter = DeviceBackupArchiveWriter();
    mediaDirectory = path.join(temporaryDirectory.path, 'media');
    outputDirectory = path.join(temporaryDirectory.path, 'backups');
    now = DateTime.utc(2026, 8, 7, 8);
    backupFilePath = '';
  });

  tearDown(() async {
    await appDatabase.close();
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  BackupExportUseCases buildUseCases() {
    return BackupExportUseCases(
      snapshotRepository: snapshotRepository,
      archiveWriter: archiveWriter,
      outputDirectoryProvider: () async => outputDirectory,
      clock: () => now,
      appVersion: '1.0.0-test',
    );
  }

  test('全量导出：归档包含清单、双 Dataset、媒体索引与去重媒体文件', () async {
    await seedDatabase();
    final useCases = buildUseCases();

    // 1. 预估：菜谱 2（含回收站）、分类 2（含空分类）、媒体按路径去重 3 张。
    final estimate = await useCases.estimate();
    expect(estimate.recipeTotal, 2);
    expect(estimate.categoryTotal, 2);
    expect(estimate.categoryEmpty, 1);
    expect(estimate.mediaTotal, 3);
    expect(estimate.estimatedTotalBytes, greaterThan(0));

    // 2. 创建全量备份。
    final result = await useCases.createFullBackup();
    backupFilePath = result.filePath;
    expect(result.fileName, endsWith(backupFileExtension));
    expect(result.byteSize, greaterThan(0));
    expect(result.statistics.recipeTotal, 2);
    expect(result.statistics.recipeByStatus['published'], 1);
    expect(result.statistics.recipeByStatus['trashed'], 1);
    expect(result.statistics.categoryTotal, 2);
    expect(result.statistics.categoryEmpty, 1);
    // 封面与 gallery-b 内容相同 → 去重后唯一媒体 2 个。
    expect(result.statistics.mediaTotal, 2);

    // 3. 归档文件确实以最终名存在（原子发布完成，无 .partial 残留）。
    expect(File(result.filePath).existsSync(), isTrue);
    expect(File('$backupFilePath.partial').existsSync(), isFalse);

    // 4. 解压复核：必需条目齐全。
    final bytes = File(backupFilePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final byName = <String, ArchiveFile>{
      for (final file in archive.files) file.name: file,
    };
    expect(
      byName.keys,
      containsAll(<String>[
        BackupArchivePaths.manifestFile,
        BackupArchivePaths.recipesDataset,
        BackupArchivePaths.categoriesDataset,
        BackupArchivePaths.mediaIndexFile,
      ]),
    );

    // 5. Manifest 解析：版本、统计与媒体统计一致。
    final manifest = BackupManifest.fromJson(
      jsonDecode(
        utf8.decode(byName[BackupArchivePaths.manifestFile]!.content),
      ) as Map<String, Object?>,
    );
    expect(manifest.formatVersion, 1);
    expect(manifest.appVersion, '1.0.0-test');
    expect(manifest.datasets.length, 2);
    expect(manifest.datasets.first.name, BackupDatasetName.recipes);
    expect(manifest.datasets.first.schemaVersion, 1);
    expect(manifest.datasets.first.recordCount, 2);
    expect(manifest.datasets[1].name, BackupDatasetName.categories);
    expect(manifest.datasets[1].recordCount, 2);
    expect(manifest.media.count, 2);
    expect(manifest.statistics.recipeTotal, 2);

    // 6. 菜谱 Dataset：软删除菜谱含 deletedAt，图片引用为 sha256。
    final recipeLines = utf8
        .decode(byName[BackupArchivePaths.recipesDataset]!.content)
        .trim()
        .split('\n');
    expect(recipeLines, hasLength(2));
    final publishedRecord = RecipeBackupRecord.fromJson(
      jsonDecode(recipeLines[0]) as Map<String, Object?>,
    );
    expect(publishedRecord.id, 'recipe-published');
    expect(publishedRecord.title, '番茄炒蛋');
    expect(publishedRecord.coverImage?.sha256, hasLength(64));
    expect(publishedRecord.images, hasLength(2));
    // 封面与 gallery-b 同内容 → 引用同一 sha256。
    expect(
      publishedRecord.coverImage?.sha256,
      publishedRecord.images[1].sha256,
    );
    final trashedRecord = RecipeBackupRecord.fromJson(
      jsonDecode(recipeLines[1]) as Map<String, Object?>,
    );
    expect(trashedRecord.id, 'recipe-trashed');
    expect(trashedRecord.deletedAt, isNotNull);

    // 7. 分类 Dataset：空分类保留（共 2 个，空分类排序在前）。
    final categoryLines = utf8
        .decode(byName[BackupArchivePaths.categoriesDataset]!.content)
        .trim()
        .split('\n');
    expect(categoryLines, hasLength(2));
    final categoryRecord = CategoryBackupRecord.fromJson(
      jsonDecode(categoryLines[0]) as Map<String, Object?>,
    );
    expect(categoryRecord.id, 'cat-empty');
    expect(categoryRecord.name, '空分类');
    final publishedCategory = CategoryBackupRecord.fromJson(
      jsonDecode(categoryLines[1]) as Map<String, Object?>,
    );
    expect(publishedCategory.id, 'cat-published');
    expect(publishedCategory.name, '家常菜');

    // 8. 媒体索引：2 个唯一条目，引用关系完整。
    final indexLines = utf8
        .decode(byName[BackupArchivePaths.mediaIndexFile]!.content)
        .trim()
        .split('\n');
    expect(indexLines, hasLength(2));
    final indexEntries = indexLines
        .map(
          (line) => BackupMediaIndexEntry.fromJson(
            jsonDecode(line) as Map<String, Object?>,
          ),
        )
        .toList();
    final coverEntry = indexEntries.firstWhere(
      (entry) => entry.recipeRefs.contains('recipe-published'),
    );
    expect(coverEntry.mime, 'image/jpeg');
    expect(coverEntry.recipeRefs, <String>['recipe-published']);

    // 9. 归档内媒体条目与索引一致（2 个唯一文件）。
    final mediaEntries = archive.files
        .where((file) => file.name.startsWith(BackupArchivePaths.mediaRoot))
        .toList();
    expect(mediaEntries, hasLength(2));
    for (final entry in indexEntries) {
      expect(byName.containsKey(entry.relativeKey), isTrue);
      expect(sha256.convert(byName[entry.relativeKey]!.content).toString(),
          entry.sha256);
    }
  });

  test('媒体文件缺失：备份失败、不生成最终归档并清理半成品', () async {
    await seedDatabase();
    final useCases = buildUseCases();

    // 删除一张必需图片，使校验失败。
    final missing = File(
      path.join(mediaDirectory, 'gallery-a.jpg'),
    );
    await missing.delete();

    await expectLater(
      useCases.createFullBackup(),
      throwsA(
        isA<BackupException>().having(
          (error) => error.code,
          'code',
          BackupErrorCode.mediaMissing,
        ),
      ),
    );
    // 未交付任何最终归档，也无 .partial 残留。
    expect(Directory(outputDirectory).existsSync(), isFalse);
  });

  test('创建前取消：抛取消异常且不写任何文件', () async {
    await seedDatabase();
    final useCases = buildUseCases();
    final token = BackupCancellationToken();
    token.cancel();
    await expectLater(
      useCases.createFullBackup(token: token),
      throwsA(isA<BackupOperationCancelledException>()),
    );
    expect(Directory(outputDirectory).existsSync(), isFalse);
  });

  test('回收站菜谱与空分类完整纳入统计（导出再导出幂等）', () async {
    await seedDatabase();
    final useCases = buildUseCases();
    final first = await useCases.createFullBackup();
    // 推进时钟 1 毫秒，使第二次导出生成不同文件名（生产时钟为真实时间）。
    now = now.add(const Duration(milliseconds: 1));
    final second = await useCases.createFullBackup();
    expect(first.statistics.recipeTotal, second.statistics.recipeTotal);
    expect(first.statistics.categoryTotal, second.statistics.categoryTotal);
    expect(first.statistics.mediaTotal, second.statistics.mediaTotal);
    // 两次导出生成不同文件名（毫秒级时间戳），互不覆盖。
    expect(first.filePath, isNot(second.filePath));
  });
}
