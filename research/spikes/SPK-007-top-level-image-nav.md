# SPK-007：WebView 图片顶层导航 + 同源读取可行性

- ID：SPK-007
- 标题：图片作为 WebView 顶层文档后，能否用同源 fetch / Canvas 导出读取图片字节
- 状态：TODO（代码载体随 IMPORT-008 重构提供，真机验证待项目负责人执行）
- 日期：2026-08-03
- 关联风险：R-018
- 关联任务：IMPORT-008、ADR-0019

## 问题

小红书图片 CDN 拒绝客户端/应用网络栈（全部 403），必须由 WebView/Chromium 发起图片请求。当前页面内 JS 跨域 fetch 方案受 CORS、credentials×ACAO、页面 CSP 与混合内容限制而不可靠。

候选路线（ADR-0019）：把每张图片 URL 作为 WebView **顶层页面**逐张打开，图片文档与图片 URL 同源后，在图片所属来源环境中读取图片字节。

本 Spike 要回答：Android WebView 对顶层图片文档的具体实现是否支持——
1. 图片作为顶层文档加载并渲染（`<img>` `complete && naturalWidth>0`）；
2. 在该图片文档上下文中执行 `evaluateJavascript`（图片文档是否存在可执行的脚本上下文）；
3. 路径 A：同源 `fetch(location.href)` 能否返回图片字节（而非被 CORS/其他策略拦截）；
4. 路径 B：Canvas 绘制 + `toDataURL`/`toBlob` 导出是否抛出 SecurityError。

## 成功标准

- 对真实小红书图文链接，图片顶层导航后至少一条路径（同源 fetch 或 Canvas）能稳定导出原始或可解码图片字节；
- 单张导出耗时与内存可接受（单张上限 16MB、长边 ≤2560px）；
- 逐张串行、单张失败继续下一张、最多保存 9 张的策略可跑通；
- 正文提取成功时图片全部失败只产生"配图部分失败"，不整体失败。

## 非目标

- 不验证 `shouldInterceptRequest` 抓包方案（ADR-0019 已拒绝）。
- 不验证服务端浏览器方案、应用内登录、Cookie 复用。
- 不做 iOS（WKWebView）验证。

## 测试环境

- 真机（Android，华为 DBR-W10），`flutter run` Debug 构建。
- 至少 2–3 个不同 Android System WebView 版本（真机 + 模拟器 API 36 可选）。
- Wi-Fi 与移动网络各一轮。
- Logcat 抓取 `WebViewFetch` 标签（带 requestId 与阶段）。

## 样本与输入

- 10–20 个真实公开小红书图文链接（无需登录即可访问的分享链接/规范化样本）。
- 覆盖：单图、九图以上、带签名查询参数图片 URL、无登录/登录墙/风控页。

## 候选方案

- 路径 A：顶层导航图片 URL → 图片文档中同源 `fetch(location.href)` → ArrayBuffer → Base64 → 回传写盘。
- 路径 B：顶层导航图片 URL → 图片文档中 Canvas 绘制 `<img>` → `toDataURL('image/webp')` → 回传写盘（必要时限制长边 2048–2560px）。
- 兜底：两路径均失败时，正文照常成功，图片按"配图部分失败"处理并提示用户手动补图。

## 实验步骤

1. 项目负责人安装含 IMPORT-008 重构版本的 APK（移动 UA、360×800 视口、阶段状态机、逐张顶层导航取图）。
2. 粘贴小红书图文链接，抓取 Logcat `WebViewFetch` 日志，逐阶段核对：
   - `NAVIGATING` 提交与进入 `WAITING_CONTENT` 的耗时；
   - `EXTRACTING` 提取到的标题/正文/图片数量；
   - 每张图片：`fetch image [序号]`、图片文档就绪（`w/h`）、`image saved via fetch`（路径 A）或 `via canvas`（路径 B）或失败原因。
3. 对失败案例确认失败原因（`status-xxx` / `fetch-error` / `SecurityError` / `not-ready` / `single-timeout`）。
4. 记录 10–20 个链接中路径 A / 路径 B 的成功率与失败原因分布。
5. 若路径 A 全失败且路径 B 可用的概率较低，记录 WebView 版本差异。

## 结果数据

（项目负责人回传后填写）

- 样本数量与成功率：路径 A / 路径 B / 全部失败。
- 典型失败原因与对应样本。
- 单张导出耗时、内存（Logcat 内存指标，可选）。
- WebView 包名与版本、Android API 与设备型号。

## 失败与限制

- 若顶层图片文档中 JS 不可执行或同源 fetch/Canvas 均不可用：Spike 结论为"拒绝"该路线。
- 此时按 `修复方案.md` 决策分支：正文导入成功 + 图片提示用户手动补充；或评估服务端真实浏览器方案（成本、隐私、平台条款、稳定性单独评估）。

## 结论

（待验证后填写）采用 / 拒绝 / 继续研究

## 对产品、架构和排期的影响

- 决定 IMPORT-008 图片取图最终实现方式（WebView 会话取字节 vs 服务端浏览器 vs 提示手动补图）。
- 影响 IMORT-006 配图封面、IMPORT-007 图文 OCR 的依赖前提。
- 若拒绝顶层导航路线，需重新评估架构（可能引入服务端组件，需新 ADR 与成本评估）。

## 后续任务或 ADR

- Spike 成功后：逐张传输正式化（可选引入 `androidx.webkit` WebMessageListener 传输 ArrayBuffer、来源受限桥、nonce/大小限制）。
- Spike 失败后：评估服务端浏览器方案 ADR。
