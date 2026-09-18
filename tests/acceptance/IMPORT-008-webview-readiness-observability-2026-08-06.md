# IMPORT-008 WebView 内容就绪与平台提取 + 可观测性验收方法

> 对应：《解决方案.md》第二、第三阶段；ADR-0033；并入 IMPORT-008。
>
> 创建：2026-08-06　状态：VERIFY（等待项目负责人 Android 真机执行）

## 一、任务目标

验证第二阶段（内容就绪与平台提取）与第三阶段（可观测性）：

1. **平台 readiness**：小红书/抖音/通用页面按平台规则判定"目标内容已就绪"，
   减少壳页/登录/验证/删除/App 拉起页被当正文。
2. **平台提取**：抖音特化提取（`__RENDER_DATA__`）、通用 JSON-LD Recipe/Article
   优先、小红书 note 提取。
3. **ResultValidator**：登录墙/验证/已删除/访问受限正确分类。
4. **正文与图片彻底解耦**：图片阶段 SSL / renderer gone 不使正文成功变整单失败。
5. **可观测性**：请求结束输出 `OBS ...` 汇总日志，字段完整可解释。

## 二、前置条件

- Android 模拟器或真机（Debug 构建）。
- 识图多模态 LLM 与菜谱生成 LLM 已配置（走完整导入流水线）。
- 真实样本：小红书图文链接、抖音视频链接、带 JSON-LD 的菜谱网页（如美食博客）、
  普通网页、已删除/登录墙/验证码页面各一。
- `adb logcat -s WebViewFetch` 可查看日志。

## 三、测试方法（逐项执行并回传结果）

### 1. 平台 readiness 命中

1. 分别导入小红书图文、抖音视频、普通菜谱网页。
2. 观察 `probe` 日志与 `OBS` 日志的 `readiness=` 字段。
3. 预期：小红书命中 `noteState`/`noteDom`；抖音命中 `renderData`/`pageDom`；
   通用命中 `mainArticle`/`jsonld`/`pageDom`；且不再把"加载中/导航栏/登录提示"
   判为就绪。
4. 记录：各平台 `readiness=` 命中理由；是否误判壳页。

### 2. 抖音特化提取

1. 导入一条抖音视频链接。
2. 预期：`OBS` 或 `extracted` 日志显示标题/描述来自 `__RENDER_DATA__` 解析
   （非仅整页文本）；能提取视频封面图。
3. 记录：标题/描述/封面来源；封面成功数。

### 3. 通用 JSON-LD

1. 导入一个含 `application/ld+json` Recipe/Article 的菜谱网页。
2. 预期：标题/描述/食材/做法来自 JSON-LD（`extracted` 日志）；正文含
   "食材："或"做法："。
3. 记录：是否命中 JSON-LD；正文结构。

### 4. 登录墙/验证/已删除分类

1. 分别导入登录墙、验证码、已删除内容的链接。
2. 预期：分别得到 `loginWall`/`verification`/`gone` 分类；`OBS` 的
   `readiness=` 或 `final=` 反映该分类；用户提示文案正确。
3. 记录：每个场景的最终错误分类与提示。

### 5. 图片阶段 SSL/renderer gone 不整单失败

1. 正文成功、图片阶段触发 SSL 错误或 renderer gone。
2. 预期：正文仍返回成功，仅配图数量偏少；`OBS` 中 `final=ok`，
   `imgFail` 与 `imgFailReasons` 记录原因；不出现"网页加载失败"。
3. 记录：正文是否成功；`imgFail`/`final` 值。

### 6. OBS 汇总日志字段

1. 任意一次正常导入，抓取 `OBS` 日志行。
2. 核对字段：`req`/`platform`/`stage=..ms`/`redirect`/`http`/`readiness`/
   `fp`/`bodyLen`/`imgAttempt`/`imgOk`/`imgFail`/`imgFailReasons`/
   `rendererGone`/`final`/`totalMs`。
3. 预期：字段齐全、`totalMs` ≤ 配置 timeoutMs；`http` 在有 HTTP 错误时非空。
4. 记录：一条完整 `OBS` 日志。

### 7. 回归

1. 第一阶段能力回归：同一 URL 多次导入稳定、取消记为 cancelled、
   renderer gone 后重试可恢复、普通网页导入正常。
2. 既有导入路径（单图/纯文本/OCR/自动路由）不回归。

## 四、结果回传模板

| 验收项 | 预期 | 实际结果（通过/失败/未执行） | 备注 |
|---|---|---|---|
| 各平台 readiness 正确命中 | 是 | | 记录 readiness 理由 |
| 抖音特化提取（renderData） | 是 | | |
| 通用 JSON-LD 优先 | 是 | | |
| 登录墙/验证/删除分类 | 是 | | 记录 final 分类 |
| 图片阶段 SSL/robust 不整单失败 | 是 | | |
| OBS 字段齐全、totalMs≤超时 | 是 | | 附一条 OBS 日志 |
| 第一阶段回归正常 | 是 | | |

- 设备/系统/网络：
- 构建版本：
- 截图/录屏/Logcat 路径：

## 五、Codex 说明

- Codex 已实施代码并完成静态复核（IDE 诊断无错误）。
- 按 ADR-0015，Codex 未执行自动测试、构建、模拟器或真机验收。
- 当前任务状态：并入 `IMPORT-008`（DOING/VERIFY）；项目负责人反馈结果后归档并
  决定进入 `DONE` 或返回 `DOING`。
- iOS（WKWebView）未验证。