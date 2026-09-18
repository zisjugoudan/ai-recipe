import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/importing/import_task_runner.dart';
import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/recipe/recipe.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_dialogs.dart';
import '../../shared/widgets/pixel_ui.dart';
import 'import_draft_review_page.dart';
import 'import_image_picker.dart';

class ImportProgressPage extends StatefulWidget {
  const ImportProgressPage({
    super.key,
    required this.backend,
    required this.taskId,
    required this.onDataChanged,
    this.onOpenManualEditor,
    this.imagePicker,
    this.initialImage,
    this.initialText,
  });

  final AiRecipeBackendFacade backend;
  final String taskId;
  final VoidCallback onDataChanged;
  final Future<void> Function()? onOpenManualEditor;
  final ImportImagePicker? imagePicker;
  /// 快速导入"拍照选图"带入的本地图片：任务打开后直接用图片内容运行
  /// （本地 OCR + 自有 LLM），而不是按占位链接走 WebView 抓取。
  final PickedImportImage? initialImage;
  /// 快速导入"剪贴板"带入的本地文本：任务打开后直接用文本内容运行
  /// （自有 LLM 整理成菜谱），而不是按占位链接走 WebView 抓取。
  final String? initialText;

  @override
  State<ImportProgressPage> createState() => _ImportProgressPageState();
}

class _ImportProgressPageState extends State<ImportProgressPage> {
  static const _pollInterval = Duration(milliseconds: 450);

  ImportTask? _task;
  ImportContent? _evidence;
  ImportCancellationToken? _cancellationToken;
  Timer? _pollTimer;
  late final ImportImagePicker _imagePicker;
  var _loading = true;
  var _running = false;
  var _changingState = false;
  var _cancellingTask = false;
  var _reviewOpen = false;
  var _selectingImage = false;
  var _lostImageRecoveryAttempted = false;
  // 解析中按返回时：允许离开页面，但任务转入后台继续，绝不取消。
  // _allowPop 用于临时放行"后台继续"确认后的真正退出。
  var _allowPop = false;
  String? _pageError;

  /// 当前是否处于真正解析/运行中的状态（排队或运行中）。
  ///
  /// 只有在这个状态下，返回键才会被拦截并提示"转后台继续"，
  /// 其它状态（待确认/失败/已取消/已完成）保持默认返回行为。
  bool get _isWorking {
    final task = _task;
    return task != null &&
        (task.status == ImportTaskStatus.queued ||
            task.status == ImportTaskStatus.running);
  }

  /// 解析中按返回：不取消任务，仅离开页面并让任务在后台继续。
  ///
  /// 弹出二次确认，明确告知用户任务会保留，避免误以为"返回=取消"。
  Future<void> _confirmLeaveToBackground() async {
    if (!mounted || !_isWorking) return;
    final leave = await showPixelConfirm(
      context: context,
      title: '解析将在后台继续',
      message: '离开后任务不会取消，会继续在本机后台解析。稍后可在「导入任务」中查看进度和草稿。',
      confirmLabel: '后台继续',
      cancelLabel: '留在本页',
    );
    if (leave == true && mounted) {
      setState(() => _allowPop = true);
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _imagePicker = widget.imagePicker ?? DeviceImportImagePicker();
    unawaited(_loadAndContinue());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAndContinue() async {
    try {
      var task = await widget.backend.getImportTask(widget.taskId);
      if (task.status == ImportTaskStatus.running) {
        await widget.backend.recoverInterruptedImports();
        task = await widget.backend.getImportTask(widget.taskId);
      }
      if (!mounted) return;
      setState(() {
        _applyTaskSnapshot(task);
        _loading = false;
        _pageError = null;
      });
      await _continueFor(task);
      if (task.status == ImportTaskStatus.failed ||
          task.status == ImportTaskStatus.cancelled) {
        await _recoverLostImageSelection();
      }
    } on AiRecipeBackendException catch (error) {
      _showLoadError(error.message);
    } catch (_) {
      _showLoadError('导入任务暂时无法读取，请稍后重试。');
    }
  }

  void _showLoadError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _pageError = message;
    });
  }

  bool _applyTaskSnapshot(
    ImportTask incoming, {
    bool allowCancelledRestart = false,
  }) {
    final current = _task;
    if (current != null && current.id == incoming.id) {
      if (incoming.localVersion < current.localVersion) return false;
      if (!allowCancelledRestart &&
          current.status == ImportTaskStatus.cancelled &&
          incoming.status != ImportTaskStatus.cancelled) {
        return false;
      }
    }
    _task = incoming;
    return true;
  }

  void _notifyDataChangedSafely() {
    try {
      widget.onDataChanged();
    } catch (_) {
      // A host refresh failure must not replace an already persisted task result.
    }
  }

  Future<void> _continueFor(ImportTask task) async {
    final initialImage = widget.initialImage;
    final initialText = widget.initialText;
    switch (task.status) {
      case ImportTaskStatus.queued:
        if (initialImage != null) {
          // 图片任务：用图片内容运行（快速导入"拍照选图"，IMPORT-009）。
          await _runLocalImageFallback(initialImage);
        } else if (initialText != null && initialText.trim().isNotEmpty) {
          // 文本任务：用输入文本运行（快速导入"剪贴板"）。
          await _runTextFallback(initialText);
        } else {
          await _run();
        }
      case ImportTaskStatus.needsReview:
        _scheduleReview();
      case ImportTaskStatus.running ||
          ImportTaskStatus.completed ||
          ImportTaskStatus.failed ||
          ImportTaskStatus.cancelled:
        return;
    }
  }

  Future<void> _run() async {
    if (_running || _changingState) return;
    final token = ImportCancellationToken();
    setState(() {
      _running = true;
      _cancellationToken = token;
      _pageError = null;
    });
    _startPolling();
    try {
      final result = await widget.backend.runImportTask(
        widget.taskId,
        cancellationToken: token,
      );
      if (mounted) {
        setState(() {
          if (_applyTaskSnapshot(result.task)) {
            _evidence = result.content;
          }
        });
      }
      _notifyDataChangedSafely();
    } on AiRecipeBackendException catch (error) {
      _pageError = error.message;
      await _reloadTaskSilently();
    } catch (_) {
      _pageError = '解析暂时无法继续，请稍后重试。';
      await _reloadTaskSilently();
    } finally {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (mounted) {
        setState(() {
          _running = false;
          _cancellationToken = null;
        });
      }
    }
    if (!mounted) return;
    final task = _task;
    if (task?.status == ImportTaskStatus.needsReview) {
      _scheduleReview();
    }
  }

  Future<ImportTaskRunResult> _runPastedTextFallback(String text) async {
    if (_running || _changingState) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前任务正在处理，请稍候。',
      );
    }
    final token = ImportCancellationToken();
    setState(() {
      _running = true;
      _cancellationToken = token;
      _pageError = null;
    });
    _startPolling();
    try {
      final result = await widget.backend.runImportWithPastedText(
        widget.taskId,
        text,
        cancellationToken: token,
      );
      if (mounted) {
        setState(() {
          if (_applyTaskSnapshot(result.task, allowCancelledRestart: true)) {
            _evidence = result.content;
          }
        });
      }
      _notifyDataChangedSafely();
      return result;
    } catch (_) {
      await _reloadTaskSilently();
      rethrow;
    } finally {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (mounted) {
        setState(() {
          _running = false;
          _cancellationToken = null;
        });
      }
    }
  }

  Future<void> _openPastedTextFallback() async {
    final task = _task;
    if (task == null || _running || _changingState) return;
    final result = await showModalBottomSheet<ImportTaskRunResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PastedTextFallbackSheet(
        sourceUrl: task.normalizedUrl,
        onSubmit: _runPastedTextFallback,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (_applyTaskSnapshot(result.task, allowCancelledRestart: true)) {
        _evidence = result.content;
      }
    });
    if (result.task.status == ImportTaskStatus.needsReview) {
      _scheduleReview();
    }
  }

  Future<ImportTaskRunResult> _runLocalImageFallback(
    PickedImportImage image,
  ) async {
    if (_running || _changingState) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前已有导入操作正在执行。',
      );
    }
    final token = ImportCancellationToken();
    setState(() {
      _running = true;
      _cancellationToken = token;
      _pageError = null;
    });
    _startPolling();
    try {
      final result = await widget.backend.runImportWithLocalImage(
        widget.taskId,
        image.localAssetId,
        mimeType: image.mimeType,
        cancellationToken: token,
      );
      if (mounted) {
        setState(() {
          if (_applyTaskSnapshot(result.task, allowCancelledRestart: true)) {
            _evidence = result.content;
          }
        });
      }
      _notifyDataChangedSafely();
      return result;
    } catch (_) {
      await _reloadTaskSilently();
      rethrow;
    } finally {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (mounted) {
        setState(() {
          _running = false;
          _cancellationToken = null;
        });
      }
    }
  }

  /// 用输入文本运行快速导入（剪贴板入口，自有 LLM 整理成菜谱）。
  Future<ImportTaskRunResult> _runTextFallback(String text) async {
    if (_running || _changingState) {
      throw const AiRecipeBackendException(
        code: AiRecipeBackendErrorCode.invalidTaskState,
        message: '当前已有导入操作正在执行。',
      );
    }
    final token = ImportCancellationToken();
    setState(() {
      _running = true;
      _cancellationToken = token;
      _pageError = null;
    });
    _startPolling();
    try {
      final result = await widget.backend.runImportWithText(
        widget.taskId,
        text,
        cancellationToken: token,
      );
      if (mounted) {
        setState(() {
          if (_applyTaskSnapshot(result.task, allowCancelledRestart: true)) {
            _evidence = result.content;
          }
        });
      }
      _notifyDataChangedSafely();
      return result;
    } catch (_) {
      await _reloadTaskSilently();
      rethrow;
    } finally {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (mounted) {
        setState(() {
          _running = false;
          _cancellationToken = null;
        });
      }
    }
  }

  Future<void> _openImageFallback() async {
    if (_running || _changingState || _selectingImage) return;
    setState(() {
      _selectingImage = true;
      _pageError = null;
    });
    try {
      final image = await _imagePicker.pickImage();
      if (!mounted || image == null) return;
      final result = await _runLocalImageFallback(image);
      if (!mounted) return;
      if (result.task.status == ImportTaskStatus.needsReview) {
        _scheduleReview();
      }
    } on ImportImagePickerException catch (error) {
      if (mounted) setState(() => _pageError = error.message);
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _pageError = error.message);
    } catch (_) {
      if (mounted) setState(() => _pageError = '图片暂时无法处理，请重新选择。');
    } finally {
      if (mounted) setState(() => _selectingImage = false);
    }
  }

  Future<void> _recoverLostImageSelection() async {
    if (_lostImageRecoveryAttempted ||
        _running ||
        _changingState ||
        _selectingImage) {
      return;
    }
    _lostImageRecoveryAttempted = true;
    try {
      final image = await _imagePicker.retrieveLostImage();
      if (!mounted || image == null) return;
      final task = _task;
      if (task == null ||
          (task.status != ImportTaskStatus.failed &&
              task.status != ImportTaskStatus.cancelled)) {
        return;
      }
      final result = await _runLocalImageFallback(image);
      if (!mounted) return;
      if (result.task.status == ImportTaskStatus.needsReview) {
        _scheduleReview();
      }
    } on ImportImagePickerException catch (error) {
      if (mounted) setState(() => _pageError = error.message);
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _pageError = error.message);
    } catch (_) {
      if (mounted) setState(() => _pageError = '无法恢复上次的图片选择结果，请重新选择。');
    }
  }

  Future<void> _showVideoFallbackUnavailable() => _showUnavailableDialog(
    key: const Key('videoFallbackUnavailableDialog'),
    title: '视频导入暂不可用',
    message: '当前没有可用的本地或托管 ASR Provider，暂不能从视频继续。可改用粘贴正文或手动创建。',
  );

  Future<void> _showUnavailableDialog({
    required Key key,
    required String title,
    required String message,
  }) {
    return showPixelInfo(
      context: context,
      key: key,
      title: title,
      message: message,
      okLabel: '知道了',
    );
  }

  Future<void> _openManualEditor() async {
    final callback = widget.onOpenManualEditor;
    if (callback != null) await callback();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_reloadTaskSilently());
    });
  }

  Future<void> _reloadTaskSilently() async {
    try {
      final task = await widget.backend.getImportTask(widget.taskId);
      if (!mounted) return;
      setState(() => _applyTaskSnapshot(task));
    } catch (_) {
      // The active operation owns the user-facing error. Poll failures are transient.
    }
  }

  void _scheduleReview() {
    if (_reviewOpen || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openReview());
    });
  }

  Future<void> _openReview() async {
    if (_reviewOpen || !mounted) return;
    setState(() => _reviewOpen = true);
    try {
      // 重新打开任务（后台继续/未完成列表/重启）时本页内存里没有证据，
      // 从本地读取本次解析时已持久化的原始内容依据，供确认页展示与复制。
      _evidence ??= await widget.backend.getImportEvidence(widget.taskId);
      // 多草稿（IMAGE-002）：一次导入可能产出多份菜谱草稿。
      // 多草稿先弹选择框（每项=菜名，可"全部确认"一键添加）；
      // 单草稿直接进入确认页。
      var task = await widget.backend.getImportTask(widget.taskId);
      while (mounted && task.status == ImportTaskStatus.needsReview) {
        final recipeIds = task.allResultRecipeIds;
        if (recipeIds.isEmpty) break;
        if (recipeIds.length == 1) {
          await _pushReviewPage(taskId: widget.taskId, recipeId: recipeIds.single);
          // 单草稿确认页返回后任务要么完成、要么用户未操作返回；重载后退出。
          final reloaded = await _safeReloadTask();
          if (!mounted || reloaded == null || reloaded.status != ImportTaskStatus.needsReview) {
            break;
          }
          break;
        }
        // 多草稿：弹选择框。
        final action = await _showMultiDraftPicker(task);
        if (!mounted || action == null) {
          await _reloadTaskSilently();
          break;
        }
        if (action.confirmAll) {
          final confirmation = await widget.backend.confirmImportDraft(
            widget.taskId,
            confirmAll: true,
          );
          widget.onDataChanged();
          // 用 context.mounted 覆盖路由退场过渡期，避免在失效 context 上 pop。
          if (!context.mounted) return;
          Navigator.of(context).pop<Recipe>(confirmation.recipe);
          return;
        }
        await _pushReviewPage(taskId: widget.taskId, recipeId: action.recipeId!);
        if (!context.mounted) return;
        if (_poppedRecipe != null) {
          // 用户已在确认页保存该草稿：带回首页，任务后续状态由确认页决定。
          Navigator.of(context).pop<Recipe>(_poppedRecipe);
          return;
        }
        // 用户在确认页未保存直接返回：回到多草稿弹窗继续处理其他草稿
        // （返回本身不会添加任何菜谱；"全部确认"已有二次确认防误触）。
        final reloaded = await _safeReloadTask();
        if (!mounted) break;
        if (reloaded == null || reloaded.status != ImportTaskStatus.needsReview) {
          break;
        }
        task = reloaded;
      }
      await _reloadTaskSilently();
    } catch (_) {
      // 任务读取失败：回退单草稿确认（兼容旧版本行为）。
      if (!context.mounted) return;
      final result = await Navigator.of(context).push<ImportDraftReviewResult>(
        MaterialPageRoute<ImportDraftReviewResult>(
          builder: (context) => ImportDraftReviewPage(
            backend: widget.backend,
            taskId: widget.taskId,
            evidence: _evidence,
            onDataChanged: widget.onDataChanged,
          ),
        ),
      );
      if (!context.mounted) return;
      if (result?.recipe != null) {
        Navigator.of(context).pop<Recipe>(result!.recipe);
        return;
      }
      if (result?.discarded == true) {
        Navigator.of(context).pop<Recipe>();
        return;
      }
      await _reloadTaskSilently();
    } finally {
      if (mounted) setState(() => _reviewOpen = false);
    }
  }

  /// 草稿确认页返回后短暂保存的正式菜谱（用于多草稿逐份确认后带回首页）。
  Recipe? _poppedRecipe;

  Future<void> _pushReviewPage({
    required String taskId,
    required String recipeId,
  }) async {
    // 进入确认页前须确认 context 仍挂载（覆盖路由退场过渡期），
    // 避免在已 deactivate 的 Element 上 push 触发 framework 断言。
    if (!context.mounted) return;
    _poppedRecipe = null;
    final result = await Navigator.of(context).push<ImportDraftReviewResult>(
      MaterialPageRoute<ImportDraftReviewResult>(
        builder: (context) => ImportDraftReviewPage(
          backend: widget.backend,
          taskId: taskId,
          recipeId: recipeId,
          evidence: _evidence,
          onDataChanged: widget.onDataChanged,
        ),
      ),
    );
    if (!mounted) return;
    _poppedRecipe = result?.recipe;
  }

  /// 重新加载任务；失败返回 null（不抛错）。
  Future<ImportTask?> _safeReloadTask() async {
    try {
      return await widget.backend.getImportTask(widget.taskId);
    } catch (_) {
      return null;
    }
  }

  /// 多草稿选择框：列出每份草稿的菜名，支持点击进入编辑确认、单项删除、
  /// 多选删除与"全部确认"一键添加（IMAGE-002）。
  Future<_MultiDraftAction?> _showMultiDraftPicker(ImportTask task) async {
    final drafts = await Future.wait<Recipe>(
      task.allResultRecipeIds.map(
        (id) => widget.backend.getImportDraft(widget.taskId, recipeId: id),
      ),
    );
    // 拉取多份草稿期间用户可能已按返回键退出，须用 context.mounted 覆盖
    // deactivated 过渡期，避免在失效 context 上 showDialog 触发 framework 断言。
    if (!context.mounted) return null;
    return showDialog<_MultiDraftAction>(
      context: context,
      // 多草稿选择框只能通过右上角关闭按钮退出，点空白处不关闭，避免误触丢失弹窗。
      barrierDismissible: false,
      builder: (dialogContext) => _MultiDraftPickerDialog(
        backend: widget.backend,
        taskId: widget.taskId,
        drafts: drafts,
      ),
    );
  }

  Future<void> _cancel() async {
    if (_changingState) return;
    setState(() {
      _changingState = true;
      _cancellingTask = true;
      _pageError = null;
    });
    _cancellationToken?.cancel();
    try {
      final task = await widget.backend.cancelImportTask(widget.taskId);
      if (!mounted) return;
      setState(() => _applyTaskSnapshot(task));
      _notifyDataChangedSafely();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _pageError = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _changingState = false;
          _cancellingTask = false;
        });
      }
    }
  }

  Future<void> _retry() async {
    if (_changingState || _running) return;
    setState(() {
      _changingState = true;
      _pageError = null;
    });
    try {
      final task = await widget.backend.retryImportTask(widget.taskId);
      if (!mounted) return;
      setState(() => _applyTaskSnapshot(task));
      _notifyDataChangedSafely();
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _pageError = error.message);
      return;
    } finally {
      if (mounted) setState(() => _changingState = false);
    }
    await _run();
  }

  Future<void> _openCompletedRecipe() async {
    final recipeId = _task?.resultRecipeId;
    if (recipeId == null) return;
    try {
      final recipe = await widget.backend.getRecipe(recipeId);
      if (mounted) Navigator.of(context).pop<Recipe>(recipe);
    } on AiRecipeBackendException catch (error) {
      if (mounted) setState(() => _pageError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final working = _isWorking;
    // 解析中按返回：拦截并把任务转入后台继续（绝不取消）。
    // 其它状态（待确认/失败/已取消/已完成）不拦截，保持默认返回。
    return PopScope(
      canPop: _allowPop || !working,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !working) return;
        unawaited(_confirmLeaveToBackground());
      },
      child: Scaffold(
        appBar: const PixelPageAppBar(
          title: '解析中',
          eyebrow: 'AI 导入流程',
        ),
        body: _loading
            ? const AppLoadingState(label: '正在读取本地导入任务…')
            : _task == null
            ? _LoadFailure(message: _pageError, onRetry: _loadAndContinue)
            : _ProgressBody(
                task: _task!,
                pageError: _pageError,
                busy: _running || _changingState || _selectingImage,
                stateChangeBusy: _changingState,
                cancelBusy: _cancellingTask,
                onCancel: _cancel,
                onRetry: _retry,
                onReview: _openReview,
                onOpenRecipe: _openCompletedRecipe,
                onPastedTextFallback: _openPastedTextFallback,
                onImageFallback: _openImageFallback,
                onVideoFallback: _showVideoFallbackUnavailable,
                onManualFallback: _openManualEditor,
              ),
      ),
    );
  }
}

class _ProgressBody extends StatelessWidget {
  const _ProgressBody({
    required this.task,
    required this.pageError,
    required this.busy,
    required this.stateChangeBusy,
    required this.cancelBusy,
    required this.onCancel,
    required this.onRetry,
    required this.onReview,
    required this.onOpenRecipe,
    required this.onPastedTextFallback,
    required this.onImageFallback,
    required this.onVideoFallback,
    required this.onManualFallback,
  });

  final ImportTask task;
  final String? pageError;
  final bool busy;
  final bool stateChangeBusy;
  final bool cancelBusy;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onReview;
  final VoidCallback onOpenRecipe;
  final VoidCallback onPastedTextFallback;
  final VoidCallback onImageFallback;
  final VoidCallback onVideoFallback;
  final VoidCallback onManualFallback;

  bool get _isWorking =>
      task.status == ImportTaskStatus.queued ||
      task.status == ImportTaskStatus.running;

  @override
  Widget build(BuildContext context) {
    final progress = task.progress.clamp(0.0, 1.0);
    final hasPersistedTaskError =
        task.status == ImportTaskStatus.failed &&
        task.errorMessage?.trim().isNotEmpty == true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
      children: <Widget>[
        _SourceCard(task: task),
        const SizedBox(height: 20),
        PxLabel(_stageEyebrow(task.stage), color: AppColors.greenDeep),
        const SizedBox(height: 5),
        Text(
          _stageLabel(task.stage),
          key: const Key('importStageLabel'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        PixelProgressBar(
          key: const Key('importProgressIndicator'),
          value: progress,
        ),
        if (_isWorking) ...<Widget>[
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              const PixelLoader(size: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  // 运行中实时展示当前操作说明（如“正在识别第 2/3 张图片”
                  // “正在生成第 1/3 份草稿”）；没有详情时回退到静态提示。
                  task.progressDetail?.trim().isNotEmpty == true
                      ? task.progressDetail!
                      : 'AI 正在逐块拼装你的菜谱，稍等片刻',
                  key: const Key('importProgressDetailLabel'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        _StageTimeline(task: task),
        const SizedBox(height: 14),
        _StatusNotice(task: task),
        if (pageError?.trim().isNotEmpty == true && !hasPersistedTaskError)
          ...<Widget>[
            const SizedBox(height: 12),
            _InlineError(message: pageError!),
          ],
        const SizedBox(height: 18),
        ..._actions(context),
      ],
    );
  }

  List<Widget> _actions(BuildContext context) {
    switch (task.status) {
      case ImportTaskStatus.queued:
      case ImportTaskStatus.running:
        return <Widget>[
          OutlinedButton.icon(
            key: const Key('cancelImportButton'),
            onPressed: stateChangeBusy ? null : onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(cancelBusy ? '正在取消…' : '取消解析'),
          ),
        ];
      case ImportTaskStatus.needsReview:
        return <Widget>[
          FilledButton.icon(
            key: const Key('openImportDraftButton'),
            onPressed: busy ? null : onReview,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('确认 AI 草稿'),
          ),
        ];
      case ImportTaskStatus.failed:
        return <Widget>[
          _FallbackActions(
            busy: busy,
            onPastedText: onPastedTextFallback,
            onImage: onImageFallback,
            onVideo: onVideoFallback,
            onManual: onManualFallback,
          ),
          if (task.canRetry) ...<Widget>[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const Key('retryImportButton'),
              onPressed: busy ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('稍后重试（${task.attempt + 1}/${task.maxAttempts}）'),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('dismissFailedImportButton'),
            onPressed: busy ? null : onCancel,
            icon: const Icon(Icons.close_rounded),
            label: Text(cancelBusy ? '正在结束…' : '结束此导入'),
          ),
        ];
      case ImportTaskStatus.cancelled:
        return <Widget>[
          _FallbackActions(
            busy: busy,
            onPastedText: onPastedTextFallback,
            onImage: onImageFallback,
            onVideo: onVideoFallback,
            onManual: onManualFallback,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('returnFromCancelledImportButton'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('返回添加页'),
          ),
        ];
      case ImportTaskStatus.completed:
        return <Widget>[
          FilledButton.icon(
            key: const Key('openCompletedRecipeButton'),
            onPressed: task.resultRecipeId == null ? null : onOpenRecipe,
            icon: const Icon(Icons.menu_book_rounded),
            label: const Text('查看已保存菜谱'),
          ),
        ];
    }
  }
}

class _FallbackActions extends StatelessWidget {
  const _FallbackActions({
    required this.busy,
    required this.onPastedText,
    required this.onImage,
    required this.onVideo,
    required this.onManual,
  });

  final bool busy;
  final VoidCallback onPastedText;
  final VoidCallback onImage;
  final VoidCallback onVideo;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return PixelSurface(
      color: AppColors.card2,
      borderColor: AppColors.amber.withValues(alpha: .45),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const PxLabel('继续整理'),
          const SizedBox(height: 8),
          Text(
            '暂时无法获取公开内容',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '链接可能已失效，或平台限制了访问。选择一种降级方式继续，不必丢掉当前任务。',
            style: TextStyle(color: AppColors.ink2, height: 1.45),
          ),
          const SizedBox(height: 14),
          _FallbackRoute(
            buttonKey: const Key('pastedTextFallbackButton'),
            icon: Icons.content_paste_rounded,
            title: '粘贴正文',
            subtitle: '把原帖文字粘贴进来，由 AI 继续整理',
            badge: '推荐',
            onTap: busy ? null : onPastedText,
          ),
          const SizedBox(height: 8),
          _FallbackRoute(
            buttonKey: const Key('imageFallbackButton'),
            icon: Icons.image_outlined,
            title: '上传截图',
            subtitle: '使用本地 OCR 识别图片文字',
            badge: 'OCR',
            onTap: busy ? null : onImage,
          ),
          const SizedBox(height: 8),
          _FallbackRoute(
            buttonKey: const Key('videoFallbackButton'),
            icon: Icons.video_file_outlined,
            title: '上传视频',
            subtitle: '从视频语音和画面中提取菜谱信息',
            badge: 'ASR',
            onTap: busy ? null : onVideo,
          ),
          const SizedBox(height: 8),
          _FallbackRoute(
            buttonKey: const Key('manualRecipeFallbackButton'),
            icon: Icons.edit_note_rounded,
            title: '手动创建',
            subtitle: '跳过 AI，直接进入菜谱编辑器',
            badge: '离线',
            onTap: busy ? null : onManual,
          ),
          const SizedBox(height: 12),
          const PixelNotice(
            title: '失败详情仅保存在本地',
            message: '不会上传链接、日志或你选择的本地文件。',
            icon: Icons.privacy_tip_outlined,
            tone: PixelNoticeTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _FallbackRoute extends StatelessWidget {
  const _FallbackRoute({
    required this.buttonKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PixelRowTile(
    key: buttonKey,
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: PixelBadge(label: badge, tone: PixelNoticeTone.amber),
    onTap: onTap,
  );
}

class _PastedTextFallbackSheet extends StatefulWidget {
  const _PastedTextFallbackSheet({
    required this.sourceUrl,
    required this.onSubmit,
  });

  final String sourceUrl;
  final Future<ImportTaskRunResult> Function(String text) onSubmit;

  @override
  State<_PastedTextFallbackSheet> createState() =>
      _PastedTextFallbackSheetState();
}

class _PastedTextFallbackSheetState extends State<_PastedTextFallbackSheet> {
  final _controller = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先粘贴要整理的正文内容。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(text);
      if (!mounted) return;
      if (result.outcome != ImportTaskRunOutcome.needsReview) {
        setState(() {
          _busy = false;
          _error = result.task.errorMessage ?? '正文处理未完成，请修改后重试。';
        });
        return;
      }
      Navigator.of(context).pop(result);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '正文暂时无法处理，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: PixelSurface(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const PxLabel('本地处理'),
              const SizedBox(height: 6),
              Text(
                '粘贴正文继续',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                widget.sourceUrl,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: AppColors.ink3,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('fallbackTextField'),
                controller: _controller,
                enabled: !_busy,
                minLines: 6,
                maxLines: 12,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '菜谱正文',
                  hintText: '粘贴原文、配料和制作步骤……',
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const Key('submitPastedTextFallbackButton'),
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: PixelLoader(size: 3),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(_busy ? '正在生成草稿…' : '生成 AI 菜谱草稿'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.task});

  final ImportTask task;

  @override
  Widget build(BuildContext context) {
    // 快速导入"拍照选图/剪贴板"的占位任务：展示真实来源语义（本地图片/文本），
    // 不暴露内部占位链接（如 https://local-image/capture），避免误解为网页链接导入。
    final isLocalImage = task.sourceUrl == localImageCapturePlaceholderUrl;
    final isLocalText = task.sourceUrl == localTextCapturePlaceholderUrl;
    final title = isLocalImage
        ? '本地图片导入'
        : isLocalText
        ? '文本整理导入'
        : _platformLabel(task.sourcePlatform);
    final subtitle = isLocalImage
        ? '已选择本地图片，直接识别图片内容'
        : isLocalText
        ? '已粘贴本地正文，直接整理成菜谱'
        : task.normalizedUrl;
    final badge = isLocalImage
        ? '图片'
        : isLocalText
        ? '文本'
        : switch (task.sourcePlatform) {
            ImportSourcePlatform.xiaohongshu => 'XHS',
            ImportSourcePlatform.douyin => 'DY',
            ImportSourcePlatform.web => 'WEB',
          };
    return PixelSurface(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          ClipPath(
            clipper: const PixelCutClipper(cut: 3),
            child: SizedBox.square(
              dimension: 36,
              child: ColoredBox(
                color: AppColors.greenSoft,
                child: Icon(
                  isLocalImage
                      ? Icons.image_outlined
                      : isLocalText
                      ? Icons.content_paste_rounded
                      : Icons.link_rounded,
                  color: AppColors.greenDeep,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PixelBadge(
            label: badge,
            tone: PixelNoticeTone.green,
          ),
        ],
      ),
    );
  }
}

class _StageTimeline extends StatelessWidget {
  const _StageTimeline({required this.task});

  final ImportTask task;

  static const stages = <ImportTaskStage>[
    ImportTaskStage.queued,
    ImportTaskStage.fetching,
    ImportTaskStage.extracting,
    ImportTaskStage.ocr,
    ImportTaskStage.transcribing,
    ImportTaskStage.generating,
    ImportTaskStage.review,
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = stages.indexOf(task.stage);
    return PixelSurface(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 2),
      child: Column(
        children: stages.indexed.map((entry) {
          final index = entry.$1;
          final stage = entry.$2;
          final done =
              task.status == ImportTaskStatus.completed ||
              task.status == ImportTaskStatus.needsReview ||
              (currentIndex >= 0 && index < currentIndex);
          final current =
              currentIndex == index &&
              task.status != ImportTaskStatus.failed &&
              task.status != ImportTaskStatus.cancelled;
          return _StageRow(
            label: _stageLabel(stage),
            done: done,
            current: current,
            last: index == stages.length - 1,
          );
        }).toList(),
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.done,
    required this.current,
    required this.last,
  });

  final String label;
  final bool done;
  final bool current;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final activeColor = done || current ? AppColors.greenDeep : AppColors.line;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Column(
              children: <Widget>[
                ClipPath(
                  clipper: const PixelCutClipper(cut: 2),
                  child: SizedBox.square(
                    dimension: 22,
                    child: ColoredBox(
                      color: done
                          ? AppColors.greenDeep
                          : current
                          ? AppColors.greenSoft
                          : AppColors.paper2,
                      child: Center(
                        child: done
                            ? const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 14,
                              )
                            : current
                            ? const PixelLoader(size: 3)
                            : Container(
                                width: 8,
                                height: 8,
                                color: activeColor,
                              ),
                      ),
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? AppColors.green : AppColors.line2,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 15, top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: current || done
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: current || done ? AppColors.ink : AppColors.ink3,
                ),
              ),
            ),
          ),
          if (current)
            const Padding(
              padding: EdgeInsets.only(top: 3, bottom: 15),
              child: PixelBadge(label: '进行中', tone: PixelNoticeTone.green),
            ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.task});

  final ImportTask task;

  @override
  Widget build(BuildContext context) {
    final (icon, tone, title, message) = switch (task.status) {
      ImportTaskStatus.queued => (
        Icons.hourglass_top_rounded,
        PixelNoticeTone.blue,
        '等待开始',
        '任务已保存在本机队列中。',
      ),
      ImportTaskStatus.running => (
        Icons.auto_awesome_rounded,
        PixelNoticeTone.green,
        '正在解析',
        '可以离开本页，任务状态会保留在本机。',
      ),
      ImportTaskStatus.needsReview => (
        Icons.fact_check_outlined,
        PixelNoticeTone.amber,
        '解析完成，请确认后保存',
        'AI 结果不会自动发布，请重点检查低置信度内容。',
      ),
      ImportTaskStatus.completed => (
        Icons.check_circle_outline_rounded,
        PixelNoticeTone.green,
        '菜谱已保存',
        '导入任务已完成，可以打开正式菜谱。',
      ),
      ImportTaskStatus.failed => (
        Icons.error_outline_rounded,
        PixelNoticeTone.red,
        '导入失败',
        task.errorMessage ?? '暂时无法完成解析。',
      ),
      ImportTaskStatus.cancelled => (
        Icons.cancel_outlined,
        PixelNoticeTone.blue,
        '解析已取消',
        '任务和已生成的草稿不会自动保存为正式菜谱。',
      ),
    };
    return PixelNotice(
      title: title,
      message: task.status == ImportTaskStatus.failed
          ? '$message\n尝试 ${task.attempt}/${task.maxAttempts} · ${task.retryable ? '可重试' : '不可重试'}'
          : message,
      icon: icon,
      tone: tone,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => PixelNotice(
    title: '当前操作未完成',
    message: message,
    icon: Icons.error_outline_rounded,
    tone: PixelNoticeTone.red,
  );
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: AppErrorState(message: message ?? '导入任务暂时无法读取。', onRetry: onRetry),
    ),
  );
}

String _platformLabel(ImportSourcePlatform platform) => switch (platform) {
  ImportSourcePlatform.xiaohongshu => '小红书链接',
  ImportSourcePlatform.douyin => '抖音链接',
  ImportSourcePlatform.web => '网页链接',
};

String _stageEyebrow(ImportTaskStage stage) => switch (stage) {
  ImportTaskStage.queued => '已排队',
  ImportTaskStage.fetching => '阶段 1/6 · 获取内容',
  ImportTaskStage.extracting => '阶段 2/6 · 整理信息',
  ImportTaskStage.ocr => '阶段 3/6 · 识别图片',
  ImportTaskStage.transcribing => '阶段 4/6 · 识别语音',
  ImportTaskStage.generating => '阶段 5/6 · 生成菜谱',
  ImportTaskStage.review => '阶段 6/6 · 检查结果',
  ImportTaskStage.completed => '已完成',
  ImportTaskStage.failed => '导入失败',
  ImportTaskStage.cancelled => '已取消',
};

String _stageLabel(ImportTaskStage stage) => switch (stage) {
  ImportTaskStage.queued => '已加入解析队列',
  ImportTaskStage.fetching => '正在获取公开内容',
  ImportTaskStage.extracting => '正在整理正文、图片和视频信息',
  ImportTaskStage.ocr => '正在识别图片内容',
  ImportTaskStage.transcribing => '正在识别视频语音',
  ImportTaskStage.generating => '正在生成结构化菜谱',
  ImportTaskStage.review => '正在检查结果格式',
  ImportTaskStage.completed => '菜谱已保存',
  ImportTaskStage.failed => '导入失败',
  ImportTaskStage.cancelled => '已取消',
};

/// 多草稿选择动作：点击某份草稿进入编辑确认，或一键"全部确认"。
class _MultiDraftAction {
  const _MultiDraftAction({this.recipeId, this.confirmAll = false});

  final String? recipeId;
  final bool confirmAll;
}

/// 多草稿选择框（IMAGE-002）：像素风弹窗，标题"N 道菜谱"。
///
/// - 每项显示菜名，点击整行进入该草稿编辑确认；
/// - 每项右侧删除按钮可单独删除（草稿移入回收站可恢复）；
/// - 左侧勾选框支持多选，底部"删除所选"批量删除；
/// - 底部"全部确认"一键添加全部草稿。
class _MultiDraftPickerDialog extends StatefulWidget {
  const _MultiDraftPickerDialog({
    required this.backend,
    required this.taskId,
    required this.drafts,
  });

  final AiRecipeBackendFacade backend;
  final String taskId;
  final List<Recipe> drafts;

  @override
  State<_MultiDraftPickerDialog> createState() =>
      _MultiDraftPickerDialogState();
}

class _MultiDraftPickerDialogState extends State<_MultiDraftPickerDialog> {
  late List<Recipe> _drafts = widget.drafts;
  final Set<String> _selected = <String>{};

  /// 选择模式：长按某个草稿条目进入，此时点击条目只切换选中，
  /// 不会进入编辑确认页；取消全部选中后自动退出。
  var _selectionMode = false;
  var _busy = false;
  String? _error;

  /// 单个/批量删除草稿：删除后刷新剩余列表；全部删除则关闭弹窗由外层重载任务。
  Future<void> _deleteDrafts(Set<String> ids) async {
    if (_busy || ids.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final task = await widget.backend.deleteImportDrafts(
        widget.taskId,
        ids,
      );
      if (!mounted) return;
      if (task.status == ImportTaskStatus.needsReview) {
        final remaining = await Future.wait<Recipe>(
          task.allResultRecipeIds.map(
            (id) => widget.backend.getImportDraft(widget.taskId, recipeId: id),
          ),
        );
        if (!mounted) return;
        setState(() {
          _drafts = remaining;
          _selected.clear();
          _selectionMode = false;
        });
      } else {
        // 草稿已全部删除、任务已结束（取消/完成）：关闭弹窗，外层重载任务。
        Navigator.of(context).pop();
      }
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '草稿暂时无法删除，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 删除前二次确认（草稿移入回收站可恢复）。
  Future<void> _confirmDelete(Set<String> ids) async {
    if (_busy || ids.isEmpty) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: ids.length > 1 ? '删除所选 ${ids.length} 份草稿？' : '删除这份菜谱草稿？',
      message: '草稿将移入回收站（可恢复），导入任务将不再关联它。',
      confirmLabel: '删除',
      confirmColor: AppColors.red,
    );
    if (confirmed == true && mounted) {
      await _deleteDrafts(ids);
    }
  }

  /// 长按某个草稿条目：进入选择模式并选中该项。
  void _enterSelection(String recipeId) {
    if (_busy) return;
    setState(() {
      _selectionMode = true;
      _selected.add(recipeId);
    });
  }

  /// 切换选中状态；取消全部选中后自动退出选择模式。
  void _toggle(String recipeId, bool selected) {
    setState(() {
      if (selected) {
        _selectionMode = true;
        _selected.add(recipeId);
      } else {
        _selected.remove(recipeId);
        if (_selected.isEmpty) {
          _selectionMode = false;
        }
      }
    });
  }

  /// "全部确认"前二次确认：一键发布全部草稿是批量入库操作，防止误触。
  Future<void> _confirmConfirmAll() async {
    if (_busy || _drafts.isEmpty) return;
    final confirmed = await showPixelConfirm(
      context: context,
      title: '确认全部添加这 ${_drafts.length} 道菜谱？',
      message: '保存后可在菜谱库中查看和管理。若暂不确定，请选择"稍后处理"。',
      confirmLabel: '全部添加',
    );
    if (confirmed == true && mounted) {
      Navigator.of(
        context,
      ).pop(const _MultiDraftAction(confirmAll: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 弹窗容器用 PixelSurface（切角 + 墨色描边 + 硬投影），与整 UI 像素风格一致。
    // PopScope 拦截系统返回键：只有右上角关闭按钮才能退出弹窗。
    return PopScope(
      canPop: false,
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '本次识别到 ${_drafts.length} 道菜谱',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _selectionMode
                                ? '已选择 ${_selected.length} 项：点按切换选中，或删除所选'
                                : '点击进入编辑确认，长按可多选删除，或一键全部添加',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 右上角关闭按钮：弹窗唯一退出入口。
                    PixelIconBtn(
                      icon: Icons.close_rounded,
                      tooltip: '关闭',
                      size: 30,
                      iconSize: 16,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null) ...[
                  PixelNotice(title: _error!, tone: PixelNoticeTone.red),
                  const SizedBox(height: 8),
                ],
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _drafts.length,
                    itemBuilder: (context, index) =>
                        _buildDraftTile(_drafts[index]),
                  ),
                ),
                const SizedBox(height: 12),
                // Wrap 自动换行，避免"删除所选"与"全部确认"同时出现时横向溢出。
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (_selected.isNotEmpty)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _confirmDelete(Set<String>.of(_selected)),
                        child: Text('删除所选 (${_selected.length})'),
                      ),
                    FilledButton(
                      onPressed: _busy ? null : _confirmConfirmAll,
                      child: const Text('全部确认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 单份草稿条目：勾选框（多选） + 菜名/简介 + 单个删除按钮。
  ///
  /// 长按条目进入选择模式（与点击由同一 InkWell 处理，互斥且稳定）；
  /// 选择模式下点按只切换选中，不进入编辑确认页。
  Widget _buildDraftTile(Recipe draft) {
    final selected = _selected.contains(draft.id);
    final description = draft.description?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: PixelSurface(
        cut: 6,
        elevation: 0,
        color: selected ? AppColors.greenSofter : AppColors.card,
        borderColor: selected ? AppColors.greenDeep : AppColors.line2,
        borderWidth: 1.5,
        onTap: _busy
            ? null
            : () {
                if (_selectionMode) {
                  // 选择模式下：点按切换选中。
                  _toggle(draft.id, !selected);
                } else {
                  // 普通模式：点击进入该草稿编辑确认页。
                  Navigator.of(
                    context,
                  ).pop(_MultiDraftAction(recipeId: draft.id));
                }
              },
        // 长按选择（多选删除的移动端习惯入口）。
        onLongPress: _busy ? null : () => _enterSelection(draft.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: <Widget>[
              _buildCheckbox(
                selected: selected,
                onChanged: _busy
                    ? null
                    : () => _toggle(draft.id, !selected),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      draft.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (description != null && description.isNotEmpty)
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.ink3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              PixelIconBtn(
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.red,
                tooltip: '删除草稿',
                size: 30,
                iconSize: 16,
                onTap: _busy
                    ? () {}
                    : () => _confirmDelete(<String>{draft.id}),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 像素风勾选框：选中时绿色填充 + 白色对勾。
  Widget _buildCheckbox({
    required bool selected,
    required VoidCallback? onChanged,
  }) {
    return GestureDetector(
      onTap: onChanged,
      child: PixelSurface(
        cut: 4,
        elevation: 0,
        color: selected ? AppColors.greenDeep : AppColors.card,
        borderColor: selected ? AppColors.greenDeep : AppColors.line2,
        borderWidth: 1.5,
        child: SizedBox.square(
          dimension: 20,
          child: selected
              ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}

