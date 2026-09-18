import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../domain/backup/backup_archive_constants.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../domain/backup/backup_errors.dart';
import '../../domain/backup/backup_manifest.dart';
import '../../domain/backup/backup_records.dart';
import '../../domain/backup/backup_repository.dart';
import '../../domain/recipe/recipe.dart';

/// 备份导出预估（创建前展示给用户的空间与规模预期）。
class BackupEstimate {
  const BackupEstimate({
    required this.recipeTotal,
    required this.categoryTotal,
    required this.categoryEmpty,
    required this.mediaTotal,
    required this.mediaBytes,
    required this.estimatedTotalBytes,
  });

  final int recipeTotal;
  final int categoryTotal;
  final int categoryEmpty;
  final int mediaTotal;
  final int mediaBytes;
  final int estimatedTotalBytes;
}

/// 导出阶段（UI 进度展示用）。
enum BackupExportStage {
  /// 读取一致性快照。
  snapshot,

  /// 校验媒体文件并计算 SHA-256。
  hashing,

  /// 写入归档。
  writing,

  /// 重读归档复核。
  verifying,
}

/// 导出进度回调。
class BackupExportProgress {
  const BackupExportProgress({
    required this.stage,
    this.processed = 0,
    this.total = 0,
    this.detail = '',
  });

  final BackupExportStage stage;
  final int processed;
  final int total;
  final String detail;

  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0, 1);
}

/// 导出结果。
class BackupExportResult {
  const BackupExportResult({
    required this.filePath,
    required this.fileName,
    required this.byteSize,
    required this.statistics,
  });

  final String filePath;
  final String fileName;
  final int byteSize;
  final BackupContentStatistics statistics;
}

/// 创建全量备份用例（BACKUP-003）。
///
/// 流水线：一致性快照 → 统计与空间预估 → 媒体可读性与哈希 → 组装
/// NDJSON Dataset → 生成媒体索引 → 构造 Manifest → 归档写入（含重读
/// 复核）→ 原子发布。任一步失败或取消都会让写入器清理半成品，
/// 不向用户交付不完整备份。
class BackupExportUseCases {
  BackupExportUseCases({
    required BackupSnapshotRepository snapshotRepository,
    required BackupArchiveWriter archiveWriter,
    required Future<String> Function() outputDirectoryProvider,
    required DateTime Function() clock,
    required String appVersion,
  }) : _snapshotRepository = snapshotRepository,
       _archiveWriter = archiveWriter,
       _outputDirectoryProvider = outputDirectoryProvider,
       _clock = clock,
       _appVersion = appVersion;

  final BackupSnapshotRepository _snapshotRepository;
  final BackupArchiveWriter _archiveWriter;
  final Future<String> Function() _outputDirectoryProvider;
  final DateTime Function() _clock;
  final String _appVersion;

  /// 统计与空间预估（不哈希媒体，仅读取文件大小）。
  Future<BackupEstimate> estimate({BackupCancellationToken? token}) async {
    final snapshot = await _snapshotRepository.loadSnapshot(token: token);
    final categoryEmpty = _countEmptyCategories(snapshot);

    var mediaBytes = 0;
    var mediaTotal = 0;
    final seenPaths = <String>{};
    for (final media in snapshot.media) {
      if (seenPaths.contains(media.sourcePath)) continue;
      seenPaths.add(media.sourcePath);
      mediaTotal += 1;
      try {
        mediaBytes += await _snapshotRepository.mediaFileSize(
          media.sourcePath,
        );
      } on BackupException {
        // 预估容忍缺失/不可读媒体：缺失文件按 0 体积计入，
        // 创建备份时才严格失败（见验收 4.4），避免脏路径卡死预估页。
      }
    }
    // 数据体积 + 媒体体积 + 10% 元数据开销的保守预估。
    final dataBytes = _estimateDataBytes(snapshot);
    final estimatedTotalBytes =
        dataBytes + mediaBytes + ((dataBytes + mediaBytes) * 0.1).ceil();
    return BackupEstimate(
      recipeTotal: snapshot.recipes.length,
      categoryTotal: snapshot.categories.length,
      categoryEmpty: categoryEmpty,
      mediaTotal: mediaTotal,
      mediaBytes: mediaBytes,
      estimatedTotalBytes: estimatedTotalBytes,
    );
  }

  /// 创建全量备份，返回最终归档路径与统计。
  ///
  /// [token] 取消：快照、校验、组装阶段即时响应；ZIP 写入与复核阶段
  /// 完成后统一清理并抛取消（见 DeviceBackupArchiveWriter 说明）。
  /// [outputFileName] 缺省时按当前时间自动命名；替换模式（BACKUP-005）
  /// 用它注入固定前缀的回滚备份文件名。
  Future<BackupExportResult> createFullBackup({
    BackupCancellationToken? token,
    void Function(BackupExportProgress)? onProgress,
    String? outputFileName,
  }) async {
    token?.throwIfCancelled();

    // 1. 一致性快照。
    onProgress?.call(const BackupExportProgress(
      stage: BackupExportStage.snapshot,
      detail: '正在读取菜谱数据…',
    ));
    final snapshot = await _snapshotRepository.loadSnapshot(token: token);

    // 2. 媒体校验 + SHA-256 去重。
    final uniqueMedia = _uniqueMediaByPath(snapshot.media);
    onProgress?.call(BackupExportProgress(
      stage: BackupExportStage.hashing,
      processed: 0,
      total: uniqueMedia.length,
      detail: '正在校验 ${uniqueMedia.length} 张图片…',
    ));
    // path → (sha256, byteSize, extension)。
    final hashedMedia = <String, _HashedMedia>{};
    for (final entry in uniqueMedia.indexed) {
      token?.throwIfCancelled();
      final media = entry.$2;
      final byteSize = await _snapshotRepository.mediaFileSize(
        media.sourcePath,
      );
      if (byteSize <= 0) {
        throw BackupException(
          BackupErrorCode.mediaMissing,
          '图片内容为空，无法备份：${media.sourcePath}',
        );
      }
      final sha256 = await _snapshotRepository.hashMediaFile(media.sourcePath);
      hashedMedia[media.sourcePath] = _HashedMedia(
        sha256: sha256,
        byteSize: byteSize,
        extension: _normalizeExtension(media.sourcePath),
        sourcePath: media.sourcePath,
      );
      if (entry.$1 % 10 == 0 || entry.$1 == uniqueMedia.length - 1) {
        onProgress?.call(BackupExportProgress(
          stage: BackupExportStage.hashing,
          processed: entry.$1 + 1,
          total: uniqueMedia.length,
          detail: '已校验 ${entry.$1 + 1}/${uniqueMedia.length} 张图片',
        ));
      }
    }

    // 3. 组装 NDJSON Dataset。
    token?.throwIfCancelled();
    final recipesBytes = _encodeRecipes(snapshot.recipes, hashedMedia);
    final categoriesBytes = _encodeCategories(
      snapshot.categories,
      hashedMedia,
    );

    // 按 sha256 内容寻址去重：同一内容只写一个归档条目。
    // hashedMedia 是 path → 哈希 映射（编码引用时需按原路径查找），
    // 归档写入/统计/媒体数则必须按内容去重，否则 ZIP 内同名条目
    // （media/sha256/<sha>.<ext>）互相覆盖导致条目数与预期不符。
    final uniqueMediaBySha = <String, _HashedMedia>{
      for (final item in hashedMedia.values) item.sha256: item,
    };

    // 4. 媒体索引（按 sha256 聚合引用）。
    final mediaIndexBytes = _encodeMediaIndex(snapshot.media, hashedMedia);

    // 5. 统计（媒体按内容去重后的唯一集合）。
    final statistics = _buildStatistics(snapshot, uniqueMediaBySha);

    // 6. Manifest。
    final manifest = BackupManifest(
      formatVersion: backupFormatVersion,
      minimumReaderVersion: backupMinimumReaderVersion,
      createdAt: _clock().toUtc().toIso8601String(),
      appVersion: _appVersion,
      datasets: <BackupDatasetDescriptor>[
        BackupDatasetDescriptor(
          name: BackupDatasetName.recipes,
          schemaVersion: 1,
          recordCount: snapshot.recipes.length,
          byteSize: recipesBytes.length,
          sha256: _sha256Hex(recipesBytes),
        ),
        BackupDatasetDescriptor(
          name: BackupDatasetName.categories,
          schemaVersion: 1,
          recordCount: snapshot.categories.length,
          byteSize: categoriesBytes.length,
          sha256: _sha256Hex(categoriesBytes),
        ),
      ],
      media: BackupMediaStatistics(
        count: uniqueMediaBySha.length,
        byteSize: statistics.mediaBytes,
      ),
      statistics: statistics,
    );

    // 7. 写入归档（写入器内部完成重读复核与原子发布）。
    onProgress?.call(BackupExportProgress(
      stage: BackupExportStage.writing,
      detail: '正在写入备份文件…',
    ));
    final fileName = outputFileName ?? _backupFileName(_clock());
    final receipt = await _archiveWriter.write(
      BackupWriteRequest(
        manifest: manifest,
        datasets: <String, List<int>>{
          BackupArchivePaths.recipesDataset: recipesBytes,
          BackupArchivePaths.categoriesDataset: categoriesBytes,
        },
        mediaIndexBytes: mediaIndexBytes,
        mediaFiles: _mediaFilesToWrite(uniqueMediaBySha),
        outputDirectory: await _outputDirectoryProvider(),
        outputFileName: fileName,
      ),
    );

    onProgress?.call(BackupExportProgress(
      stage: BackupExportStage.verifying,
      detail: '正在复核备份文件…',
    ));
    return BackupExportResult(
      filePath: receipt.filePath,
      fileName: fileName,
      byteSize: receipt.byteSize,
      statistics: statistics,
    );
  }

  /// 路径去重（同路径只哈希/写一次，但引用关系全部保留）。
  static List<BackupSnapshotMedia> _uniqueMediaByPath(
    List<BackupSnapshotMedia> media,
  ) {
    final seen = <String>{};
    final result = <BackupSnapshotMedia>[];
    for (final item in media) {
      if (seen.contains(item.sourcePath)) continue;
      seen.add(item.sourcePath);
      result.add(item);
    }
    return result;
  }

  /// 编码菜谱 NDJSON（图片路径替换为内容寻址引用）。
  static List<int> _encodeRecipes(
    List<Recipe> recipes,
    Map<String, _HashedMedia> hashedMedia,
  ) {
    final buffer = StringBuffer();
    for (final recipe in recipes) {
      final record = _toRecipeBackupRecord(recipe, hashedMedia);
      buffer
        ..write(record.encodeNdjson())
        ..write('\n');
    }
    return utf8.encode(buffer.toString());
  }

  static RecipeBackupRecord _toRecipeBackupRecord(
    Recipe recipe,
    Map<String, _HashedMedia> hashedMedia,
  ) {
    BackupMediaReference? coverReference;
    final cover = recipe.coverImage;
    if (cover != null && cover.trim().isNotEmpty) {
      final hashed = hashedMedia[cover];
      if (hashed != null) {
        coverReference = BackupMediaReference(sha256: hashed.sha256);
      }
    }
    final images = <BackupMediaReference>[];
    for (final entry in recipe.images.indexed) {
      final imagePath = entry.$2;
      if (imagePath.trim().isEmpty) continue;
      final hashed = hashedMedia[imagePath];
      if (hashed == null) {
        throw BackupException(
          BackupErrorCode.mediaMissing,
          '菜谱「${recipe.title}」的图片无法校验：$imagePath',
        );
      }
      images.add(
        BackupMediaReference(sha256: hashed.sha256, sortOrder: entry.$1),
      );
    }
    return RecipeBackupRecord(
      id: recipe.id,
      userId: recipe.userId,
      title: recipe.title,
      description: recipe.description,
      coverImage: coverReference,
      images: images,
      servings: recipe.servings,
      prepTimeMinutes: recipe.prepTimeMinutes,
      cookTimeMinutes: recipe.cookTimeMinutes,
      totalTimeMinutes: recipe.totalTimeMinutes,
      difficulty: recipe.difficulty,
      notes: recipe.notes,
      favorite: recipe.favorite,
      status: recipe.status,
      sourceId: recipe.sourceId,
      ingredients: recipe.ingredients,
      steps: recipe.steps,
      categoryIds: recipe.categoryIds,
      tags: recipe.tags,
      createdAt: recipe.createdAt,
      updatedAt: recipe.updatedAt,
      localVersion: recipe.localVersion,
      deletedAt: recipe.deletedAt,
    );
  }

  static List<int> _encodeCategories(
    List<RecipeCategory> categories,
    Map<String, _HashedMedia> hashedMedia,
  ) {
    final buffer = StringBuffer();
    for (final category in categories) {
      BackupMediaReference? coverReference;
      final cover = category.coverImage;
      if (cover != null && cover.trim().isNotEmpty) {
        final hashed = hashedMedia[cover];
        if (hashed != null) {
          coverReference = BackupMediaReference(sha256: hashed.sha256);
        }
      }
      final record = CategoryBackupRecord(
        id: category.id,
        userId: category.userId,
        name: category.name,
        coverImage: coverReference,
        sortOrder: category.sortOrder,
        createdAt: category.createdAt,
        updatedAt: category.updatedAt,
        localVersion: category.localVersion,
        deletedAt: category.deletedAt,
      );
      buffer
        ..write(record.encodeNdjson())
        ..write('\n');
    }
    return utf8.encode(buffer.toString());
  }

  /// 生成媒体索引 NDJSON：按 sha256 聚合全部引用位置。
  static List<int> _encodeMediaIndex(
    List<BackupSnapshotMedia> media,
    Map<String, _HashedMedia> hashedMedia,
  ) {
    final bySha = <String, _MediaIndexAccumulator>{};
    for (final item in media) {
      final hashed = hashedMedia[item.sourcePath];
      if (hashed == null) {
        throw BackupException(
          BackupErrorCode.mediaMissing,
          '图片缺少哈希结果：${item.sourcePath}',
        );
      }
      final accumulator = bySha.putIfAbsent(hashed.sha256, () {
        return _MediaIndexAccumulator(
          sha256: hashed.sha256,
          byteSize: hashed.byteSize,
          mime: _mimeForExtension(hashed.extension),
          relativeKey: BackupArchivePaths.mediaEntryPath(
            hashed.sha256,
            hashed.extension,
          ),
        );
      });
      switch (item.role) {
        case BackupMediaRole.categoryCover:
          if (item.ownerId != null) {
            accumulator.categoryRefs.add(item.ownerId!);
          }
        case BackupMediaRole.cover:
        case BackupMediaRole.gallery:
          if (item.ownerId != null) {
            accumulator.recipeRefs.add(item.ownerId!);
          }
      }
    }
    final buffer = StringBuffer();
    for (final entry in bySha.values) {
      final indexEntry = BackupMediaIndexEntry(
        sha256: entry.sha256,
        mime: entry.mime,
        byteSize: entry.byteSize,
        relativeKey: entry.relativeKey,
        recipeRefs: entry.recipeRefs.toSet().toList(),
        categoryRefs: entry.categoryRefs.toSet().toList(),
      );
      buffer
        ..write(const JsonEncoder().convert(indexEntry.toJson()))
        ..write('\n');
    }
    return utf8.encode(buffer.toString());
  }

  static BackupContentStatistics _buildStatistics(
    BackupSnapshot snapshot,
    Map<String, _HashedMedia> uniqueMedia,
  ) {
    final byStatus = <String, int>{
      'published': 0,
      'draft': 0,
      'archived': 0,
      'trashed': 0,
    };
    for (final recipe in snapshot.recipes) {
      final key = recipe.deletedAt != null ? 'trashed' : recipe.status.wireName;
      byStatus[key] = byStatus[key]! + 1;
    }
    final categoryEmpty = _countEmptyCategories(snapshot);
    final mediaBytes =
        uniqueMedia.values.fold<int>(0, (sum, item) => sum + item.byteSize);
    final dataBytes = _estimateDataBytes(snapshot);
    return BackupContentStatistics(
      recipeTotal: snapshot.recipes.length,
      recipeByStatus: byStatus,
      categoryTotal: snapshot.categories.length,
      categoryEmpty: categoryEmpty,
      mediaTotal: uniqueMedia.length,
      mediaBytes: mediaBytes,
      totalBytes:
          dataBytes + mediaBytes + ((dataBytes + mediaBytes) * 0.1).ceil(),
    );
  }

  /// 空分类数量：未被任何菜谱引用的分类（包括空分类与软删除分类）。
  static int _countEmptyCategories(BackupSnapshot snapshot) {
    final referenced = <String>{};
    for (final recipe in snapshot.recipes) {
      referenced.addAll(recipe.categoryIds);
    }
    return snapshot.categories
        .where((category) => !referenced.contains(category.id))
        .length;
  }

  /// 数据体量粗略预估（NDJSON 每行约 1KB 量级，按记录数估算）。
  static int _estimateDataBytes(BackupSnapshot snapshot) {
    final ingredientCount = snapshot.recipes.fold<int>(
      0,
      (sum, recipe) => sum + recipe.ingredients.length,
    );
    final stepCount = snapshot.recipes.fold<int>(
      0,
      (sum, recipe) => sum + recipe.steps.length,
    );
    return snapshot.recipes.length * 1024 +
        snapshot.categories.length * 256 +
        ingredientCount * 128 +
        stepCount * 128;
  }

  static List<BackupMediaFileToWrite> _mediaFilesToWrite(
    Map<String, _HashedMedia> hashedMedia,
  ) {
    return hashedMedia.values
        .map(
          (item) => BackupMediaFileToWrite(
            sha256: item.sha256,
            extension: item.extension,
            sourcePath: item.sourcePath,
          ),
        )
        .toList();
  }

  /// 备份文件名：ai-recipe-UTC时间戳.airecipe-backup（yyyyMMdd-HHmmssSSS）。
  static String _backupFileName(DateTime now) {
    final utc = now.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final date = '${utc.year}${two(utc.month)}${two(utc.day)}';
    final time =
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}${three(utc.millisecond)}';
    return 'ai-recipe-$date-$time$backupFileExtension';
  }

  /// 扩展名归一化（去点、小写；未知类型保留原样）。
  static String _normalizeExtension(String sourcePath) {
    final raw = p.extension(sourcePath).toLowerCase();
    final ext = raw.startsWith('.') ? raw.substring(1) : raw;
    return ext.isEmpty ? 'jpg' : ext;
  }

  static String _mimeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  static String _sha256Hex(List<int> bytes) =>
      sha256.convert(bytes).toString();
}

/// 已哈希媒体信息（path → 唯一媒体；sourcePath 为设备原路径，仅写入阶段读取字节用）。
class _HashedMedia {
  const _HashedMedia({
    required this.sha256,
    required this.byteSize,
    required this.extension,
    required this.sourcePath,
  });

  final String sha256;
  final int byteSize;
  final String extension;
  final String sourcePath;
}

/// 媒体索引聚合器（按 sha256 收集引用）。
class _MediaIndexAccumulator {
  _MediaIndexAccumulator({
    required this.sha256,
    required this.byteSize,
    required this.mime,
    required this.relativeKey,
  });

  final String sha256;
  final int byteSize;
  final String mime;
  final String relativeKey;
  final List<String> recipeRefs = <String>[];
  final List<String> categoryRefs = <String>[];
}
