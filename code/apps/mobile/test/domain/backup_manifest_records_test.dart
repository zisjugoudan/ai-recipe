import 'dart:convert';

import 'package:ai_recipe/domain/backup/backup_archive_constants.dart';
import 'package:ai_recipe/domain/backup/backup_errors.dart';
import 'package:ai_recipe/domain/backup/backup_manifest.dart';
import 'package:ai_recipe/domain/backup/backup_records.dart';
import 'package:ai_recipe/domain/ingredient/ingredient_spec.dart';
import 'package:ai_recipe/domain/recipe/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

/// 备份格式核心测试（BACKUP-002）：manifest 严格解析、NDJSON 记录
/// 编解码往返、内容寻址路径与版本常量。这些是导入端（BACKUP-004）
/// 依赖的稳定契约，必须先于 UI 验证。
void main() {
  group('BackupArchivePaths', () {
    test('媒体内容寻址路径：前两位分目录 + 完整哈希 + 扩展名', () {
      const sha256 =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      expect(
        BackupArchivePaths.mediaEntryPath(sha256, 'jpg'),
        'media/sha256/01/$sha256.jpg',
      );
    });

    test('哈希长度不足时抛格式异常（防路径注入）', () {
      expect(
        () => BackupArchivePaths.mediaEntryPath('abc', 'jpg'),
        throwsFormatException,
      );
    });
  });

  group('BackupManifest', () {
    BackupManifest sampleManifest() {
      return BackupManifest(
        formatVersion: 1,
        minimumReaderVersion: 1,
        createdAt: '2026-08-07T08:00:00.000Z',
        appVersion: '1.0.0',
        datasets: <BackupDatasetDescriptor>[
          BackupDatasetDescriptor(
            name: BackupDatasetName.recipes,
            schemaVersion: 1,
            recordCount: 1,
            byteSize: 120,
            sha256: 'a' * 64,
          ),
        ],
        media: const BackupMediaStatistics(count: 2, byteSize: 2048),
        statistics: const BackupContentStatistics(
          recipeTotal: 1,
          recipeByStatus: <String, int>{'published': 1},
          categoryTotal: 1,
          categoryEmpty: 0,
          mediaTotal: 2,
          mediaBytes: 2048,
          totalBytes: 4096,
        ),
      );
    }

    test('toJson → fromJson 往返保留全部字段', () {
      final manifest = sampleManifest();
      final decoded = BackupManifest.fromJson(
        jsonDecode(manifest.encode()) as Map<String, Object?>,
      );
      expect(decoded.formatVersion, 1);
      expect(decoded.minimumReaderVersion, 1);
      expect(decoded.createdAt, manifest.createdAt);
      expect(decoded.appVersion, manifest.appVersion);
      expect(decoded.datasets.single.name, BackupDatasetName.recipes);
      expect(decoded.datasets.single.sha256, 'a' * 64);
      expect(decoded.media.count, 2);
      expect(decoded.statistics.recipeTotal, 1);
      expect(decoded.statistics.recipeByStatus['published'], 1);
    });

    test('未知 Dataset 名称抛 formatNotSupported（防静默跳过）', () {
      final json = sampleManifest().toJson();
      (json['datasets'] as List<Object?>).add(
        <String, Object?>{
          'name': 'inventory',
          'schemaVersion': 1,
          'recordCount': 0,
          'byteSize': 0,
          'sha256': 'b' * 64,
        },
      );
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            BackupErrorCode.formatNotSupported,
          ),
        ),
      );
    });

    test('format 名不符抛 formatNotSupported（防误认其他 ZIP）', () {
      final json = sampleManifest().toJson()..['format'] = 'not-a-backup';
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            BackupErrorCode.formatNotSupported,
          ),
        ),
      );
    });

    test('reader 版本不足抛 formatNotSupported', () {
      final json = sampleManifest().toJson()..['formatVersion'] = 2;
      expect(
        () => BackupManifest.fromJson(json),
        throwsA(
          isA<BackupException>().having(
            (error) => error.code,
            'code',
            BackupErrorCode.formatNotSupported,
          ),
        ),
      );
    });

    test('非法 sha256 抛 FormatException', () {
      final json = sampleManifest().toJson();
      final dataset = (json['datasets'] as List<Object?>).single
          as Map<String, Object?>;
      dataset['sha256'] = 'not-a-hash';
      expect(() => BackupManifest.fromJson(json), throwsFormatException);
    });
  });

  group('RecipeBackupRecord 编解码', () {
    test('完整字段往返保留图片引用与排序', () {
      final record = RecipeBackupRecord(
        id: 'recipe-1',
        userId: 'user-1',
        title: '番茄炒蛋',
        description: '家常',
        coverImage: BackupMediaReference(sha256: 'c' * 64),
        images: <BackupMediaReference>[
          BackupMediaReference(sha256: 'd' * 64, sortOrder: 1),
        ],
        servings: 2,
        prepTimeMinutes: 5,
        cookTimeMinutes: 10,
        totalTimeMinutes: 15,
        difficulty: RecipeDifficulty.easy,
        notes: '少盐',
        favorite: true,
        status: RecipeStatus.published,
        sourceId: null,
        ingredients: <Ingredient>[
          Ingredient(
            id: 'ing-1',
            name: '番茄',
            quantity: '2',
            unit: '个',
            optional: false,
            preparation: '切块',
            substitutes: const <String>['圣女果'],
            sortOrder: 0,
            confidence: 0.9,
            baseConceptId: 'base-1',
            baseConceptName: '番茄',
            cut: IngredientCut.fromWireName('belly'),
            fatLevel: IngredientFatLevel.fromWireName('lean'),
            form: IngredientForm.fromWireName('whole'),
            processing: IngredientProcessing.fromWireName('raw'),
            specConfidence: 0.8,
            specSource: IngredientSpecSource.fromWireName('user'),
          ),
        ],
        steps: <RecipeStep>[
          RecipeStep(
            id: 'step-1',
            stepNumber: 1,
            description: '翻炒',
            durationSeconds: 60,
            temperature: '200°C',
            heatLevel: '中火',
            cookware: '炒锅',
            tips: '快炒',
            mediaUrl: null,
            confidence: 0.95,
          ),
        ],
        categoryIds: const <String>['cat-1'],
        tags: const <String>['快手菜'],
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 2),
        localVersion: 3,
        deletedAt: null,
      );

      final decoded = RecipeBackupRecord.fromJson(
        jsonDecode(record.encodeNdjson()) as Map<String, Object?>,
      );
      expect(decoded.id, record.id);
      expect(decoded.title, record.title);
      expect(decoded.coverImage?.sha256, 'c' * 64);
      expect(decoded.images.single.sortOrder, 1);
      expect(decoded.ingredients.single.cut, IngredientCut.belly);
      expect(decoded.ingredients.single.specSource, IngredientSpecSource.user);
      expect(decoded.steps.single.description, '翻炒');
      expect(decoded.categoryIds, <String>['cat-1']);
      expect(decoded.tags, <String>['快手菜']);
      expect(decoded.localVersion, 3);
      expect(decoded.deletedAt, isNull);
    });

    test('空图片/空食材/软删除往返保持原状', () {
      final record = RecipeBackupRecord(
        id: 'recipe-2',
        title: '空数据菜谱',
        coverImage: null,
        images: const <BackupMediaReference>[],
        difficulty: RecipeDifficulty.medium,
        status: RecipeStatus.draft,
        ingredients: const <Ingredient>[],
        steps: const <RecipeStep>[],
        categoryIds: const <String>[],
        tags: const <String>[],
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
        localVersion: 1,
        deletedAt: DateTime.utc(2026, 7, 3),
      );
      final decoded = RecipeBackupRecord.fromJson(
        jsonDecode(record.encodeNdjson()) as Map<String, Object?>,
      );
      expect(decoded.coverImage, isNull);
      expect(decoded.images, isEmpty);
      expect(decoded.ingredients, isEmpty);
      expect(decoded.deletedAt, isNotNull);
    });
  });

  group('CategoryBackupRecord 编解码', () {
    test('分类封面引用与空分类往返', () {
      final record = CategoryBackupRecord(
        id: 'cat-empty',
        userId: null,
        name: '空分类',
        coverImage: BackupMediaReference(sha256: 'e' * 64),
        sortOrder: 2,
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
        localVersion: 1,
        deletedAt: null,
      );
      final decoded = CategoryBackupRecord.fromJson(
        jsonDecode(record.encodeNdjson()) as Map<String, Object?>,
      );
      expect(decoded.id, 'cat-empty');
      expect(decoded.name, '空分类');
      expect(decoded.coverImage?.sha256, 'e' * 64);
      expect(decoded.sortOrder, 2);
    });
  });
}
