import 'backup_records.dart';

/// 导入模式（BACKUP-004/005）。
enum BackupImportMode {
  /// 默认：把备份中的菜谱/分类合并进当前库，不删除任何现有数据。
  merge,

  /// 高级恢复：用备份替换当前菜谱库范围（不含账号、密钥、设置、冰箱）。
  /// 替换前必须创建并验证内部回滚备份，二次确认后才执行。
  replace,
}

/// 单个冲突的解决方式（架构 9.1 每个冲突支持四种选择）。
enum BackupConflictResolution {
  /// 保留当前版本（不导入备份版本）。
  keepCurrent,

  /// 使用备份版本覆盖当前版本。
  useBackup,

  /// 两者都保留：为备份副本生成新 UUID，并在确定性映射表中
  /// 重写分类、媒体与未来扩展引用。
  keepBoth,
}

/// 冲突类型（架构 9.1）。
enum BackupConflictKind {
  /// 相同 UUID 但规范化内容哈希不同（同一菜谱被修改过）。
  sameIdDifferentContent,

  /// 分类同 ID 但内容不一致。
  categoryIdMismatch,

  /// 不同 UUID 但内容完全相同（可能重复，默认仍保留两份）。
  possibleDuplicate,

  /// 备份引用但包内缺失的媒体（包本身损坏，预检直接失败）。
  missingMedia,

  /// 当前库引用了备份要替换掉、且回滚备份中也缺失的媒体（仅替换模式）。
  currentMediaMissing,
}

/// 一个冲突项（展示给用户并等待解决）。
class BackupImportConflict {
  const BackupImportConflict({
    required this.kind,
    required this.backupId,
    this.backupTitle,
    this.currentTitle,
    this.resolution = BackupConflictResolution.keepCurrent,
  });

  final BackupConflictKind kind;
  final String backupId;
  final String? backupTitle;
  final String? currentTitle;
  final BackupConflictResolution resolution;

  BackupImportConflict copyWith({BackupConflictResolution? resolution}) {
    return BackupImportConflict(
      kind: kind,
      backupId: backupId,
      backupTitle: backupTitle,
      currentTitle: currentTitle,
      resolution: resolution ?? this.resolution,
    );
  }
}

/// 替换模式的删除影响预览（架构 9.2）。
class BackupReplaceImpact {
  const BackupReplaceImpact({
    required this.deleteRecipes,
    required this.deleteCategories,
    required this.deleteMedia,
  });

  /// 将被删除/替换的菜谱数量（含回收站）。
  final int deleteRecipes;

  /// 将被删除/替换的分类数量。
  final int deleteCategories;

  /// 当前库中被删除菜谱引用的媒体文件数量。
  final int deleteMedia;
}

/// 导入计划（架构 10：预检必须只读，用户确认前不能改变当前库）。
///
/// 生成后展示新增、跳过、可能重复、冲突、缺失媒体与预计空间；
/// 用户选择合并/替换与冲突策略后，才进入执行阶段。
class BackupImportPlan {
  const BackupImportPlan({
    required this.mode,
    required this.backupFileName,
    required this.createdAt,
    required this.backupAppVersion,
    required this.compatible,
    required this.compatibilityMessage,
    required this.addRecipes,
    required this.skipRecipes,
    required this.possibleDuplicateCount,
    required this.conflicts,
    required this.addCategories,
    required this.skipCategories,
    required this.mediaTotal,
    required this.mediaBytes,
    required this.mediaMissing,
    required this.replaceImpact,
    required this.idMapping,
    this.skippedRecipeIds = const <String>[],
    this.skippedCategoryIds = const <String>[],
  });

  final BackupImportMode mode;
  final String backupFileName;
  final String createdAt;

  /// 创建备份的应用版本（提示数据是否来自更新/更旧的版本）。
  final String backupAppVersion;

  /// 是否满足导入条件（版本兼容 + 必需数据集齐全 + 无缺失媒体）。
  final bool compatible;

  /// 不兼容时的中文说明（compatible 为 false 时展示给用户）。
  final String compatibilityMessage;

  final int addRecipes;
  final int skipRecipes;
  final int possibleDuplicateCount;
  final List<BackupImportConflict> conflicts;
  final int addCategories;
  final int skipCategories;
  final int mediaTotal;
  final int mediaBytes;

  /// 备份引用但包内缺失的媒体数量（>0 时 incompatible）。
  final int mediaMissing;

  /// 与当前库完全一致的菜谱记录（同 UUID 同内容），合并执行时跳过不写入。
  final List<String> skippedRecipeIds;

  /// 与当前库完全一致的分类记录，合并执行时跳过不写入。
  final List<String> skippedCategoryIds;

  /// 替换模式的删除影响（merge 模式为 null）。
  final BackupReplaceImpact? replaceImpact;

  /// 确定性 ID 映射（keepBoth 时备份副本的新 UUID 等），
  /// 执行阶段据此重写引用，保证可复现。
  final Map<String, String> idMapping;

  /// 返回新计划（纯函数）。冲突解决方式修改后调用；
  /// 未修改的字段原样保留。
  BackupImportPlan copyWith({
    BackupImportMode? mode,
    List<BackupImportConflict>? conflicts,
  }) {
    return BackupImportPlan(
      mode: mode ?? this.mode,
      backupFileName: backupFileName,
      createdAt: createdAt,
      backupAppVersion: backupAppVersion,
      compatible: compatible,
      compatibilityMessage: compatibilityMessage,
      addRecipes: addRecipes,
      skipRecipes: skipRecipes,
      possibleDuplicateCount: possibleDuplicateCount,
      conflicts: conflicts ?? this.conflicts,
      addCategories: addCategories,
      skipCategories: skipCategories,
      mediaTotal: mediaTotal,
      mediaBytes: mediaBytes,
      mediaMissing: mediaMissing,
      replaceImpact: replaceImpact,
      idMapping: idMapping,
      skippedRecipeIds: skippedRecipeIds,
      skippedCategoryIds: skippedCategoryIds,
    );
  }
}

/// 导入数据集的解析结果（staging 校验完成后产生）。
class BackupImportPayload {
  const BackupImportPayload({
    required this.recipes,
    required this.categories,
    required this.mediaIndex,
  });

  /// 已解析并通过逐行 Schema 校验的菜谱备份记录。
  final List<RecipeBackupRecord> recipes;

  /// 已解析并通过逐行 Schema 校验的分类备份记录。
  final List<CategoryBackupRecord> categories;

  /// 媒体索引（sha256 → 条目）。
  final List<BackupMediaIndexEntry> mediaIndex;
}
