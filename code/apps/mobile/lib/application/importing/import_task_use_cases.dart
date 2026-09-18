import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';

typedef ImportTaskIdGenerator = String Function();
typedef ImportTaskClock = DateTime Function();

class ImportTaskNotFoundException implements Exception {
  const ImportTaskNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'ImportTaskNotFoundException: $id';
}

class CreateImportTask {
  const CreateImportTask({
    required ImportTaskRepository repository,
    required ImportTaskIdGenerator idGenerator,
    required ImportTaskClock clock,
  }) : _repository = repository,
       _idGenerator = idGenerator,
       _clock = clock;

  final ImportTaskRepository _repository;
  final ImportTaskIdGenerator _idGenerator;
  final ImportTaskClock _clock;

  Future<ImportTask> call(String sourceUrl, {int maxAttempts = 3}) async {
    final source = ImportSourceLink.parse(sourceUrl);
    final task = ImportTask.queued(
      id: _idGenerator(),
      source: source,
      now: _clock(),
      maxAttempts: maxAttempts,
    );
    await _repository.upsertTask(task, expectedLocalVersion: null);
    return task;
  }
}

abstract class _ExistingImportTaskUseCase {
  const _ExistingImportTaskUseCase(this.repository, this.clock);

  final ImportTaskRepository repository;
  final ImportTaskClock clock;

  Future<ImportTask> load(String id) async {
    final task = await repository.getTaskById(id);
    if (task == null) {
      throw ImportTaskNotFoundException(id);
    }
    return task;
  }

  Future<ImportTask> save(ImportTask previous, ImportTask updated) async {
    if (identical(previous, updated)) {
      return previous;
    }
    await repository.upsertTask(
      updated,
      expectedLocalVersion: previous.localVersion,
    );
    return updated;
  }
}

class StartImportTask extends _ExistingImportTaskUseCase {
  const StartImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task, task.start(clock()));
  }
}

class StartImportTaskWithFallback extends _ExistingImportTaskUseCase {
  const StartImportTaskWithFallback({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task, task.startWithFallback(clock()));
  }
}

class AdvanceImportTask extends _ExistingImportTaskUseCase {
  const AdvanceImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(
    String id, {
    required ImportTaskStage stage,
    required double progress,
    // 进度详情（可选）：运行中实时展示的当前操作说明；不传则保留已有详情。
    String? progressDetail,
  }) async {
    final task = await load(id);
    return save(
      task,
      task.advance(
        nextStage: stage,
        nextProgress: progress,
        progressDetail: progressDetail,
        now: clock(),
      ),
    );
  }
}

class MarkImportTaskNeedsReview extends _ExistingImportTaskUseCase {
  const MarkImportTaskNeedsReview({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(
    String id, {
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
  }) async {
    final task = await load(id);
    return save(
      task,
      task.markNeedsReview(
        recipeId: recipeId,
        additionalRecipeIds: additionalRecipeIds,
        now: clock(),
      ),
    );
  }
}

/// 待确认任务更换关联草稿（用于“重新生成”）。
class ReassignImportTaskRecipe extends _ExistingImportTaskUseCase {
  const ReassignImportTaskRecipe({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(
    String id, {
    required String recipeId,
    List<String> additionalRecipeIds = const <String>[],
  }) async {
    final task = await load(id);
    return save(
      task,
      task.reassignResultRecipe(
        recipeId: recipeId,
        additionalRecipeIds: additionalRecipeIds,
        now: clock(),
      ),
    );
  }
}

class CompleteImportTask extends _ExistingImportTaskUseCase {
  const CompleteImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task, task.complete(clock()));
  }
}

class FailImportTask extends _ExistingImportTaskUseCase {
  const FailImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(
    String id, {
    required ImportTaskErrorCode code,
    String? message,
    required bool retryable,
    DateTime? nextRetryAt,
  }) async {
    final task = await load(id);
    return save(
      task,
      task.fail(
        code: code,
        message: message,
        canRetry: retryable,
        nextRetryAt: nextRetryAt,
        now: clock(),
      ),
    );
  }
}

class CancelImportTask extends _ExistingImportTaskUseCase {
  const CancelImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    while (true) {
      final task = await load(id);
      final cancelled = task.cancel(clock());
      if (identical(task, cancelled)) {
        return task;
      }
      try {
        return await save(task, cancelled);
      } on ImportTaskWriteConflictException {
        // Cancellation is a user intent and therefore retries against the
        // latest persisted version instead of losing to a concurrent worker.
      }
    }
  }
}

class RetryImportTask extends _ExistingImportTaskUseCase {
  const RetryImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task, task.retry(clock()));
  }
}

class RecoverInterruptedImportTasks {
  const RecoverInterruptedImportTasks({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
    Set<String> skipTaskIds = const {},
  }) : _repository = repository,
       _clock = clock,
       _skipTaskIds = skipTaskIds;

  final ImportTaskRepository _repository;
  final ImportTaskClock _clock;

  /// 需要跳过的任务 ID（通常是当前进程内仍在实时运行的导入任务）。
  /// 这些任务并非"遗留中断"，不应被恢复或置为失败。
  final Set<String> _skipTaskIds;

  Future<List<ImportTask>> call() async {
    final now = _clock();
    final tasks = await _repository.listRecoverableTasks(now);
    final recovered = <ImportTask>[];
    for (final task in tasks) {
      // 跳过仍在实时运行的任务，避免误判为中断。
      if (_skipTaskIds.contains(task.id)) {
        recovered.add(task);
        continue;
      }
      final updated = switch (task.status) {
        ImportTaskStatus.running => task.recoverAfterRestart(now),
        ImportTaskStatus.failed when task.canRetry => task.retry(now),
        _ => task,
      };
      if (identical(task, updated)) {
        recovered.add(task);
        continue;
      }
      try {
        await _repository.upsertTask(
          updated,
          expectedLocalVersion: task.localVersion,
        );
        recovered.add(updated);
      } on ImportTaskWriteConflictException {
        final latest = await _repository.getTaskById(task.id);
        if (latest == null) {
          throw ImportTaskNotFoundException(task.id);
        }
        recovered.add(latest);
      }
    }
    return recovered;
  }
}
