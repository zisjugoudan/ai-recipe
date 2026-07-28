import 'package:ai_recipe/application/importing/import_task_use_cases.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/importing/import_task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryImportTaskRepository implements ImportTaskRepository {
  final Map<String, ImportTask> tasks = <String, ImportTask>{};

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
  Future<void> upsertTask(ImportTask task) async {
    tasks[task.id] = task;
  }
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
}
