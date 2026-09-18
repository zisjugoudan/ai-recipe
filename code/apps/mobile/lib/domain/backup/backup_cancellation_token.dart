import 'dart:async';

import 'backup_errors.dart';

/// 备份操作取消令牌。
///
/// 与导入取消令牌同语义：取消为一次性、幂等；管线在快照、校验、
/// 写入、复核各阶段检查，取消后抛 [BackupOperationCancelledException]，
/// 由调用方清理半成品归档。
class BackupCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  /// 已取消则抛出备份取消异常。
  void throwIfCancelled() {
    if (isCancelled) {
      throw const BackupOperationCancelledException();
    }
  }
}
