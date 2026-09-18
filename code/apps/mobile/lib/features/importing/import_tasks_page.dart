import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../domain/importing/import_task.dart';
import '../../shared/widgets/app_page_header.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';

/// 未完成导入任务列表页（IMPORT-009）。
///
/// 列出所有尚未完成的导入（排队/解析中/待确认/失败/已取消），点击进入对应
/// 导入进度页；排队/解析中任务可单个取消，失败/已取消任务可单个删除，并支持
/// 一键清空全部已结束任务。
class ImportTasksPage extends StatefulWidget {
  const ImportTasksPage({
    super.key,
    required this.backend,
    required this.onDataChanged,
    required this.onOpenImportTask,
  });

  final AiRecipeBackendFacade backend;
  final VoidCallback onDataChanged;
  final Future<void> Function(ImportTask task) onOpenImportTask;

  @override
  State<ImportTasksPage> createState() => _ImportTasksPageState();
}

class _ImportTasksPageState extends State<ImportTasksPage> {
  /// 列表覆盖：排队/解析中/待确认/失败/已取消（完成的任务不在此列）。
  static const _unfinishedStatuses = <ImportTaskStatus>{
    ImportTaskStatus.queued,
    ImportTaskStatus.running,
    ImportTaskStatus.needsReview,
    ImportTaskStatus.failed,
    ImportTaskStatus.cancelled,
  };

  late Future<List<ImportTask>> _tasks;
  var _busy = false;
  String? _errorMessage;

  /// 长按选择模式：长按任务进入，点按切换选中，全部取消后自动退出。
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tasks = _load();
  }

  Future<List<ImportTask>> _load() {
    return widget.backend.listImportTasks(statuses: _unfinishedStatuses);
  }

  void _reload() {
    setState(() {
      _tasks = _load();
      _errorMessage = null;
      // 列表数据变化后退出选择模式，避免选中项与列表不一致。
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 长按某个任务：进入选择模式并选中该项。
  void _enterSelection(String taskId) {
    if (_busy) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(taskId);
    });
  }

  /// 选择模式下点按切换选中；全部取消选中后自动退出选择模式。
  void _toggleSelection(String taskId) {
    setState(() {
      if (!_selectedIds.remove(taskId)) {
        _selectedIds.add(taskId);
      }
      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 全选 / 取消全选当前列表中的全部任务；取消全选后退出选择模式。
  void _toggleSelectAll(List<ImportTask> tasks) {
    setState(() {
      if (_selectedIds.length == tasks.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(tasks.map((task) => task.id));
      }
    });
  }

  /// 批量删除所选任务：全部选中任务均会删除；进行中（排队/解析中）与
  /// 待确认任务删除前会在确认弹窗中提示会中断解析并移除 AI 草稿。
  Future<void> _deleteSelected() async {
    if (_busy || _selectedIds.isEmpty) return;
    final tasks = await _tasks;
    final selected = tasks
        .where((task) => _selectedIds.contains(task.id))
        .toList(growable: false);
    // 进行中/待确认的任务数量：用于确认弹窗的后果提示。
    final activeCount = selected
        .where(
          (task) =>
              task.status == ImportTaskStatus.queued ||
              task.status == ImportTaskStatus.running ||
              task.status == ImportTaskStatus.needsReview,
        )
        .length;
    final confirmed = await _confirm(
      title: '删除所选 ${selected.length} 条导入记录？',
      message: activeCount > 0
          ? '其中 $activeCount 条正在进行或待确认：删除将中断解析并移除已生成的 AI 草稿。删除后无法恢复。'
          : '删除后无法恢复，任务关联的菜谱不会被影响。',
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.deleteImportTasks(selected.map((task) => task.id));
      widget.onDataChanged();
      _exitSelection();
      if (!mounted) return;
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '删除失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTask(ImportTask task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.backend.cancelImportTask(task.id);
      widget.onDataChanged();
      if (!mounted) return;
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '取消失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTask(ImportTask task) async {
    if (_busy) return;
    final confirmed = await _confirm(
      title: '删除这条导入记录？',
      message: '删除后无法恢复，任务关联的菜谱不会被影响。',
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.deleteImportTask(task.id);
      widget.onDataChanged();
      if (!mounted) return;
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '删除失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearFinished() async {
    final finished = await _tasks.then(
      (tasks) => tasks
          .where(
            (task) =>
                task.status == ImportTaskStatus.failed ||
                task.status == ImportTaskStatus.cancelled,
          )
          .map((task) => task.id)
          .toList(growable: false),
    );
    if (finished.isEmpty || _busy) return;
    final confirmed = await _confirm(
      title: '清空 ${finished.length} 条已结束记录？',
      message: '失败和已取消的导入记录将被删除，无法恢复。',
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.backend.deleteImportTasks(finished);
      widget.onDataChanged();
      if (!mounted) return;
      _reload();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = '清空失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showPixelConfirm(context: context, title: title, message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(title: '导入任务', eyebrow: '未完成导入'),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<ImportTask>>(
          future: _tasks,
          builder: (context, state) {
            if (state.connectionState == ConnectionState.waiting) {
              return const AppLoadingState();
            }
            if (state.hasError) {
              return AppErrorState(
                message: '导入任务暂时无法读取。',
                onRetry: _reload,
              );
            }
            final tasks = state.requireData;
            if (tasks.isEmpty) {
              return AppEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: '没有未完成的导入',
                message: '新增链接导入后，会在这里统一管理进度。',
              );
            }
            final finishedCount = tasks
                .where(
                  (task) =>
                      task.status == ImportTaskStatus.failed ||
                      task.status == ImportTaskStatus.cancelled,
                )
                .length;
            return Stack(
              children: <Widget>[
                ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
                  children: <Widget>[
                    if (_selectionMode)
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '已选择 ${_selectedIds.length} 项',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(
                                color: AppColors.greenDeep,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            key: const Key('selectAllImportTasksButton'),
                            onPressed: _busy ? null : () => _toggleSelectAll(tasks),
                            icon: Icon(
                              _selectedIds.length == tasks.length
                                  ? Icons.deselect_rounded
                                  : Icons.select_all_rounded,
                              size: 18,
                            ),
                            label: Text(
                              _selectedIds.length == tasks.length
                                  ? '取消全选'
                                  : '全选',
                            ),
                          ),
                          TextButton(
                            key: const Key('exitImportSelectionButton'),
                            onPressed: _busy ? null : _exitSelection,
                            child: const Text('取消'),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '共 ${tasks.length} 条未完成',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (finishedCount > 0)
                            TextButton.icon(
                              key: const Key('clearFinishedImportTasksButton'),
                              onPressed: _busy ? null : _clearFinished,
                              icon: const Icon(
                                Icons.delete_sweep_outlined,
                                size: 18,
                              ),
                              label: Text('清空已结束（$finishedCount）'),
                            ),
                        ],
                      ),
                    if (_errorMessage != null) ...<Widget>[
                      const SizedBox(height: 8),
                      PixelNotice(
                        title: '操作未完成',
                        message: _errorMessage!,
                        icon: Icons.warning_amber_rounded,
                        tone: PixelNoticeTone.red,
                      ),
                    ],
                    const SizedBox(height: 10),
                    ...tasks.map((task) => _TaskTile(
                      key: Key('importTask_${task.id}'),
                      task: task,
                      busy: _busy,
                      selectionMode: _selectionMode,
                      selected: _selectedIds.contains(task.id),
                      onTap: _selectionMode
                          ? () => _toggleSelection(task.id)
                          : () => widget.onOpenImportTask(task),
                      onLongPress: () => _enterSelection(task.id),
                      onCancel: _selectionMode
                          ? null
                          : task.status == ImportTaskStatus.queued ||
                                  task.status == ImportTaskStatus.running
                              ? () => _cancelTask(task)
                              : null,
                      onDelete: _selectionMode
                          ? null
                          : task.status == ImportTaskStatus.failed ||
                                  task.status == ImportTaskStatus.cancelled
                              ? () => _deleteTask(task)
                              : null,
                    )),
                    // 为底部批量操作栏预留空间，避免遮挡最后一项。
                    const SizedBox(height: 88),
                  ],
                ),
                if (_selectionMode)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: PixelBottomActionBar(
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '进行中/待确认任务将一并终止',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            key: const Key('deleteSelectedImportTasksButton'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.red,
                            ),
                            onPressed: _busy || _selectedIds.isEmpty
                                ? null
                                : _deleteSelected,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 17,
                            ),
                            label: Text('删除所选 (${_selectedIds.length})'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    super.key,
    required this.task,
    required this.busy,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.onCancel,
    this.onDelete,
  });

  final ImportTask task;
  final bool busy;

  /// 是否处于长按选择模式：隐藏单个取消/删除按钮，改为勾选标记。
  final bool selectionMode;

  /// 选择模式下该项是否被选中。
  final bool selected;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  static String _platformLabel(ImportSourcePlatform platform) =>
      switch (platform) {
        ImportSourcePlatform.xiaohongshu => '小红书',
        ImportSourcePlatform.douyin => '抖音',
        ImportSourcePlatform.web => '网页',
      };

  static String _statusLabel(ImportTaskStatus status) => switch (status) {
    ImportTaskStatus.queued => '排队中',
    ImportTaskStatus.running => '解析中',
    ImportTaskStatus.needsReview => '待确认',
    ImportTaskStatus.failed => '失败',
    ImportTaskStatus.cancelled => '已取消',
    ImportTaskStatus.completed => '完成',
  };

  static String _timeLabel(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final isWorking =
        task.status == ImportTaskStatus.queued ||
        task.status == ImportTaskStatus.running;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PixelSurface(
        cut: 5,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        // 选中态使用深绿描边突出显示。
        borderColor: selected ? AppColors.greenDeep : AppColors.line2,
        borderWidth: selected ? 2 : 1.5,
        onTap: busy ? null : onTap,
        onLongPress: busy ? null : onLongPress,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      PixelBadge(
                        label: _platformLabel(task.sourcePlatform),
                        tone: PixelNoticeTone.blue,
                      ),
                      const SizedBox(width: 8),
                      PixelBadge(
                        label: _statusLabel(task.status),
                        tone: isWorking
                            ? PixelNoticeTone.amber
                            : task.status == ImportTaskStatus.failed
                            ? PixelNoticeTone.red
                            : PixelNoticeTone.green,
                      ),
                      const Spacer(),
                      Text(
                        _timeLabel(task.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    task.sourceUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (task.status == ImportTaskStatus.failed &&
                      task.errorMessage?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      task.errorMessage!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (task.status == ImportTaskStatus.needsReview) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      'AI 草稿已生成，点此确认',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (selectionMode)
              _SelectionMark(selected: selected)
            else ...<Widget>[
              if (onCancel != null)
                IconButton(
                  key: Key('cancelImportTask_${task.id}'),
                  tooltip: '取消解析',
                  onPressed: busy ? null : onCancel,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              if (onDelete != null)
                IconButton(
                  key: Key('deleteImportTask_${task.id}'),
                  tooltip: '删除记录',
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 选择模式的勾选标记：选中=深绿方块 + 白色对勾，未选中=空心描边方块。
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? AppColors.greenDeep : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.greenDeep : AppColors.line2,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
          : null,
    );
  }
}
