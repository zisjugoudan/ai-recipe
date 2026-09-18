import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/backup/backup_import_use_cases.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../domain/backup/backup_import_plan.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 导入流程阶段。
enum _ImportPhase {
  /// 默认态：选择备份文件。
  picking,

  /// 加载态：解压校验 + 只读预检当前库。
  previewing,

  /// 审阅态：展示导入计划、选择模式与冲突策略。
  reviewing,

  /// 执行态：按确认的计划写入（支持取消）。
  executing,

  /// 完成态：展示导入结果。
  done,
}

/// 从备份导入页（BACKUP-004/005）。
///
/// 状态覆盖：
/// - 默认态（picking）：选择 .airecipe-backup 文件入口 + 隐私与安全说明。
/// - 加载态（previewing）：解压、安全校验与预检的实时阶段文案。
/// - 审阅态（reviewing）：新增/跳过/冲突/替换影响展示，模式与冲突策略选择；
///   备份缺失媒体（mediaMissing>0）时禁止执行并解释原因。
/// - 执行态（executing）：逐阶段进度 + 取消；替换模式先二次确认清库范围。
/// - 成功态（done）：写入数量、跳过数量、媒体数与回滚备份路径。
/// - 错误态：预检/执行失败的可读错误 + 返回重选入口。
/// - 取消态：执行中取消后回到审阅态，不残留 staging。
class BackupImportPage extends StatefulWidget {
  const BackupImportPage({super.key, required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<BackupImportPage> createState() => _BackupImportPageState();
}

class _BackupImportPageState extends State<BackupImportPage> {
  var _phase = _ImportPhase.picking;
  String _previewingText = '正在读取备份文件…';
  String? _error;
  String? _sourceName;

  /// 预检阶段进度（staging 逐条上报的百分比；preflight 分析无百分比）。
  BackupImportProgress? _previewProgress;

  /// 预检结果（sessionId 供执行阶段取回 staging 数据）。
  BackupImportPreviewResult? _preview;

  /// 当前计划（用户调整模式/冲突策略后更新，执行阶段以此为准）。
  BackupImportPlan? _plan;

  /// 执行阶段进度与取消令牌。
  BackupImportProgress? _execProgress;
  BackupCancellationToken? _token;
  BackupImportResult? _result;

  // ---- 选择与预检 ----

  Future<void> _pickFile() async {
    setState(() => _error = null);
    FilePickerResult? picked;
    try {
      // 使用 FileType.any：自定义扩展名 .airecipe-backup 在 Android 上
      // 无法映射 MIME（FileUtils.getMimeTypes 会因未知扩展名返回空数组而报
      // "Unsupported filter"），因此不依赖系统过滤，改为选择后自行校验扩展名。
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    } catch (_) {
      // 系统文件选择器异常（如桌面端未配置）时给出可读提示。
      if (mounted) {
        setState(() => _error = '无法打开文件选择器，请稍后重试。');
      }
      return;
    }
    if (picked == null || picked.files.isEmpty) return; // 用户取消选择
    final file = picked.files.single;
    final path = file.path;
    if (path == null || path.trim().isEmpty) return;
    // 自行校验扩展名（大小写不敏感），非备份文件给出可读提示并留在选择页。
    final name = file.name;
    if (!name.toLowerCase().endsWith('.airecipe-backup')) {
      if (mounted) {
        setState(() => _error = '请选择 .airecipe-backup 备份文件。');
      }
      return;
    }
    await _startPreview(path, name);
  }

  Future<void> _startPreview(String path, String fileName) async {
    setState(() {
      _phase = _ImportPhase.previewing;
      _sourceName = fileName;
      _preview = null;
      _plan = null;
      _error = null;
      _previewProgress = null;
    });
    try {
      final preview = await widget.backend.previewBackupImport(
        sourcePath: path,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _previewingText = progress.detail;
              _previewProgress = progress;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _plan = preview.plan;
        _phase = _ImportPhase.reviewing;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _phase = _ImportPhase.picking;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '无法读取该备份文件，请确认文件完整后重试。';
        _phase = _ImportPhase.picking;
      });
    }
  }

  // ---- 审阅（纯函数修改计划） ----

  void _setMode(BackupImportMode mode) {
    final plan = _plan;
    if (plan == null || plan.mode == mode) return;
    setState(() => _plan = plan.copyWith(mode: mode));
  }

  void _setConflict(int index, BackupConflictResolution resolution) {
    final plan = _plan;
    if (plan == null) return;
    final updated = widget.backend.resolveImportConflict(plan, index, resolution);
    setState(() => _plan = updated);
  }

  // ---- 执行 ----

  Future<void> _confirmAndExecute() async {
    final plan = _plan;
    final sessionId = _preview?.sessionId;
    if (plan == null || sessionId == null) return;

    if (!plan.compatible) return; // 不兼容时按钮本身已禁用

    // 替换模式二次确认：清库范围与回滚备份保障。
    if (plan.mode == BackupImportMode.replace) {
      final impact = plan.replaceImpact;
      final confirmed = await showPixelConfirm(
        context: context,
        title: '替换当前菜谱库？',
        message: '将删除当前 ${impact?.deleteRecipes ?? 0} 道菜谱、'
            '${impact?.deleteCategories ?? 0} 个分类，'
            '并写入备份中的全部数据。\n\n'
            '执行前会先创建并验证一份回滚备份；失败时自动尽力恢复。'
            '此操作不可撤销，请确认。',
        confirmLabel: '开始替换',
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() {
      _phase = _ImportPhase.executing;
      _execProgress = null;
      _error = null;
    });
    final token = BackupCancellationToken();
    _token = token;
    try {
      final result = await widget.backend.executeBackupImport(
        sessionId: sessionId,
        plan: plan,
        cancellationToken: token,
        onProgress: (progress) {
          if (mounted) setState(() => _execProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _phase = _ImportPhase.done;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      if (error.code == AiRecipeBackendErrorCode.backupCancelled) {
        setState(() => _phase = _ImportPhase.reviewing);
        _showMessage(
          '导入已取消。若此前正在替换恢复，原数据已自动恢复，请检查菜谱库。',
        );
        return;
      }
      setState(() {
        _error = error.message;
        _phase = _ImportPhase.reviewing;
      });
    } catch (_) {
      if (!mounted) return;
      // 替换模式先清库再写入：异常时已自动从回滚备份恢复，但恢复为
      // best-effort，若仍有缺失需引导用户用回滚备份手动恢复。
      setState(() {
        _error = plan.mode == BackupImportMode.replace
            ? '导入未能完成，已尝试自动恢复原数据。若菜谱库仍有缺失，'
                '可在备份目录找到回滚备份（ai-recipe-rollback-*.airecipe-backup）'
                '并重新导入恢复。'
            : '导入暂时无法完成，当前数据未受影响，请重试。';
        _phase = _ImportPhase.reviewing;
      });
    }
  }

  void _cancelExecution() {
    _token?.cancel();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    // 页面销毁时取消仍在进行的导入并释放会话，避免后台遗留任务。
    _token?.cancel();
    final sessionId = _preview?.sessionId;
    if (sessionId != null && _phase == _ImportPhase.previewing) {
      widget.backend.discardImportPreview(sessionId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: '从备份导入',
        eyebrow: '数据与存储',
      ),
      body: switch (_phase) {
        _ImportPhase.picking => _buildPicking(),
        _ImportPhase.previewing => _buildPreviewing(),
        _ImportPhase.reviewing => _buildReviewing(),
        _ImportPhase.executing => _buildExecuting(),
        _ImportPhase.done => _buildDone(),
      },
    );
  }

  // ---- 各阶段 UI ----

  Widget _buildPicking() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      children: <Widget>[
        const PxLabel('导入恢复', color: AppColors.greenDeep),
        const SizedBox(height: 5),
        Text(
          '选择一份 .airecipe-backup 备份',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        const Text(
          '将安全校验备份文件后恢复菜谱、分类与图片。'
          '可先预览导入计划，再选择合并或替换方式。',
          style: TextStyle(color: AppColors.ink2, fontSize: 12.5, height: 1.55),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...<Widget>[
          AppErrorState(
            message: _error!,
            onRetry: () => setState(() => _error = null),
          ),
          const SizedBox(height: 14),
        ],
        FilledButton.icon(
          key: const Key('pickBackupFileButton'),
          onPressed: _pickFile,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('选择备份文件'),
        ),
        const SizedBox(height: 20),
        PixelNotice(
          title: '安全与隐私',
          message: '仅接受本应用生成的 .airecipe-backup 文件；导入前会校验文件'
              '完整性、版本兼容性与图片哈希。备份包含你的全部菜谱数据，'
              '请只导入可信来源的文件。',
          icon: Icons.shield_outlined,
          tone: PixelNoticeTone.neutral,
        ),
        if (_sourceName != null) ...<Widget>[
          const SizedBox(height: 12),
          PixelNotice(
            title: '上次尝试',
            message: _sourceName!,
            icon: Icons.description_outlined,
            tone: PixelNoticeTone.amber,
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewing() {
    final progress = _previewProgress;
    // 数据量大时解压校验耗时较长：无百分比阶段（preflight 分析）用
    // 不确定动画，有百分比阶段（staging 逐条解析/校验）实时前进，
    // 避免用户只看到静态文案或停在 0% 误以为卡住。
    final hasFraction = progress != null && progress.total > 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      children: <Widget>[
        const AppLoadingState(label: '正在分析备份…'),
        const SizedBox(height: 14),
        PixelSurface(
          cut: PixelCut.sm,
          color: AppColors.card,
          borderColor: AppColors.line2,
          borderWidth: 1.2,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _sourceName ?? '备份文件',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _previewingText,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.ink2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
              PixelProgressBar(
                value: progress?.fraction ?? 0,
                indeterminate: !hasFraction,
                label: hasFraction
                    ? '${(progress.fraction * 100).round()}%'
                    : '处理中…',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewing() {
    final plan = _plan!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
      children: <Widget>[
        Row(
          children: <Widget>[
            PixelStatCard(
              value: '${plan.addRecipes}',
              label: '新增菜谱',
            ),
            const SizedBox(width: 8),
            PixelStatCard(
              value: '${plan.skipRecipes + plan.possibleDuplicateCount}',
              label: '跳过/重复',
              color: AppColors.ink,
            ),
            const SizedBox(width: 8),
            PixelStatCard(
              value: '${plan.conflicts.length}',
              label: '冲突',
              color: plan.conflicts.isEmpty
                  ? AppColors.ink
                  : AppColors.amber,
            ),
          ],
        ),
        const SizedBox(height: 10),
        PixelStatCard(
          value: '${plan.addCategories} 分类 / ${plan.mediaTotal} 图片',
          label: '${_formatBytes(plan.mediaBytes)} 待导入媒体',
          color: AppColors.greenDeep,
          expand: false,
        ),
        const SizedBox(height: 14),
        if (_error != null) ...<Widget>[
          AppErrorState(
            message: _error!,
            onRetry: () => setState(() => _error = null),
          ),
          const SizedBox(height: 14),
        ],
        if (!plan.compatible) ...<Widget>[
          AppErrorState(
            message: plan.compatibilityMessage,
            onRetry: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 14),
        ],
        const PxLabel('导入方式', color: AppColors.greenDeep),
        const SizedBox(height: 8),
        PixelSeg(
          tabs: const <String>['合并导入', '替换恢复'],
          index: plan.mode == BackupImportMode.replace ? 1 : 0,
          onChanged: (index) => _setMode(
            index == 0 ? BackupImportMode.merge : BackupImportMode.replace,
          ),
        ),
        const SizedBox(height: 8),
        if (plan.mode == BackupImportMode.replace) ...<Widget>[
          PixelNotice(
            title: '替换范围',
            message: '将删除当前 ${plan.replaceImpact?.deleteRecipes ?? 0} 道'
                '菜谱、${plan.replaceImpact?.deleteCategories ?? 0} 个分类、'
                '${plan.replaceImpact?.deleteMedia ?? 0} 个图片文件，'
                '再写入备份内容。执行前自动创建并验证回滚备份。',
            icon: Icons.warning_amber_rounded,
            tone: PixelNoticeTone.amber,
          ),
          const SizedBox(height: 14),
        ],
        if (plan.conflicts.isNotEmpty) ...<Widget>[
          const PxLabel('冲突处理', color: AppColors.greenDeep),
          const SizedBox(height: 8),
          const Text(
            '备份与当前库存在相同记录但内容不同，请为每条记录选择保留方式。',
            style: TextStyle(color: AppColors.ink2, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          for (final (index, conflict) in plan.conflicts.indexed) ...<Widget>[
            _ConflictTile(
              conflict: conflict,
              index: index,
              onChanged: (resolution) => _setConflict(index, resolution),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('executeImportButton'),
          onPressed: plan.compatible ? _confirmAndExecute : null,
          icon: plan.mode == BackupImportMode.replace
              ? const Icon(Icons.restore_page_outlined)
              : const Icon(Icons.play_arrow_outlined),
          label: Text(
            plan.mode == BackupImportMode.replace ? '开始替换' : '开始导入',
          ),
        ),
      ],
    );
  }

  Widget _buildExecuting() {
    final progress = _execProgress;
    // 无明确百分比（total<=0，如收尾阶段）时用不确定动画，避免
    // 进度条停在 0% 让用户误以为卡住。
    final hasFraction = progress != null && progress.total > 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      children: <Widget>[
        const PxLabel('正在导入', color: AppColors.greenDeep),
        const SizedBox(height: 10),
        PixelSurface(
          cut: PixelCut.lg,
          elevation: 2,
          color: AppColors.card,
          borderColor: AppColors.ink,
          borderWidth: 1.5,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _stageLabel(progress?.stage),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              PixelProgressBar(
                value: progress?.fraction ?? 0,
                indeterminate: !hasFraction,
                label: hasFraction
                    ? '${(progress.fraction * 100).round()}%'
                    : '处理中…',
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const PixelLoader(size: 6),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      progress?.detail ?? '正在准备…',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  OutlinedButton(
                    key: const Key('cancelImportButton'),
                    onPressed: _cancelExecution,
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDone() {
    final result = _result!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      children: <Widget>[
        const PxLabel('导入完成', color: AppColors.greenDeep),
        const SizedBox(height: 10),
        PixelNotice(
          title: result.mode == BackupImportMode.replace
              ? '菜谱库已替换'
              : '菜谱库已合并',
          message: '写入 ${result.writtenRecipes} 道菜谱、'
              '${result.writtenCategories} 个分类，'
              '跳过 ${result.skippedRecipes} 道菜谱、'
              '${result.skippedCategories} 个分类，'
              '导入 ${result.mediaFiles} 个图片文件。',
          icon: Icons.check_circle_outline_rounded,
          tone: PixelNoticeTone.green,
        ),
        if (result.rollbackBackupPath != null) ...<Widget>[
          const SizedBox(height: 14),
          PixelNotice(
            title: '回滚备份已保留',
            message:
                '${result.rollbackBackupPath}\n如需手动恢复可重新导入该文件。',
            icon: Icons.history_rounded,
            tone: PixelNoticeTone.blue,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('finishImportButton'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.done_outlined),
          label: const Text('完成'),
        ),
      ],
    );
  }

  String _stageLabel(BackupImportStage? stage) {
    return switch (stage) {
      BackupImportStage.staging => '校验备份文件',
      BackupImportStage.preflight => '分析当前菜谱库',
      BackupImportStage.creatingRollback => '创建回滚备份',
      BackupImportStage.preparingMedia => '准备图片',
      BackupImportStage.applying => '写入菜谱库',
      BackupImportStage.finalizing => '完成导入',
      null => '准备中',
    };
  }
}

/// 单个冲突的解决条目：类型标签 + 标题 + 三种策略选择。
class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    required this.conflict,
    required this.index,
    required this.onChanged,
  });

  final BackupImportConflict conflict;
  final int index;
  final ValueChanged<BackupConflictResolution> onChanged;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      cut: PixelCut.sm,
      color: AppColors.card,
      borderColor: AppColors.line2,
      borderWidth: 1.2,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PixelBadge(
                label: _kindLabel(conflict.kind),
                tone: PixelNoticeTone.amber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conflict.backupTitle ?? conflict.backupId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (conflict.currentTitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '当前库：${conflict.currentTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ],
          const SizedBox(height: 10),
          PixelSeg(
            tabs: const <String>['保留当前', '用备份覆盖', '两者保留'],
            index: _resolutionIndex(conflict.resolution),
            onChanged: (i) => onChanged(_resolutionAt(i)),
          ),
        ],
      ),
    );
  }

  static String _kindLabel(BackupConflictKind kind) {
    return switch (kind) {
      BackupConflictKind.sameIdDifferentContent => '内容已修改',
      BackupConflictKind.categoryIdMismatch => '分类不一致',
      BackupConflictKind.possibleDuplicate => '可能重复',
      BackupConflictKind.missingMedia => '缺少图片',
      BackupConflictKind.currentMediaMissing => '图片缺失',
    };
  }

  static int _resolutionIndex(BackupConflictResolution resolution) {
    return switch (resolution) {
      BackupConflictResolution.keepCurrent => 0,
      BackupConflictResolution.useBackup => 1,
      BackupConflictResolution.keepBoth => 2,
    };
  }

  static BackupConflictResolution _resolutionAt(int index) {
    return switch (index) {
      0 => BackupConflictResolution.keepCurrent,
      1 => BackupConflictResolution.useBackup,
      _ => BackupConflictResolution.keepBoth,
    };
  }
}

/// 字节数人性化格式化（B/KB/MB/GB，与备份页一致）。
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
