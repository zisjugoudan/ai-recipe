import 'dart:math' as math;

import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_content.dart';
import '../../domain/importing/import_content_adapter.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import 'import_pipeline_contracts.dart';
import 'import_task_use_cases.dart';

enum ImportTaskRunOutcome { needsReview, failed, cancelled }

class ImportTaskRunResult {
  const ImportTaskRunResult({
    required this.task,
    required this.outcome,
    this.content,
  });

  final ImportTask task;
  final ImportTaskRunOutcome outcome;
  final ImportContent? content;
}

class ImportRetryPolicy {
  const ImportRetryPolicy({
    this.initialDelay = const Duration(seconds: 30),
    this.maximumDelay = const Duration(minutes: 15),
  });

  final Duration initialDelay;
  final Duration maximumDelay;

  Duration delayForAttempt(int attempt) {
    if (attempt < 1) {
      throw ArgumentError.value(attempt, 'attempt', 'must be at least 1');
    }
    var milliseconds = initialDelay.inMilliseconds;
    for (var index = 1; index < attempt; index += 1) {
      milliseconds = math.min(milliseconds * 2, maximumDelay.inMilliseconds);
    }
    return Duration(milliseconds: milliseconds);
  }
}

class ImportTaskRunner {
  ImportTaskRunner({
    required ImportTaskRepository repository,
    required ImportContentAdapterRegistry adapterRegistry,
    required ImportContentProcessor processor,
    required ImportRecipeDraftDiscarder discardRecipeDraft,
    required ImportTaskClock clock,
    ImportRetryPolicy retryPolicy = const ImportRetryPolicy(),
  }) : _repository = repository,
       _adapterRegistry = adapterRegistry,
       _processor = processor,
       _discardRecipeDraft = discardRecipeDraft,
       _clock = clock,
       _retryPolicy = retryPolicy;

  final ImportTaskRepository _repository;
  final ImportContentAdapterRegistry _adapterRegistry;
  final ImportContentProcessor _processor;
  final ImportRecipeDraftDiscarder _discardRecipeDraft;
  final ImportTaskClock _clock;
  final ImportRetryPolicy _retryPolicy;

  static const Set<ImportTaskStage> _processorStages = <ImportTaskStage>{
    ImportTaskStage.extracting,
    ImportTaskStage.ocr,
    ImportTaskStage.transcribing,
    ImportTaskStage.generating,
  };

  Future<ImportTaskRunResult> run(
    String taskId, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final initial = await _loadTask(taskId);
    if (initial.status != ImportTaskStatus.queued) {
      throw const ImportTaskTransitionException(
        'Only queued import tasks can be run.',
      );
    }
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledResult(taskId, content: null);
    }

    var current = await _start(taskId);
    if (current.status == ImportTaskStatus.cancelled) {
      return _cancelledResult(taskId, content: null, task: current);
    }
    ImportContent? content;

    try {
      final source = _sourceForTask(current);
      final adapter = _adapterRegistry.adapterFor(current.sourcePlatform);
      content = await adapter.fetch(
        source,
        cancellationToken: cancellationToken,
      );
      final cancelled = await _cancelIfRequestedOrPersisted(
        taskId,
        cancellationToken,
      );
      if (cancelled != null) {
        return _cancelledResult(taskId, content: content, task: cancelled);
      }
      _validateContentSource(source, content);

      current = await _advance(
        taskId,
        stage: ImportTaskStage.extracting,
        progress: math.max(current.progress, 0.25),
      );
      if (current.status == ImportTaskStatus.cancelled) {
        return _cancelledResult(taskId, content: content, task: current);
      }
      return await _processStartedTask(
        taskId,
        current: current,
        content: content,
        cancellationToken: cancellationToken,
        allowPipelineRetry: true,
      );
    } on ImportOperationCancelledException {
      return _cancelledResult(taskId, content: content);
    } on ImportContentAdapterException catch (error) {
      if (error.kind == ImportContentAdapterErrorKind.cancelled) {
        return _cancelledResult(taskId, content: content);
      }
      return _failedOrCancelled(
        taskId,
        code: _mapAdapterError(error.kind),
        message: error.message,
        retryable: error.retryable,
        content: content,
        cancellationToken: cancellationToken,
      );
    } catch (_) {
      return _failedOrCancelled(
        taskId,
        code: ImportTaskErrorCode.unknown,
        message: 'The import failed unexpectedly.',
        retryable: false,
        content: content,
        cancellationToken: cancellationToken,
      );
    }
  }

  Future<ImportTaskRunResult> runWithContent(
    String taskId,
    ImportContent content, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final initial = await _loadTask(taskId);
    // 允许三类任务用内容运行：排队任务（快速导入"拍照选图/剪贴板"新建的
    // 占位任务，IMPORT-009）与失败/已取消任务（人工降级输入）。
    if (initial.status != ImportTaskStatus.queued &&
        initial.status != ImportTaskStatus.failed &&
        initial.status != ImportTaskStatus.cancelled) {
      throw const ImportTaskTransitionException(
        '只有排队、失败或已取消的导入任务可以使用内容运行。',
      );
    }
    _validateContentSource(_sourceForTask(initial), content);
    if (cancellationToken?.isCancelled ?? false) {
      return _cancelledResult(taskId, content: content);
    }

    final current = await _startWithFallback(taskId);
    if (current.status == ImportTaskStatus.cancelled) {
      return _cancelledResult(taskId, content: content, task: current);
    }
    return _processStartedTask(
      taskId,
      current: current,
      content: content,
      cancellationToken: cancellationToken,
      allowPipelineRetry: false,
    );
  }

  /// 待确认任务使用既有原文重新生成草稿。
  ///
  /// - 只接受 `needsReview` 状态的任务；复用调用方传入的原文 `content` 重新执行
  ///   Processor，不重新抓取、不重新 OCR/ASR。
  /// - 成功后把任务 `resultRecipeId` 指向新草稿（状态保持 `needsReview`），并
  ///   best-effort 安全删除旧草稿（只删除 ID、来源匹配且仍为草稿的数据）。
  /// - 失败时任务保持 `needsReview`、旧草稿保留，把 `ImportPipelineException`
  ///   抛给上层显示稳定错误，不把任务标记为失败。
  Future<ImportTaskRunResult> regenerateWithContent(
    String taskId,
    ImportContent content, {
    ImportCancellationToken? cancellationToken,
  }) async {
    final initial = await _loadTask(taskId);
    if (initial.status != ImportTaskStatus.needsReview) {
      throw const ImportTaskTransitionException(
        '只有待确认的导入任务可以重新生成。',
      );
    }
    _validateContentSource(_sourceForTask(initial), content);

    final oldRecipeId = initial.resultRecipeId;
    String? generatedRecipeId;
    List<String> generatedAdditionalIds = const <String>[];
    try {
      final draft = await _processor.process(
        content,
        // 重新生成不推进任务阶段（任务保持 review），因此使用空进度回调。
        onProgress: (_, _, [detail]) async {},
        cancellationToken: cancellationToken,
      );
      generatedRecipeId = draft.recipeId;
      generatedAdditionalIds = draft.additionalRecipeIds;
    } on ImportOperationCancelledException {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.cancelled,
        message: '重新生成已取消。',
        retryable: false,
      );
    } on ImportPipelineException {
      // 保持 needsReview，旧草稿保留，错误由上层展示。
      rethrow;
    } catch (_) {
      throw const ImportPipelineException(
        code: ImportTaskErrorCode.unknown,
        message: '重新生成失败，请稍后重试。',
        retryable: false,
      );
    }

    // 任务关联新草稿（保持 needsReview、localVersion 递增）。
    final updated = await _reassignResultRecipe(
      taskId,
      generatedRecipeId!,
      additionalRecipeIds: generatedAdditionalIds,
    );

    // 新草稿关联成功后，best-effort 清理旧草稿；清理失败不阻断重新生成成功，
    // 安全丢弃器仍保证不会误删正式菜谱或不匹配来源的草稿。
    if (oldRecipeId != null && oldRecipeId != generatedRecipeId) {
      try {
        await _discardRecipeDraft(
          recipeId: oldRecipeId,
          sourceId: initial.normalizedUrl,
        );
      } catch (_) {
        // best-effort：残留的孤立草稿不参与任务关联，不影响用户操作。
      }
    }

    return ImportTaskRunResult(
      task: updated,
      outcome: ImportTaskRunOutcome.needsReview,
      content: content,
    );
  }

  Future<ImportTaskRunResult> _processStartedTask(
    String taskId, {
    required ImportTask current,
    required ImportContent content,
    required bool allowPipelineRetry,
    ImportCancellationToken? cancellationToken,
  }) async {
    var active = current;
    String? generatedRecipeId;
    List<String> generatedAdditionalIds = const <String>[];
    try {
      final draft = await _processor.process(
        content,
        cancellationToken: cancellationToken,
        onProgress: (stage, progress, [detail]) async {
          cancellationToken?.throwIfCancelled();
          if (!_processorStages.contains(stage)) {
            throw const ImportPipelineException(
              code: ImportTaskErrorCode.schemaInvalid,
              message: 'The processor reported an unsupported task stage.',
              retryable: false,
            );
          }
          try {
            active = await _advance(
              taskId,
              stage: stage,
              progress: progress,
              detail: detail,
            );
            if (active.status == ImportTaskStatus.cancelled) {
              throw const ImportOperationCancelledException();
            }
          } on ImportTaskTransitionException catch (error) {
            throw ImportPipelineException(
              code: ImportTaskErrorCode.schemaInvalid,
              message: _sanitizeMessage(
                error.message,
                fallback: 'Invalid import task progress.',
              ),
              retryable: false,
            );
          }
        },
      );
      generatedRecipeId = draft.recipeId;
      generatedAdditionalIds = draft.additionalRecipeIds;

      final cancelled = await _cancelIfRequestedOrPersisted(
        taskId,
        cancellationToken,
      );
      if (cancelled != null) {
        return _cancelledResult(
          taskId,
          content: content,
          task: cancelled,
          recipeId: generatedRecipeId,
          sourceId: active.normalizedUrl,
        );
      }

      if (active.stage != ImportTaskStage.generating || active.progress < 0.9) {
        active = await _advance(
          taskId,
          stage: ImportTaskStage.generating,
          progress: math.max(active.progress, 0.9),
        );
        if (active.status == ImportTaskStatus.cancelled) {
          return _cancelledResult(
            taskId,
            content: content,
            task: active,
            recipeId: generatedRecipeId,
            sourceId: current.normalizedUrl,
          );
        }
      }

      active = await _markNeedsReview(
        taskId,
        recipeId: generatedRecipeId,
        additionalRecipeIds: generatedAdditionalIds,
      );
      if (active.status == ImportTaskStatus.cancelled) {
        return _cancelledResult(
          taskId,
          content: content,
          task: active,
          recipeId: generatedRecipeId,
          sourceId: current.normalizedUrl,
        );
      }

      final latest = await _loadTask(taskId);
      if (latest.status == ImportTaskStatus.cancelled) {
        return _cancelledResult(
          taskId,
          content: content,
          task: latest,
          recipeId: generatedRecipeId,
          sourceId: current.normalizedUrl,
        );
      }
      return ImportTaskRunResult(
        task: latest,
        outcome: ImportTaskRunOutcome.needsReview,
        content: content,
      );
    } on ImportOperationCancelledException {
      return _cancelledResult(
        taskId,
        content: content,
        recipeId: generatedRecipeId,
        sourceId: generatedRecipeId == null ? null : current.normalizedUrl,
      );
    } on ImportPipelineException catch (error) {
      if (error.code == ImportTaskErrorCode.cancelled) {
        return _cancelledResult(
          taskId,
          content: content,
          recipeId: generatedRecipeId,
          sourceId: generatedRecipeId == null ? null : current.normalizedUrl,
        );
      }
      return _failedOrCancelled(
        taskId,
        code: error.code,
        message: error.message,
        retryable: allowPipelineRetry && error.retryable,
        content: content,
        cancellationToken: cancellationToken,
        recipeId: generatedRecipeId,
        sourceId: generatedRecipeId == null ? null : current.normalizedUrl,
      );
    } catch (_) {
      return _failedOrCancelled(
        taskId,
        code: ImportTaskErrorCode.unknown,
        message: 'The import failed unexpectedly.',
        retryable: false,
        content: content,
        cancellationToken: cancellationToken,
        recipeId: generatedRecipeId,
        sourceId: generatedRecipeId == null ? null : current.normalizedUrl,
      );
    }
  }

  Future<ImportTaskRunResult> _failedOrCancelled(
    String taskId, {
    required ImportTaskErrorCode code,
    required String message,
    required bool retryable,
    required ImportContent? content,
    ImportCancellationToken? cancellationToken,
    String? recipeId,
    String? sourceId,
  }) async {
    final cancellation = await _cancelIfRequestedOrPersisted(
      taskId,
      cancellationToken,
    );
    if (cancellation != null) {
      return _cancelledResult(
        taskId,
        task: cancellation,
        content: content,
        recipeId: recipeId,
        sourceId: sourceId,
      );
    }

    final failed = await _fail(
      taskId,
      code: code,
      message: message,
      retryable: retryable,
    );
    if (failed.status == ImportTaskStatus.cancelled) {
      return _cancelledResult(
        taskId,
        task: failed,
        content: content,
        recipeId: recipeId,
        sourceId: sourceId,
      );
    }
    await _discardGeneratedDraft(recipeId: recipeId, sourceId: sourceId);
    return ImportTaskRunResult(
      task: failed,
      outcome: ImportTaskRunOutcome.failed,
      content: content,
    );
  }

  Future<ImportTaskRunResult> _cancelledResult(
    String taskId, {
    required ImportContent? content,
    ImportTask? task,
    String? recipeId,
    String? sourceId,
  }) async {
    final cancelled = task?.status == ImportTaskStatus.cancelled
        ? task!
        : await _cancel(taskId);
    await _discardGeneratedDraft(recipeId: recipeId, sourceId: sourceId);
    return ImportTaskRunResult(
      task: cancelled,
      outcome: ImportTaskRunOutcome.cancelled,
      content: content,
    );
  }

  Future<void> _discardGeneratedDraft({
    required String? recipeId,
    required String? sourceId,
  }) async {
    if (recipeId == null || sourceId == null) {
      return;
    }
    await _discardRecipeDraft(recipeId: recipeId, sourceId: sourceId);
  }

  Future<ImportTask?> _cancelIfRequestedOrPersisted(
    String taskId,
    ImportCancellationToken? cancellationToken,
  ) async {
    final latest = await _loadTask(taskId);
    if (latest.status == ImportTaskStatus.cancelled) {
      return latest;
    }
    if (cancellationToken?.isCancelled ?? false) {
      return _cancel(taskId);
    }
    return null;
  }

  Future<ImportTask> _loadTask(String taskId) async {
    final task = await _repository.getTaskById(taskId);
    if (task == null) {
      throw ImportTaskNotFoundException(taskId);
    }
    return task;
  }

  Future<ImportTask> _start(String taskId) async {
    try {
      return await StartImportTask(repository: _repository, clock: _clock)(
        taskId,
      );
    } on ImportTaskWriteConflictException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    } on ImportTaskTransitionException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    }
  }

  Future<ImportTask> _startWithFallback(String taskId) async {
    try {
      return await StartImportTaskWithFallback(
        repository: _repository,
        clock: _clock,
      )(taskId);
    } on ImportTaskWriteConflictException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    } on ImportTaskTransitionException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    }
  }

  /// 并发进度上报（如多草稿并发生成）写同一任务时的有限重试次数。
  /// 乐观锁写冲突或进度交错回退不应让整单失败。
  static const int _progressWriteRetries = 3;

  Future<ImportTask> _advance(
    String taskId, {
    required ImportTaskStage stage,
    required double progress,
    String? detail,
  }) async {
    var safeProgress = progress;
    for (var attempt = 0;; attempt += 1) {
      try {
        return await AdvanceImportTask(repository: _repository, clock: _clock)(
          taskId,
          stage: stage,
          progress: safeProgress,
          progressDetail: detail,
        );
      } on ImportTaskWriteConflictException catch (error) {
        if (attempt >= _progressWriteRetries) {
          return _latestCancellationOrRethrow(taskId, error);
        }
        final latest = await _loadTask(taskId);
        if (latest.status == ImportTaskStatus.cancelled) return latest;
        // 并发上报交错：以最新已保存进度为下限重试，保证保存值单调不减。
        safeProgress = math.max(safeProgress, latest.progress);
      } on ImportTaskTransitionException catch (error) {
        final latest = await _loadTask(taskId);
        if (latest.status == ImportTaskStatus.cancelled) return latest;
        // 进度倒退（并发交错）：基于最新版本取 max 后重试；其余非法转移
        // （状态/阶段不匹配）不是并发引起，原样抛出交由上层定位。
        if (latest.stage == stage && latest.progress > safeProgress) {
          safeProgress = math.max(safeProgress, latest.progress);
          continue;
        }
        return _latestCancellationOrRethrow(taskId, error);
      }
    }
  }

  Future<ImportTask> _markNeedsReview(
    String taskId, {
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
  }) async {
    try {
      return await MarkImportTaskNeedsReview(
        repository: _repository,
        clock: _clock,
      )(taskId, recipeId: recipeId, additionalRecipeIds: additionalRecipeIds);
    } on ImportTaskWriteConflictException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    } on ImportTaskTransitionException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    }
  }

  Future<ImportTask> _reassignResultRecipe(
    String taskId,
    String recipeId, {
    List<String> additionalRecipeIds = const <String>[],
  }) async {
    try {
      return await ReassignImportTaskRecipe(
        repository: _repository,
        clock: _clock,
      )(taskId, recipeId: recipeId, additionalRecipeIds: additionalRecipeIds);
    } on ImportTaskWriteConflictException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    } on ImportTaskTransitionException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    }
  }

  /// 并发写入冲突或非法状态转移时：若任务已被取消则返回最新取消状态（优雅
  /// 收尾），否则把原始异常原样抛出，避免用误导性消息（如
  /// “Only queued import tasks can be run.”）掩盖真实错误（如进度倒退、
  /// 阶段回退），保证失败原因可被上层准确定位。
  Future<ImportTask> _latestCancellationOrRethrow(
    String taskId,
    Object originalError,
  ) async {
    final latest = await _loadTask(taskId);
    if (latest.status == ImportTaskStatus.cancelled) {
      return latest;
    }
    Error.throwWithStackTrace(originalError, StackTrace.current);
  }

  Future<ImportTask> _cancel(String taskId) {
    return CancelImportTask(repository: _repository, clock: _clock)(taskId);
  }

  Future<ImportTask> _fail(
    String taskId, {
    required ImportTaskErrorCode code,
    required String message,
    required bool retryable,
  }) async {
    final task = await _loadTask(taskId);
    if (task.status == ImportTaskStatus.cancelled) {
      return task;
    }
    final nextRetryAt = retryable
        ? _clock().add(_retryPolicy.delayForAttempt(task.attempt))
        : null;
    try {
      return await FailImportTask(repository: _repository, clock: _clock)(
        taskId,
        code: code,
        message: _sanitizeMessage(message, fallback: 'Import task failed.'),
        retryable: retryable,
        nextRetryAt: nextRetryAt,
      );
    } on ImportTaskWriteConflictException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    } on ImportTaskTransitionException catch (error) {
      return _latestCancellationOrRethrow(taskId, error);
    }
  }

  static ImportSourceLink _sourceForTask(ImportTask task) => ImportSourceLink(
    sourceUrl: task.sourceUrl,
    normalizedUrl: task.normalizedUrl,
    platform: task.sourcePlatform,
  );

  static void _validateContentSource(
    ImportSourceLink expected,
    ImportContent content,
  ) {
    if (content.source.platform != expected.platform ||
        content.source.normalizedUrl != expected.normalizedUrl) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The content belongs to a different import source.',
        retryable: false,
      );
    }
  }

  static ImportTaskErrorCode _mapAdapterError(
    ImportContentAdapterErrorKind kind,
  ) => switch (kind) {
    ImportContentAdapterErrorKind.unsupportedPlatform =>
      ImportTaskErrorCode.unsupportedPlatform,
    ImportContentAdapterErrorKind.contentUnavailable =>
      ImportTaskErrorCode.contentUnavailable,
    ImportContentAdapterErrorKind.authorizationRequired =>
      ImportTaskErrorCode.authorizationRequired,
    ImportContentAdapterErrorKind.networkUnavailable =>
      ImportTaskErrorCode.networkUnavailable,
    ImportContentAdapterErrorKind.timeout => ImportTaskErrorCode.timeout,
    ImportContentAdapterErrorKind.invalidPayload =>
      ImportTaskErrorCode.extractionFailed,
    ImportContentAdapterErrorKind.cancelled => ImportTaskErrorCode.cancelled,
    ImportContentAdapterErrorKind.unknown => ImportTaskErrorCode.fetchFailed,
  };

  static String _sanitizeMessage(String message, {required String fallback}) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return fallback;
    }
    return normalized.length <= 240
        ? normalized
        : '${normalized.substring(0, 237)}...';
  }
}
