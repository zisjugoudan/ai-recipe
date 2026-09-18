import 'dart:convert';

import 'backup_archive_constants.dart';
import 'backup_errors.dart';

/// 归档中一个 Dataset 的描述（manifest.datasets[i]）。
///
/// 每个 Dataset 拥有独立的 schemaVersion，与容器 formatVersion 解耦，
/// 便于未来按 Dataset 粒度迁移（MigrationRegistry 链式迁移）。
class BackupDatasetDescriptor {
  const BackupDatasetDescriptor({
    required this.name,
    required this.schemaVersion,
    required this.recordCount,
    required this.byteSize,
    required this.sha256,
  });

  final String name;
  final int schemaVersion;
  final int recordCount;
  final int byteSize;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'schemaVersion': schemaVersion,
    'recordCount': recordCount,
    'byteSize': byteSize,
    'sha256': sha256,
  };

  /// 严格反序列化：未知字段、类型不符、范围非法直接抛格式异常，
  /// 不允许静默容错导致导入端读到损坏元数据。
  factory BackupDatasetDescriptor.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final schemaVersion = json['schemaVersion'];
    final recordCount = json['recordCount'];
    final byteSize = json['byteSize'];
    final sha256 = json['sha256'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Dataset 名称缺失');
    }
    if (schemaVersion is! int || schemaVersion <= 0) {
      throw const FormatException('Dataset schemaVersion 非法');
    }
    if (recordCount is! int || recordCount < 0) {
      throw const FormatException('Dataset recordCount 非法');
    }
    if (byteSize is! int || byteSize < 0) {
      throw const FormatException('Dataset byteSize 非法');
    }
    if (sha256 is! String || !_isSha256(sha256)) {
      throw const FormatException('Dataset sha256 非法');
    }
    return BackupDatasetDescriptor(
      name: name,
      schemaVersion: schemaVersion,
      recordCount: recordCount,
      byteSize: byteSize,
      sha256: sha256.toLowerCase(),
    );
  }
}

/// 归档媒体统计（manifest.media）。
class BackupMediaStatistics {
  const BackupMediaStatistics({
    required this.count,
    required this.byteSize,
  });

  final int count;
  final int byteSize;

  Map<String, Object?> toJson() => <String, Object?>{
    'count': count,
    'byteSize': byteSize,
  };

  factory BackupMediaStatistics.fromJson(Map<String, Object?> json) {
    final count = json['count'];
    final byteSize = json['byteSize'];
    if (count is! int || count < 0) {
      throw const FormatException('媒体统计 count 非法');
    }
    if (byteSize is! int || byteSize < 0) {
      throw const FormatException('媒体统计 byteSize 非法');
    }
    return BackupMediaStatistics(count: count, byteSize: byteSize);
  }
}

/// 备份内容统计（manifest.statistics），供导入端与 UI 展示预期影响。
class BackupContentStatistics {
  const BackupContentStatistics({
    required this.recipeTotal,
    required this.recipeByStatus,
    required this.categoryTotal,
    required this.categoryEmpty,
    required this.mediaTotal,
    required this.mediaBytes,
    required this.totalBytes,
  });

  /// 全部菜谱数量（正式 + 草稿 + 归档 + 回收站软删除）。
  final int recipeTotal;

  /// 按状态拆分（published/draft/archived/trashed）。
  final Map<String, int> recipeByStatus;

  final int categoryTotal;

  /// 无任何菜谱关联的"空分类"数量。
  final int categoryEmpty;

  final int mediaTotal;

  /// 全部媒体字节（去重后）。
  final int mediaBytes;

  /// 归档预估总字节（数据 + 媒体 + 清单与元数据开销）。
  final int totalBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'recipeTotal': recipeTotal,
    'recipeByStatus': recipeByStatus,
    'categoryTotal': categoryTotal,
    'categoryEmpty': categoryEmpty,
    'mediaTotal': mediaTotal,
    'mediaBytes': mediaBytes,
    'totalBytes': totalBytes,
  };

  factory BackupContentStatistics.fromJson(Map<String, Object?> json) {
    final recipeTotal = json['recipeTotal'];
    final recipeByStatus = json['recipeByStatus'];
    final categoryTotal = json['categoryTotal'];
    final categoryEmpty = json['categoryEmpty'];
    final mediaTotal = json['mediaTotal'];
    final mediaBytes = json['mediaBytes'];
    final totalBytes = json['totalBytes'];
    if (recipeTotal is! int || recipeTotal < 0) {
      throw const FormatException('statistics.recipeTotal 非法');
    }
    if (recipeByStatus is! Map<String, Object?>) {
      throw const FormatException('statistics.recipeByStatus 非法');
    }
    if (categoryTotal is! int || categoryTotal < 0) {
      throw const FormatException('statistics.categoryTotal 非法');
    }
    if (categoryEmpty is! int || categoryEmpty < 0) {
      throw const FormatException('statistics.categoryEmpty 非法');
    }
    if (mediaTotal is! int || mediaTotal < 0) {
      throw const FormatException('statistics.mediaTotal 非法');
    }
    if (mediaBytes is! int || mediaBytes < 0) {
      throw const FormatException('statistics.mediaBytes 非法');
    }
    if (totalBytes is! int || totalBytes < 0) {
      throw const FormatException('statistics.totalBytes 非法');
    }
    final byStatus = <String, int>{};
    for (final entry in recipeByStatus.entries) {
      final value = entry.value;
      if (entry.key.trim().isEmpty) {
        throw const FormatException('recipeByStatus 状态名为空');
      }
      if (value is! int || value < 0) {
        throw const FormatException('recipeByStatus 计数非法');
      }
      byStatus[entry.key] = value;
    }
    return BackupContentStatistics(
      recipeTotal: recipeTotal,
      recipeByStatus: byStatus,
      categoryTotal: categoryTotal,
      categoryEmpty: categoryEmpty,
      mediaTotal: mediaTotal,
      mediaBytes: mediaBytes,
      totalBytes: totalBytes,
    );
  }
}

/// 归档包描述文件（manifest.json）模型。
///
/// 顶层字段严格校验：format 必须为 [backupFormatName]；
/// formatVersion / minimumReaderVersion 不高于当前 reader 版本时才可读；
/// datasets 只包含已知名称；媒体统计与内容统计允许但要求完整。
class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.minimumReaderVersion,
    required this.createdAt,
    required this.appVersion,
    required this.datasets,
    required this.media,
    required this.statistics,
  });

  final int formatVersion;
  final int minimumReaderVersion;

  /// 备份创建时间（UTC ISO-8601）。
  final String createdAt;

  /// 创建备份的应用版本。
  final String appVersion;

  final List<BackupDatasetDescriptor> datasets;
  final BackupMediaStatistics media;
  final BackupContentStatistics statistics;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': backupFormatName,
    'formatVersion': formatVersion,
    'minimumReaderVersion': minimumReaderVersion,
    'createdAt': createdAt,
    'appVersion': appVersion,
    'datasets': datasets.map((dataset) => dataset.toJson()).toList(),
    'media': media.toJson(),
    'statistics': statistics.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// 严格反序列化并执行版本兼容检查。
  ///
  /// [readerFormatVersion] 为当前 reader 支持的容器版本，未通过时抛出
  /// [BackupException]（formatNotSupported），不允许导入未知主版本。
  factory BackupManifest.fromJson(
    Map<String, Object?> json, {
    int readerFormatVersion = backupFormatVersion,
  }) {
    final format = json['format'];
    if (format != backupFormatName) {
      throw const BackupException(
        BackupErrorCode.formatNotSupported,
        '不是有效的 AI 食谱备份文件。',
      );
    }
    final formatVersion = json['formatVersion'];
    final minimumReaderVersion = json['minimumReaderVersion'];
    final createdAt = json['createdAt'];
    final appVersion = json['appVersion'];
    final datasets = json['datasets'];
    final media = json['media'];
    final statistics = json['statistics'];
    if (formatVersion is! int || formatVersion <= 0) {
      throw const FormatException('formatVersion 非法');
    }
    if (minimumReaderVersion is! int || minimumReaderVersion <= 0) {
      throw const FormatException('minimumReaderVersion 非法');
    }
    if (formatVersion > readerFormatVersion ||
        minimumReaderVersion > readerFormatVersion) {
      throw const BackupException(
        BackupErrorCode.formatNotSupported,
        '备份由更高版本的应用创建，请先升级应用后再导入。',
      );
    }
    if (createdAt is! String || createdAt.isEmpty) {
      throw const FormatException('createdAt 缺失');
    }
    if (appVersion is! String || appVersion.isEmpty) {
      throw const FormatException('appVersion 缺失');
    }
    if (datasets is! List<Object?>) {
      throw const FormatException('datasets 非法');
    }
    final datasetList = datasets
        .map((item) => BackupDatasetDescriptor.fromJson(
            (item as Map<Object?, Object?>).cast<String, Object?>()))
        .toList();
    for (final dataset in datasetList) {
      if (!BackupDatasetName.all.contains(dataset.name)) {
        // 运行时信息拼入错误消息，不能用 const。
        throw BackupException(
          BackupErrorCode.formatNotSupported,
          '备份包含当前版本无法识别的数据：${dataset.name}。',
        );
      }
    }
    if (media is! Map<Object?, Object?>) {
      throw const FormatException('media 非法');
    }
    if (statistics is! Map<Object?, Object?>) {
      throw const FormatException('statistics 非法');
    }
    return BackupManifest(
      formatVersion: formatVersion,
      minimumReaderVersion: minimumReaderVersion,
      createdAt: createdAt,
      appVersion: appVersion,
      datasets: datasetList,
      media: BackupMediaStatistics.fromJson(
        media.cast<String, Object?>(),
      ),
      statistics: BackupContentStatistics.fromJson(
        statistics.cast<String, Object?>(),
      ),
    );
  }
}

/// 校验字符串是否为 64 位十六进制 SHA-256（小写化后比对）。
bool _isSha256(String value) {
  final trimmed = value.toLowerCase();
  if (trimmed.length != 64) return false;
  final codeUnit = RegExp(r'^[0-9a-f]{64}$');
  return codeUnit.hasMatch(trimmed);
}
