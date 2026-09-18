# IMPORT-003 公开内容获取与人工降级

> 状态：v1 已实现并通过自动化验收
> 日期：2026-07-28
> 关联任务：`IMPORT-003`

## 1. 目标

在不依赖登录态、不绕过平台访问控制的前提下，为小红书和抖音公开分享链接建立可测试的内容获取能力，输出 `ImportContent`，并在自动获取不可用时提供结构化人工降级输入。

## 2. 范围

### 本轮实现

- 可注入的 `ImportHttpTransport`。
- GET 请求超时、取消、有限重定向、重定向目标校验、响应体大小限制和 Content-Type 白名单。
- 小红书与抖音已知公开域名白名单。
- HTML 公共元数据解析：`title`、description、Open Graph、JSON-LD、图片和公开视频引用。
- 平台公开内容 Adapter 和稳定错误映射。
- 人工粘贴文本、本地图片、本地视频三种降级输入。
- 固定 HTML Fixture 回归测试。

### 明确不做

- 不携带或复用用户浏览器 Cookie。
- 不模拟登录、不处理验证码、不逆向签名。
- 不绕过访问控制、反爬策略、地区限制或付费限制。
- 不承诺平台内部页面结构永久稳定。
- 不下载媒体字节；本轮只提取公开媒体引用，下载与缓存另立任务。

## 3. 分层

```text
Application / ImportTaskRunner
  -> Domain / ImportContentAdapterRegistry
    -> Provider / XiaohongshuPublicContentAdapter
    -> Provider / DouyinPublicContentAdapter
      -> Provider / ImportHttpTransport
        -> package:http streaming client
```

人工降级不伪装成平台抓取。`ImportFallbackContentFactory` 接收显式的用户输入，并生成同一 `ImportContent` 契约供后续 OCR、ASR 和 LLM Processor 使用。

## 4. HTTP 安全契约

### 请求限制

- 只允许 `http` 和 `https`。
- URI 不得包含用户名或密码。
- 初始地址和每次重定向的主机必须在当前平台白名单内。
- HTTPS 页面不得重定向降级到 HTTP。
- 默认超时 15 秒。
- 默认最多 4 次重定向。
- 默认响应体上限 2 MiB。
- 默认接受 `text/html`、`application/xhtml+xml`、`text/plain` 和 `application/json`。
- 使用流式读取；一旦超过声明或实际字节上限立即终止。

### 日志边界

Transport 和 Adapter 不记录：

- Cookie、Authorization、API Key。
- 完整响应正文。
- 页面内嵌用户数据。

异常只返回稳定错误类型和经过控制的固定消息。

## 5. 状态和错误映射

| 情况 | Adapter 错误 | 是否重试 |
|---|---|---:|
| 401 / 403 或明确登录页 | `authorizationRequired` | 否 |
| 404 / 410 或明确已删除页 | `contentUnavailable` | 否 |
| 请求超时 | `timeout` | 是 |
| Socket / Client 网络错误 | `networkUnavailable` | 是 |
| 429 / 5xx | `networkUnavailable` | 是 |
| 重定向越界、类型不支持、正文超限 | `invalidPayload` | 否 |
| 页面没有可用文本或媒体 | `invalidPayload` | 否 |
| 用户取消 | `cancelled` | 否 |

Runner 继续使用 IMPORT-002 的映射将 Adapter 错误写入持久化导入任务。

## 6. 公共元数据优先级

### 文本

1. Open Graph `og:title`、`og:description`。
2. JSON-LD `headline` / `name`、`description`、`caption`。
3. HTML `<title>` 和标准 description。

### 媒体

1. Open Graph `og:image`、`og:video` / `og:video:url`。
2. JSON-LD `image`、`thumbnailUrl`、`video.contentUrl`、`video.embedUrl`。
3. 相对 URL 以最终响应 URL 解析。

同一 URL 去重并保持首次出现顺序。`resolvedUrl` 记录最终公开页面地址；`source` 始终保留用户原始链接和规范化链接。

## 7. 内容警告

- 缺标题：`missingTitle`。
- 缺文本：`missingText`。
- 缺媒体：`missingMedia`。
- 文本或媒体任一缺失：`partialContent`。
- 有图片：`requiresOcr`，后续 Processor 可按策略决定是否执行。
- 有视频：`requiresAsr`。
- 最终地址与输入规范化地址不同：`redirected`。

## 8. 人工降级

| 输入 | 生成内容 | 后续阶段 |
|---|---|---|
| 粘贴正文 | `body` 文本片段 | LLM 整理 |
| 本地图片 | 本地 image 引用 | OCR → LLM |
| 本地视频 | 本地 video 引用 | ASR / 抽帧 OCR → LLM |

降级输入必须与原导入任务来源关联，不静默更换来源平台。空文本、空资产 ID、错误媒体类型在进入流水线前拒绝。

### 8.1 任务状态与恢复语义

- 人工降级复用原导入任务 ID、原始链接和来源平台，不创建无法审计的“无来源”任务。
- 失败或已取消任务接受人工降级后，直接从 `running/extracting` 进入统一 Processor，不再调用公开平台 Adapter。
- 人工降级不是 Adapter 自动重试，不受 `retryable`、`nextRetryAt` 或 `maxAttempts` 限制，也不增加 Adapter 的 `attempt`。
- 人工降级执行失败时不安排自动重试，避免后续调度器错误地改用公开链接 Adapter；用户可以重新提交正文或媒体。
- 正文和本地媒体选择属于敏感临时输入，首版不持久化其内容。应用在 Processor 完成前中断时，任务标记为 `interrupted` 且不可自动重试，要求用户重新选择降级输入。
- Runner 必须在改变任务状态前校验降级内容的来源平台和规范化 URL 与原任务一致。

### 8.2 当前 Flutter 切片能力边界

- 粘贴正文与手动创建为可运行路径。
- 截图和视频入口必须可见，但在媒体选择器尚未接入、OCR 路由不可用或 ASR Provider 不可用时，只显示真实能力说明和替代入口，不伪造处理成功。
- 后续接入媒体选择器时，页面仍只调用 Application/Facade；不得直接访问 OCR/ASR Provider、文件系统或密钥存储。

## 9. 测试策略

固定 Fixture 至少覆盖：

- 小红书公开图文元数据。
- 抖音公开视频元数据。
- JSON-LD 补充字段。
- 短链接重定向。
- 登录要求、内容删除、空载荷。
- 非白名单重定向、重定向过多、正文超限和不支持 Content-Type。
- 取消和网络/超时映射。
- 三种人工降级输入。

在线页面只作为后续人工兼容性抽样，不作为 CI 唯一依据。
