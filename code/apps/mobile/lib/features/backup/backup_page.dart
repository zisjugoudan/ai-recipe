import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/backup/backup_export_use_cases.dart';
import '../../domain/backup/backup_cancellation_token.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import 'backup_import_page.dart';

/// 数据与存储页（BACKUP-003）：创建全量备份的入口与执行页。
///
/// 状态覆盖：
/// - 默认态：预估卡片展示菜谱/分类/媒体规模与预估空间。
/// - 空状态：没有任何菜谱时提示仍可创建空备份。
/// - 加载态：预估读取中与备份执行中的进度展示。
/// - 成功态：显示最终归档文件名、体积与统计。
/// - 错误态：媒体缺失/写入失败等可读错误信息 + 重试入口。
/// - 取消态：用户取消后回到预估态，不残留半成品。
class BackupPage extends StatefulWidget {
  /// [saveBackupFile]：另存为回调，返回用户选择的落盘位置；返回 null 表示
  /// 用户取消。默认使用系统文件选择器（SAF），测试可注入 fake。
  ///
  /// [initialResult]：页面打开时展示的最近一次备份结果（测试注入用；
  /// 产品上创建成功回调同样写入该状态）。
  ///
  /// [estimateBackup]：预估回调（测试注入用，默认走 [backend] 的真实
  /// 预估，避免 widget 测试触发真实 SQLite）。
  const BackupPage({
    super.key,
    required this.backend,
    this.saveBackupFile,
    this.initialResult,
    this.estimateBackup,
    this.onDataChanged,
  });

  final AiRecipeBackendFacade backend;
  final Future<String?> Function({
    required String sourcePath,
    required String fileName,
  })? saveBackupFile;
  final BackupExportResult? initialResult;
  final Future<BackupEstimate> Function()? estimateBackup;

  /// 导入完成回调：从备份导入写入数据后通知上层（主界面/菜谱库）
  /// 刷新，否则用户回到主界面仍看到旧数据，误以为导入没有成功。
  final VoidCallback? onDataChanged;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  /// 预估读取状态：null=加载中，data=成功，error=失败。
  BackupEstimate? _estimate;
  String? _estimateError;
  var _loadingEstimate = true;

  /// 备份执行状态（进度对话框内部驱动）。
  var _creating = false;
  BackupExportResult? _lastResult;

  /// 另存为进行中（防重复点击）。
  var _saving = false;

  @override
  void initState() {
    super.initState();
    // 测试注入的最近备份结果在首次构建即可见（含「另存为」入口）。
    _lastResult = widget.initialResult;
    _loadEstimate();
  }

  Future<void> _loadEstimate() async {
    setState(() {
      _loadingEstimate = true;
      _estimateError = null;
    });
    try {
      final estimate = widget.estimateBackup != null
          ? await widget.estimateBackup!()
          : await widget.backend.estimateBackup();
      if (!mounted) return;
      setState(() {
        _estimate = estimate;
        _loadingEstimate = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _estimateError = error.message;
        _loadingEstimate = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _estimateError = '预估暂时无法完成，请稍后重试。';
        _loadingEstimate = false;
      });
    }
  }

  Future<void> _startBackup() async {
    if (_creating) return;
    final estimate = _estimate;
    // 二次确认：全量备份包含回收站与全部图片，提醒空间与范围。
    final confirmed = await showPixelConfirm(
      context: context,
      title: '创建全量备份？',
      message: estimate == null
          ? '将导出全部菜谱（含草稿、归档与回收站）及所有图片。'
          : '将导出 ${estimate.recipeTotal} 道菜谱、'
                '${estimate.mediaTotal} 个图片文件，'
                '预估占用 ${_formatBytes(estimate.estimatedTotalBytes)}。',
      confirmLabel: '开始备份',
    );
    if (confirmed != true || !mounted) return;

    // 创建期间禁用按钮；进度对话框无论成功/取消/失败结束都复位。
    setState(() => _creating = true);
    final token = BackupCancellationToken();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BackupProgressDialog(
        backend: widget.backend,
        token: token,
        onCompleted: (result) {
          if (mounted) {
            setState(() => _lastResult = result);
          }
        },
        onCancelled: () {
          if (mounted) _showMessage('备份已取消。');
        },
        onRetryEstimate: _loadEstimate,
      ),
    );
    if (mounted) setState(() => _creating = false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openImport() async {
    // 从备份导入页（BACKUP-004/005）：选择文件 → 预检 → 策略 → 执行。
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackupImportPage(backend: widget.backend),
      ),
    );
    if (!mounted) return;
    // 导入可能写入大量菜谱：返回后必须刷新主界面与备份页统计，
    // 否则用户回到主界面仍看到旧数据，误以为导入没有成功。
    widget.onDataChanged?.call();
    _loadEstimate();
  }

  /// 把最近创建的备份文件另存到用户选择的位置（系统文件选择器）。
  ///
  /// 备份默认落在应用私有文档目录，普通文件管理器不可见，因此提供
  /// 「另存为」出口把文件保存到用户可选目录（如下载）。
  Future<void> _saveBackupAs() async {
    final result = _lastResult;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      final savedTo = widget.saveBackupFile != null
          ? await widget.saveBackupFile!(
              sourcePath: result.filePath,
              fileName: result.fileName,
            )
          : await _defaultSaveBackupFile(result.filePath, result.fileName);
      if (!mounted) return;
      if (savedTo != null) {
        // Android 上 file_picker 的 saveFile 返回的是拼接的
        // Downloads/<文件名> 伪路径（用户实际可选其他目录），显示路径
        // 会误导，因此只提示已保存到所选位置；其余平台路径可信。
        _showMessage(
          Platform.isAndroid
              ? '备份已保存到所选位置'
              : '备份已另存到：$savedTo',
        );
      }
      // savedTo == null 表示用户在文件选择器中取消，不提示。
    } catch (_) {
      if (!mounted) return;
      _showMessage('另存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 默认另存实现：系统文件选择器（SAF）选择目标位置后把备份内容写入。
  ///
  /// file_picker 8.x 在 Android/iOS 上 `saveFile` 必须传 [FilePicker.saveFile]
  /// 的 `bytes` 参数（否则 Dart 端抛 ArgumentError），插件只会把传入的
  /// bytes 写入用户选择的文件并返回路径。返回 null 表示用户取消；
  /// 写入失败抛异常由调用方提示。
  static Future<String?> _defaultSaveBackupFile(
    String sourcePath,
    String fileName,
  ) async {
    final target = await FilePicker.platform.saveFile(
      dialogTitle: '另存为备份文件',
      fileName: fileName,
      // Android/iOS 必需：插件将 bytes 写入用户所选文件。
      // 注：bytes 经平台通道整体传输，超大备份（数百 MB）存在平台通道
      // 传输上限，属 BACKUP-006 大规模导出已知限制。
      bytes: await File(sourcePath).readAsBytes(),
    );
    if (target == null) return null;
    return target;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: '数据与存储',
        eyebrow: '本地数据',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
        children: <Widget>[
          const PxLabel('全量备份', color: AppColors.greenDeep),
          const SizedBox(height: 5),
          Text(
            '创建 .airecipe-backup 备份',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '备份包含全部菜谱（正式、草稿、归档、回收站）、分类与所有图片，'
            '不包含冰箱库存、导入任务、设置与 API 密钥。文件默认保存在本机应用'
            '文档目录，创建成功后可在下方「另存为」导出到其他位置（如下载）。',
            style: TextStyle(color: AppColors.ink2, fontSize: 12.5, height: 1.55),
          ),
          const SizedBox(height: 16),
          if (_loadingEstimate)
            const AppLoadingState(label: '正在统计本地数据…')
          else if (_estimateError != null) ...<Widget>[
            AppErrorState(message: _estimateError!, onRetry: _loadEstimate),
            const SizedBox(height: 14),
            // 预估失败不阻塞创建：直接创建时媒体校验会在弹窗内报错。
            FilledButton.icon(
              key: const Key('createBackupButtonFallback'),
              onPressed: _startBackup,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('创建全量备份'),
            ),
          ]
          else
            _buildEstimateBody(),
          const SizedBox(height: 20),
          PixelNotice(
            title: '备份范围说明',
            message: '回收站中的软删除菜谱也会一并备份；如果任何必需图片缺失或'
                '不可读，本次备份会失败并清理半成品，不会交付不完整备份。',
            icon: Icons.info_outline_rounded,
            tone: PixelNoticeTone.neutral,
          ),
          // 最近一次备份结果：独立于预估状态始终展示（创建成功回调写入，
          // 测试可经 initialResult 注入）。含「另存为」出口。
          if (_lastResult != null) ...<Widget>[
            const SizedBox(height: 14),
            PixelNotice(
              title: '上次备份已创建',
              message: '${_lastResult!.fileName}\n'
                  '${_formatBytes(_lastResult!.byteSize)}\n'
                  '${_lastResult!.filePath}',
              icon: Icons.check_circle_outline_rounded,
              tone: PixelNoticeTone.green,
            ),
            const SizedBox(height: 10),
            // 另存为出口：备份默认在应用私有目录，普通文件管理器不可见，
            // 复制到用户选择的系统位置（如下载）后即可正常访问。
            OutlinedButton.icon(
              key: const Key('saveBackupAsButton'),
              onPressed: _saving ? null : _saveBackupAs,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: PixelLoader(size: 3),
                    )
                  : const Icon(Icons.save_alt_outlined),
              label: Text(_saving ? '正在另存…' : '另存为（导出到其他位置）'),
            ),
          ],
        ],
      ),
    );
  }

  /// 预估成功后的默认/空状态主体。
  Widget _buildEstimateBody() {
    final estimate = _estimate!;
    final hasContent = estimate.recipeTotal > 0 || estimate.mediaTotal > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            PixelStatCard(
              value: '${estimate.recipeTotal}',
              label: '菜谱（含回收站）',
            ),
            const SizedBox(width: 8),
            PixelStatCard(
              value: '${estimate.categoryTotal}',
              label: '分类',
              color: AppColors.ink,
            ),
            const SizedBox(width: 8),
            PixelStatCard(
              value: '${estimate.mediaTotal}',
              label: '图片',
              color: AppColors.ink,
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 单独一行的整宽统计卡：不在 Row 内，必须关闭 Expanded。
        PixelStatCard(
          value: _formatBytes(estimate.estimatedTotalBytes),
          label: '预估备份体积',
          color: AppColors.greenDeep,
          expand: false,
        ),
        if (!hasContent) ...<Widget>[
          const SizedBox(height: 14),
          PixelNotice(
            title: '暂无菜谱数据',
            message: '当前没有任何菜谱。仍可创建一份空备份，或先添加菜谱后再备份。',
            icon: Icons.inbox_outlined,
            tone: PixelNoticeTone.blue,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('createBackupButton'),
          onPressed: _creating ? null : _startBackup,
          icon: _creating
              ? const SizedBox.square(
                  dimension: 20,
                  child: PixelLoader(size: 3),
                )
              : const Icon(Icons.archive_outlined),
          label: Text(_creating ? '正在创建…' : '创建全量备份'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('openImportButton'),
          onPressed: _openImport,
          icon: const Icon(Icons.settings_backup_restore_outlined),
          label: const Text('从备份导入'),
        ),
      ],
    );
  }
}

/// 备份执行进度弹窗：实时展示阶段与进度，支持取消。
///
/// 完成后自动关闭并回调 [onCompleted]；取消/失败关闭并分别回调。
class _BackupProgressDialog extends StatefulWidget {
  const _BackupProgressDialog({
    required this.backend,
    required this.token,
    required this.onCompleted,
    required this.onCancelled,
    required this.onRetryEstimate,
  });

  final AiRecipeBackendFacade backend;
  final BackupCancellationToken token;
  final ValueChanged<BackupExportResult> onCompleted;
  final VoidCallback onCancelled;

  /// 失败后「知道了」关闭弹窗，由父页面重新加载预估。
  final VoidCallback onRetryEstimate;

  @override
  State<_BackupProgressDialog> createState() => _BackupProgressDialogState();
}

class _BackupProgressDialogState extends State<_BackupProgressDialog> {
  BackupExportProgress? _progress;
  String? _error;
  var _finished = false;
  var _cancelling = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    // 页面销毁时取消仍在进行的备份，避免后台遗留任务。
    widget.token.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final result = await widget.backend.createFullBackup(
        cancellationToken: widget.token,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _finished = true);
      widget.onCompleted(result);
      Navigator.of(context).pop();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      if (error.code == AiRecipeBackendErrorCode.backupCancelled) {
        widget.onCancelled();
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '备份暂时无法完成，请稍后重试。');
    }
  }

  Future<void> _cancel() async {
    if (_finished || _cancelling || _error != null) return;
    setState(() => _cancelling = true);
    widget.token.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 执行中禁止返回键直接退出；完成后或出错时允许。
      canPop: _finished || _error != null,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: PixelSurface(
          cut: PixelCut.lg,
          elevation: 2,
          color: AppColors.card,
          borderColor: AppColors.ink,
          borderWidth: 1.5,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                _error != null ? '备份失败' : '正在创建备份',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.red),
                )
              else ...<Widget>[
                _buildStageText(),
                const SizedBox(height: 8),
                PixelProgressBar(
                  value: _progress?.fraction ?? 0,
                  label: _progress == null
                      ? '准备中…'
                      : '${(_progress!.fraction * 100).round()}%',
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    const PixelLoader(size: 6),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _progress?.detail ?? '正在读取菜谱数据…',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (_error != null)
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onRetryEstimate();
                      },
                      child: const Text('知道了'),
                    )
                  else if (_finished)
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('完成'),
                    )
                  else
                    OutlinedButton(
                      key: const Key('cancelBackupButton'),
                      onPressed: _cancelling ? null : _cancel,
                      child: Text(_cancelling ? '正在取消…' : '取消'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageText() {
    final progress = _progress;
    final label = switch (progress?.stage) {
      BackupExportStage.snapshot => '读取一致性快照',
      BackupExportStage.hashing => '校验图片并计算哈希',
      BackupExportStage.writing => '写入备份归档',
      BackupExportStage.verifying => '复核备份文件',
      null => '准备中',
    };
    return Text(
      label,
      style: const TextStyle(fontSize: 12, color: AppColors.ink2),
    );
  }
}

/// 字节数人性化格式化（B/KB/MB/GB）。
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
