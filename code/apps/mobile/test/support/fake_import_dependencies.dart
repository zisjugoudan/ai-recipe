import 'package:ai_recipe/application/importing/import_pipeline_contracts.dart';
import 'package:ai_recipe/domain/importing/import_cancellation_token.dart';
import 'package:ai_recipe/domain/importing/import_content.dart';
import 'package:ai_recipe/domain/importing/import_content_adapter.dart';
import 'package:ai_recipe/domain/importing/import_task.dart';
import 'package:ai_recipe/domain/importing/import_task_repository.dart';

Future<void> discardImportRecipeDraft({
  required String recipeId,
  required String sourceId,
}) async {}

class MemoryImportTaskRepository implements ImportTaskRepository {
  final Map<String, ImportTask> tasks = <String, ImportTask>{};
  final List<ImportTask> savedTasks = <ImportTask>[];

  @override
  Future<ImportTask?> getTaskById(
    String id, {
    bool includeDeleted = false,
  }) async {
    final task = tasks[id];
    if (task == null || (!includeDeleted && task.deletedAt != null)) {
      return null;
    }
    return task;
  }

  @override
  Future<List<ImportTask>> listRecoverableTasks(DateTime now) async {
    return tasks.values
        .where(
          (task) =>
              task.deletedAt == null &&
              (task.status == ImportTaskStatus.queued ||
                  task.status == ImportTaskStatus.running ||
                  (task.canRetry &&
                      (task.nextRetryAt == null ||
                          !task.nextRetryAt!.isAfter(now)))),
        )
        .toList();
  }

  @override
  Future<List<ImportTask>> listTasks({
    Set<ImportTaskStatus>? statuses,
    bool includeDeleted = false,
    int? limit,
  }) async {
    var result = tasks.values.where(
      (task) => includeDeleted || task.deletedAt == null,
    );
    if (statuses != null && statuses.isNotEmpty) {
      result = result.where((task) => statuses.contains(task.status));
    }
    final list = result.toList();
    return limit == null ? list : list.take(limit).toList();
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
  Future<void> upsertTask(ImportTask task, {int? expectedLocalVersion}) async {
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
    savedTasks.add(task);
  }

  final Map<String, ImportContent> evidence = <String, ImportContent>{};

  @override
  Future<void> saveImportEvidence(String taskId, ImportContent content) async {
    evidence[taskId] = content;
  }

  @override
  Future<ImportContent?> loadImportEvidence(String taskId) async {
    return evidence[taskId];
  }
}

typedef FakeAdapterHandler =
    Future<ImportContent> Function(
      ImportSourceLink source,
      ImportCancellationToken? cancellationToken,
    );

class FakeImportContentAdapter implements ImportContentAdapter {
  FakeImportContentAdapter({required this.platform, required this.handler});

  @override
  final ImportSourcePlatform platform;
  final FakeAdapterHandler handler;
  int callCount = 0;

  @override
  Future<ImportContent> fetch(
    ImportSourceLink source, {
    ImportCancellationToken? cancellationToken,
  }) {
    callCount += 1;
    return handler(source, cancellationToken);
  }
}

typedef FakeProcessorHandler =
    Future<ImportRecipeDraftResult> Function(
      ImportContent content,
      ImportPipelineProgressCallback onProgress,
      ImportCancellationToken? cancellationToken,
    );

class FakeImportContentProcessor implements ImportContentProcessor {
  FakeImportContentProcessor(this.handler);

  final FakeProcessorHandler handler;
  int callCount = 0;

  @override
  Future<ImportRecipeDraftResult> process(
    ImportContent content, {
    required ImportPipelineProgressCallback onProgress,
    ImportCancellationToken? cancellationToken,
  }) {
    callCount += 1;
    return handler(content, onProgress, cancellationToken);
  }
}

ImportContent sampleImportContent(
  ImportSourceLink source, {
  String title = 'Sample recipe',
  String? resolvedUrl,
}) {
  return ImportContent(
    source: source,
    resolvedUrl: resolvedUrl ?? source.normalizedUrl,
    contentType: ImportContentType.mixed,
    title: title,
    capturedAt: DateTime.utc(2026, 7, 28, 10),
    textFragments: <ImportTextFragment>[
      ImportTextFragment(
        kind: ImportTextFragmentKind.body,
        text: 'Prepare ingredients and cook them.',
        order: 0,
      ),
    ],
    media: <ImportMediaReference>[
      ImportMediaReference(
        kind: ImportMediaKind.image,
        remoteUrl: 'https://example.com/recipe.jpg',
        order: 0,
      ),
    ],
  );
}
