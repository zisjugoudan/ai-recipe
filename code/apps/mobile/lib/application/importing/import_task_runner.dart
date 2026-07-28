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
    required ImportTaskClock clock,
    ImportRetryPolicy retryPolicy = const ImportRetryPolicy(),
  }) : _repository = repository,
       _adapterRegistry = adapterRegistry,
       _processor = processor,
       _clock = clock,
       _retryPolicy = retryPolicy;

  final ImportTaskRepository _repository;
  final ImportContentAdapterRegistry _adapterRegistry;
  final ImportContentProcessor _processor;
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

    cancellationToken?.throwIfCancelled();
    var current = await StartImportTask(repository: _repository, clock: _clock)(
      taskId,
    );
    ImportContent? content;

    try {
      cancellationToken?.throwIfCancelled();
      final source = ImportSourceLink(
        sourceUrl: current.sourceUrl,
        normalizedUrl: current.normalizedUrl,
        platform: current.sourcePlatform,
      );
      final adapter = _adapterRegistry.adapterFor(current.sourcePlatform);
      content = await adapter.fetch(
        source,
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancelled();
      _validateAdapterResult(source, content);

      current = await _advance(
        taskId,
        stage: ImportTaskStage.extracting,
        progress: math.max(current.progress, 0.25),
      );

      final draft = await _processor.process(
        content,
        cancellationToken: cancellationToken,
        onProgress: (stage, progress) async {
          cancellationToken?.throwIfCancelled();
          if (!_processorStages.contains(stage)) {
            throw const ImportPipelineException(
              code: ImportTaskErrorCode.schemaInvalid,
              message: 'The processor reported an unsupported task stage.',
              retryable: false,
            );
          }
          try {
            current = await _advance(taskId, stage: stage, progress: progress);
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
      cancellationToken?.throwIfCancelled();

      if (current.stage != ImportTaskStage.generating ||
          current.progress < 0.9) {
        current = await _advance(
          taskId,
          stage: ImportTaskStage.generating,
          progress: math.max(current.progress, 0.9),
        );
      }
      current = await MarkImportTaskNeedsReview(
        repository: _repository,
        clock: _clock,
      )(taskId, recipeId: draft.recipeId);
      return ImportTaskRunResult(
        task: current,
        outcome: ImportTaskRunOutcome.needsReview,
        content: content,
      );
    } on ImportOperationCancelledException {
      current = await _cancel(taskId);
      return ImportTaskRunResult(
        task: current,
        outcome: ImportTaskRunOutcome.cancelled,
        content: content,
      );
    } on ImportContentAdapterException catch (error) {
      if (error.kind == ImportContentAdapterErrorKind.cancelled) {
        current = await _cancel(taskId);
        return ImportTaskRunResult(
          task: current,
          outcome: ImportTaskRunOutcome.cancelled,
          content: content,
        );
      }
      current = await _fail(
        taskId,
        code: _mapAdapterError(error.kind),
        message: error.message,
        retryable: error.retryable,
      );
      return ImportTaskRunResult(
        task: current,
        outcome: ImportTaskRunOutcome.failed,
        content: content,
      );
    } on ImportPipelineException catch (error) {
      if (error.code == ImportTaskErrorCode.cancelled) {
        current = await _cancel(taskId);
        return ImportTaskRunResult(
          task: current,
          outcome: ImportTaskRunOutcome.cancelled,
          content: content,
        );
      }
      current = await _fail(
        taskId,
        code: error.code,
        message: error.message,
        retryable: error.retryable,
      );
      return ImportTaskRunResult(
        task: current,
        outcome: ImportTaskRunOutcome.failed,
        content: content,
      );
    } catch (_) {
      current = await _fail(
        taskId,
        code: ImportTaskErrorCode.unknown,
        message: 'The import failed unexpectedly.',
        retryable: false,
      );
      return ImportTaskRunResult(
        task: current,
        outcome: ImportTaskRunOutcome.failed,
        content: content,
      );
    }
  }

  Future<ImportTask> _loadTask(String taskId) async {
    final task = await _repository.getTaskById(taskId);
    if (task == null) {
      throw ImportTaskNotFoundException(taskId);
    }
    return task;
  }

  Future<ImportTask> _advance(
    String taskId, {
    required ImportTaskStage stage,
    required double progress,
  }) {
    return AdvanceImportTask(repository: _repository, clock: _clock)(
      taskId,
      stage: stage,
      progress: progress,
    );
  }

  Future<ImportTask> _cancel(String taskId) {
    return CancelImportTask(repository: _repository, clock: _clock)(taskId);
  }

  Future<ImportTask> _fail(
    String taskId, {
    required ImportTaskErrorCode code,
    required String message,
    required bool retryable,
  }) {
    final taskFuture = _loadTask(taskId);
    return taskFuture.then((task) {
      final nextRetryAt = retryable
          ? _clock().add(_retryPolicy.delayForAttempt(task.attempt))
          : null;
      return FailImportTask(repository: _repository, clock: _clock)(
        taskId,
        code: code,
        message: _sanitizeMessage(message, fallback: 'Import task failed.'),
        retryable: retryable,
        nextRetryAt: nextRetryAt,
      );
    });
  }

  static void _validateAdapterResult(
    ImportSourceLink expected,
    ImportContent content,
  ) {
    if (content.source.platform != expected.platform ||
        content.source.normalizedUrl != expected.normalizedUrl) {
      throw const ImportContentAdapterException(
        kind: ImportContentAdapterErrorKind.invalidPayload,
        message: 'The adapter returned content for a different source.',
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
