/// 备份/恢复管线稳定错误（BACKUP-002）。
///
/// 所有失败统一映射为 [BackupException]，携带稳定错误码 [BackupErrorCode]
/// 与面向用户的中文信息，不允许把底层 IO/JSON/ZIP 异常直接上抛到 UI。
/// 错误码用于导入端分诊（哪些可重试、哪些需要人工修复）。
library;

/// 备份/恢复错误码（稳定契约，导入端与 UI 依据此分类展示）。
enum BackupErrorCode {
  /// 用户取消操作。
  cancelled,

  /// 必需媒体文件不存在。
  mediaMissing,

  /// 必需媒体文件不可读（权限、损坏、IO 异常）。
  mediaUnreadable,

  /// 媒体内容哈希与预期不一致。
  mediaHashMismatch,

  /// 数据关系或字段校验失败（如分类关系悬空）。
  dataValidationFailed,

  /// 归档写入失败（磁盘满、IO 异常）。
  archiveWriteFailed,

  /// 归档重读复核失败（条目缺失或哈希不一致）。
  archiveVerificationFailed,

  /// 备份格式名/版本不受支持。
  formatNotSupported,

  /// 归档安全校验失败（Zip Slip / Zip Bomb / 重复路径 / 非法路径 /
  /// 单文件或总大小超限）。导入端视为不可信输入直接拒绝。
  archiveSecurityViolation,

  /// 必需数据集缺失（如备份缺少 recipes/categories 数据集）。
  missingDataset,

  /// 归档内 JSON 资源超限（单行过大、嵌套过深、记录数超限）。
  jsonResourceLimit,

  /// 内部未知错误（保留给未分类异常）。
  internalError,
}

/// 归档安全校验阈值（导入端硬上限，BACKUP-004）。
class BackupImportLimits {
  BackupImportLimits._();

  /// 单个解压文件上限：50MB（媒体单张上限）。
  static const int maxEntryBytes = 50 * 1024 * 1024;

  /// 归档解压总字节上限：2GB（超大库保护）。
  static const int maxTotalBytes = 2 * 1024 * 1024 * 1024;

  /// 归档内条目数上限：10 万（含目录项）。
  static const int maxEntryCount = 100000;

  /// 单条 NDJSON 行长度上限：1MB（JSON 资源消耗防护）。
  static const int maxJsonLineBytes = 1024 * 1024;
}

/// 备份/恢复管线统一异常。
class BackupException implements Exception {
  const BackupException(this.code, this.message);

  final BackupErrorCode code;
  final String message;

  /// 是否可重试（媒体缺失、数据校验失败等需先修复，不可重试；
  /// 写入/复核失败、取消属于可安全重试）。
  bool get retryable =>
      code == BackupErrorCode.archiveWriteFailed ||
      code == BackupErrorCode.archiveVerificationFailed ||
      code == BackupErrorCode.cancelled ||
      code == BackupErrorCode.internalError;

  @override
  String toString() => 'BackupException($code): $message';
}

/// 取消专用异常（复用导入取消语义，便于 UI 区分"用户主动取消"）。
class BackupOperationCancelledException implements Exception {
  const BackupOperationCancelledException([
    this.message = '备份操作已取消。',
  ]);

  final String message;

  @override
  String toString() => 'BackupOperationCancelledException: $message';
}
