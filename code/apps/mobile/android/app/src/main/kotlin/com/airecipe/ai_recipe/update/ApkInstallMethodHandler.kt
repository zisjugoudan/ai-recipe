package com.airecipe.ai_recipe.update

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * APK 安装平台通道（UPDATE-001，仅 Android）。
 *
 * 通道：`ai_recipe/apk_install`
 * 方法：`installApk`，参数 `{ path }`（APK 绝对路径）。
 *
 * 通过 FileProvider（authorities = packageName.updatefileprovider）把 APK
 * 暴露为 content:// URI，再以 ACTION_VIEW + package-archive mimeType 拉起
 * 系统安装器；Android 8+ 未授权「安装未知应用」时系统会自行引导到设置页。
 */
class ApkInstallMethodHandler(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> installApk(call, result)
            else -> result.notImplemented()
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("invalid_path", "APK 路径为空", null)
            return
        }
        val apkFile = File(path)
        if (!apkFile.exists()) {
            result.error("file_not_found", "APK 文件不存在", null)
            return
        }
        try {
            val contentUri: Uri = FileProvider.getUriForFile(
                activity,
                activity.packageName + ".updatefileprovider",
                apkFile,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(intent)
            result.success(null)
        } catch (e: Exception) {
            result.error(
                "install_failed",
                e.message ?: "无法打开系统安装器",
                null,
            )
        }
    }
}
