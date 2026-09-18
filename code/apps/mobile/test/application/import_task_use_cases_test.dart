import 'package:ai_recipe/application/importing/import_task_use_cases.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/importing/import_task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryImportTaskRepository implements ImportTaskRepository {
  final Map<String, ImportTask> tasks = <String, ImportTask>{};
  final List<int?> expectedLocalVersions = <int?>[];
  void Function(ImportTask task, int? expectedLocalVersion)? beforeUpsert;

  @override
  Future<ImportTask?> getTaskById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final task = tasks[id];
    if (!includeDeleted && task?.deletedAt != null) {
      return null;
    }
    return task;
  }

  @override
  Future<List<ImportTask>> listRecoverableTasks(DateTime now) async {
    return tasks.values
        .where((task) {
          if (task.deletedAt != null) {
            return false;
          }
          if (task.status == ImportTaskStatus.queued ||
              task.status == ImportTaskStatus.running) {
            return true;
          }
          return task.status == ImportTaskStatus.failed &&
              task.canRetry &&
              (task.nextRetryAt == null || !task.nextRetryAt!.isAfter(now));
        })
        .toList(growable: false);
  }

  @override
  Future<List<ImportTask>> listTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  }) async {
    var result = tasks.values.where((task) {
      return (includeDeleted || task.deletedAt == null) &&
          (statuses == null || statuses.contains(task.status));
    }).toList();
    if (limit != null && result.length > limit) {
      result = result.take(limit).toList();
    }
    return result;
  }

  @override
  Future<void> permanentlyDeleteTask(String id) async {
    tasks.remove(id);
  }

  @override
  Future<void> softDeleteTask(String id, DateTime deletedAt) {
    throw UnimplementedError();
  }

  @override
  Future<void> upsertTask(
    ImportTask task, {
    int? expectedLocalVersion,
  }) async {
    expectedLocalVersions.add(expectedLocalVersion);
    beforeUpsert?.call(task, expectedLocalVersion);
    final current = tasks[task.id];
    if (expectedLocalVersion == null) {
      if (current != null) {
        throw ImportTaskWriteConflictException(
          id: task.id,
          expectedLocalVersion: null,
          actualLocalVersion: current.localVersion,
        );
      }
    } else {
      if (task.localVersion != expectedLocalVersion + 1) {
        throw ArgumentError.value(
          task.localVersion,
          'task.localVersion',
          'must be exactly one greater than expectedLocalVersion',
        );
      }
      if (current?.localVersion != expectedLocalVersion) {
        throw ImportTaskWriteConflictException(
          id: task.id,
          expectedLocalVersion: expectedLocalVersion,
          actualLocalVersion: current?.localVersion,
        );
      }
    }
    tasks[task.id] = task;
  }

  @override
  Future<void> saveImportEvidence(String taskId, ImportContent content) async {}

  @override
  Future<ImportContent?> loadImportEvidence(String taskId) async => null;
}

void main() {
  late _MemoryImportTaskRepository repository;
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    repository = _MemoryImportTaskRepository();
    now = DateTime.utc(2026, 7, 28, 10);
  });

  test('application use cases complete the import lifecycle', () async {
    final create = CreateImportTask(
      repository: repository,
      idGenerator: () => 'task-app-1',
      clock: clock,
    );
    final start = StartImportTask(repository: repository, clock: clock);
    final advance = AdvanceImportTask(repository: repository, clock: clock);
    final review = MarkImportTaskNeedsReview(
      repository: repository,
      clock: clock,
    );
    final complete = CompleteImportTask(repository: repository, clock: clock);

    final created = await create('https://v.douyin.com/abc/');
    expect(created.status, ImportTaskStatus.queued);

    now = now.add(const Duration(minutes: 1));
    await start(created.id);
    now = now.add(const Duration(minutes: 1));
    await advance(
      created.id,
      stage: ImportTaskStage.generating,
      progress: 0.85,
    );
    now = now.add(const Duration(minutes: 1));
    await review(created.id, recipeId: 'recipe-draft');
    now = now.add(const Duration(minutes: 1));
    final completed = await complete(created.id);

    expect(completed.status, ImportTaskStatus.completed);
    expect(completed.resultRecipeId, 'recipe-draft');
    expect(repository.tasks[created.id]!.localVersion, 5);
  });

  test('missing task ids use a stable application exception', () async {
    final start = StartImportTask(repository: repository, clock: clock);

    await expectLater(
      start('missing'),
      throwsA(
        isA<ImportTaskNotFoundException>().having(
          (error) => error.id,
          'id',
          'missing',
        ),
      ),
    );
  });

  test('recovery requeues interrupted and due failed tasks', () async {
    ImportTask makeTask(String id) => ImportTask.queued(
      id: id,
      source: ImportSourceLink.parse('https://v.douyin.com/$id/'),
      now: now,
    );

    repository.tasks['queued'] = makeTask('queued');
    repository.tasks['running'] = makeTask(
      'running',
    ).start(now.add(const Duration(minutes: 1)));
    repository.tasks['failed'] = makeTask('failed').fail(
      code: ImportTaskErrorCode.timeout,
      canRetry: true,
      nextRetryAt: now.add(const Duration(minutes: 2)),
      now: now.add(const Duration(minutes: 1)),
    );
    now = now.add(const Duration(minutes: 2));

    final recovered = await RecoverInterruptedImportTasks(
      repository: repository,
      clock: clock,
    )();

    expect(recovered, hasLength(3));
    expect(repository.tasks['queued']!.attempt, 1);
    expect(repository.tasks['running']!.status, ImportTaskStatus.queued);
    expect(repository.tasks['running']!.attempt, 2);
    expect(repository.tasks['failed']!.status, ImportTaskStatus.queued);
    expect(repository.tasks['failed']!.attempt, 2);
  });

  test('recovery skips tasks still running in-flight', () async {
    // 回归：解析中按返回后任务仍在后台实时运行，重新打开页面触发的
    // 恢复不应把该任务误判为"遗留中断"而改动它。
    final running = ImportTask.queued(
      id: 'in-flight',
      source: ImportSourceLink.parse('https://v.douyin.com/in-flight/'),
      now: now,
    ).start(now.add(const Duration(minutes: 1)));
    repository.tasks[running.id] = running;

    final recovered = await RecoverInterruptedImportTasks(
      repository: repository,
      clock: clock,
      skipTaskIds: {running.id},
    )();

    // 被跳过的在途任务保持 running，不被恢复到 queued。
    expect(recovered, hasLength(1));
    expect(repository.tasks[running.id]!.status, ImportTaskStatus.running);
  });

  test(
    'fallback start use case persists a failed task as extracting',
    () async {
      final failed =
          ImportTask.queued(
            id: 'fallback-task',
            source: ImportSourceLink.parse(
              'https://v.douyin.com/fallback-task/',
            ),
            now: now,
          ).fail(
            code: ImportTaskErrorCode.contentUnavailable,
            canRetry: false,
            now: now,
          );
      repository.tasks[failed.id] = failed;

      final started = await StartImportTaskWithFallback(
        repository: repository,
        clock: clock,
      )(failed.id);

      expect(started.status, ImportTaskStatus.running);
      expect(started.stage, ImportTaskStage.extracting);
      expect(started.progress, 0.25);
      expect(repository.tasks[failed.id], same(started));
    },
  );

  test(
    'fallback start use case rejects queued tasks without persisting',
    () async {
      final queued = ImportTask.queued(
        id: 'queued-fallback-task',
        source: ImportSourceLink.parse(
          'https://v.douyin.com/queued-fallback-task/',
        ),
        now: now,
      );
      repository.tasks[queued.id] = queued;

      await expectLater(
        StartImportTaskWithFallback(repository: repository, clock: clock)(
          queued.id,
        ),
        throwsA(isA<ImportTaskTransitionException>()),
      );
      expect(repository.tasks[queued.id], same(queued));
    },
  );

  test('state transitions write with the previously loaded local version', () async {
    final created = await CreateImportTask(
      repository: repository,
      idGenerator: () => 'task-cas-versions',
      clock: clock,
    )('https://v.douyin.com/cas-versions/');

    now = now.add(const Duration(minutes: 1));
    await StartImportTask(repository: repository, clock: clock)(created.id);
    now = now.add(const Duration(minutes: 1));
    await AdvanceImportTask(repository: repository, clock: clock)(
      created.id,
      stage: ImportTaskStage.extracting,
      progress: 0.25,
    );

    expect(repository.expectedLocalVersions, <int?>[null, 1, 2]);
  });

  test('cancel retries a CAS conflict and preserves the user intent', () async {
    final queued = ImportTask.queued(
      id: 'task-cancel-conflict',
      source: ImportSourceLink.parse(
        'https://v.douyin.com/task-cancel-conflict/',
      ),
      now: now,
    );
    final running = queued.start(now.add(const Duration(minutes: 1)));
    repository.tasks[running.id] = running;
    now = now.add(const Duration(minutes: 2));

    repository.beforeUpsert = (attempted, expectedLocalVersion) {
      repository.beforeUpsert = null;
      final current = repository.tasks[attempted.id]!;
      repository.tasks[attempted.id] = current.advance(
        nextStage: ImportTaskStage.extracting,
        nextProgress: 0.25,
        now: now,
      );
    };

    final cancelled = await CancelImportTask(
      repository: repository,
      clock: clock,
    )(running.id);

    expect(cancelled.status, ImportTaskStatus.cancelled);
    expect(cancelled.errorCode, isNull);
    expect(repository.tasks[running.id]!.status, ImportTaskStatus.cancelled);
    expect(repository.expectedLocalVersions, <int?>[2, 3]);
  });

  test('cancelling an already cancelled task is idempotent', () async {
    final cancelled = ImportTask.queued(
      id: 'task-already-cancelled',
      source: ImportSourceLink.parse(
        'https://v.douyin.com/task-already-cancelled/',
      ),
      now: now,
    ).cancel(now.add(const Duration(minutes: 1)));
    repository.tasks[cancelled.id] = cancelled;
    now = now.add(const Duration(minutes: 2));

    final result = await CancelImportTask(
      repository: repository,
      clock: clock,
    )(cancelled.id);

    expect(result, same(cancelled));
    expect(repository.expectedLocalVersions, isEmpty);
  });

}
