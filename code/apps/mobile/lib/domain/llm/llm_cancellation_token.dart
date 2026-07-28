import 'dart:async';

import 'llm_provider_exception.dart';

class LlmCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const LlmProviderException(LlmProviderErrorKind.cancelled, '请求已取消');
    }
  }
}
