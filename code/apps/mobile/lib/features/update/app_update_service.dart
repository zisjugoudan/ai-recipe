import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/update/app_update.dart';
import 'apk_installer.dart';

/// 在线更新服务（UPDATE-001）。
///
/// 数据源：Gitee 公开仓库根目录的 `version.json`（项目负责人提供：
/// https://gitee.com/eb-Dog/delicious-food/blob/master/version.json，
/// 实际请求 raw 直链 `…/raw/master/version.json`）。
///
/// version.json 字段（宽容解析，支持以下候选键，取第一个非空值）：
/// - 最新版本号（必填）：`version` / `latest_version` / `tag_name` / `latestVersion`
/// - 更新说明：`note` / `changelog` / `update_note` / `release_notes` / `body` / `description`
/// - APK 下载直链：`apk_url` / `apkUrl` / `download_url` / `downloadUrl` / `url` / `apk`
/// - 发布页地址（可选，用于用户浏览器打开）：`html_url` / `page_url` / `release_page`
class AppUpdateService {
  const AppUpdateService({http.Client? httpClient}) : _httpClient = httpClient;

  final http.Client? _httpClient;

  /// Gitee 公开仓库地址（项目负责人提供）。
  static const giteeOwner = 'eb-Dog';
  static const giteeRepo = 'delicious-food';

  /// version.json 所在的 Git 分支（按顺序回退尝试；项目负责人给的链接为 master）。
  static const versionBranches = <String>['master', 'main'];

  /// 浏览器 UA 请求头：Gitee 对无 UA 或脚本 UA 的请求有反爬（可能 403）。
  static const _browserHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
    'Accept': 'application/json,text/plain,*/*',
  };

  /// 指定分支下 version.json 的 raw 直链（公开仓库可匿名读取）。
  static Uri _versionFileUri(String branch) => Uri.parse(
        'https://gitee.com/$giteeOwner/$giteeRepo/raw/$branch/version.json',
      );

  /// 检查是否有新版本。
  ///
  /// [currentVersion] 为当前运行版本（由页面读取）。
  /// 成功且无新版本时返回 [AppUpdateCheckResult]（latestRelease 为 null）；
  /// 请求/解析失败时返回带中文 errorMessage 的结果，不抛异常。
  Future<AppUpdateCheckResult> checkForUpdate(String currentVersion) async {
    try {
      final client = _httpClient ?? http.Client();
      try {
        // 依次尝试 master / main 分支，任一返回 200 即采用其内容。
        http.Response? lastResponse;
        for (final branch in versionBranches) {
          final response = await client
              .get(_versionFileUri(branch), headers: _browserHeaders)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            final release = _parseVersionConfig(response.body);
            if (release == null) {
              return AppUpdateCheckResult(
                currentVersion: currentVersion,
                errorMessage: 'version.json 内容无法识别，请检查文件格式。',
              );
            }
            // 只有当最新版本严格大于当前版本时才提示更新。
            final hasNew =
                compareAppVersions(release.version, currentVersion) > 0;
            return AppUpdateCheckResult(
              currentVersion: currentVersion,
              latestRelease: hasNew ? release : null,
            );
          }
          lastResponse = response;
        }
        // 全部分支均失败：按状态码给出可行动的提示。
        final status = lastResponse?.statusCode ?? 0;
        if (status == 403) {
          // 403：私有仓库匿名读取 / 风控拒绝，与「仓库不存在」要区分开。
          return AppUpdateCheckResult(
            currentVersion: currentVersion,
            errorMessage: '检查更新被拒绝（HTTP 403）。请确认仓库已设为公开；'
                '若仓库是私有的，需要为应用配置 Gitee 访问令牌。',
          );
        }
        // 404：再请求一次仓库详情，区分「仓库存在但缺 version.json」
        // 与「仓库不存在/私有（匿名不可见）」。
        final exists = await _repoExists(client);
        return AppUpdateCheckResult(
          currentVersion: currentVersion,
          errorMessage: exists
              ? '仓库里还没有 version.json 更新配置（HTTP $status）。'
                  '请确认文件已在 master 或 main 分支根目录。'
              : '找不到更新仓库（HTTP $status）。请确认仓库已设为公开且路径正确。',
        );
      } finally {
        // 只有内部创建的 Client 需要关闭（测试注入的由调用方管理）。
        if (_httpClient == null) client.close();
      }
    } catch (_) {
      return AppUpdateCheckResult(
        currentVersion: currentVersion,
        errorMessage: '网络暂时不可用，无法检查更新。',
      );
    }
  }

  /// 判断仓库对匿名访问是否可见（公开仓库返回 200，私有/不存在返回 404/403）。
  Future<bool> _repoExists(http.Client client) async {
    try {
      final response = await client
          .get(_repoUri)
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      // 网络异常时不额外报错，沿用「仓库不存在」文案即可；
      // 主请求本身已能说明问题。
      return false;
    }
  }

  /// 仓库详情接口（用于区分「仓库不存在/私有」与「暂无更新配置」）。
  static Uri get _repoUri => Uri.parse(
        'https://gitee.com/api/v5/repos/$giteeOwner/$giteeRepo',
      );

  /// 从 JSON Map 中按候选键取第一个非空字符串值。
  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// 解析 version.json 内容；缺少有效版本号或 JSON 非法时返回 null。
  AppReleaseInfo? _parseVersionConfig(String body) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final tagName = _firstString(decoded, <String>[
      'version',
      'latest_version',
      'tag_name',
      'latestVersion',
    ]);
    if (tagName == null) return null;
    final version = tagName.replaceFirst(RegExp('^[vV]'), '');
    if (int.tryParse(version.split('.').first) == null) return null;

    return AppReleaseInfo(
      tagName: tagName,
      version: version,
      body: _firstString(decoded, <String>[
            'note',
            'changelog',
            'update_note',
            'release_notes',
            'body',
            'description',
          ]) ??
          '',
      apkDownloadUrl: _firstString(decoded, <String>[
        'apk_url',
        'apkUrl',
        'download_url',
        'downloadUrl',
        'url',
        'apk',
        'apk_link',
        'apkLink',
      ]),
      releasePageUrl: _firstString(decoded, <String>[
            'html_url',
            'page_url',
            'release_page',
            'homepage',
            'project_url',
          ]) ??
          '',
      apkSizeBytes: null,
    );
  }

  /// 下载 APK 到应用临时目录，返回本地文件路径。
  ///
  /// [onProgress] 在收到分块数据时回调（0.0~1.0）；不保证精确。
  /// [sizeBytes] 为服务端返回的附件大小，用于计算进度；为 null 时仅按
  /// 已下载字节数递增展示。
  Future<String> downloadApk({
    required String url,
    required int? sizeBytes,
    void Function(double progress)? onProgress,
  }) async {
    final client = _httpClient ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      // 与检查更新一致：带浏览器 UA，降低 Gitee 对脚本请求的反爬拒绝。
      request.headers.addAll(_browserHeaders);
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        throw StateError('下载失败（HTTP ${streamed.statusCode}）');
      }
      final dir = await getTemporaryDirectory();
      final targetDir = Directory(p.join(dir.path, 'ai_recipe_update'));
      if (!await targetDir.exists()) await targetDir.create(recursive: true);
      final fileName = Uri.parse(url).pathSegments.isNotEmpty
          ? Uri.parse(url).pathSegments.last
          : 'ai_recipe_update.apk';
      final target = File(p.join(targetDir.path, fileName));
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in streamed.stream) {
          received += chunk.length;
          if (onProgress != null) {
            final ratio = (sizeBytes != null && sizeBytes > 0)
                ? (received / sizeBytes).clamp(0.0, 1.0)
                : null;
            onProgress(ratio ?? 0.0);
          }
          sink.add(chunk);
        }
      } finally {
        await sink.close();
      }
      return target.path;
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  /// 调用系统安装器安装已下载的 APK（仅 Android）。
  Future<void> installApk(String apkPath) => ApkInstaller.install(apkPath);
}
