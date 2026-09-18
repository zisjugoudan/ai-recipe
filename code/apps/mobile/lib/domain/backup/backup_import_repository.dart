import 'backup_cancellation_token.dart';
import 'backup_errors.dart';
import 'backup_manifest.dart';
import 'backup_records.dart';

/// 归档读取请求（BACKUP-004）。
class BackupArchiveStageRequest {
  const BackupArchiveStageRequest({
    required this.sourcePath,
    required this.sessionId,
    required this.stagingDirectory,
    this.token,
    this.onProgress,
  });

  /// 用户选择的 .airecipe-backup 文件路径。
  final String sourcePath;

  /// 导入会话 ID（staging 根目录下会话子目录名与清理账本主键）。
  final String sessionId;

  /// staging 根目录（应用文档目录下的 backup-import/）。
  final String stagingDirectory;

  /// 取消令牌：解压/校验过程中用户可取消。
  final BackupCancellationToken? token;

  /// 进度回调：解压、数据集解析与媒体校验过程中逐步上报
  /// （processed/total，单位：记录数 + 媒体数），供 UI 展示百分比。
  final void Function(int processed, int total)? onProgress;
}

/// 已解压并校验的归档（staging 产物）。
///
/// 解压成功后数据集与媒体 SHA-256 已按 manifest 校验一致；
/// [mediaEntries] 提供内容寻址键 → staging 实际文件路径的映射，
/// 供导入提交阶段复制到菜谱封面目录。
class BackupStagedArchive {
  const BackupStagedArchive({
    required this.sessionId,
    required this.stagingRoot,
    required this.manifest,
    required this.recipes,
    required this.categories,
    required this.mediaEntries,
    required this.totalBytes,
  });

  final String sessionId;

  /// 本次导入会话的 staging 根目录绝对路径（staging 根下的子目录）。
  final String stagingRoot;

  final BackupManifest manifest;

  /// 已逐行 Schema 校验的菜谱记录。
  final List<RecipeBackupRecord> recipes;

  /// 已逐行 Schema 校验的分类记录。
  final List<CategoryBackupRecord> categories;

  /// 已校验的媒体条目（relativeKey → staging 文件路径）。
  final List<BackupStagedMedia> mediaEntries;

  /// 归档解压后的总字节（含数据与媒体，用于空间提示）。
  final int totalBytes;
}

/// staging 中的单个媒体文件（已按 SHA-256 校验）。
class BackupStagedMedia {
  const BackupStagedMedia({
    required this.sha256,
    required this.mime,
    required this.byteSize,
    required this.relativeKey,
    required this.stagingPath,
  });

  final String sha256;
  final String mime;
  final int byteSize;
  final String relativeKey;

  /// staging 目录下的实际文件路径（已校验与 sha256 一致）。
  final String stagingPath;
}

/// 归档读取器（BACKUP-004）。
///
/// 实现负责：ZIP 安全检查（Zip Slip / Zip Bomb / 重复路径 / 非法路径 /
/// 大小上限）→ manifest 版本兼容 → 数据集与媒体 SHA-256 校验 → 逐行
/// Schema 校验 → 生成 [BackupStagedArchive]。任何一步失败都清理本次
/// staging 目录并抛 [BackupException]，不向导入端交付不可信内容。
abstract interface class BackupArchiveReader {
  Future<BackupStagedArchive> stage(BackupArchiveStageRequest request);

  /// 删除某个 staging 会话目录（成功 finalize 或失败 rollback 后调用）。
  ///
  /// [stagingDirectory] 为 stage 请求中的 staging 根目录。
  Future<void> cleanupSession(String stagingDirectory, String sessionId);

  /// 清理 staging 根下全部遗留会话目录（应用启动时调用）。
  ///
  /// staging 是瞬时数据：任何在启动时仍存在的会话目录都来自崩溃中断，
  /// 直接删除并返回删除数量。
  Future<int> cleanupAbandonedSessions(String stagingDirectory);
}

/// 当前库规模摘要（替换模式删除影响预览用）。
class BackupLibrarySummary {
  const BackupLibrarySummary({
    required this.recipeCount,
    required this.categoryCount,
    required this.mediaCount,
  });

  /// 菜谱总数（含回收站软删除）。
  final int recipeCount;

  /// 分类总数（含软删除与空分类）。
  final int categoryCount;

  /// 被引用的去重媒体文件数（菜谱封面 + 画廊图 + 分类封面）。
  final int mediaCount;
}

/// 导入目标仓库读取接口（预检只读）。
///
/// 预检阶段只读当前库，比较备份记录并生成 ImportPlan，不得修改数据库
/// 或文件系统（架构 10：用户确认 ImportPlan 前不能改变当前库）。
/// 记录内容哈希统一由领域层 [canonicalRecipeHash]/[canonicalCategoryHash]
/// 及当前库对应的 FromDomain 变体计算，本仓库只负责批量加载。
abstract interface class BackupImportPreflightRepository {
  /// 读取当前库全部菜谱 ID（含软删除）与规范化内容哈希。
  Future<Map<String, String>> loadRecipeIdHashes({
    BackupCancellationToken? token,
  });

  /// 读取当前库全部分类 ID（含软删除）与规范化内容哈希。
  Future<Map<String, String>> loadCategoryIdHashes({
    BackupCancellationToken? token,
  });

  /// 读取当前库规模摘要（替换模式删除影响预览）。
  Future<BackupLibrarySummary> loadLibrarySummary({
    BackupCancellationToken? token,
  });
}

/// 导入提交仓库（架构 12：两阶段 + 清理账本）。
///
/// prepare：把 staging 媒体复制到不可变内容寻址媒体库，记录本次新建；
/// database commit：单个 SQLite 事务写入菜谱、分类、关系与媒体引用；
/// finalize：写入完成标记并删除 staging；rollback：删除本次新建且无其他
/// 引用的媒体并清理 staging。
abstract interface class BackupImportCommitRepository {
  /// 替换模式：删除当前库菜谱库范围内的全部数据（菜谱、分类、关系、
  /// 图片、食材、步骤），保留账号、密钥、设置、冰箱等非备份范围数据。
  Future<int> clearLibrary({
    BackupCancellationToken? token,
  });

  /// 导入完成后删除当前库不再被任何菜谱引用的封面目录/文件
  /// （替换模式替换掉旧菜谱后遗留的孤儿图片）。
  Future<int> removeOrphanedCoverFiles({BackupCancellationToken? token});

  /// 在一个 SQLite 事务内写入全部菜谱与分类（合并与替换共用）。
  ///
  /// [recipeMediaPaths] 由 [BackupImportMediaWriter] 在提交前生成
  /// （最终菜谱 ID → 本地封面/画廊路径），[categoryCoverPaths] 为
  /// 最终分类 ID → 本地封面路径；事务引用的文件必须已落盘。
  /// 返回写入的菜谱数（合并模式下跳过与 keepCurrent 冲突的不计）。
  ///
  /// [clearExisting] 为 true（替换模式）时，在同一事务内先删除当前库
  /// 菜谱库范围全部数据再写入备份内容：整体要么全部成功、要么全部
  /// 回滚，避免「先清库、后写入」两步之间失败（含进程被杀）导致
  /// 菜谱库停留在清空状态（BACKUP-005）。
  ///
  /// [onProgress] 按「已写入分类数 + 已写入菜谱数 / 总数」逐步上报，
  /// 供 UI 展示写入阶段百分比（大备份导入时进度条持续前进）。
  Future<int> applyImport({
    required List<RecipeBackupRecord> recipes,
    required List<CategoryBackupRecord> categories,
    required Map<String, BackupRecipeMediaPaths> recipeMediaPaths,
    required Map<String, String> categoryCoverPaths,
    BackupCancellationToken? token,
    bool clearExisting = false,
    void Function(int processed, int total)? onProgress,
  });
}

/// 单个菜谱在导入后的本地媒体路径（媒体引用 → 设备文件路径）。
class BackupRecipeMediaPaths {
  const BackupRecipeMediaPaths({this.coverImage, this.images = const <String>[]});

  /// 封面本地绝对路径（备份无封面时为 null）。
  final String? coverImage;

  /// 画廊图本地绝对路径列表（顺序与备份记录 images 一致）。
  final List<String> images;
}

/// 媒体落盘结果：菜谱/分类 → 本地媒体路径 + 本次新建文件清单（供回滚）。
class BackupMediaWriteResult {
  const BackupMediaWriteResult({
    required this.recipeMediaPaths,
    required this.categoryCoverPaths,
    required this.createdFiles,
  });

  /// 最终菜谱 ID → 导入后的本地封面/画廊路径。
  final Map<String, BackupRecipeMediaPaths> recipeMediaPaths;

  /// 最终分类 ID → 导入后的本地封面路径。
  final Map<String, String> categoryCoverPaths;

  /// 本次复制新建的绝对路径（rollback 时删除；同一 sha256 复用不重复）。
  final List<String> createdFiles;
}

/// 媒体落盘接口：把 staging 媒体写入应用私有封面目录并返回
/// 「菜谱记录 → 本地文件路径」的映射（导入提交前先准备媒体，
/// 保证数据库事务引用的文件都已存在）。
abstract interface class BackupImportMediaWriter {
  /// 复制 staging 媒体到 `<documents>/recipe_covers/<id>/`。
  ///
  /// [recipes]/[categories] 是冲突解决后**最终**写入的记录（keepBoth 时
  /// 已携带新 UUID），[stagedMedia] 提供 sha256 → staging 文件路径；
  /// 同一 sha256 被多个位置引用时按各自容器复制（内容寻址去重仅对
  /// 同容器内同哈希生效）。返回每个记录的本地路径与本次新建文件清单。
  ///
  /// [onProgress] 按「已写入媒体引用数 / 总引用数（封面 + 画廊 + 分类
  /// 封面）」逐步上报，供 UI 展示图片准备阶段百分比。
  Future<BackupMediaWriteResult> stageMediaToCoverStorage({
    required List<RecipeBackupRecord> recipes,
    required List<CategoryBackupRecord> categories,
    required List<BackupStagedMedia> stagedMedia,
    BackupCancellationToken? token,
    void Function(int processed, int total)? onProgress,
  });

  /// 删除本次导入新建的封面文件（rollback 用，best-effort）。
  Future<void> rollbackMedia(List<String> createdFiles);
}
