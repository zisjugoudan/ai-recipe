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
    await _repository.upsertTask(task);
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

  Future<ImportTask> save(ImportTask task) async {
    await repository.upsertTask(task);
    return task;
  }
}

class StartImportTask extends _ExistingImportTaskUseCase {
  const StartImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task.start(clock()));
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
  }) async {
    final task = await load(id);
    return save(
      task.advance(nextStage: stage, nextProgress: progress, now: clock()),
    );
  }
}

class MarkImportTaskNeedsReview extends _ExistingImportTaskUseCase {
  const MarkImportTaskNeedsReview({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id, {required String recipeId}) async {
    final task = await load(id);
    return save(task.markNeedsReview(recipeId: recipeId, now: clock()));
  }
}

class CompleteImportTask extends _ExistingImportTaskUseCase {
  const CompleteImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task.complete(clock()));
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
    final task = await load(id);
    final cancelled = task.cancel(clock());
    if (identical(task, cancelled)) {
      return task;
    }
    return save(cancelled);
  }
}

class RetryImportTask extends _ExistingImportTaskUseCase {
  const RetryImportTask({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : super(repository, clock);

  Future<ImportTask> call(String id) async {
    final task = await load(id);
    return save(task.retry(clock()));
  }
}

class RecoverInterruptedImportTasks {
  const RecoverInterruptedImportTasks({
    required ImportTaskRepository repository,
    required ImportTaskClock clock,
  }) : _repository = repository,
       _clock = clock;

  final ImportTaskRepository _repository;
  final ImportTaskClock _clock;

  Future<List<ImportTask>> call() async {
    final now = _clock();
    final tasks = await _repository.listRecoverableTasks(now);
    final recovered = <ImportTask>[];
    for (final task in tasks) {
      final updated = switch (task.status) {
        ImportTaskStatus.running => task.recoverAfterRestart(now),
        ImportTaskStatus.failed when task.canRetry => task.retry(now),
        _ => task,
      };
      if (!identical(task, updated)) {
        await _repository.upsertTask(updated);
      }
      recovered.add(updated);
    }
    return recovered;
  }
}
