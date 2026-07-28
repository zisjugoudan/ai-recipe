import '../../domain/importing/import_cancellation_token.dart';
import '../../domain/importing/import_task.dart';
import '../../domain/importing/import_task_repository.dart';
import 'import_task_runner.dart';

class ImportDispatcherBusyException implements Exception {
  const ImportDispatcherBusyException();

  @override
  String toString() =>
      'ImportDispatcherBusyException: a dispatch batch is already running.';
}

class ImportDispatchReport {
  const ImportDispatchReport({required this.results, required this.cancelled});

  final List<ImportTaskRunResult> results;
  final bool cancelled;

  int get processedCount => results.length;
}

class SingleImportTaskDispatcher {
  SingleImportTaskDispatcher({
    required ImportTaskRepository repository,
    required ImportTaskRunner runner,
  }) : _repository = repository,
       _runner = runner;

  final ImportTaskRepository _repository;
  final ImportTaskRunner _runner;
  bool _dispatching = false;

  bool get isDispatching => _dispatching;

  Future<ImportDispatchReport> dispatchPending({
    int? limit,
    ImportCancellationToken? cancellationToken,
  }) async {
    if (_dispatching) {
      throw const ImportDispatcherBusyException();
    }
    if (limit != null && limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }

    _dispatching = true;
    try {
      final queued = await _repository.listTasks(
        statuses: const <ImportTaskStatus>{ImportTaskStatus.queued},
      );
      queued.sort((left, right) {
        final createdComparison = left.createdAt.compareTo(right.createdAt);
        return createdComparison != 0
            ? createdComparison
            : left.id.compareTo(right.id);
      });
      final selected = limit == null ? queued : queued.take(limit);
      final results = <ImportTaskRunResult>[];
      var cancelled = false;

      for (final task in selected) {
        if (cancellationToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        final result = await _runner.run(
          task.id,
          cancellationToken: cancellationToken,
        );
        results.add(result);
        if (cancellationToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
      }

      return ImportDispatchReport(
        results: List<ImportTaskRunResult>.unmodifiable(results),
        cancelled: cancelled,
      );
    } finally {
      _dispatching = false;
    }
  }
}
