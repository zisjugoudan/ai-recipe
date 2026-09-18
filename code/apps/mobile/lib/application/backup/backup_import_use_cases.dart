import 'package:path/path.dart' as p;

import '../../domain/backup/backup_archive_constants.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../domain/backup/backup_errors.dart';
import '../../domain/backup/backup_import_plan.dart';
import '../../domain/backup/backup_import_repository.dart';
import '../../domain/backup/backup_record_hashing.dart';
import '../../domain/backup/backup_records.dart';
import 'backup_export_use_cases.dart';

/// 导入阶段（UI 进度展示用）。
enum BackupImportStage {
  /// 解压归档并执行安全校验（Zip Slip/Bomb、manifest、SHA-256）。
  staging,

  /// 预检当前库并生成导入计划（只读）。
  preflight,

  /// 替换模式：创建并验证内部回滚备份。
  creatingRollback,

  /// 把 staging 媒体复制到菜谱封面目录。
  preparingMedia,

  /// 写入 SQLite（单个事务）。
  applying,

  /// 收尾（清理 staging、删除孤儿图片）。
  finalizing,
}

/// 导入进度回调。
class BackupImportProgress {
  const BackupImportProgress({
    required this.stage,
    this.processed = 0,
    this.total = 0,
    this.detail = '',
  });

  final BackupImportStage stage;
  final int processed;
  final int total;
  final String detail;

  double get fraction => total <= 0 ? 0 : (processed / total).clamp(0, 1);
}

/// 预检结果：会话 ID（执行阶段凭此取回 staging 数据）+ 导入计划。
class BackupImportPreviewResult {
  const BackupImportPreviewResult({
    required this.sessionId,
    required this.plan,
  });

  final String sessionId;
  final BackupImportPlan plan;
}

/// 导入执行结果。
class BackupImportResult {
  const BackupImportResult({
    required this.sessionId,
    required this.mode,
    required this.writtenRecipes,
    required this.writtenCategories,
    required this.skippedRecipes,
    required this.skippedCategories,
    required this.mediaFiles,
    this.rollbackBackupPath,
  });

  final String sessionId;
  final BackupImportMode mode;
  final int writtenRecipes;
  final int writtenCategories;
  final int skippedRecipes;
  final int skippedCategories;
  final int mediaFiles;

  /// 替换模式创建的回滚备份路径（保留供用户取走或后续手动恢复）。
  final String? rollbackBackupPath;
}

/// 备份导入用例（BACKUP-004/005）。
///
/// 流水线（架构 10/12）：
/// 1. [previewImport]：staging（ZIP 安全检查 + 版本兼容 + SHA-256 校验）→
///    预检当前库（只读）→ 生成 [BackupImportPlan]；不改变当前库。
/// 2. 用户确认计划并选择模式（合并/替换）与冲突策略
///    （[resolveConflict]/[resolveAllConflicts]/[copyWith]）。
/// 3. [executeImport]：合并模式按冲突解决结果写入；替换模式先创建并验证
///    回滚备份，再清库、写入；任一步失败回滚媒体并尽力从回滚备份恢复。
class BackupImportUseCases {
  BackupImportUseCases({
    required BackupArchiveReader archiveReader,
    required BackupImportPreflightRepository preflightRepository,
    required BackupImportCommitRepository commitRepository,
    required BackupImportMediaWriter mediaWriter,
    required BackupExportUseCases exportUseCases,
    required Future<String> Function() stagingDirectoryProvider,
    required String Function() idGenerator,
  }) : _archiveReader = archiveReader,
       _preflightRepository = preflightRepository,
       _commitRepository = commitRepository,
       _mediaWriter = mediaWriter,
       _exportUseCases = exportUseCases,
       _stagingDirectoryProvider = stagingDirectoryProvider,
       _idGenerator = idGenerator;

  final BackupArchiveReader _archiveReader;
  final BackupImportPreflightRepository _preflightRepository;
  final BackupImportCommitRepository _commitRepository;
  final BackupImportMediaWriter _mediaWriter;

  /// 替换模式回滚备份复用导出用例（创建并复核归档）。
  final BackupExportUseCases _exportUseCases;

  final Future<String> Function() _stagingDirectoryProvider;
  final String Function() _idGenerator;

  /// 会话 → staging 数据（preview 后驻留内存，execute 时取回，用完移除）。
  final Map<String, BackupStagedArchive> _stagedBySession =
      <String, BackupStagedArchive>{};

  // ---- 预检（只读） ----

  /// 解压并校验备份，预检当前库，生成导入计划。
  ///
  /// 成功后 [BackupImportPreviewResult.sessionId] 用于 [executeImport]；
  /// 任一步失败清理本次 staging 目录并抛 [BackupException]。
  Future<BackupImportPreviewResult> previewImport({
    required String sourcePath,
    BackupCancellationToken? token,
    void Function(BackupImportProgress)? onProgress,
  }) async {
    token?.throwIfCancelled();
    final sessionId = _idGenerator();
    final stagingDirectory = await _stagingDirectoryProvider();

    // 1. staging（安全校验 + 版本兼容 + 哈希校验）。
    onProgress?.call(const BackupImportProgress(
      stage: BackupImportStage.staging,
      detail: '正在读取并校验备份文件…',
    ));
    final staged = await _archiveReader.stage(
      BackupArchiveStageRequest(
        sourcePath: sourcePath,
        sessionId: sessionId,
        stagingDirectory: stagingDirectory,
        token: token,
        // 解压/解析/媒体校验逐条上报，预检页进度条随大备份实时前进。
        onProgress: (processed, total) => onProgress?.call(
          BackupImportProgress(
            stage: BackupImportStage.staging,
            processed: processed,
            total: total,
            detail: '正在读取并校验备份文件…',
          ),
        ),
      ),
    );

    try {
      // 2. 预检当前库（只读）。
      onProgress?.call(const BackupImportProgress(
        stage: BackupImportStage.preflight,
        detail: '正在分析当前菜谱库…',
      ));
      final currentRecipeHashes = await _preflightRepository
          .loadRecipeIdHashes(token: token);
      final currentCategoryHashes = await _preflightRepository
          .loadCategoryIdHashes(token: token);
      final librarySummary = await _preflightRepository
          .loadLibrarySummary(token: token);

      // 3. 生成计划。
      final plan = _buildPlan(
        staged: staged,
        sourceFileName: p.basename(sourcePath),
        currentRecipeHashes: currentRecipeHashes,
        currentCategoryHashes: currentCategoryHashes,
        librarySummary: librarySummary,
      );
      _stagedBySession[sessionId] = staged;
      return BackupImportPreviewResult(sessionId: sessionId, plan: plan);
    } catch (_) {
      // 预检失败：清理 staging，避免残留。
      await _archiveReader.cleanupSession(stagingDirectory, sessionId);
      rethrow;
    }
  }

  /// 修改单个冲突的解决方式，返回新计划（纯函数，不触碰任何数据）。
  BackupImportPlan resolveConflict(
    BackupImportPlan plan,
    int index,
    BackupConflictResolution resolution,
  ) {
    if (index < 0 || index >= plan.conflicts.length) return plan;
    final conflicts = List<BackupImportConflict>.of(plan.conflicts);
    conflicts[index] = conflicts[index].copyWith(resolution: resolution);
    return plan.copyWith(conflicts: conflicts);
  }

  /// 把同一解决方式应用到全部冲突。
  BackupImportPlan resolveAllConflicts(
    BackupImportPlan plan,
    BackupConflictResolution resolution,
  ) {
    final conflicts = plan.conflicts
        .map((conflict) => conflict.copyWith(resolution: resolution))
        .toList(growable: false);
    return plan.copyWith(conflicts: conflicts);
  }

  /// 放弃预检会话（用户返回或切换文件），清理 staging。
  Future<void> discardPreview(String sessionId) async {
    _stagedBySession.remove(sessionId);
    final stagingDirectory = await _stagingDirectoryProvider();
    await _archiveReader.cleanupSession(stagingDirectory, sessionId);
  }

  /// 清理启动时遗留的 staging 会话目录。
  Future<int> cleanupAbandonedSessions() {
    final stagingDirectory = _stagingDirectoryProvider();
    return stagingDirectory.then(
      (root) => _archiveReader.cleanupAbandonedSessions(root),
    );
  }

  // ---- 执行 ----

  /// 按已确认的计划执行导入。
  ///
  /// 合并模式：按冲突解决结果写入（跳过、覆盖、双保留）。
  /// 替换模式：先创建并验证回滚备份 → 清空菜谱库 → 全部写入 → 清理孤儿
  /// 图片；失败时回滚本次新建媒体并尽力从回滚备份恢复。
  Future<BackupImportResult> executeImport({
    required String sessionId,
    required BackupImportPlan plan,
    BackupCancellationToken? token,
    void Function(BackupImportProgress)? onProgress,
  }) async {
    token?.throwIfCancelled();
    final staged = _stagedBySession[sessionId];
    if (staged == null) {
      throw const BackupException(
        BackupErrorCode.formatNotSupported,
        '导入会话已过期，请重新选择备份文件。',
      );
    }
    final stagingDirectory = await _stagingDirectoryProvider();
    try {
      final result = plan.mode == BackupImportMode.replace
          ? await _executeReplace(
              staged: staged,
              plan: plan,
              token: token,
              onProgress: onProgress,
            )
          : await _executeMerge(
              staged: staged,
              plan: plan,
              token: token,
              onProgress: onProgress,
            );
      // finalize：成功即删除 staging。
      await _archiveReader.cleanupSession(stagingDirectory, sessionId);
      return result;
    } catch (_) {
      // 失败同样清理 staging（媒体回滚已在子方法内完成）。
      await _archiveReader.cleanupSession(stagingDirectory, sessionId);
      rethrow;
    } finally {
      _stagedBySession.remove(sessionId);
    }
  }

  /// 合并模式：按冲突解决结果产出最终记录并写入。
  Future<BackupImportResult> _executeMerge({
    required BackupStagedArchive staged,
    required BackupImportPlan plan,
    BackupCancellationToken? token,
    void Function(BackupImportProgress)? onProgress,
  }) async {
    final resolved = _resolveMergeRecords(staged, plan);
    onProgress?.call(BackupImportProgress(
      stage: BackupImportStage.preparingMedia,
      detail: '正在准备 ${resolved.recipes.length} 张图片…',
    ));
    final mediaResult = await _mediaWriter.stageMediaToCoverStorage(
      recipes: resolved.recipes,
      categories: resolved.categories,
      stagedMedia: staged.mediaEntries,
      token: token,
      // 每复制一张图片上报一次进度（引用数口径）。
      onProgress: (processed, total) => onProgress?.call(
        BackupImportProgress(
          stage: BackupImportStage.preparingMedia,
          processed: processed,
          total: total,
          detail: '正在准备图片 $processed/$total…',
        ),
      ),
    );
    try {
      onProgress?.call(const BackupImportProgress(
        stage: BackupImportStage.applying,
        detail: '正在写入菜谱库…',
      ));
      final written = await _commitRepository.applyImport(
        recipes: resolved.recipes,
        categories: resolved.categories,
        recipeMediaPaths: mediaResult.recipeMediaPaths,
        categoryCoverPaths: mediaResult.categoryCoverPaths,
        token: token,
        // 每写入一条记录上报一次进度（分类 + 菜谱口径）。
        onProgress: (processed, total) => onProgress?.call(
          BackupImportProgress(
            stage: BackupImportStage.applying,
            processed: processed,
            total: total,
            detail: '正在写入菜谱库 $processed/$total…',
          ),
        ),
      );
      onProgress?.call(const BackupImportProgress(
        stage: BackupImportStage.finalizing,
        detail: '正在完成导入…',
      ));
      return BackupImportResult(
        sessionId: staged.sessionId,
        mode: BackupImportMode.merge,
        writtenRecipes: written,
        writtenCategories: resolved.categories.length,
        skippedRecipes: plan.skipRecipes + plan.possibleDuplicateCount,
        skippedCategories: plan.skipCategories,
        mediaFiles: mediaResult.createdFiles.length,
      );
    } catch (_) {
      // 数据库事务失败：删除本次新建媒体，避免残留孤儿图片。
      await _mediaWriter.rollbackMedia(mediaResult.createdFiles);
      rethrow;
    }
  }

  /// 替换模式：回滚备份 → 清库 → 全部写入 → 清理孤儿图片。
  Future<BackupImportResult> _executeReplace({
    required BackupStagedArchive staged,
    required BackupImportPlan plan,
    BackupCancellationToken? token,
    void Function(BackupImportProgress)? onProgress,
  }) async {
    // 1. 强制创建并验证回滚备份（未验证通过不进入清库）。
    onProgress?.call(const BackupImportProgress(
      stage: BackupImportStage.creatingRollback,
      detail: '正在创建回滚备份…',
    ));
    final rollback = await _exportUseCases.createFullBackup(
      token: token,
      outputFileName: _rollbackFileName(),
      // 回滚备份内部阶段（快照/哈希/打包）进度桥接为创建阶段进度，
      // 大备份下回滚备份创建耗时较长，进度条不能停在 0。
      onProgress: (export) => onProgress?.call(BackupImportProgress(
        stage: BackupImportStage.creatingRollback,
        processed: export.processed,
        total: export.total,
        detail: export.detail.isEmpty ? '正在创建回滚备份…' : export.detail,
      )),
    );

    try {
      // 2. 全部备份记录写入（替换模式）：applyImport 在同一事务内先
      //    清空当前库再写入备份，整体要么全部成功要么全部回滚，避免
      //    「先清库、后写入」两步之间失败（含进程被杀）导致空库。
      onProgress?.call(BackupImportProgress(
        stage: BackupImportStage.preparingMedia,
        detail: '正在准备 ${staged.recipes.length} 张图片…',
      ));
      final mediaResult = await _mediaWriter.stageMediaToCoverStorage(
        recipes: staged.recipes,
        categories: staged.categories,
        stagedMedia: staged.mediaEntries,
        token: token,
        onProgress: (processed, total) => onProgress?.call(
          BackupImportProgress(
            stage: BackupImportStage.preparingMedia,
            processed: processed,
            total: total,
            detail: '正在准备图片 $processed/$total…',
          ),
        ),
      );
      try {
        onProgress?.call(const BackupImportProgress(
          stage: BackupImportStage.applying,
          detail: '正在写入菜谱库…',
        ));
        final written = await _commitRepository.applyImport(
          recipes: staged.recipes,
          categories: staged.categories,
          recipeMediaPaths: mediaResult.recipeMediaPaths,
          categoryCoverPaths: mediaResult.categoryCoverPaths,
          token: token,
          clearExisting: true,
          onProgress: (processed, total) => onProgress?.call(
            BackupImportProgress(
              stage: BackupImportStage.applying,
              processed: processed,
              total: total,
              detail: '正在写入菜谱库 $processed/$total…',
            ),
          ),
        );
        await _commitRepository.removeOrphanedCoverFiles(token: token);
        onProgress?.call(const BackupImportProgress(
          stage: BackupImportStage.finalizing,
          detail: '正在完成导入…',
        ));
        return BackupImportResult(
          sessionId: staged.sessionId,
          mode: BackupImportMode.replace,
          writtenRecipes: written,
          writtenCategories: staged.categories.length,
          skippedRecipes: 0,
          skippedCategories: 0,
          mediaFiles: mediaResult.createdFiles.length,
          rollbackBackupPath: rollback.filePath,
        );
      } catch (_) {
        // 写入失败：事务已回滚（原库保留），删除本次新建媒体；
        // 再尽力从回滚备份恢复，作为双保险。
        await _mediaWriter.rollbackMedia(mediaResult.createdFiles);
        await _tryRestoreFromRollback(rollback.filePath, token);
        rethrow;
      }
    } catch (_) {
      // 回滚备份创建或媒体准备本身失败：库未受影响（applyImport 为
      // 单事务），回滚备份文件保留供用户检查，无需额外恢复动作。
      rethrow;
    }
  }

  /// 尽力从回滚备份恢复（替换失败时调用，best-effort，不抛错）。
  Future<void> _tryRestoreFromRollback(
    String rollbackPath,
    BackupCancellationToken? token,
  ) async {
    try {
      // 恢复是安全网：必须使用独立的新令牌完成整个恢复流程，
      // 绝不能继承已取消的导入令牌——否则用户取消/导入失败时恢复
      // 第一步（staging）就会因 throwIfCancelled 立即中断，导致菜谱库
      // 停留在 clearLibrary 后的空状态（BACKUP-005 根因之一）。
      final restoreToken = BackupCancellationToken();
      final sessionId = _idGenerator();
      final stagingDirectory = await _stagingDirectoryProvider();
      final staged = await _archiveReader.stage(
        BackupArchiveStageRequest(
          sourcePath: rollbackPath,
          sessionId: sessionId,
          stagingDirectory: stagingDirectory,
          token: restoreToken,
        ),
      );
      final mediaResult = await _mediaWriter.stageMediaToCoverStorage(
        recipes: staged.recipes,
        categories: staged.categories,
        stagedMedia: staged.mediaEntries,
        token: restoreToken,
      );
      await _commitRepository.applyImport(
        recipes: staged.recipes,
        categories: staged.categories,
        recipeMediaPaths: mediaResult.recipeMediaPaths,
        categoryCoverPaths: mediaResult.categoryCoverPaths,
        token: restoreToken,
        clearExisting: true,
      );
      await _commitRepository.removeOrphanedCoverFiles(token: restoreToken);
      await _archiveReader.cleanupSession(stagingDirectory, sessionId);
    } catch (_) {
      // best-effort：恢复失败时保留回滚备份文件，供用户手动恢复。
    }
  }

  // ---- 计划构建与冲突解决（纯函数） ----

  /// 依据 staging 数据与当前库哈希生成导入计划（只读）。
  static BackupImportPlan _buildPlan({
    required BackupStagedArchive staged,
    required String sourceFileName,
    required Map<String, String> currentRecipeHashes,
    required Map<String, String> currentCategoryHashes,
    required BackupLibrarySummary librarySummary,
  }) {
    var addRecipes = 0;
    var skipRecipes = 0;
    var possibleDuplicateCount = 0;
    final skippedRecipeIds = <String>[];
    final skippedCategoryIds = <String>[];
    final conflicts = <BackupImportConflict>[];

    // 备份引用但包内缺失的媒体（损坏备份 → 计划标记不兼容，UI 阻止执行）。
    final indexSha = staged.mediaEntries.map((item) => item.sha256).toSet();
    var mediaMissing = 0;

    for (final record in staged.recipes) {
      mediaMissing += _missingMediaCount(
        indexSha,
        cover: record.coverImage,
        images: record.images,
      );
      final backupHash = canonicalRecipeHash(record);
      final currentHash = currentRecipeHashes[record.id];
      if (currentHash != null) {
        if (currentHash == backupHash) {
          skipRecipes += 1;
          skippedRecipeIds.add(record.id);
        } else {
          conflicts.add(BackupImportConflict(
            kind: BackupConflictKind.sameIdDifferentContent,
            backupId: record.id,
            backupTitle: record.title,
          ));
        }
      } else if (currentRecipeHashes.containsValue(backupHash)) {
        // 不同 UUID 但内容完全相同：可能重复，默认不导入（保留当前库）。
        possibleDuplicateCount += 1;
        conflicts.add(BackupImportConflict(
          kind: BackupConflictKind.possibleDuplicate,
          backupId: record.id,
          backupTitle: record.title,
        ));
      } else {
        addRecipes += 1;
      }
    }

    var addCategories = 0;
    var skipCategories = 0;
    for (final record in staged.categories) {
      mediaMissing += _missingMediaCount(
        indexSha,
        cover: record.coverImage,
        images: const <BackupMediaReference>[],
      );
      final backupHash = canonicalCategoryHash(record);
      final currentHash = currentCategoryHashes[record.id];
      if (currentHash != null) {
        if (currentHash == backupHash) {
          skipCategories += 1;
          skippedCategoryIds.add(record.id);
        } else {
          conflicts.add(BackupImportConflict(
            kind: BackupConflictKind.categoryIdMismatch,
            backupId: record.id,
            backupTitle: record.name,
          ));
        }
      } else {
        addCategories += 1;
      }
    }

    final mediaBytes = staged.mediaEntries.fold<int>(
      0,
      (sum, item) => sum + item.byteSize,
    );
    final compatible = mediaMissing == 0;
    return BackupImportPlan(
      mode: BackupImportMode.merge,
      backupFileName: sourceFileName,
      createdAt: staged.manifest.createdAt,
      backupAppVersion: staged.manifest.appVersion,
      compatible: compatible,
      compatibilityMessage: compatible
          ? ''
          : '备份缺少 $mediaMissing 张图片，无法完整恢复，请使用其他备份或重新创建备份。',
      addRecipes: addRecipes,
      skipRecipes: skipRecipes,
      possibleDuplicateCount: possibleDuplicateCount,
      conflicts: conflicts,
      addCategories: addCategories,
      skipCategories: skipCategories,
      mediaTotal: staged.mediaEntries.length,
      mediaBytes: mediaBytes,
      mediaMissing: mediaMissing,
      skippedRecipeIds: skippedRecipeIds,
      skippedCategoryIds: skippedCategoryIds,
      replaceImpact: BackupReplaceImpact(
        deleteRecipes: librarySummary.recipeCount,
        deleteCategories: librarySummary.categoryCount,
        deleteMedia: librarySummary.mediaCount,
      ),
      idMapping: const <String, String>{},
    );
  }

  /// 统计记录引用的媒体中不在媒体索引/归档内的数量。
  static int _missingMediaCount(
    Set<String> indexSha, {
    BackupMediaReference? cover,
    required List<BackupMediaReference> images,
  }) {
    var missing = 0;
    if (cover != null && !indexSha.contains(cover.sha256)) {
      missing += 1;
    }
    for (final image in images) {
      if (!indexSha.contains(image.sha256)) {
        missing += 1;
      }
    }
    return missing;
  }

  /// 合并模式：把计划与冲突解决结果翻译成最终写入记录。
  ///
  /// - keepCurrent：跳过该记录；
  /// - useBackup：使用备份版本（同 ID 覆盖）；
  /// - keepBoth：为备份副本生成新 UUID，并建立旧 → 新 ID 映射；
  ///   分类 ID 变更会同步重写到引用它的菜谱 categoryIds。
  ({List<RecipeBackupRecord> recipes, List<CategoryBackupRecord> categories})
      _resolveMergeRecords(BackupStagedArchive staged, BackupImportPlan plan) {
    // 1. 分类：先确定旧 → 新 ID 映射（keepBoth）。
    final categoryIdMap = <String, String>{};
    final finalCategories = <CategoryBackupRecord>[];
    for (final category in staged.categories) {
      final conflict = _conflictFor(
        plan.conflicts,
        kind: BackupConflictKind.categoryIdMismatch,
        backupId: category.id,
      );
      if (conflict != null &&
          conflict.resolution == BackupConflictResolution.keepCurrent) {
        continue;
      }
      if (plan.skippedCategoryIds.contains(category.id)) {
        // 与当前库完全一致：跳过不写入。
        continue;
      }
      if (conflict != null &&
          conflict.resolution == BackupConflictResolution.keepBoth) {
        final newId = _newId();
        categoryIdMap[category.id] = newId;
        finalCategories.add(_copyCategoryWithId(category, newId));
        continue;
      }
      finalCategories.add(category);
    }

    // 2. 菜谱：按冲突解决结果保留/覆盖/双保留，并重写分类引用。
    final finalRecipes = <RecipeBackupRecord>[];
    for (final recipe in staged.recipes) {
      final conflict = _conflictFor(
        plan.conflicts,
        kind: BackupConflictKind.sameIdDifferentContent,
        backupId: recipe.id,
      ) ??
          _conflictFor(
            plan.conflicts,
            kind: BackupConflictKind.possibleDuplicate,
            backupId: recipe.id,
          );
      if (plan.skippedRecipeIds.contains(recipe.id)) {
        // 与当前库完全一致（同 UUID 同内容）：跳过不写入。
        continue;
      }
      if (conflict == null) {
        // 真新增。
        finalRecipes.add(_copyRecipeWithMappedCategories(recipe, categoryIdMap));
        continue;
      }
      if (conflict.resolution == BackupConflictResolution.keepCurrent) {
        continue;
      }
      var record = recipe;
      if (conflict.kind == BackupConflictKind.sameIdDifferentContent &&
          conflict.resolution == BackupConflictResolution.keepBoth) {
        // 同 ID 双保留：备份副本换新 UUID，当前版本保留。
        record = _copyRecipeWithId(recipe, _newId());
      }
      finalRecipes.add(_copyRecipeWithMappedCategories(record, categoryIdMap));
    }
    return (recipes: finalRecipes, categories: finalCategories);
  }

  /// 在冲突列表中查找某个备份记录对应的冲突。
  static BackupImportConflict? _conflictFor(
    List<BackupImportConflict> conflicts, {
    required BackupConflictKind kind,
    required String backupId,
  }) {
    for (final conflict in conflicts) {
      if (conflict.kind == kind && conflict.backupId == backupId) {
        return conflict;
      }
    }
    return null;
  }

  /// 回滚备份文件名：`ai-recipe-rollback-` 加 UTC 时间戳与备份扩展名。
  String _rollbackFileName() {
    final now = DateTime.now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final date = '${now.year}${two(now.month)}${two(now.day)}';
    final time =
        '${two(now.hour)}${two(now.minute)}${two(now.second)}${three(now.millisecond)}';
    return 'ai-recipe-rollback-$date-$time$backupFileExtension';
  }

  static RecipeBackupRecord _copyRecipeWithId(
    RecipeBackupRecord record,
    String newId, {
    List<String>? categoryIds,
  }) {
    return RecipeBackupRecord(
      id: newId,
      userId: record.userId,
      title: record.title,
      description: record.description,
      coverImage: record.coverImage,
      images: record.images,
      servings: record.servings,
      prepTimeMinutes: record.prepTimeMinutes,
      cookTimeMinutes: record.cookTimeMinutes,
      totalTimeMinutes: record.totalTimeMinutes,
      difficulty: record.difficulty,
      notes: record.notes,
      favorite: record.favorite,
      status: record.status,
      sourceId: record.sourceId,
      ingredients: record.ingredients,
      steps: record.steps,
      categoryIds: categoryIds ?? record.categoryIds,
      tags: record.tags,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      localVersion: record.localVersion,
      deletedAt: record.deletedAt,
    );
  }

  /// 重写菜谱的分类引用（keepBoth 分类换新 UUID 后同步到菜谱）。
  static RecipeBackupRecord _copyRecipeWithMappedCategories(
    RecipeBackupRecord record,
    Map<String, String> categoryIdMap,
  ) {
    if (categoryIdMap.isEmpty) return record;
    final mapped = record.categoryIds
        .map((id) => categoryIdMap[id] ?? id)
        .toList(growable: false);
    // 保持原 ID，只替换分类引用；与原记录字段完全一致时浅拷贝即可。
    return _copyRecipeWithId(record, record.id, categoryIds: mapped);
  }

  static CategoryBackupRecord _copyCategoryWithId(
    CategoryBackupRecord record,
    String newId,
  ) {
    return CategoryBackupRecord(
      id: newId,
      userId: record.userId,
      name: record.name,
      coverImage: record.coverImage,
      sortOrder: record.sortOrder,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      localVersion: record.localVersion,
      deletedAt: record.deletedAt,
    );
  }

  String _newId() => _idGenerator();
}
