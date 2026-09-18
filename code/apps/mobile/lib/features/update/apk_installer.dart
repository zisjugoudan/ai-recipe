import 'package:flutter/services.dart';

/// APK 安装平台通道（UPDATE-001，仅 Android）。
///
/// 通道：`ai_recipe/apk_install`
/// 方法：`installApk`，参数 `{ path }`（APK 绝对路径）。
/// 原生侧通过 FileProvider 生成 content:// URI 并拉起系统安装器
/// （ACTION_VIEW + REQUEST_INSTALL_PACKAGES），安装进度/结果由系统接管。
class ApkInstaller {
  const ApkInstaller._();

  static const MethodChannel _channel = MethodChannel('ai_recipe/apk_install');

  /// 触发系统安装器安装指定 APK。
  ///
  /// 若用户未授予「安装未知应用」权限，Android 8+ 系统会自行引导到
  /// 设置页，不在此处抛错。
  static Future<void> install(String apkPath) async {
    await _channel.invokeMethod<void>('installApk', <String, Object>{
      'path': apkPath,
    });
  }
}
