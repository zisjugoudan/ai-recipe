import '../importing/import_task_runner.dart';
import 'import_execution_plan.dart';

enum ImportTaskRunnerFactoryErrorCode {
  routeNotBound,
  configurationUnavailable,
  providerUnavailable,
}

class ImportTaskRunnerFactoryException implements Exception {
  const ImportTaskRunnerFactoryException({
    required this.code,
    required this.message,
  });

  final ImportTaskRunnerFactoryErrorCode code;
  final String message;

  @override
  String toString() => 'ImportTaskRunnerFactoryException(${code.name})';
}

abstract interface class ImportTaskRunnerFactory {
  Future<ImportTaskRunner> create(ImportExecutionPlan plan, {String? userId});
}
