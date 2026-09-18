import 'dart:typed_data';

import '../recipe/recipe.dart';
import 'backup_cancellation_token.dart';
import 'backup_manifest.dart';

/// 媒体文件在快照中的引用角色。
enum BackupMediaRole {
  /// 菜谱封面（recipes.cover_image）。
  cover,

  /// 菜谱画廊图（recipe_images）。
  gallery,

  /// 分类封面（recipe_categories.cover_image）。
  categoryCover,
}

/// 快照中的单个媒体文件及其引用位置。
///
/// `sourcePath` 是当前设备的文件路径，仅用于读取与哈希；
/// 归档内一律使用内容寻址相对键，不落盘绝对路径。
class BackupSnapshotMedia {
  const BackupSnapshotMedia({
    required this.sourcePath,
    required this.role,
    this.ownerId,
    this.sortOrder,
  });

  final String sourcePath;
  final BackupMediaRole role;

  /// 引用主体 ID（菜谱 ID 或分类 ID）。
  final String? ownerId;

  /// 画廊排序（cover 可空）。
  final int? sortOrder;
}

/// 一致性快照：全部菜谱（含软删除）、全部分类（含空分类与软删除）
/// 以及它们引用的媒体文件清单。
class BackupSnapshot {
  const BackupSnapshot({
    required this.recipes,
    required this.categories,
    required this.media,
  });

  final List<Recipe> recipes;
  final List<RecipeCategory> categories;
  final List<BackupSnapshotMedia> media;
}

/// 一致性快照读取接口（BACKUP-002）。
///
/// 实现必须在单个 SQLite 事务内完成全部读取，保证"记录 ↔ 分类关系 ↔
/// 图片路径"来自同一时间点；图片文件本身与数据库无法共享事务，因此
/// 媒体可读性校验由导出用例在快照之后单独执行。
abstract interface class BackupSnapshotRepository {
  /// 读取一致性快照（含正式、草稿、归档与回收站软删除数据）。
  Future<BackupSnapshot> loadSnapshot({BackupCancellationToken? token});

  /// 读取媒体文件字节数；不存在或不可读时抛 [BackupException]。
  Future<int> mediaFileSize(String sourcePath);

  /// 计算媒体文件 SHA-256（小写十六进制）；文件缺失/不可读抛异常。
  Future<String> hashMediaFile(String sourcePath);

  /// 读取媒体文件完整字节（供写入归档与复核）。
  Future<Uint8List> readMediaBytes(String sourcePath);
}

/// 待写入归档的媒体文件（已去重：同 sha256 只保留一个）。
class BackupMediaFileToWrite {
  const BackupMediaFileToWrite({
    required this.sha256,
    required this.extension,
    required this.sourcePath,
  });

  final String sha256;

  /// 小写扩展名（不含点），如 jpg/png/webp。
  final String extension;
  final String sourcePath;
}

/// 一次归档写入请求。
class BackupWriteRequest {
  const BackupWriteRequest({
    required this.manifest,
    required this.datasets,
    required this.mediaIndexBytes,
    required this.mediaFiles,
    required this.outputDirectory,
    required this.outputFileName,
  });

  final BackupManifest manifest;

  /// Dataset 名称 → NDJSON UTF-8 字节（写入后按 manifest 复核哈希）。
  final Map<String, List<int>> datasets;

  /// 媒体索引（media/index.v1.ndjson）UTF-8 字节。
  final List<int> mediaIndexBytes;

  final List<BackupMediaFileToWrite> mediaFiles;

  /// 最终归档保存目录（应用文档目录 backups/）。
  final String outputDirectory;

  /// 最终文件名（如 ai-recipe-20260806-153000.airecipe-backup）。
  final String outputFileName;
}

/// 归档写入回执。
class BackupWriteReceipt {
  const BackupWriteReceipt({required this.filePath, required this.byteSize});

  final String filePath;
  final int byteSize;
}

/// 归档写入接口。
///
/// 实现负责：写 `.partial` 临时文件 → 组装 ZIP（manifest + NDJSON
/// Dataset + 内容寻址媒体）→ 重读归档复核（条目齐全、Dataset 与媒体
/// 哈希一致）→ 原子重命名为最终文件；任一步骤失败必须清理半成品。
abstract interface class BackupArchiveWriter {
  Future<BackupWriteReceipt> write(BackupWriteRequest request);
}
