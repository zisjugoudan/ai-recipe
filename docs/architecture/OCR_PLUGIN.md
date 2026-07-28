# OCR Provider 与可下载模型插件架构

> 任务：`OCR-001`
> 状态：已完成
> 本地首选：PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile
> 真机验证：`SPK-002`

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

## 3. 非目标

- 本轮不集成 Android/iOS ONNX Runtime，不下载真实模型，不承诺性能或准确率。
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

Manifest 是不可信输入，必须严格 Schema 校验。核心字段：

```json
{
  "schemaVersion": 1,
  "packageId": "paddleocr-ppocrv5-mobile-zh",
  "version": "1.0.0",
  "engine": "onnxruntime",
  "platforms": ["android", "ios"],
  "languages": ["zh-Hans", "en"],
  "minAppVersion": "0.1.0",
  "license": "Apache-2.0",
  "files": [
    {
      "role": "detector",
      "path": "det.onnx",
      "downloadUrl": "https://models.example.invalid/ocr/det.onnx",
      "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
      "sizeBytes": 1
    }
  ]
}
```

约束：

- 版本使用语义化版本格式。
- 下载地址必须是 HTTPS。
- 文件路径必须是包内相对路径，禁止绝对路径、反斜杠和 `..`。
- SHA-256 必须是 64 位十六进制字符串。
- 文件大小必须大于 0，角色和路径不得重复。
- 平台和语言不能为空。
- 安装流程使用 `notInstalled → downloading → verifying → installed`；失败进入 `failed`。

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
- 临时文件在失败、取消或应用重启恢复时清理。
- 模型包不得包含脚本、动态库或可执行文件。

## 9. 本地与云端边界

### 本地 PaddleOCR

- 默认不上传图片。
- 原生插件只接收应用可访问的本地媒体句柄和已安装模型版本。
- 模型下载、状态管理与推理解耦。

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

## 11. 自动化验证

纯 Dart Provider、Manifest、证据字段和导入预处理流水线已经完成并通过：

```text
dart format lib test：通过
flutter analyze --no-pub：No issues found
flutter test --no-pub：141 项全部通过
```

测试覆盖 OCR 输入输出模型、Manifest 严格校验、安装状态、稳定错误、取消、跳过、媒体排序、数量限制、部分结果、文本去重和 Runner 集成。Android/iOS ONNX Runtime 原生桥接、真实模型下载、云 OCR 供应商实现及真机性能指标仍属于 `SPK-002`，不在 `OCR-001` 完成范围内。
