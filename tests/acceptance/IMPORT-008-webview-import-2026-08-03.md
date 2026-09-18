# IMPORT-008：链接导入改用浏览器内核（WebView）抓取网页文本与图片

> 日期：2026-08-03（ADR-0019 状态机重构版）
> 状态：`DOING`（代码已按 ADR-0019 重构，等待项目负责人构建与真机 Spike 复测；iOS 未验证）
> 平台：Android
> 关联：`ADR-0018`、`ADR-0019`、`SPK-007`、`IMPORT-006`、`IMPORT-007`、`BUG-003`

## 1. 用户价值

链接导入改用内置浏览器内核（Android WebView）加载网页，从 DOM 提取网页真实文本与图片，规避直连抓取遇到的 CDN 403、登录墙与平台风控；任意网页链接（小红书、抖音优先，其他平台零改造）均可尝试抓取。

## 2. 已实现

- **领域**：`ImportSourcePlatform` 新增 `web`；`ImportSourceLink.parse` 未知域名归为 `web`（不再抛不支持）。
- **Android 原生（ADR-0019 重构版）**：`WebViewFetchMethodHandler`（通道 `ai_recipe/webview_fetch`）按显式阶段状态机推进：
  - `NAVIGATING`（≤18s）→ 主框架提交（`onPageCommitVisible`，旧系统以 `onPageFinished` 兜底）；
  - `WAITING_CONTENT`（≤12s）→ 每 400ms 轻量 DOM 探测（标题/正文长度、图片候选、`__INITIAL_STATE__`、登录墙/风控特征），满足任一条件即进入提取；
  - `EXTRACTING`（≤5s）→ 注入平台提取脚本（小红书 `__INITIAL_STATE__` 递归 / 通用 DOM），成功后立即 `stopLoading()`；
  - `FETCHING_IMAGES`（总 ≤25s，单张 ≤9s）→ 逐张把图片 URL 作为 WebView 顶层页面打开，图片文档就绪后路径 A 同源 `fetch(location.href)` 读取原始字节，路径 B Canvas 导出兜底；每张独立超时、失败继续下一张、最多 12 候选、成功保存 ≤9 张、每张完成立即写盘。
  - 结果分类映射：`timeout`（导航超时）/`network`（含 SSL、渲染进程崩溃）/`loginRequired`/`verificationRequired`（403、验证码、风控）/`emptyContent`（内容不存在、无内容、提取失败）；正文成功时图片失败只影响配图数量，不整体失败。
  - 请求隔离：每次抓取递增 requestId，所有定时任务/回调核对当前阶段；取消/超时执行 `stopLoading()` + 清理全部 Handler + 终止图片队列。
- **WebView 配置**：默认系统移动 UA（不覆盖桌面 UA）+ 360×800 移动视口（attach 到 decorView 最底层被 Flutter 界面覆盖，用户不可见）；不在第三方页面暴露 `addJavascriptInterface`，页面脚本只用 `evaluateJavascript` 返回值。
- **Dart**：`WebViewContentFetcher`（MethodChannel 封装）+ `WebViewImportContentAdapter`（映射 `ImportContent`；**小红书/抖音平台不再回退远程直连**（ADR-0019，避免重复 403 与日志混淆），web 平台保留直连快速路径；错误分类中文映射）。
- **装配**：组合根为 xiaohongshu/douyin/web 注册 WebView Adapter，替换直连 Adapter；`importTransport` 参数移除。
- **UI**：导入进度页/确认页/详情页的平台标签与徽标支持 `web`。
- 测试定义已更新（未运行）：WebView Adapter 成功映射（web 回退）、**xiaohongshu 不回退直连**、平台/URL 拒绝、错误分类、空内容失败；`ImportSourceLink.parse` 未知域名归为 web。

## 3. 已知限制

- **顶层图片同源读取是否可行依赖 Android WebView 对图片文档的具体实现，必须先完成 SPK-007 真机 Spike，不能在验证前视为已解决**（ADR-0019）。若路径 A/B 均不可用，按 `修复方案.md` 决策分支：正文导入成功 + 提示手动补图，或评估服务端真实浏览器方案。
- 移动 UA 下小红书/抖音可能直接返回登录墙或风控页，此时按分类提示降级（粘贴正文/截图/手动录入）；默认匿名导入仅处理无需登录的公开内容（ADR-0019）。
- 图片字节仍经 OCR-002 本地直通校验（本地文件、魔数、宽高、大小）。
- 后台隐藏 WebView 挂载在 decorView 最底层（360×800，被 Flutter 界面覆盖），不展示给用户。
- 隐私设置"允许获取网页内容"授权联动（第二步）；本轮不采集、不存储 Cookie，不读取用户浏览器登录态。
- iOS（WKWebView）未实现；iOS 上 WebView Adapter 会返回"当前设备暂不支持浏览器内核抓取"，可改用粘贴正文降级。

## 4. Android 人工复测步骤（分阶段核对）

### 4.1 前置条件

1. 在项目根目录执行 `flutter run` 并选择真机（DBR W10）。
2. 在"自定义 LLM API"确认自有 AI 服务已配置且可连接。

### 4.2 阶段日志核对（小红书图文链接，核心）

抓取 Logcat 中 `WebViewFetch` 标签，按顺序核对（每条日志带 `req=<id> stage=<阶段> t=<秒>`）：

1. `fetchPage` → `onPageStarted` → `onPageCommitVisible` → `enter WAITING_CONTENT`；
2. `probe hasContent=... img=... risk=... login=...`（1 到若干轮）；
3. `enter EXTRACTING` → `extracted title=... bodyLen=... hasContent=true images=N`；
4. 每张图片：`fetch image idx=... host=... hash=...` → `image doc ready w=.. h=..` → `image saved via fetch`（路径 A）或 `via canvas`（路径 B）或失败原因；
5. `finish images saved=K`。

**回传要求**：完整复制第 3 步之后的日志（特别是每张图是 `via fetch`、`via canvas` 还是失败原因 `status-xxx`/`fetch-error`/`SecurityError`/`not-ready`/`single-timeout`），并说明正文是否进入草稿确认页。

### 4.3 验收原则（ADR-0019）

- **只要正文提取成功（`hasContent=true`），后续图片失败/超时/风控都只能产生"配图部分失败"结果，不得让整个导入变成"网页加载超时"。**
- 小红书配图全部失败时，确认页应正常进入、展示"配图暂未获取"，且 Logcat 不再出现 `[AIRecipe][RemoteImage] 403`（已不再回退直连）。

### 4.4 其余用例

1. 小红书图文链接：正文与配图提取、确认页展示、详情页轮播、强停重启后仍显示。
2. 抖音链接：正文与配图提取（若移动 UA 下不可用，记录分类提示）。
3. 普通网页链接（如 `https://example.com`）：正文提取 + 图片直连快速路径。
4. 需要登录的页面：提示"该页面需要登录后才能查看内容"，可使用粘贴正文降级。
5. 风控/验证码页面：提示"平台正在进行安全验证或限制访问"，可重试或降级。
6. 断网/超时：分别核对 `network`（页面加载失败）与 `timeout`（导航超时）中文提示，任务可重试。
7. 已失效链接：提示"该网页内容不存在或已删除"。

### 4.5 回传模板

```text
IMPORT-008 Android 真机复测（ADR-0019）

1. 小红书链接正文是否提取成功（hasContent=true）：
2. Logcat `WebViewFetch` 第 3 步之后日志（extracted / 每张图 fetch 结果 / finish images）：
3. 配图是否显示在确认页并随草稿保存（重启后仍显示）：
4. 抖音链接结果（正文/配图/分类提示）：
5. 普通网页链接结果（如 example.com）：
6. 登录墙/风控/断网/失效链接分别给出的提示：
7. 是否出现任何异常崩溃或英文错误：
8. 其他问题：
```

## 5. 验证边界

Codex 不执行自动测试、分析器、格式化、构建、模拟器、真机或真实网络/浏览器加载（`ADR-0015`）。本文件是项目负责人可直接执行的 Android 测试方法；实现代码与测试定义已完成，等待项目负责人构建与真机 Spike 复测反馈后归档（SPK-007 结论决定取图最终方案），iOS 未验证。
