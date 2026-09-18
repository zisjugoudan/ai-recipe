package com.airecipe.ai_recipe

import com.airecipe.ai_recipe.ocr.LocalOcrMethodHandler
import com.airecipe.ai_recipe.update.ApkInstallMethodHandler
import com.airecipe.ai_recipe.webview.WebViewFetchMethodHandler
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var localOcrHandler: LocalOcrMethodHandler? = null
    private var webViewFetchHandler: WebViewFetchMethodHandler? = null
    private var apkInstallHandler: ApkInstallMethodHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val handler = LocalOcrMethodHandler(applicationContext)
        localOcrHandler = handler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_recipe/local_ocr"
        ).setMethodCallHandler(handler)

        // IMPORT-008：后台隐藏 WebView 抓取任意网页（文本 + 图片地址）。
        val webViewHandler = WebViewFetchMethodHandler(this)
        webViewFetchHandler = webViewHandler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_recipe/webview_fetch"
        ).setMethodCallHandler(webViewHandler)

        // UPDATE-001：在线更新安装 APK（FileProvider + 系统安装器）。
        val updateHandler = ApkInstallMethodHandler(this)
        apkInstallHandler = updateHandler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ai_recipe/apk_install"
        ).setMethodCallHandler(updateHandler)
    }

    override fun onDestroy() {
        localOcrHandler?.close()
        localOcrHandler = null
        webViewFetchHandler?.close()
        webViewFetchHandler = null
        apkInstallHandler = null
        super.onDestroy()
    }
}
