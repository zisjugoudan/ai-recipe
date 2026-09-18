/// 在线更新领域模型（UPDATE-001）。
///
/// 数据来源：Gitee 公开仓库的 Release（`/repos/{owner}/{repo}/releases/latest`）。
/// 当前版本号来自运行时 `package_info_plus`，最新版本号来自 Release 的 tag_name。
library;

/// 一次「检查更新」的结果。
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.currentVersion,
    this.latestRelease,
    this.errorMessage,
  });

  /// 当前运行的应用版本（如 1.0.0）。
  final String currentVersion;

  /// 最新的 Release 信息；为 null 表示没有新版本。
  final AppReleaseInfo? latestRelease;

  /// 检查失败时的中文错误提示；为 null 表示检查成功。
  final String? errorMessage;

  /// 是否存在可升级的新版本。
  bool get hasUpdate => latestRelease != null;

  /// 是否发生过错误。
  bool get hasError => errorMessage != null;
}

/// Gitee Release 信息（从中解析版本号、更新说明与 APK 下载地址）。
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.tagName,
    required this.version,
    required this.body,
    required this.apkDownloadUrl,
    required this.releasePageUrl,
    this.apkSizeBytes,
  });

  /// Release 的 tag（如 v1.1.0），原始值。
  final String tagName;

  /// 归一化后的版本号（去掉 v 前缀，如 1.1.0），用于与当前版本比较。
  final String version;

  /// 更新说明（Release body），可为空字符串。
  final String body;

  /// APK 附件的下载直链；找不到附件时为 null。
  final String? apkDownloadUrl;

  /// Release 页面地址（用户浏览器打开备用）。
  final String releasePageUrl;

  /// APK 附件大小（字节），用于下载进度展示。
  final int? apkSizeBytes;
}

/// 简单的语义化版本比较器（major.minor.patch，可选 v 前缀）。
///
/// 返回负数/零/正数表示 [a] 小于/等于/大于 [b]。
int compareAppVersions(String a, String b) {
  final partsA = _versionParts(a);
  final partsB = _versionParts(b);
  final len = partsA.length > partsB.length ? partsA.length : partsB.length;
  for (var i = 0; i < len; i++) {
    final va = i < partsA.length ? partsA[i] : 0;
    final vb = i < partsB.length ? partsB[i] : 0;
    if (va != vb) return va.compareTo(vb);
  }
  return 0;
}

/// 把版本字符串拆成整数数组：剥离 v 前缀，按 . 分段，忽略非数字段。
List<int> _versionParts(String version) {
  final normalized = version.trim().replaceFirst(RegExp('^[vV]'), '');
  final parts = <int>[];
  for (final segment in normalized.split('.')) {
    final parsed = int.tryParse(segment.trim());
    if (parsed == null) return <int>[0];
    parts.add(parsed);
  }
  return parts.isEmpty ? <int>[0] : parts;
}
