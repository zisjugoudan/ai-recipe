import 'dart:async';

class ImportOperationCancelledException implements Exception {
  const ImportOperationCancelledException([
    this.message = 'Import operation was cancelled.',
  ]);

  final String message;

  @override
  String toString() => 'ImportOperationCancelledException: $message';
}

class ImportCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const ImportOperationCancelledException();
    }
  }
}
