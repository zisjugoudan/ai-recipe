# OCR Provider 与可下载模型插件架构

> 基础契约任务：`OCR-001`（已完成）
> 原生 Runtime 验证：`SPK-002`（DOING）
> 远程图片安全暂存：`OCR-002`（DONE）
> 本地首选：PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile

## 1. 目标

让本地 OCR 插件和云端 OCR Adapter 使用同一个领域契约，并以预处理方式接入导入流水线：

```text
ImportContent.media(image)
→ OcrProvider
→ OcrDocument / OcrTextBlock
→ ImportTextFragment（含置信度和媒体来源序号）
→ 新 ImportContent
→ LlmRecipeGenerationProcessor
```

OCR 只负责识别图片文字，不直接创建 Recipe，也不猜测食材、用量和步骤关系。

## 2. 本轮范围

- 定义 `OcrProvider`、图片输入、识别文档、文本块和稳定错误。
- 定义 PaddleOCR 模型包 Manifest、文件哈希、版本、平台和安装状态。
- 定义 OCR 导入预处理器，将识别结果补入统一 `ImportContent.textFragments`。
- 支持本地插件和云 API 共用输出，不把供应商类型泄漏给 UI。
- 扩展文本片段的可选 OCR 证据字段：`confidence`、`sourceMediaOrder`、`sourceProvider`。
- 覆盖跳过、空结果、部分结果、取消、错误映射和 Runner 进度集成测试。
- `SPK-002` 阶段扩展模型包下载/校验/激活/删除/恢复、同包进程内串行队列、Flutter MethodChannel、Android ONNX Runtime 健康检查与首阶段真实检测/识别推理。
- `OCR-002` 扩展远程 HTTPS 图片安全暂存，本地 OCR 在调用原生 Runtime 前获得受校验的应用私有临时文件。

## 3. 非目标

- `OCR-001` 不集成原生 Runtime；`SPK-002` 当前实现的是 Android 首阶段图片识别链路，不承诺真实 PP-OCRv5 模型兼容性、方向分类、复杂版面、性能或准确率。
- 本轮不实现具体云 OCR 供应商签名协议。
- 本轮不下载平台视频、抽帧或实现 ASR。
- 不允许 Manifest 下载脚本、动态库或可执行文件；首版只允许模型数据和词典。

## 4. Provider 契约

`OcrProvider` 每次识别一张图片，输入只允许：

- HTTPS 远程图片 URL；或
- 应用媒体库中的 `localAssetId`；
- 可选 MIME、宽高和稳定顺序。

输出 `OcrDocument`：

- `providerId`、`modelVersion`、`language`；
- 按阅读顺序排列的 `OcrTextBlock`；
- 每个文本块的 `text`、`confidence`、`readingOrder`；
- 可选页码和归一化四边形坐标；
- 本地计算的 `fullText` 和平均置信度。

Provider 不返回日志内容、原图路径、API Key 或供应商原始响应。

## 5. 稳定错误

| OcrProviderErrorKind | 导入任务错误 | 可重试 |
|---|---|---|
| `cancelled` | `cancelled` | 否 |
| `networkUnavailable` | `networkUnavailable` | 是 |
| `timeout` | `timeout` | 是 |
| `rateLimited` | `ocrFailed` | 是 |
| `unknown` | `ocrFailed` | 是 |
| `unavailable`、`modelNotInstalled`、`invalidInput`、`unauthorized`、`invalidResponse`、`inferenceFailed` | `ocrFailed` | 否 |

错误文案最长保留 240 字符并压缩空白，不记录供应商响应正文。

## 6. 导入预处理规则

- 没有 `requiresOcr` 时直接调用下游 Processor，不调用 OCR。
- 有 `requiresOcr` 但没有图片时返回 `ocrFailed`。
- 默认最多识别前 20 张图片，超出时保留 `partialContent`。
- 每张图片识别前检查取消，并通过同一取消令牌通知 Provider。
- 识别文本去空、去重后追加到 `textFragments`，顺序从现有最大 `order + 1` 开始。
- 每个 OCR 片段保留平均置信度、原媒体 `order` 和 Provider ID。
- 至少获得一个非空 OCR 片段后移除 `requiresOcr`；全部为空则返回 `ocrFailed`。
- 识别完成后只把新的 `ImportContent` 交给结构化菜谱 Processor，不改变 Recipe Schema。

## 7. 模型插件 Manifest

Manifest 是不可信输入，必须严格 Schema 校验。`schemaVersion: 1` 只保留安装、哈希校验和健康检查兼容，不包含真实推理参数；`schemaVersion: 2` 必须提供 `runtimeConfig`，Android `recognize` 只接受 v2。

v2 核心示例：

```json
{
  "schemaVersion": 2,
  "packageId": "paddleocr-ppocrv5-mobile-zh",
  "version": "1.0.0",
  "engine": "onnxruntime",
  "platforms": ["android"],
  "languages": ["zh-Hans", "en"],
  "minAppVersion": "0.1.0",
  "license": "Apache-2.0",
  "files": [
    {
      "role": "detector",
      "path": "models/detector.onnx",
      "downloadUrl": "https://models.example.invalid/ocr/detector.onnx",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "sizeBytes": 1
    },
    {
      "role": "recognizer",
      "path": "models/recognizer.onnx",
      "downloadUrl": "https://models.example.invalid/ocr/recognizer.onnx",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "sizeBytes": 1
    },
    {
      "role": "dictionary",
      "path": "models/dictionary.txt",
      "downloadUrl": "https://models.example.invalid/ocr/dictionary.txt",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "sizeBytes": 1
    }
  ],
  "runtimeConfig": {
    "type": "paddleocr-ppocrv5",
    "detector": {
      "modelRole": "detector",
      "tensor": {"inputName": null, "outputName": null},
      "resizeLongSide": 960,
      "normalization": {
        "scale": 0.00392156862745098,
        "mean": [0.485, 0.456, 0.406],
        "standardDeviation": [0.229, 0.224, 0.225],
        "colorOrder": "bgr"
      },
      "pixelThreshold": 0.3,
      "boxThreshold": 0.6,
      "maxCandidates": 1000,
      "unclipRatio": 1.5
    },
    "recognizer": {
      "modelRole": "recognizer",
      "dictionaryRole": "dictionary",
      "tensor": {"inputName": null, "outputName": null},
      "imageShape": [3, 48, 320],
      "normalization": {
        "scale": 0.00392156862745098,
        "mean": [0.5, 0.5, 0.5],
        "standardDeviation": [0.5, 0.5, 0.5],
        "colorOrder": "bgr"
      },
      "blankIndex": 0,
      "useSpaceCharacter": false
    }
  }
}
```

约束：

- 版本使用语义化版本格式；下载地址必须是 HTTPS。
- 文件路径必须是包内相对路径，禁止绝对路径、反斜杠和 `..`。
- SHA-256 必须是 64 位十六进制字符串；文件大小必须大于 0，角色和路径不得重复。
- 文件角色和 Runtime 角色使用 `^[a-z][a-z0-9_-]*$`；平台和语言不能为空。
- `runtimeConfig.type` 当前只允许 `paddleocr-ppocrv5`。
- Detector 长边限制为 32–4096；概率阈值限制为 0–1；候选数限制为 1–10000；`unclipRatio` 必须大于 0 且不超过 10。
- Recognizer `imageShape` 必须为 `[3, 正整数, 正整数]`，`blankIndex >= 0`。
- 归一化数组固定三项，标准差必须大于 0；颜色顺序只允许 `bgr` 或 `rgb`。
- JSON Schema 负责字段和数值约束；Dart 与 Kotlin 应用层额外校验 Detector、Recognizer、Dictionary 角色都能引用 `files`，且三个角色不能冲突。
- 安装流程使用 `notInstalled → downloading → verifying → installed`；失败进入 `failed`。

完整机器可读契约：`docs/api/ocr-model-manifest.schema.json`。
## 8. 安装安全边界

```text
获取受信任 Manifest
→ 严格解析
→ 检查平台、App 版本与空间
→ 下载到临时目录
→ 校验大小和 SHA-256
→ 原子移动到版本目录
→ 健康检查
→ 激活版本
```

- Manifest 来源域名和模型文件域名使用白名单。
- 下载失败、哈希不符或健康检查失败时不激活，并保留上一可用版本。
- 临时文件在失败、取消或应用重启恢复时清理；同一服务实例内的同包安装、删除和恢复使用串行队列；跨 isolate、多服务实例、跨进程和 OS 文件锁级别互斥仍待实现。
- `active.json`、`state.json` 和安装后的 `manifest.json` 使用临时文件原子切换；Windows 目标覆盖失败时使用备份回退。
- 升级失败或取消时保留上一 active 版本与 `installedVersion`；active 包读取必须校验 Manifest 包 ID 和版本与指针一致。
- 安装取消通过 `OcrModelInstallCancellationToken` 显式触发；取消检查覆盖容量检查、下载 chunk、Manifest 写入、staging rename、health check 和 active 切换前。
- 下载前空间预检按 Manifest 模型总大小 + 64 MiB 安全余量计算；容量未知时跳过预检，容量不可用或空间不足使用稳定错误。
- 激活成功后默认保留 active + 1 个最新 inactive 版本；旧版本回收为 best-effort，不得让已激活版本失败。
- `active.json` 写入成功是安装提交点；提交点后的状态写入或观察者回调异常不得删除已激活模型。
- 模型包不得包含脚本、动态库或可执行文件。

## 9. 本地与云端边界

### 本地 PaddleOCR

- 默认不上传图片。
- Android 原生插件当前只接收应用私有目录文件或 `content://` URI，以及已安装模型版本；不直接访问远程 URL。
- 远程 HTTPS 图片由 `RemoteStagingOcrProvider` 在 Dart 层暂存为应用私有临时文件，再交给本地 OCR；已有 `localAssetId` 直接透传，云 OCR 不经过该暂存层。
- 模型下载、状态管理与推理解耦。

#### OCR-002 远程图片安全暂存边界

1. URL 只允许 HTTPS，拒绝 userinfo、fragment、控制字符和缺失主机。
2. 每一跳先解析 DNS，要求全部结果均为公网 IPv4/IPv6；任一环回、私网、link-local、CGNAT、文档或保留地址都会让该跳失败。
3. Socket 连接固定到已经验证的 IP，HTTP Host、TLS SNI 和证书校验仍使用原始域名，避免校验后重新解析造成 DNS rebinding。
4. 只跟随 301、302、303、307、308，并在每个目标上重新执行完整 URL 与 DNS 校验；限制重定向次数。
5. 只解析 HTTP/1.0 与 HTTP/1.1，限制响应头大小，拒绝重复敏感 Header、冲突的 Content-Length/Transfer-Encoding 和不支持的传输编码。
6. 响应体支持 Content-Length、chunked 和 connection-close；连接、TLS、响应阶段和总操作均有超时，取消会销毁活动连接。
7. 只接受 `image/jpeg`、`image/png`、`image/webp`，并复核 magic bytes、下载字节数、图片边长和总像素。
8. 临时文件在成功使用、下载失败、图片校验失败、Provider 失败和取消后清理；外部错误信息不得包含 URL、主机、IP 或本地路径。

该层解决“公开 Adapter 返回远程 URL，而原生 OCR 只接收本地来源”的工程边界。当前自动化测试使用可控 DNS/连接，不代表真实小红书/抖音图片端到端链路、平台防盗链或真机网络行为已经验收。

### 云端 OCR

- 使用独立 Provider Adapter；配置、Key 与普通设置分离。
- 调用前由产品层明确提示图片会上传到哪个 Provider。
- Key 只存 Keychain/Keystore，不写 SQLite、日志、备份或同步。
- Transport 必须使用 HTTPS，不允许忽略 TLS 错误。

## 10. SPK-002 必测矩阵

| 指标 | Android | iOS |
|---|---:|---:|
| 模型压缩下载体积 | 待测 | 待测 |
| 首次模型加载耗时 | 待测 | 待测 |
| 单张 1080p 图片耗时 | 待测 | 待测 |
| 峰值内存 | 待测 | 待测 |
| 中文字符准确率 | 待测 | 待测 |
| 食材行阅读顺序正确率 | 待测 | 待测 |
| 竖排、倾斜、低清晰度表现 | 待测 | 待测 |
| 取消、低内存和模型损坏处理 | 待测 | 待测 |

Windows 只验证纯 Dart 契约与流水线；Android/iOS 原生桥接、模型安装和性能必须在真机完成。

## 11. Flutter 原生桥接契约

MethodChannel 名称固定为：

```text
ai_recipe/local_ocr
```

| 方法 | 输入 | 输出 | 当前状态 |
|---|---|---|---|
| `probe` | 无 | `runtimeAvailable`、`recognitionSupported`、可选 `runtimeVersion` | Android 已实现 |
| `healthCheck` | 模型目录与严格 Manifest | 成功返回空；失败返回稳定平台错误 | Android 已实现 |
| `recognize` | 模型目录、Manifest v2 和图片输入 | `OcrDocument` JSON | Android 已实现首阶段检测、裁剪、识别和 CTC 解码 |
| `getAvailableStorageBytes` | 模型包目录 | 可用字节数 | Android 已实现基础查询 |

Dart 侧 `PlatformOcrRuntimeBridge` 负责：

- 校验 `probe` 响应类型。
- 传递模型目录、Manifest 和图片输入。
- 严格解析 OCR 文档、文本块、坐标和置信度。
- 将平台错误转换为稳定 `OcrProviderErrorKind`，不暴露原生堆栈或供应商响应。

## 12. Android ONNX Runtime 阶段实现

Android 依赖：

```text
com.microsoft.onnxruntime:onnxruntime-android:1.20.0
```

当前原生实现：

1. `probe` 获取 `OrtEnvironment`；Runtime 可加载时同时返回 `runtimeAvailable: true` 与 `recognitionSupported: true`。
2. `healthCheck` 校验模型目录和包内相对路径，对 Manifest 中每个 `.onnx` 文件创建 `OrtSession`，并要求至少一个输入和输出。
3. `recognize` 严格解析 Manifest v2 Runtime 契约，缓存 Detector/Recognizer Session 和 UTF-8 词典。
4. 图片输入只允许应用私有目录文件或 `content://` URI；解码前检查来源边界，解码后限制尺寸和像素量。
5. Detector 执行缩放、归一化、NCHW Tensor 和 ONNX 推理；当前后处理采用阈值概率图连通域与轴对齐矩形。
6. Recognizer 对候选区域裁剪、缩放和 ONNX 推理，使用词典进行 CTC 去重/去 blank 解码，并输出文本、平均置信度和阅读顺序。
7. 路径、输入、模型、图片解码、ONNX 推理和响应失败使用稳定且脱敏的错误码。

当前实现已打通 Flutter → Android → ONNX Runtime 的首阶段真实推理代码路径，但检测后处理不是完整 Paddle DB contour/min-area-rect，未实现方向分类器，对旋转文字、倾斜文本和复杂排版的效果可能较差。尚未使用真实 PP-OCRv5 mobile 模型和 Android 真机样本证明模型兼容性、准确率、耗时或内存，因此不能视为最终可用结论。

## 13. Application 与组合根

- `LocalOcrModelUseCases` 暴露状态查询、安装、删除和中断恢复，安装入口可传入取消令牌。
- `AiRecipeBackendFacade` 暴露模型管理入口，并将模型包异常映射为稳定后端错误。
- 设备组合根装配模型下载客户端、`DeviceOcrModelPackageService`、`PlatformOcrRuntimeBridge`、`PlatformOcrStorageCapacityProvider` 和 `PlatformOcrProvider`；默认及注入的本地 OCR Builder 都会经过 `RemoteStagingOcrProvider`，暂存器可注入测试替身。
- 本地 OCR Provider 只有在 active 模型存在且原生探测明确报告支持真实识别时才可进入导入执行计划。

## 14. 自动化验证

2026-07-28 从 Windows ASCII Junction `C:\tmp\ai-recipe-mobile` 执行：

```text
dart --suppress-analytics format lib test：118 个文件，0 个变化
flutter --suppress-analytics analyze --no-pub：No issues found
flutter --suppress-analytics test --no-pub：259 项全部通过
flutter --suppress-analytics build apk --debug：成功
```

2026-07-29 完成 Android 首阶段识别与 OCR-002 后重新验证：

```text
dart format --output=none --set-exit-if-changed lib test：130 个文件，0 个变化
dart analyze：No issues found
flutter analyze --no-pub：No issues found
flutter test --no-pub：307 项全部通过
Android :app:testDebugUnitTest --rerun-tasks：BUILD SUCCESSFUL
```

新增测试覆盖：

- 模型包 Manifest、下载、哈希、安装、激活、删除、失败回滚和恢复。
- 同包并发安装只下载一次，失败后的后续安装可继续，删除和恢复会等待同包安装结束。
- 升级失败时保留上一 active 和 `installedVersion`。
- 成功升级后清理 `.tmp-*` 与 `.bak-*`。
- active Manifest 包 ID 或版本不一致时拒绝返回可用包。
- MethodChannel 参数、响应解析、稳定错误和 `PlatformOcrProvider` 行为。
- Facade 模型管理错误映射与设备组合根能力探测。
- 安装显式取消、下载 chunk 取消检查、staging 清理、升级取消保留上一 active。
- Android 空间预检、容量未知时继续安装、容量不可用/空间不足稳定错误映射。
- 默认 active + 1 inactive 回收、`retainedInactiveVersions: 0` 回收策略和配置参数校验。
- 激活提交点保护：最终状态写入或回调失败不删除已激活包。
- 远程图片 URL 与公网地址策略、DNS 混合结果、逐跳重定向、固定地址连接、Content-Length/chunked、响应 framing、响应头限制、取消销毁连接和错误脱敏。
- JPEG/PNG/WebP 的 MIME + magic bytes、字节/边长/像素限制，以及成功、失败和取消后的暂存文件清理。
- 本地图片透传、远程图片暂存包装和设备组合根接入。

### 未验收

- Android 首阶段 `recognize` 已实现，但完整 Paddle DB 后处理、方向分类器、旋转/倾斜文本和复杂版面仍未验收。
- 真实 PP-OCRv5 mobile 模型、转换参数、词典与许可证证据。
- Android 真机体积、加载耗时、1080p 单图耗时、峰值内存和准确率。
- iOS Runtime、构建和真机验证。
- 跨 isolate、多服务实例、跨进程和 OS 文件锁级别同包互斥。
- iOS Runtime、iOS 容量查询、iOS 安装取消和 iOS 旧版本回收验证。
- Manifest 签名、固定公钥、可信索引或其他可信发布机制。

阶段验收记录：`tests/acceptance/SPK-002-local-ocr-runtime-slice-2026-07-28.md`、`tests/acceptance/SPK-002-android-real-ocr-runtime-2026-07-29.md`、`tests/acceptance/OCR-002-secure-remote-image-staging-2026-07-29.md`。`OCR-002` 已完成，`SPK-002` 继续保持 `DOING`。
