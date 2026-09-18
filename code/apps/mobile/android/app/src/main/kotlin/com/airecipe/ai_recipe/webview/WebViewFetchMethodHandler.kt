package com.airecipe.ai_recipe.webview

import android.app.Activity
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors

/**
 * 后台隐藏 WebView 抓取平台通道（IMPORT-008 / ADR-0019 重构版）。
 *
 * 用真实浏览器内核加载目标网页，按显式阶段状态机推进：
 * NAVIGATING → WAITING_CONTENT → EXTRACTING → FETCHING_IMAGES。
 *
 * 本轮生命周期与竞态加固（《解决方案.md》第一阶段，并入 IMPORT-008）：
 * - **请求隔离**：用 [RequestContext] 承载每次抓取的独立状态；所有异步入口
 *   （WebView 回调、evaluateJavascript 回调、Handler 延迟任务、图片写盘 worker）
 *   在回调开始处统一校验 `ctx === activeRequest && !ctx.cancelled`，天然丢弃
 *   迟到回调，杜绝“请求 A 的回调写进请求 B”。
 * - **导航/图片代次**：`navigationGeneration` 在每次主框架导航时递增，DOM 探测
 *   只接受创建时的代次；`imageGeneration` 在每张图片开始时递增，图片回调只接受
 *   创建时的代次。旧导航/旧图片的迟到回调即便属同一请求也会被丢弃。
 * - **新请求终止旧请求**：启动新请求前把旧请求标记为 superseded 并彻底停止
 *   （stopLoading、取消计时器、失效代次、清理专属目录），不显示“网页超时”。
 * - **真实总超时**：以 Dart 传入的 timeoutMs 建立请求级绝对截止时间
 *   `requestDeadline`，所有阶段的剩余时间都只会消费这一个总预算；
 *   阶段/单图超时取 `min(请求剩余, 阶段, 单图)`。
 * - **renderer gone 重建**：渲染进程崩溃后销毁并置空 WebView，下一次请求重建，
 *   错误分类为 rendererGone（不归入普通网络不可用）。
 * - **请求专属图片目录**：`filesDir/webview-imports/<requestId>/images/`，
 *   迟到 worker 只会写回旧请求自己的目录，不会污染新请求。
 *
 * 通道：`ai_recipe/webview_fetch`
 * 方法：
 * - `fetchPage`：参数 `{ url, platform, timeoutMs }`，成功返回
 *   `{ status:'ok', title, description, authorName, bodyText, imageUrls,
 *      images:[{url,localPath}], resolvedUrl }`；失败 error code 为
 *   invalidUrl / network / timeout / loginRequired / verificationRequired /
 *   emptyContent / cancelled / superseded / rendererGone。
 * - `cancelFetch`：取消当前抓取（原生立即停止导航、JS、图片下载与写盘）。
 * - `dispose`：销毁 WebView 并清理。
 */
class WebViewFetchMethodHandler(
    private val activity: Activity,
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) : MethodChannel.MethodCallHandler, Closeable {

    // ---- 抓取状态 ----

    private var webView: WebView? = null

    /** 当前活跃请求；同一时刻至多一个（新请求会终止旧请求）。 */
    private var activeRequest: RequestContext? = null

    private var requestCounter = 0L

    private val imageWorker = Executors.newSingleThreadExecutor()

    // 可取消的定时任务（单一实例，armDeadline 统一重排）
    private val timeoutRunnable = Runnable { onDeadline() }

    /** 抓取阶段：由 RequestContext 承载，避免跨请求残留。 */
    private enum class Stage { IDLE, NAVIGATING, WAITING_CONTENT, EXTRACTING, FETCHING_IMAGES }

    /**
     * 单次抓取的隔离上下文（《解决方案.md》P0-1/P0-2）。
     *
     * 所有异步入口在创建时捕获本对象，回调开始时校验 `ctx === activeRequest`，
     * 以身份比较而非日志编号实现请求隔离。
     */
    private class RequestContext(
        val requestId: Long,
        val platform: String,
        val originalUrl: String,
        val result: MethodChannel.Result,
        val timeoutMs: Long,
        val imageDir: File,
    ) {
        var stage = Stage.NAVIGATING

        /** 当前主框架 URL（随重定向/导航更新）。 */
        var currentMainFrameUrl: String? = null

        /** 导航代次：每次主框架导航递增，DOM 探测只接受创建时代次。 */
        var navigationGeneration = 0L

        /** 图片代次：每张图片开始递增，图片回调只接受创建时代次。 */
        var imageGeneration = 0L

        /** 请求级取消标记（用户取消或 superseded）。 */
        var cancelled = false

        /** 结果是否已对外返回（success/error），防止重复完成。 */
        var resultMarkedFinished = false

        /** 请求级绝对截止时间（Dart timeoutMs 的总预算，PERF/IMPORT-008）。 */
        var requestDeadlineMs = 0L

        // 提取结果
        var payload: JSONObject? = null
        var resolvedUrl: String? = null

        // 内容等待阶段
        var navStartedAt = 0L
        var contentWaitStartedAt = 0L
        var extractStartedAt = 0L

        // 图片阶段
        val imageQueue = ArrayDeque<String>()
        val savedImages = mutableListOf<Map<String, Any>>()
        var imagePhaseStartedAt = 0L
        var imageSingleStartedAt = 0L
        var currentImageUrl = ""
        var imagePollActive = false

        // ---- 可观测性（《解决方案.md》第三阶段 + 第二阶段 readiness 命中理由） ----
        var redirectCount = 0
        var finalHostPathHash = ""
        var httpStatusCode = 0
        var readinessReason = ""
        var bodyFingerprint = ""
        var bodyLength = 0
        var imageAttempted = 0
        var imageSucceeded = 0
        var imageFailed = 0
        val imageFailureReasons = mutableListOf<String>()
        var finalErrorClassification = ""
        var endedAt = 0L
        val stageStartedAt = mutableMapOf<Stage, Long>()
        var rendererGoneCount = 0

        override fun toString(): String =
            "RequestContext(requestId=$requestId, stage=$stage, platform=$platform)"
    }

    // ---- 通道入口 ----

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "fetchPage" -> handleFetchPage(call, result)
            "cancelFetch" -> {
                cancelFetch()
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun close() {
        dispose()
    }

    private fun handleFetchPage(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val url = args?.get("url") as? String
        val timeoutMs = (args?.get("timeoutMs") as? Number)?.toLong() ?: DEFAULT_TIMEOUT_MS
        val platform = (args?.get("platform") as? String)?.lowercase() ?: "web"
        if (url == null ||
            !(url.startsWith("http://") || url.startsWith("https://"))) {
            result.error("invalidUrl", "网页地址无效。", null)
            return
        }
        // 新请求正确终止旧请求（superseded）：不只写日志，而是彻底停止旧请求。
        activeRequest?.let { old -> terminate(old, "superseded", "上一个抓取任务已被新请求替代。") }

        requestCounter += 1
        val ctx = RequestContext(
            requestId = requestCounter,
            platform = platform,
            originalUrl = url,
            result = result,
            timeoutMs = timeoutMs,
            imageDir = requestImageDir(requestCounter),
        )
        ctx.stage = Stage.NAVIGATING
        ctx.navStartedAt = SystemClock.elapsedRealtime()
        ctx.requestDeadlineMs = ctx.navStartedAt + timeoutMs
        activeRequest = ctx

        stopLoading()
        armDeadline()
        dlog(ctx, "fetchPage url=${Uri.parse(url).host} timeoutMs=$timeoutMs")
        val view = ensureWebView()
        view.loadUrl(url)
    }

    /** 原生取消：标记取消、停止导航、取消计时器、失效代次、清理目录。 */
    private fun cancelFetch() {
        val ctx = activeRequest ?: return
        terminate(ctx, "cancelled", "抓取已取消。")
    }

    // ---- WebView 配置（ADR-0019：移动 UA + 正常视口，移除 addJavascriptInterface） ----

    private fun ensureWebView(): WebView {
        val existing = webView
        if (existing != null) return existing

        val view = WebView(activity)
        val settings: WebSettings = view.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.loadWithOverviewMode = true
        settings.useWideViewPort = true
        // ADR-0019：不改写 UA，使用系统默认移动 UA。

        view.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(ctx, "onPageStarted url=${safeUrl(url)}")
                // 仅在初始 NAVIGATING 阶段递增导航代次：进入 WAITING_CONTENT/EXTRACTING 后，
                // SPA 客户端路由（如小红书跳 item/xxx 相对 URL）会触发 onPageStarted，
                // 递增代次会让已发出的探测/提取回调被作废，导致误判失败。
                if (ctx.stage == Stage.NAVIGATING) {
                    ctx.navigationGeneration += 1
                }
                ctx.redirectCount += 1
                ctx.currentMainFrameUrl = url
                ctx.finalHostPathHash = hostPathHash(url)
            }

            // 主框架首次提交（API 23+）：真正"文档已到手"信号。
            override fun onPageCommitVisible(view: WebView?, url: String?) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(ctx, "onPageCommitVisible url=${safeUrl(url)}")
                ctx.currentMainFrameUrl = url
                if (ctx.stage == Stage.NAVIGATING) {
                    ctx.navigationGeneration += 1
                    enterWaitContent(ctx)
                }
            }

            // 不再作为"页面就绪"信号：仅兜底（旧系统无 commit）与图片导航完成信号。
            override fun onPageFinished(view: WebView?, url: String?) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(ctx, "onPageFinished url=${safeUrl(url)}")
                when (ctx.stage) {
                    Stage.NAVIGATING -> enterWaitContent(ctx)
                    Stage.FETCHING_IMAGES -> startImageReadyPolling(ctx, ctx.imageGeneration)
                    else -> {}
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onReceivedError(
                view: WebView?,
                errorCode: Int,
                description: String?,
                failingUrl: String?,
            ) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(ctx, "onReceivedError(code) code=$errorCode url=${safeUrl(failingUrl)}")
                // 仅初始导航阶段的主框架错误才中止；SPA 客户端路由的后续导航错误忽略。
                if (ctx.stage == Stage.NAVIGATING &&
                    (failingUrl == null || failingUrl == ctx.originalUrl)
                ) {
                    abortWithNetworkError(ctx, "页面加载失败（$errorCode）。")
                }
            }

            @Suppress("OVERRIDE_DEPRECATION")
            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?,
            ) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(
                    ctx,
                    "onReceivedError main=${request?.isForMainFrame} " +
                        "code=${error?.errorCode} url=${safeUrl(request?.url?.toString())}",
                )
                if (request?.isForMainFrame == true) {
                    when (ctx.stage) {
                        Stage.FETCHING_IMAGES -> {
                            // 图片阶段的主框架错误即当前单张图片加载失败，继续下一张。
                            ctx.imagePollActive = false
                            onCurrentImageFailed(ctx, "http-error-${error?.errorCode}")
                        }
                        Stage.NAVIGATING -> {
                            // 初始导航失败才中止。
                            abortWithNetworkError(ctx, "页面加载失败（${error?.errorCode}）。")
                        }
                        else -> {
                            // WAITING_CONTENT / EXTRACTING：页面已提交，正文在加载/提取中。
                            // SPA 客户端路由会产生无 scheme 的相对 URL 导航错误
                            // （ERROR_UNSUPPORTED_SCHEME -10），属噪音，忽略，由提取脚本判定内容。
                            dlog(ctx, "ignore main-frame nav error code=${error?.errorCode} during ${ctx.stage}")
                        }
                    }
                }
            }

            // 主框架 HTTP 错误（403/404/5xx）：导航阶段立即分类结束，不等到总超时。
            @Suppress("OVERRIDE_DEPRECATION")
            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?,
            ) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                val status = errorResponse?.statusCode ?: 0
                if (request?.isForMainFrame == true) ctx.httpStatusCode = status
                dlog(
                    ctx,
                    "onReceivedHttpError status=$status main=${request?.isForMainFrame} " +
                        "url=${safeUrl(request?.url?.toString())}",
                )
                if (request?.isForMainFrame == true) {
                    when (ctx.stage) {
                        Stage.NAVIGATING -> when (status) {
                            403 -> terminate(
                                ctx,
                                "verificationRequired",
                                "平台正在进行安全验证或限制访问，请稍后重试或改用粘贴正文导入。",
                            )
                            404, 410 -> terminate(ctx, "emptyContent", "该网页内容不存在或已删除。")
                            else -> abortWithNetworkError(ctx, "页面加载失败（HTTP $status）。")
                        }
                        Stage.WAITING_CONTENT -> when (status) {
                            // 已提交但主框架 404/410：明确"内容不存在"，立即分类，避免拖到超时。
                            404, 410 -> terminate(ctx, "emptyContent", "该网页内容不存在或已删除。")
                            // 其他状态（403/5xx）在等待内容阶段可能是 SPA 中间态，交给探测/提取判定。
                            else -> dlog(ctx, "ignore http error $status while WAITING_CONTENT")
                        }
                        // EXTRACTING / FETCHING_IMAGES：由提取脚本或单图失败处理。
                        else -> {}
                    }
                }
            }

            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: android.net.http.SslError?,
            ) {
                val ctx = activeRequest ?: return
                if (ctx.cancelled) return
                dlog(ctx, "onReceivedSslError primary=${error?.primaryError}")
                handler?.cancel()
                // 正文成功后图片阶段的 SSL 错误只影响当前配图，不整单失败（P0-8）。
                if (ctx.stage == Stage.FETCHING_IMAGES) {
                    ctx.imagePollActive = false
                    onCurrentImageFailed(ctx, "ssl")
                } else {
                    abortWithNetworkError(ctx, "页面安全证书校验失败，请稍后重试。")
                }
            }

            override fun onRenderProcessGone(
                view: WebView?,
                detail: RenderProcessGoneDetail?,
            ): Boolean {
                val ctx = activeRequest ?: return true
                dlog(ctx, "onRenderProcessGone crashed=${detail?.didCrash()}")
                ctx.rendererGoneCount += 1
                // 渲染进程崩溃后必须销毁重建 WebView，不能继续复用已失效实例（P0-7）。
                destroyWebView()
                // 正文成功后图片阶段的 renderer gone 只结束配图抓取，不整单失败（P0-8）。
                if (ctx.stage == Stage.FETCHING_IMAGES) {
                    finishImages(ctx)
                } else {
                    terminate(ctx, "rendererGone", "网页渲染进程异常，请稍后重试。")
                }
                return true
            }
        }

        // console 透传 + 进度关键节点日志（诊断用）。
        view.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(message: ConsoleMessage?): Boolean {
                Log.d(TAG, "console ${message?.messageLevel()} ${message?.message()}")
                return true
            }

            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                val ctx = activeRequest ?: return
                if (newProgress == 10 || newProgress == 25 || newProgress == 50 ||
                    newProgress == 75 || newProgress == 90 || newProgress == 100
                ) {
                    dlog(ctx, "progress=$newProgress")
                }
            }
        }

        // 正常 attach 与 layout（360x800 移动视口），放到 decorView 最底层。
        val decor = activity.window.decorView as ViewGroup
        decor.addView(view, 0, android.widget.FrameLayout.LayoutParams(360, 800))
        webView = view
        return view
    }

    // ---- 阶段 2：WAITING_CONTENT（DOM 探测，ADR-0019） ----

    private fun enterWaitContent(ctx: RequestContext) {
        if (ctx.stage != Stage.NAVIGATING || ctx.cancelled) return
        ctx.stage = Stage.WAITING_CONTENT
        ctx.contentWaitStartedAt = SystemClock.elapsedRealtime()
        markStageStart(ctx, Stage.WAITING_CONTENT)
        armDeadline()
        dlog(ctx, "enter WAITING_CONTENT")
        val gen = ctx.navigationGeneration
        mainHandler.postDelayed({ probeContent(ctx, gen) }, PROBE_INTERVAL_MS)
    }

    /** 按平台 readiness 探测（《解决方案.md》第二阶段：ReadinessDetector）。 */
    private fun probeContent(ctx: RequestContext, generation: Long) {
        if (ctx.cancelled) return
        if (ctx !== activeRequest) return
        // 旧导航的探测回调直接丢弃（P0-1/P0-6）。
        if (generation != ctx.navigationGeneration) return
        if (ctx.stage != Stage.WAITING_CONTENT) return
        val view = webView ?: return
        val script = probeScript(ctx.platform, targetId(ctx.platform, ctx.originalUrl))
        view.evaluateJavascript(script) { raw ->
            if (ctx.cancelled || ctx !== activeRequest) return@evaluateJavascript
            if (generation != ctx.navigationGeneration) return@evaluateJavascript
            if (ctx.stage != Stage.WAITING_CONTENT) return@evaluateJavascript
            val parsed = try {
                JSONObject(unescapeJsonString(raw))
            } catch (_: Exception) {
                null
            }
            val risk = parsed?.optBoolean("risk", false) ?: false
            val login = parsed?.optBoolean("login", false) ?: false
            val gone = parsed?.optBoolean("gone", false) ?: false
            val ready = parsed?.optBoolean("ready", false) ?: false
            val readyReason = parsed?.optString("readyReason", "") ?: ""
            val fingerprint = parsed?.optString("fingerprint", "") ?: ""
            val imgCount = parsed?.optInt("imgCount", 0) ?: 0
            dlog(
                ctx,
                "probe ready=$ready reason=$readyReason risk=$risk login=$login " +
                    "gone=$gone img=$imgCount fp=$fingerprint",
            )
            // 命中该平台 readiness：直接进入提取。
            if (ready) {
                ctx.readinessReason = readyReason
                ctx.bodyFingerprint = fingerprint
                enterExtracting(ctx)
                return@evaluateJavascript
            }
            // 明确命中登录墙 / 风控 / 失效页：进入提取，由提取脚本分类。
            if (risk || login || gone) {
                ctx.readinessReason = when {
                    login -> "loginWall"
                    risk -> "verification"
                    else -> "gone"
                }
                enterExtracting(ctx)
                return@evaluateJavascript
            }
            // 无任何内容且长时间无变化（软空闲超时）→ 进入提取，由提取脚本决定分类。
            val elapsed = SystemClock.elapsedRealtime() - ctx.contentWaitStartedAt
            if (elapsed >= IDLE_PROBE_TIMEOUT_MS) {
                ctx.readinessReason = "idleForceExtract"
                enterExtracting(ctx)
                return@evaluateJavascript
            }
            mainHandler.postDelayed({ probeContent(ctx, generation) }, PROBE_INTERVAL_MS)
        }
    }

    // ---- 阶段 3：EXTRACTING ----

    private fun enterExtracting(ctx: RequestContext) {
        if (ctx.stage != Stage.WAITING_CONTENT || ctx.cancelled) return
        ctx.stage = Stage.EXTRACTING
        ctx.extractStartedAt = SystemClock.elapsedRealtime()
        markStageStart(ctx, Stage.EXTRACTING)
        armDeadline()
        dlog(ctx, "enter EXTRACTING")
        val script = extractScript(ctx.platform)
        val gen = ctx.navigationGeneration
        webView?.evaluateJavascript(script) { raw ->
            if (ctx.cancelled || ctx !== activeRequest) return@evaluateJavascript
            if (gen != ctx.navigationGeneration) return@evaluateJavascript
            if (ctx.stage != Stage.EXTRACTING) return@evaluateJavascript
            val parsed = try {
                JSONObject(unescapeJsonString(raw))
            } catch (_: Exception) {
                null
            }
            if (parsed == null) {
                dlog(ctx, "extract result not JSON")
                stopLoading()
                terminate(ctx, "emptyContent", "网页内容无法解析。")
                return@evaluateJavascript
            }
            ctx.payload = parsed
            ctx.resolvedUrl = parsed.optString("url", "").ifEmpty { ctx.originalUrl }
            val imageUrls = collectImageUrls(parsed)
            // 提取结果有效性校验（ResultValidator）。
            val valid = validateResult(ctx, parsed)
            dlog(
                ctx,
                "extracted title=${parsed.optString("title", "").take(30)} " +
                    "bodyLen=${ctx.bodyLength} images=${imageUrls.size} valid=$valid " +
                    "reason=${ctx.readinessReason}",
            )
            if (!valid) {
                stopLoading()
                classifyEmptyPage(
                    ctx,
                    parsed.optString("bodyText", ""),
                    parsed.optString("title", ""),
                )
                return@evaluateJavascript
            }
            // 正文已提取成功：立即停止页面继续加载。
            stopLoading()
            startFetchingImages(ctx, imageUrls)
        }
    }

    private fun collectImageUrls(payload: JSONObject): List<String> {
        val array = payload.optJSONArray("imageUrls") ?: return emptyList()
        val out = mutableListOf<String>()
        for (index in 0 until array.length()) {
            val item = array.optString(index, "")
            if (item.isNotEmpty()) out.add(item)
        }
        return out
    }

    // ---- 阶段 4：FETCHING_IMAGES（逐张顶层导航取图，ADR-0019） ----

    private fun startFetchingImages(ctx: RequestContext, imageUrls: List<String>) {
        if (ctx.cancelled) return
        if (imageUrls.isEmpty()) {
            finishImages(ctx)
            return
        }
        ctx.stage = Stage.FETCHING_IMAGES
        ctx.imageQueue.clear()
        imageUrls.take(MAX_IMAGE_CANDIDATES).forEach { ctx.imageQueue.add(it) }
        ctx.imagePhaseStartedAt = SystemClock.elapsedRealtime()
        markStageStart(ctx, Stage.FETCHING_IMAGES)
        dlog(ctx, "enter FETCHING_IMAGES candidates=${ctx.imageQueue.size}")
        fetchNextImage(ctx)
    }

    private fun fetchNextImage(ctx: RequestContext) {
        if (ctx.cancelled || ctx !== activeRequest) {
            finishImages(ctx)
            return
        }
        if (ctx.savedImages.size >= MAX_COVER_IMAGES || ctx.imageQueue.isEmpty()) {
            finishImages(ctx)
            return
        }
        ctx.imageGeneration += 1
        ctx.imageAttempted += 1
        val url = ctx.imageQueue.removeFirst()
        ctx.currentImageUrl = url
        ctx.imageSingleStartedAt = SystemClock.elapsedRealtime()
        ctx.imagePollActive = false
        // 日志脱敏：只记录序号、CDN host 与 URL 哈希，不打印完整签名 URL。
        dlog(ctx, "fetch image idx=${ctx.savedImages.size} host=${Uri.parse(url).host} hash=${url.hashCode()}")
        armDeadline()
        // 图片作为 WebView 顶层文档打开（http 升级 https，CDN 已验证支持）。
        val target = if (url.startsWith("http://")) "https://" + url.substring(7) else url
        webView?.loadUrl(target)
    }

    private fun startImageReadyPolling(ctx: RequestContext, generation: Long) {
        if (ctx.cancelled) return
        if (ctx.stage != Stage.FETCHING_IMAGES || ctx.imagePollActive) return
        ctx.imagePollActive = true
        mainHandler.postDelayed({ pollImageReady(ctx, generation) }, IMAGE_POLL_INTERVAL_MS)
    }

    /** 等待图片文档中的 <img> complete && naturalWidth>0。 */
    private fun pollImageReady(ctx: RequestContext, generation: Long) {
        if (ctx.cancelled || ctx !== activeRequest) return
        if (generation != ctx.imageGeneration) return
        if (ctx.stage != Stage.FETCHING_IMAGES || !ctx.imagePollActive) return
        webView?.evaluateJavascript(IMAGE_READY_SCRIPT) { raw ->
            if (ctx.cancelled || ctx !== activeRequest) return@evaluateJavascript
            if (generation != ctx.imageGeneration) return@evaluateJavascript
            if (ctx.stage != Stage.FETCHING_IMAGES || !ctx.imagePollActive) return@evaluateJavascript
            val parsed = try {
                JSONObject(unescapeJsonString(raw))
            } catch (_: Exception) {
                null
            }
            val ready = parsed?.optBoolean("ready", false) ?: false
            val isImage = parsed?.optBoolean("isImage", false) ?: false
            if (ready && isImage) {
                ctx.imagePollActive = false
                dlog(ctx, "image doc ready w=${parsed.optInt("w")} h=${parsed.optInt("h")}")
                downloadCurrentImage(ctx, generation)
            } else if (SystemClock.elapsedRealtime() - ctx.imageSingleStartedAt < IMAGE_SINGLE_TIMEOUT_MS) {
                mainHandler.postDelayed({ pollImageReady(ctx, generation) }, IMAGE_POLL_INTERVAL_MS)
            } else {
                dlog(ctx, "image not ready in time")
                ctx.imagePollActive = false
                onCurrentImageFailed(ctx, "not-ready")
            }
        }
    }

    /** 路径 A：图片文档同源 fetch(location.href) 读取原始字节。 */
    private fun downloadCurrentImage(ctx: RequestContext, generation: Long) {
        webView?.evaluateJavascript(FETCH_IMAGE_SCRIPT) { raw ->
            if (ctx.cancelled || ctx !== activeRequest) return@evaluateJavascript
            if (generation != ctx.imageGeneration) return@evaluateJavascript
            if (ctx.stage != Stage.FETCHING_IMAGES) return@evaluateJavascript
            val parsed = try {
                JSONObject(unescapeJsonString(raw))
            } catch (_: Exception) {
                null
            }
            if (parsed?.optBoolean("ok", false) == true) {
                val data = parsed.optString("data", "")
                val index = ctx.savedImages.size
                saveImageBytes(ctx, index, data) { savedFile ->
                    if (ctx.cancelled || ctx !== activeRequest) return@saveImageBytes
                    if (savedFile != null) {
                        dlog(ctx, "image saved via fetch")
                        ctx.savedImages.add(
                            mapOf("url" to ctx.currentImageUrl, "localPath" to savedFile.absolutePath),
                        )
                        ctx.imageSucceeded += 1
                        fetchNextImage(ctx)
                    } else {
                        dlog(ctx, "image write failed via fetch")
                        canvasExportCurrentImage(ctx, generation)
                    }
                }
            } else {
                dlog(ctx, "same-origin fetch failed: ${parsed?.optString("error")}")
                canvasExportCurrentImage(ctx, generation)
            }
        }
    }

    /** 路径 B：Canvas 绘制导出兜底（顶层同源文档不应被跨域污染）。 */
    private fun canvasExportCurrentImage(ctx: RequestContext, generation: Long) {
        webView?.evaluateJavascript(CANVAS_IMAGE_SCRIPT) { raw ->
            if (ctx.cancelled || ctx !== activeRequest) return@evaluateJavascript
            if (generation != ctx.imageGeneration) return@evaluateJavascript
            if (ctx.stage != Stage.FETCHING_IMAGES) return@evaluateJavascript
            val parsed = try {
                JSONObject(unescapeJsonString(raw))
            } catch (_: Exception) {
                null
            }
            if (parsed?.optBoolean("ok", false) == true) {
                val dataUrl = parsed.optString("data", "")
                val index = ctx.savedImages.size
                saveDataUrl(ctx, index, dataUrl) { savedFile ->
                    if (ctx.cancelled || ctx !== activeRequest) return@saveDataUrl
                    if (savedFile != null) {
                        dlog(ctx, "image saved via canvas")
                        ctx.savedImages.add(
                            mapOf("url" to ctx.currentImageUrl, "localPath" to savedFile.absolutePath),
                        )
                        ctx.imageSucceeded += 1
                        fetchNextImage(ctx)
                    } else {
                        dlog(ctx, "canvas save failed")
                        onCurrentImageFailed(ctx, "canvas-save")
                    }
                }
            } else {
                dlog(ctx, "canvas export failed: ${parsed?.optString("error")}")
                onCurrentImageFailed(ctx, "canvas")
            }
        }
    }

    private fun onCurrentImageFailed(ctx: RequestContext, reason: String) {
        dlog(ctx, "image failed reason=$reason")
        ctx.imageFailed += 1
        if (ctx.imageFailureReasons.size < MAX_COVER_IMAGES) {
            ctx.imageFailureReasons.add(reason)
        }
        ctx.imagePollActive = false
        fetchNextImage(ctx)
    }

    /** 单张完成 → 立即写盘（后台线程，避免阻塞主线程）；index 在调用方锁定。 */
    private fun saveImageBytes(ctx: RequestContext, index: Int, base64: String, onDone: (File?) -> Unit) {
        imageWorker.execute {
            val file = writeBase64ToFile(ctx, index, base64)
            mainHandler.post { onDone(file) }
        }
    }

    private fun saveDataUrl(ctx: RequestContext, index: Int, dataUrl: String, onDone: (File?) -> Unit) {
        imageWorker.execute {
            val file = writeDataUrlToFile(ctx, index, dataUrl)
            mainHandler.post { onDone(file) }
        }
    }

    // ---- 收尾：正文成功即成功；图片失败只影响配图数量 ----

    private fun finishImages(ctx: RequestContext) {
        if (ctx.stage != Stage.FETCHING_IMAGES) return
        val p = ctx.payload ?: return
        dlog(ctx, "finish images saved=${ctx.savedImages.size}")
        completeSuccess(
            ctx,
            mapOf(
                "status" to "ok",
                "title" to p.optString("title", "").trim(),
                "description" to p.optString("description", "").trim(),
                "authorName" to p.optString("authorName", "").trim(),
                "bodyText" to p.optString("bodyText", "").trim(),
                "imageUrls" to collectImageUrls(p),
                "images" to ctx.savedImages.toList(),
                "resolvedUrl" to (ctx.resolvedUrl ?: p.optString("url", "")),
            ),
        )
    }

    private fun classifyEmptyPage(ctx: RequestContext, body: String, title: String) {
        val lower = "$title $body".lowercase()
        if (loginMarkers.any { lower.contains(it) }) {
            terminate(ctx, "loginRequired", "该页面需要登录后才能查看内容，可改用粘贴正文导入。")
            return
        }
        if (verificationMarkers.any { lower.contains(it) }) {
            terminate(ctx, "verificationRequired", "平台正在进行安全验证，请稍后重试或改用粘贴正文导入。")
            return
        }
        if (goneMarkers.any { lower.contains(it) }) {
            terminate(ctx, "emptyContent", "该网页内容不存在或已删除。")
            return
        }
        terminate(ctx, "emptyContent", "网页未返回可用的文本或图片内容，请检查链接是否有效。")
    }

    // ---- 超时与清理 ----

    /** 以 Dart 传入的 timeoutMs 建立请求级绝对截止时间，所有阶段只消费这一个总预算。 */
    private fun armDeadline() {
        val ctx = activeRequest ?: return
        val nowR = SystemClock.elapsedRealtime()
        val requestRemaining = ctx.requestDeadlineMs - nowR
        if (requestRemaining <= 0) {
            mainHandler.post(timeoutRunnable)
            return
        }
        val stageRemaining = when (ctx.stage) {
            Stage.NAVIGATING -> NAVIGATING_TIMEOUT_MS - (nowR - ctx.navStartedAt)
            Stage.WAITING_CONTENT -> WAITING_CONTENT_TIMEOUT_MS - (nowR - ctx.contentWaitStartedAt)
            Stage.EXTRACTING -> EXTRACTING_TIMEOUT_MS - (nowR - ctx.extractStartedAt)
            Stage.FETCHING_IMAGES -> {
                val phaseRemaining = IMAGE_TOTAL_TIMEOUT_MS - (nowR - ctx.imagePhaseStartedAt)
                val singleRemaining = IMAGE_SINGLE_TIMEOUT_MS - (nowR - ctx.imageSingleStartedAt)
                minOf(phaseRemaining, singleRemaining)
            }
            else -> Long.MAX_VALUE
        }
        val effective = minOf(requestRemaining, stageRemaining)
        mainHandler.removeCallbacks(timeoutRunnable)
        mainHandler.postDelayed(timeoutRunnable, maxOf(1, effective))
    }

    /** 截止调度触发：先判请求绝对超时，再按阶段分类（P0-4/P0-5）。 */
    private fun onDeadline() {
        val ctx = activeRequest ?: return
        if (ctx.cancelled) return
        val nowR = SystemClock.elapsedRealtime()
        // 请求级绝对超时才是真正的总上限。
        if (nowR >= ctx.requestDeadlineMs) {
            dlog(ctx, "REQUEST_TIMEOUT total=${ctx.timeoutMs}ms")
            if (ctx.stage == Stage.FETCHING_IMAGES) {
                // 正文已成功，图片阶段超时只收尾，不整单失败（P0-8）。
                finishImages(ctx)
            } else {
                stopLoading()
                terminate(ctx, "timeout", "网页加载超时，请稍后重试。")
            }
            return
        }
        when (ctx.stage) {
            Stage.NAVIGATING -> {
                dlog(ctx, "NAVIGATION_TIMEOUT")
                stopLoading()
                terminate(ctx, "timeout", "网页加载超时，请稍后重试。")
            }
            Stage.WAITING_CONTENT -> {
                dlog(ctx, "CONTENT_NOT_READY -> extract anyway")
                // 超时后仍进入提取，由提取脚本决定是否有可用内容。
                enterExtracting(ctx)
            }
            Stage.EXTRACTING -> {
                dlog(ctx, "DOM_EXTRACTION_FAILED")
                stopLoading()
                terminate(ctx, "emptyContent", "网页内容提取超时，请稍后重试或改用粘贴正文导入。")
            }
            Stage.FETCHING_IMAGES -> {
                // 区分单图超时与图片阶段总超时；正文成功不因图片失败而整体失败。
                if (nowR - ctx.imagePhaseStartedAt >= IMAGE_TOTAL_TIMEOUT_MS) {
                    dlog(ctx, "IMAGE_PHASE_TIMEOUT")
                    finishImages(ctx)
                } else {
                    ctx.imagePollActive = false
                    onCurrentImageFailed(ctx, "single-timeout")
                }
            }
            else -> {}
        }
    }

    private fun abortWithNetworkError(ctx: RequestContext, message: String) {
        dlog(ctx, "abort: $message")
        stopLoading()
        terminate(ctx, "network", message)
    }

    /** 统一结束：清理计时器、置空 activeRequest、完成 result、清理专属目录。 */
    private fun terminate(ctx: RequestContext, code: String, message: String) {
        if (ctx.resultMarkedFinished) return
        ctx.resultMarkedFinished = true
        ctx.cancelled = true
        mainHandler.removeCallbacks(timeoutRunnable)
        if (ctx === activeRequest) activeRequest = null
        stopLoading()
        cleanupRequestDir(ctx)
        ctx.endedAt = SystemClock.elapsedRealtime()
        ctx.finalErrorClassification = code
        logObservability(ctx)
        ctx.result.error(code, message, null)
    }

    private fun completeSuccess(ctx: RequestContext, data: Map<String, Any?>) {
        if (ctx.resultMarkedFinished) return
        ctx.resultMarkedFinished = true
        ctx.cancelled = true
        mainHandler.removeCallbacks(timeoutRunnable)
        if (ctx === activeRequest) activeRequest = null
        ctx.endedAt = SystemClock.elapsedRealtime()
        ctx.finalErrorClassification = "ok"
        logObservability(ctx)
        // 成功：保留图片目录供 Dart 读取，清理交给 dispose / 下一请求 supersede。
        ctx.result.success(data)
    }

    private fun stopLoading() {
        try {
            webView?.stopLoading()
        } catch (_: Exception) {
            // WebView 已销毁时忽略。
        }
    }

    /** renderer gone / dispose 时销毁 WebView，下一次请求重建（P0-7）。 */
    private fun destroyWebView() {
        val view = webView ?: return
        webView = null
        try {
            (view.parent as? ViewGroup)?.removeView(view)
        } catch (_: Exception) {
            // 父容器异常时继续销毁。
        }
        try {
            view.stopLoading()
            view.destroy()
        } catch (_: Exception) {
            // WebView 已销毁时忽略。
        }
    }

    fun dispose() {
        val ctx = activeRequest
        if (ctx != null) {
            if (!ctx.resultMarkedFinished) {
                ctx.resultMarkedFinished = true
                ctx.result.error("timeout", "抓取任务已取消。", null)
            }
            activeRequest = null
        }
        requestCounter += 1
        stopLoading()
        destroyWebView()
        imageWorker.shutdownNow()
        cleanupAllImportDirs()
    }

    // ---- 文件写盘 ----

    /** 请求专属图片目录（P0：#4）：`webview-imports/<requestId>/images/`。 */
    private fun requestImageDir(requestId: Long): File =
        File(activity.filesDir, "webview-imports/$requestId/images").apply { mkdirs() }

    private fun cleanupRequestDir(ctx: RequestContext) {
        deleteRecursively(ctx.imageDir)
    }

    private fun cleanupAllImportDirs() {
        try {
            val root = File(activity.filesDir, "webview-imports")
            if (root.exists()) {
                root.listFiles()?.forEach { dir -> deleteRecursively(dir) }
            }
        } catch (_: Exception) {
            // 清理失败不阻塞。
        }
    }

    private fun deleteRecursively(file: File) {
        try {
            if (file.isDirectory) {
                file.listFiles()?.forEach { deleteRecursively(it) }
            }
            file.delete()
        } catch (_: Exception) {
            // 清理失败不阻塞。
        }
    }

    /** 纯 base64（同源 fetch 结果）：按文件魔数判断类型并写盘。 */
    private fun writeBase64ToFile(ctx: RequestContext, index: Int, base64: String): File? {
        if (base64.isEmpty()) return null
        val bytes = try {
            Base64.decode(base64, Base64.DEFAULT)
        } catch (_: Exception) {
            return null
        }
        if (bytes.isEmpty() || bytes.size > MAX_IMAGE_BYTES) return null
        val ext = guessImageExt(bytes) ?: return null
        val file = File(ctx.imageDir, "img-$index.$ext")
        return try {
            file.writeBytes(bytes)
            file
        } catch (_: Exception) {
            null
        }
    }

    /** data URL（Canvas 导出）：解析 MIME 与 base64 后写盘。 */
    private fun writeDataUrlToFile(ctx: RequestContext, index: Int, dataUrl: String): File? {
        val marker = ";base64,"
        val markerIndex = dataUrl.indexOf(marker)
        if (markerIndex < 0) return null
        val mime = dataUrl.substring(5, markerIndex).lowercase()
        val base64 = dataUrl.substring(markerIndex + marker.length)
        val bytes = try {
            Base64.decode(base64, Base64.DEFAULT)
        } catch (_: Exception) {
            return null
        }
        if (bytes.isEmpty() || bytes.size > MAX_IMAGE_BYTES) return null
        val ext = when (mime) {
            "image/png" -> "png"
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            else -> guessImageExt(bytes) ?: return null
        }
        val file = File(ctx.imageDir, "img-$index.$ext")
        return try {
            file.writeBytes(bytes)
            file
        } catch (_: Exception) {
            null
        }
    }

    /** 按文件魔数推断图片扩展名。 */
    private fun guessImageExt(bytes: ByteArray): String? {
        if (bytes.size >= 8 &&
            bytes[0] == 0x89.toByte() && bytes[1] == 'P'.code.toByte() &&
            bytes[2] == 'N'.code.toByte() && bytes[3] == 'G'.code.toByte()
        ) {
            return "png"
        }
        if (bytes.size >= 12 &&
            bytes[0] == 'R'.code.toByte() && bytes[1] == 'I'.code.toByte() &&
            bytes[2] == 'F'.code.toByte() && bytes[3] == 'F'.code.toByte() &&
            bytes[8] == 'W'.code.toByte() && bytes[9] == 'E'.code.toByte() &&
            bytes[10] == 'B'.code.toByte() && bytes[11] == 'P'.code.toByte()
        ) {
            return "webp"
        }
        if (bytes.size >= 3 &&
            bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte() && bytes[2] == 0xFF.toByte()
        ) {
            return "jpg"
        }
        return null
    }

    // ---- 平台分流与脚本选择（《解决方案.md》第二阶段：ReadinessDetector/ContentExtractor） ----

    /** 从初始 URL 提取目标内容 ID（小红书笔记 ID / 抖音视频 ID），用于 readiness 校验。 */
    private fun targetId(platform: String, url: String): String {
        if (platform != "xiaohongshu" && platform != "douyin") return ""
        val path = Uri.parse(url).path ?: ""
        val segments = path.split("/").filter { it.isNotBlank() }
        // 内容 ID 通常是路径最后一段且长度 >= 10。
        return segments.lastOrNull { it.length >= 10 } ?: ""
    }

    /** 按平台选择 readiness 探测脚本，并把目标 ID 注入（用于 URL 一致性校验）。 */
    private fun probeScript(platform: String, targetId: String): String {
        val script = when (platform) {
            "xiaohongshu" -> PROBE_SCRIPT_XHS
            "douyin" -> PROBE_SCRIPT_DOUYIN
            else -> PROBE_SCRIPT_GENERIC
        }
        return script.replace("__TARGET_ID__", targetId)
    }

    /** 按平台选择内容提取脚本。 */
    private fun extractScript(platform: String): String = when (platform) {
        "xiaohongshu" -> EXTRACT_SCRIPT_XHS
        "douyin" -> EXTRACT_SCRIPT_DOUYIN
        else -> EXTRACT_SCRIPT_GENERIC
    }

    /**
     * 提取结果有效性校验（ResultValidator）：确认不是"壳页/登录/验证/删除/受限"，
     * 并回填可观测性字段。返回 false 时调用方按空内容分类。
     */
    private fun validateResult(ctx: RequestContext, parsed: JSONObject): Boolean {
        val title = parsed.optString("title", "").trim()
        val body = parsed.optString("bodyText", "").trim()
        val desc = parsed.optString("description", "").trim()
        val images = collectImageUrls(parsed)
        val lower = "$title $desc $body".lowercase()
        val hasText = title.isNotEmpty() || desc.isNotEmpty() || body.isNotEmpty()
        // 命中登录/验证/删除标记且无有效正文 → 视为失效页。
        if (!hasText || images.isEmpty()) {
            val login = loginMarkers.any { lower.contains(it) }
            val verify = verificationMarkers.any { lower.contains(it) }
            val gone = goneMarkers.any { lower.contains(it) }
            if (login || verify || gone) {
                ctx.readinessReason = when {
                    login -> "loginWall"
                    verify -> "verification"
                    else -> "gone"
                }
            }
        }
        ctx.bodyLength = body.length
        ctx.bodyFingerprint = parsed.optString("fingerprint", "")
        return hasText || images.isNotEmpty()
    }

    /** 进入证据阶段时记录阶段开始时间（可观测性）。 */
    private fun markStageStart(ctx: RequestContext, s: Stage) {
        ctx.stageStartedAt[s] = SystemClock.elapsedRealtime()
    }

    /** 汇总各阶段耗时并输出请求级可观测性日志（第三阶段）。 */
    private fun logObservability(ctx: RequestContext) {
        val nowEnd = ctx.endedAt
        val sb = StringBuilder("OBS req=${ctx.requestId} platform=${ctx.platform} ")
        sb.append("stage=${
            ctx.stageStartedAt.map { (s, t) ->
                val d = (nowEnd - t).coerceAtLeast(0)
                "${s.name}=${d}ms"
            }.joinToString(",")
        } ")
        sb.append("redirect=${ctx.redirectCount} http=${
            ctx.httpStatusCode.takeIf { it > 0 }?.toString() ?: "-"
        } ")
        sb.append("readiness=\"${ctx.readinessReason}\" fp=\"${ctx.bodyFingerprint}\" bodyLen=${ctx.bodyLength} ")
        sb.append("imgAttempt=${ctx.imageAttempted} imgOk=${ctx.imageSucceeded} imgFail=${ctx.imageFailed} ")
        sb.append("imgFailReasons=${ctx.imageFailureReasons.joinToString(",")} ")
        sb.append("rendererGone=${ctx.rendererGoneCount} final=${ctx.finalErrorClassification} totalMs=${nowEnd - ctx.navStartedAt}")
        Log.d(TAG, sb.toString())
    }

    private fun dlog(ctx: RequestContext, msg: String) {
        Log.d(
            TAG,
            "req=${ctx.requestId} stage=${ctx.stage} " +
                "t=${SystemClock.elapsedRealtime() / 1000}s $msg",
        )
    }

    /** host+path 的短 hash，用于可观测性里追踪最终落到哪个页面而不暴露参数。 */
    private fun hostPathHash(url: String?): String {
        if (url.isNullOrEmpty()) return ""
        return try {
            val uri = Uri.parse(url)
            val path = uri.path ?: ""
            "${uri.host}/${path}".hashCode().toString(16)
        } catch (_: Exception) {
            ""
        }
    }

    /** URL 脱敏：只保留 host 与 path 前 60 字符，不记录签名查询参数。 */
    private fun safeUrl(url: String?): String {
        if (url.isNullOrEmpty()) return ""
        return try {
            val uri = Uri.parse(url)
            val path = uri.path ?: ""
            "${uri.host}${path.take(60)}"
        } catch (_: Exception) {
            url.take(60)
        }
    }

    private companion object {
        const val TAG = "WebViewFetch"
        /** 总超时上限（Dart 侧传入 timeoutMs 的默认值，各阶段另有独立上限）。 */
        const val DEFAULT_TIMEOUT_MS = 60000L
        /** 导航阶段上限（ADR-0019：15~20s）。 */
        const val NAVIGATING_TIMEOUT_MS = 18000L
        /** 内容等待硬上限（ADR-0019：10~15s）。 */
        const val WAITING_CONTENT_TIMEOUT_MS = 12000L
        /** 提取阶段上限（ADR-0019：3~5s）。 */
        const val EXTRACTING_TIMEOUT_MS = 5000L
        /** 图片阶段总上限（ADR-0019：20~30s）。 */
        const val IMAGE_TOTAL_TIMEOUT_MS = 25000L
        /** 单张图片上限（ADR-0019：8~10s）。 */
        const val IMAGE_SINGLE_TIMEOUT_MS = 9000L
        /** DOM 探测间隔。 */
        const val PROBE_INTERVAL_MS = 400L
        /** 图片就绪轮询间隔。 */
        const val IMAGE_POLL_INTERVAL_MS = 250L
        /** 内容无变化软空闲超时（ADR-0019：约 5s）。 */
        const val IDLE_PROBE_TIMEOUT_MS = 5000L
        /** 最多尝试的图片候选数（ADR-0019）。 */
        const val MAX_IMAGE_CANDIDATES = 12
        /** 最多成功保存的配图数（与 IMPORT-006 一致）。 */
        const val MAX_COVER_IMAGES = 9
        /** 单张图片字节上限（与 OCR-002 一致，16MB）。 */
        const val MAX_IMAGE_BYTES = 16 * 1024 * 1024

        /** evaluateJavascript 返回值会被二次 JSON 编码，先解包为普通字符串。 */
        fun unescapeJsonString(raw: String?): String {
            if (raw == null) return ""
            val trimmed = raw.trim()
            if (trimmed.length >= 2 && trimmed.startsWith("\"") && trimmed.endsWith("\"")) {
                return try {
                    JSONObject("{\"v\":$trimmed}").optString("v", raw)
                } catch (_: Exception) {
                    raw
                }
            }
            return trimmed
        }

        val loginMarkers = listOf(
            "登录", "请先登录", "登录后查看", "登录后继续", "需要登录",
            "login", "sign in",
        )

        val verificationMarkers = listOf(
            "安全验证", "验证码", "滑动验证", "滑块", "拖动滑块",
            "captcha", "security verification", "请完成验证", "访问异常",
            "风险", "操作频繁",
        )

        val goneMarkers = listOf(
            "内容不存在", "内容已删除", "作品不存在", "笔记不存在",
            "笔记已删除", "内容已失效", "页面不存在", "page not found",
            "404",
        )

        /** 小红书 readiness 探测（Outline.utils：目标笔记 ID 一致性 + 命中笔记数据/DOM + 非受限页）。 */
        val PROBE_SCRIPT_XHS = """
            (function() {
              var d = document;
              var title = (d.title || '').trim();
              var bodyEl = d.body;
              var bodyText = bodyEl ? (bodyEl.innerText || '') : '';
              var text = title + ' ' + bodyText;
              var lower = text.toLowerCase();
              var risk = /安全验证|验证码|滑动验证|滑块|请完成验证|captcha|security verification|访问异常|风险|操作频繁/i.test(text);
              var login = /登录|请先登录|登录后查看|登录后继续|需要登录|sign in/i.test(text);
              var gone = /内容不存在|内容已删除|作品不存在|笔记不存在|页面不存在|page not found|404/i.test(text);
              var imgs = d.querySelectorAll('img').length;
              var hasState = !!(window.__INITIAL_STATE__);
              var m = location.href.match(/\/(explore|discovery\/item|item)\/([0-9a-zA-Z]{10,})/);
              var cur = m ? m[2] : '';
              var targetId = '__TARGET_ID__';
              var targetIdMatch = !!targetId && cur === targetId;
              var ready = false, reason = '';
              if (!risk && !login && !gone) {
                if (hasState) { ready = true; reason = 'noteState'; }
                else if (title.length > 0 && bodyText.length > 0) { ready = true; reason = 'noteDom'; }
              }
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              var fp = h(title) + '-' + h(bodyText.slice(0, 2000)) + '-' + imgs;
              return JSON.stringify({
                url: location.href, readyState: d.readyState,
                titleLen: title.length, bodyLen: bodyText.length, imgCount: imgs,
                risk: risk, login: login, gone: gone,
                ready: ready, readyReason: reason, fingerprint: fp,
                targetIdMatch: targetIdMatch, curId: cur
              });
            })()
        """.trimIndent()

        /** 抖音 readiness 探测：命中 __RENDER_DATA__/RENDER_DATA 或有效正文 DOM，且非 App 拉起/登录/风控页。 */
        val PROBE_SCRIPT_DOUYIN = """
            (function() {
              var d = document;
              var title = (d.title || '').trim();
              var bodyEl = d.body;
              var bodyText = bodyEl ? (bodyEl.innerText || '') : '';
              var text = title + ' ' + bodyText;
              var lower = text.toLowerCase();
              var risk = /验证码|captcha|安全验证|滑动验证|滑块|请完成验证|访问频繁|操作频繁|风险/i.test(text);
              var login = /登录|请先登录|login|sign in/i.test(text);
              var gone = /内容不存在|作品不存在|视频不存在|页面不存在|page not found|404/i.test(text);
              var imgs = d.querySelectorAll('img').length;
              var rd = window.__RENDER_DATA__ || window.RENDER_DATA || '';
              var hasData = typeof rd === 'string' && rd.length > 200;
              var m = location.href.match(/\/(video|note)\/([0-9]{10,})/);
              var cur = m ? m[2] : '';
              var targetId = '__TARGET_ID__';
              var targetIdMatch = !!targetId && cur === targetId;
              var ready = false, reason = '';
              if (!risk && !login && !gone) {
                if (hasData) { ready = true; reason = 'renderData'; }
                else if (title.length > 0 && bodyText.length > 0) { ready = true; reason = 'pageDom'; }
              }
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              var fp = h(title) + '-' + h(bodyText.slice(0, 2000)) + '-' + imgs;
              return JSON.stringify({
                url: location.href, readyState: d.readyState,
                titleLen: title.length, bodyLen: bodyText.length, imgCount: imgs,
                risk: risk, login: login, gone: gone,
                ready: ready, readyReason: reason, fingerprint: fp,
                targetIdMatch: targetIdMatch, curId: cur
              });
            })()
        """.trimIndent()

        /** 通用网页 readiness：主正文候选 / JSON-LD / 正文达标，区分导航与登录/验证/错误。 */
        val PROBE_SCRIPT_GENERIC = """
            (function() {
              var d = document;
              var title = (d.title || '').trim();
              var bodyEl = d.body;
              var bodyText = bodyEl ? (bodyEl.innerText || '') : '';
              var text = title + ' ' + bodyText;
              var lower = text.toLowerCase();
              var risk = /验证码|captcha|安全验证|滑动验证|滑块|请完成验证|访问异常/i.test(text);
              var login = /登录|请先登录|login|sign in/i.test(text);
              var gone = /内容不存在|页面不存在|page not found|404/i.test(text);
              var imgs = d.querySelectorAll('img').length;
              var jsonld = document.querySelector('script[type="application/ld+json"]');
              var hasJsonld = !!jsonld;
              var main = document.querySelector('article, main, [role="main"], .article, .post, .content');
              var mainLen = main ? (main.innerText || '').length : 0;
              var ready = false, reason = '';
              if (!risk && !login && !gone) {
                if (mainLen >= 200) { ready = true; reason = 'mainArticle'; }
                else if (hasJsonld && (title.length > 0 || bodyText.length > 0)) { ready = true; reason = 'jsonld'; }
                else if (title.length >= 4 && bodyText.length >= 200) { ready = true; reason = 'pageDom'; }
              }
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              var fp = h(title) + '-' + h(bodyText.slice(0, 2000)) + '-' + imgs;
              return JSON.stringify({
                url: location.href, readyState: d.readyState,
                titleLen: title.length, bodyLen: bodyText.length, mainLen: mainLen, imgCount: imgs,
                hasJsonld: hasJsonld, risk: risk, login: login, gone: gone,
                ready: ready, readyReason: reason, fingerprint: fp
              });
            })()
        """.trimIndent()

        /** 图片文档就绪检测：<img> complete 且 naturalWidth>0，并确认是图片文档。 */
        val IMAGE_READY_SCRIPT = """
            (function() {
              var img = document.querySelector('img');
              var contentType = (document.contentType || '');
              return JSON.stringify({
                ready: !!img && img.complete && (img.naturalWidth > 0 || img.naturalHeight > 0),
                w: img ? (img.naturalWidth || 0) : 0,
                h: img ? (img.naturalHeight || 0) : 0,
                readyState: document.readyState,
                isImage: contentType.indexOf('image/') === 0
              });
            })()
        """.trimIndent()

        /**
         * 路径 A：图片成为顶层文档后与自身 URL 同源，同源 fetch(location.href)
         * 不应再被 CORS 阻止；ArrayBuffer 分块转 base64，避免大字符串拼接爆栈。
         */
        val FETCH_IMAGE_SCRIPT = """
            (function() {
              function bytesToBase64(bytes) {
                var CHUNK = 0x8000;
                var bin = '';
                for (var i = 0; i < bytes.length; i += CHUNK) {
                  bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
                }
                return btoa(bin);
              }
              return fetch(location.href).then(function(r) {
                if (!r.ok) return JSON.stringify({ ok: false, error: 'status-' + r.status });
                return r.arrayBuffer().then(function(buf) {
                  var bytes = new Uint8Array(buf);
                  if (bytes.length <= 0 || bytes.length > 16777216) {
                    return JSON.stringify({ ok: false, error: 'size-' + bytes.length });
                  }
                  return JSON.stringify({ ok: true, mime: (r.headers.get('content-type') || ''), data: bytesToBase64(bytes) });
                });
              }).catch(function(e) {
                return JSON.stringify({ ok: false, error: 'fetch-error' });
              });
            })()
        """.trimIndent()

        /**
         * 路径 B：Canvas 绘制图片文档中的 <img> 后导出（顶层同源文档不应被跨域
         * 污染）；长边限制 2560px 避免大图内存爆炸。
         */
        val CANVAS_IMAGE_SCRIPT = """
            (function() {
              try {
                var img = document.querySelector('img');
                if (!img) return JSON.stringify({ ok: false, error: 'no-img' });
                var c = document.createElement('canvas');
                var max = 2560;
                var w = img.naturalWidth || img.width || 0;
                var h = img.naturalHeight || img.height || 0;
                if (w <= 0 || h <= 0) return JSON.stringify({ ok: false, error: 'no-size' });
                var scale = Math.min(1, max / Math.max(w, h));
                c.width = Math.max(1, Math.round(w * scale));
                c.height = Math.max(1, Math.round(h * scale));
                var ctx = c.getContext('2d');
                ctx.drawImage(img, 0, 0, c.width, c.height);
                var data = c.toDataURL('image/webp', 0.9);
                return JSON.stringify({ ok: true, mime: 'image/webp', data: data });
              } catch (e) {
                return JSON.stringify({ ok: false, error: String(e) });
              }
            })()
        """.trimIndent()

        // 小红书专用：递归定位包含 title + imageList 的笔记对象（兼容 PC 正常页
        // noteData 路径与无登录分享页结构），图片优先取 urlDefault，回退 infoList/
        // urlList；缺失时回退页面正文选择器。避免抓取导航/推荐/头像等无关图片。
        val EXTRACT_SCRIPT_XHS = """
            (function() {
              var result = { title: '', description: '', authorName: '', bodyText: '', imageUrls: [], url: (location.href || '') };
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              function isObj(v) { return v !== null && typeof v === 'object'; }
              function findNote(node, depth) {
                if (!isObj(node) || depth > 12) return null;
                if (node.title && node.imageList && Array.isArray(node.imageList) && node.imageList.length) return node;
                var keys = Object.keys(node);
                for (var i = 0; i < keys.length; i++) {
                  var child = node[keys[i]];
                  if (!isObj(child)) continue;
                  var found = findNote(child, depth + 1);
                  if (found) return found;
                }
                return null;
              }
              function pickImage(item) {
                if (typeof item === 'string') return item;
                if (!isObj(item)) return '';
                var keys = ['urlDefault', 'masterUrl', 'url', 'urlPre', 'thumbnailUrl'];
                for (var i = 0; i < keys.length; i++) {
                  var v = item[keys[i]];
                  if (typeof v === 'string' && v) return v;
                }
                if (Array.isArray(item.infoList) && item.infoList.length) {
                  var info = item.infoList[0];
                  if (info && typeof info.url === 'string' && info.url) return info.url;
                }
                if (Array.isArray(item.urlList) && item.urlList.length) return pickImage(item.urlList[0]);
                return '';
              }
              try {
                var state = window.__INITIAL_STATE__;
                if (state) {
                  var note = findNote(state, 0);
                  if (note) {
                    if (note.title) result.title = String(note.title).trim();
                    if (note.desc) result.description = String(note.desc).trim();
                    var user = note.user || {};
                    if (user.nickName) result.authorName = String(user.nickName).trim();
                    if (note.interactInfo && note.interactInfo.xxUserInfo && note.interactInfo.xxUserInfo.nickName) {
                      result.authorName = result.authorName || String(note.interactInfo.xxUserInfo.nickName).trim();
                    }
                    var list = note.imageList;
                    var seen = {};
                    for (var i = 0; i < list.length && result.imageUrls.length < 30; i++) {
                      var u = pickImage(list[i]);
                      if (u && u.indexOf('data:') !== 0 && !seen[u]) { seen[u] = 1; result.imageUrls.push(u); }
                    }
                  }
                }
              } catch (e) {}
              if (!result.title) {
                var t = document.querySelector('h1') || document.querySelector('.title') || document.querySelector('#detail-title');
                if (t) result.title = (t.innerText || '').trim();
              }
              if (!result.description) {
                var d = document.querySelector('#detail-desc') || document.querySelector('.desc') || document.querySelector('.note-text') || document.querySelector('.content') || document.querySelector('.note-content');
                if (d) result.description = (d.innerText || '').trim();
              }
              if (!result.imageUrls.length) {
                var nodes = document.querySelectorAll('.swiper-slide img, .carousel img, .note-content img, .slide img, #img-container img, [class*="carousel"] img, [class*="image-list"] img, [class*="swiper"] img');
                var seen = {};
                for (var i = 0; i < nodes.length && result.imageUrls.length < 30; i++) {
                  var src = nodes[i].currentSrc || nodes[i].src || '';
                  if (src && src.indexOf('data:') !== 0 && !seen[src]) { seen[src] = 1; result.imageUrls.push(src); }
                }
              }
              var body = (result.bodyText || result.description || '').replace(/[ \t]+/g, ' ').trim();
              if (body.length > 60000) body = body.substring(0, 60000);
              return JSON.stringify({
                title: result.title,
                description: result.description,
                authorName: result.authorName,
                bodyText: body,
                imageUrls: result.imageUrls,
                url: result.url,
                fingerprint: h(result.title) + '-' + h(body.slice(0, 2000)) + '-' + result.imageUrls.length
              });
            })()
        """.trimIndent()

        /** 抖音特化提取：优先解析 __RENDER_DATA__/RENDER_DATA 中的标题/描述/封面，回退页面 DOM。 */
        val EXTRACT_SCRIPT_DOUYIN = """
            (function() {
              var result = { title: '', description: '', authorName: '', bodyText: '', imageUrls: [], url: (location.href || '') };
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              function metaContent(names) {
                for (var i = 0; i < names.length; i++) {
                  var el = document.querySelector('meta[name="' + names[i] + '"], meta[property="' + names[i] + '"]');
                  if (el && el.content) return el.content;
                }
                return '';
              }
              var rd = window.__RENDER_DATA__ || window.RENDER_DATA || '';
              if (typeof rd === 'string' && rd.length > 200) {
                try {
                  var json = JSON.parse(rd);
                  // 常见结构：json.load.json || json.videoInfoRes.item_list[0] || json.carouselData
                  var app = json.load && json.load.json ? JSON.parse(json.load.json) : json;
                  var item = null;
                  if (app.videoInfoRes && app.videoInfoRes.item_list && app.videoInfoRes.item_list.length) {
                    item = app.videoInfoRes.item_list[0];
                  } else if (app.awemeDetail) { item = app.awemeDetail; }
                  else if (app.aweme_list && app.aweme_list.length) { item = app.aweme_list[0]; }
                  if (item) {
                    if (item.desc) result.description = String(item.desc).trim();
                    if (item.title) result.title = String(item.title).trim();
                    if (item.author && item.author.nickname) result.authorName = String(item.author.nickname).trim();
                    var seen = {};
                    var collect = function(u) { if (u && typeof u === 'string' && u.indexOf('data:') !== 0 && !seen[u]) { seen[u] = 1; result.imageUrls.push(u); } };
                    if (item.images) { for (var i = 0; i < item.images.length; i++) collect(item.images[i].url_list && item.images[i].url_list[0]); }
                    if (item.video && item.video.cover && item.video.cover.url_list) { for (var j = 0; j < item.video.cover.url_list.length && result.imageUrls.length < 9; j++) collect(item.video.cover.url_list[j]); }
                    if (item.video && item.video.dynamic_cover && item.video.dynamic_cover.url_list) {
                      for (var k = 0; k < item.video.dynamic_cover.url_list.length && result.imageUrls.length < 9; k++) collect(item.video.dynamic_cover.url_list[k]);
                    }
                  }
                } catch (e) {}
              }
              if (!result.title) result.title = metaContent(['og:title', 'title']).trim() || (document.title || '').trim();
              if (!result.description) result.description = metaContent(['og:description', 'description']).trim();
              if (!result.imageUrls.length) {
                var seen2 = {};
                var nodes = document.querySelectorAll('img');
                for (var i = 0; i < nodes.length; i++) {
                  var src = nodes[i].currentSrc || nodes[i].src || '';
                  if (src && src.indexOf('data:') !== 0 && !seen2[src]) { seen2[src] = 1; result.imageUrls.push(src); if (result.imageUrls.length >= 30) break; }
                }
              }
              var body = (result.description || '').replace(/[ \t]+/g, ' ').trim();
              if (body.length > 60000) body = body.substring(0, 60000);
              return JSON.stringify({
                title: result.title,
                description: result.description,
                authorName: result.authorName,
                bodyText: body,
                imageUrls: result.imageUrls,
                url: (location.href || ''),
                fingerprint: h(result.title) + '-' + h(body.slice(0, 2000)) + '-' + result.imageUrls.length
              });
            })()
        """.trimIndent()

        // 通用网页：优先 JSON-LD Recipe/Article，其次主正文候选，最后整页文本 + 全部可见图片 + meta。
        val EXTRACT_SCRIPT_GENERIC = """
            (function() {
              function h(s) { var x = 0; for (var i = 0; i < s.length; i++) { x = (x * 31 + s.charCodeAt(i)) >>> 0; } return x.toString(16); }
              function metaContent(names) {
                for (var i = 0; i < names.length; i++) {
                  var el = document.querySelector('meta[name="' + names[i] + '"], meta[property="' + names[i] + '"]');
                  if (el && el.content) return el.content;
                }
                return '';
              }
              var title = (document.title || '').trim();
              var description = metaContent(['description', 'og:description']).trim();
              var authorName = metaContent(['author', 'og:author', 'article:author']).trim();
              var body = '';
              // JSON-LD Recipe/Article 优先（《解决方案.md》第二阶段）。
              var jsonld = document.querySelector('script[type="application/ld+json"]');
              if (jsonld && jsonld.text) {
                try {
                  var data = JSON.parse(jsonld.text);
                  var node = Array.isArray(data) ? data[0] : data;
                  var isRecipe = /Recipe/.test(node['@type'] || '');
                  var isArticle = /Article/.test(node['@type'] || '');
                  if (isRecipe || isArticle) {
                    if (node.headline) title = String(node.headline).trim();
                    else if (node.name) title = String(node.name).trim();
                    if (node.description) description = String(node.description).trim();
                    if (node.author && node.author.name) authorName = String(node.author.name).trim();
                    var parts = [];
                    if (node.recipeIngredient && Array.isArray(node.recipeIngredient)) parts.push('食材：' + node.recipeIngredient.join('；'));
                    if (node.recipeInstructions && Array.isArray(node.recipeInstructions)) {
                      var steps = [];
                      for (var i = 0; i < node.recipeInstructions.length; i++) {
                        var s = node.recipeInstructions[i];
                        steps.push((s.text || s.name || '') + '');
                      }
                      parts.push('做法：' + steps.join('。'));
                    }
                    if (node.articleBody) parts.push(String(node.articleBody));
                    body = parts.join(' ');
                  }
                } catch (e) {}
              }
              // 回退：主正文候选。
              if (!body) {
                var main = document.querySelector('article, main, [role="main"], .article, .post, .content');
                if (main) body = (main.innerText || '');
              }
              // 再回退：整页文本。
              if (!body) body = (document.body ? document.body.innerText : '') || '';
              body = body.replace(/\t|\n|\r/g, ' ').replace(/\s+/g, ' ').trim();
              if (body.length > 60000) body = body.substring(0, 60000);
              var seen = {};
              var imgs = [];
              var nodes = document.querySelectorAll('img');
              for (var i = 0; i < nodes.length; i++) {
                var src = nodes[i].currentSrc || nodes[i].src || '';
                if (src && src.indexOf('data:') !== 0 && !seen[src]) {
                  seen[src] = 1;
                  imgs.push(src);
                  if (imgs.length >= 30) break;
                }
              }
              return JSON.stringify({
                title: title,
                description: description,
                authorName: authorName,
                bodyText: body,
                imageUrls: imgs,
                url: (location.href || ''),
                fingerprint: h(title) + '-' + h(body.slice(0, 2000)) + '-' + imgs.length
              });
            })()
        """.trimIndent()
    }
}