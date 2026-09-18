import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/app_theme.dart';
import '../../domain/update/app_update.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/pixel_ui.dart';
import 'app_update_service.dart';

/// 检查更新页（UPDATE-001）。
///
/// 展示当前版本号，提供「检查更新」按钮；发现新版本时弹出更新弹窗
/// （版本号 + 更新说明 + 以后再说 / 立即升级）。「立即升级」走
/// 下载 APK → 系统安装器安装（仅 Android）。
class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key, this.service});

  /// 可注入的服务（测试用）；默认使用 [AppUpdateService]。
  final AppUpdateService? service;

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  late final AppUpdateService _service = widget.service ?? const AppUpdateService();

  /// 当前版本（从 package_info_plus 读取；读取失败回退空字符串）。
  String _currentVersion = '';

  /// 版本回退常量：与 pubspec.yaml 的 version 保持一致，
  /// 保证任何情况下页面都能显示一个版本号而不是「未知」。
  static const _fallbackVersion = '1.0.0';

  /// 页面状态：空闲 / 检查中 / 下载中 / 安装中。
  var _checking = false;
  var _downloading = false;
  double _downloadProgress = 0;
  bool _installing = false;

  /// 最近一次检查结果与错误提示。
  AppUpdateCheckResult? _lastResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    // 优先级：构建时注入（--dart-define=APP_VERSION=x.y.z）→
    // package_info_plus 运行时读取 → 回退常量。任一步成功即结束。
    const injected = String.fromEnvironment('APP_VERSION');
    if (injected.isNotEmpty) {
      _applyVersion(injected);
      return;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isNotEmpty) {
        _applyVersion(version);
        return;
      }
    } catch (_) {
      // 插件不可用/读取失败：继续走回退常量。
    }
    _applyVersion(_fallbackVersion);
  }

  void _applyVersion(String version) {
    if (!mounted) return;
    setState(() => _currentVersion = version);
  }

  /// 检查更新：请求 Gitee Release，有新版本则弹出更新弹窗。
  Future<void> _checkForUpdate() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _errorMessage = null;
      _lastResult = null;
    });
    final result = await _service.checkForUpdate(_currentVersion);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastResult = result;
      _errorMessage = result.errorMessage;
    });
    if (result.hasError) return;
    if (result.hasUpdate) {
      // 有新版：弹出更新弹窗。
      _showUpdateDialog(result.latestRelease!);
    } else {
      _showMessage('当前已是最新版本（$_currentVersion）。');
    }
  }

  /// 更新弹窗：版本号 + 更新说明 + 「以后再说」/「立即升级」。
  Future<void> _showUpdateDialog(AppReleaseInfo release) async {
    final upgrade = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: PixelSurface(
          cut: PixelCut.lg,
          elevation: 2,
          color: AppColors.card,
          borderColor: AppColors.ink,
          borderWidth: 1.5,
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.system_update_alt_rounded,
                      size: 20,
                      color: AppColors.greenDeep,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '发现新版本',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 ${release.tagName}（当前 $_currentVersion）',
                  key: const Key('updateDialogVersionText'),
                  style: const TextStyle(fontSize: 12, color: AppColors.ink3),
                ),
                const SizedBox(height: 12),
                const Text(
                  '更新说明',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                // 更新说明：空时给占位文案，避免空框。
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.paper2,
                      border: Border.all(color: AppColors.line2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        release.body.trim().isEmpty
                            ? '（该版本没有附带更新说明）'
                            : release.body,
                        key: const Key('updateDialogBodyText'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    // 以后再说：仅关闭弹窗。
                    OutlinedButton(
                      key: const Key('updateLaterButton'),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('以后再说'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('updateNowButton'),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('立即升级'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (upgrade == true && mounted) {
      await _downloadAndInstall(_lastResult?.latestRelease);
    }
  }

  /// 下载 APK 并调用系统安装器安装。
  Future<void> _downloadAndInstall(AppReleaseInfo? release) async {
    final url = release?.apkDownloadUrl;
    if (release == null || url == null || url.isEmpty) {
      _showMessage('该版本没有提供安装包，请前往发布页手动下载。');
      return;
    }
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _errorMessage = null;
    });
    try {
      final apkPath = await _service.downloadApk(
        url: url,
        sizeBytes: release.apkSizeBytes,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _installing = true;
      });
      // 触发系统安装器；Android 8+ 若未授权「安装未知应用」，系统会引导。
      await _service.installApk(apkPath);
      if (!mounted) return;
      setState(() => _installing = false);
      _showMessage('安装包已就绪，请按系统提示完成安装。');
    } on StateError catch (error) {
      _failDownload(error.message);
    } catch (_) {
      _failDownload('下载失败，请检查网络后重试，或前往发布页手动下载。');
    }
  }

  void _failDownload(String message) {
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _installing = false;
      _errorMessage = message;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PixelPageAppBar(title: '检查更新'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: <Widget>[
            // 当前版本卡片。
            PixelSurface(
              cut: 8,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: AppColors.greenDeep,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text(
                          '当前版本',
                          style: TextStyle(fontSize: 11, color: AppColors.ink3),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentVersion,
                          key: const Key('currentVersionText'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 检查更新按钮。
            FilledButton.icon(
              key: const Key('checkUpdateButton'),
              onPressed: _checking || _downloading ? null : _checkForUpdate,
              icon: _checking
                  ? const PixelLoader(size: 6, color: Colors.white)
                  : const Icon(Icons.system_update_alt_rounded, size: 18),
              label: Text(_checking ? '正在检查…' : '检查更新'),
            ),
            // 下载中：进度条 + 百分比。
            if (_downloading) ...<Widget>[
              const SizedBox(height: 16),
              PixelSurface(
                cut: 5,
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      '正在下载新版本安装包…',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    PixelProgressBar(
                      key: const Key('updateDownloadProgress'),
                      value: _downloadProgress,
                      label: '${(_downloadProgress * 100).round()}%',
                      color: AppColors.greenDeep,
                    ),
                  ],
                ),
              ),
            ],
            // 安装中提示。
            if (_installing) ...<Widget>[
              const SizedBox(height: 16),
              const PixelNotice(
                title: '正在打开系统安装器',
                message: '请在系统弹窗中确认安装；若被拦截，请允许「安装未知应用」。',
                icon: Icons.install_desktop_rounded,
                tone: PixelNoticeTone.blue,
              ),
            ],
            // 错误提示。
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              PixelNotice(
                key: const Key('updateErrorMessage'),
                title: '更新未完成',
                message: _errorMessage!,
                icon: Icons.error_outline_rounded,
                tone: PixelNoticeTone.red,
              ),
            ],
            const SizedBox(height: 16),
            const PixelNotice(
              title: '提示',
              message: '当前暂时无法更新，请加入交流群获取最新信息。后续会完善。',
              // message: '版本信息来自 Gitee 公开仓库（eb-Dog/delicious-food）的 Release，仅检查不收集任何个人信息。',
              icon: Icons.shield_outlined,
              tone: PixelNoticeTone.green,
            ),
          ],
        ),
      ),
    );
  }
}
