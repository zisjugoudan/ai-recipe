# OCR-001 Provider 与插件 Manifest 验收记录

- 日期：2026-07-28
- 状态：通过
- 任务：`OCR-001`

## 验收范围

- [x] 本地插件与云 OCR 共享同一 `OcrProvider` 输入、输出和错误契约。
- [x] OCR 文本块包含阅读顺序、置信度和可选位置证据。
- [x] `ImportTextFragment` 可选保留 OCR 置信度、媒体顺序和 Provider ID。
- [x] 模型 Manifest 严格校验版本、平台、语言、HTTPS、相对路径、SHA-256、大小和重复项。
- [x] 模型安装状态与推理接口解耦。
- [x] 无 `requiresOcr` 时跳过 OCR。
- [x] 需要 OCR 时按媒体顺序识别并把文本补入 `ImportContent`。
- [x] 空结果、无图片、取消和 Provider 错误映射为稳定导入错误。
- [x] 识别成功后移除 `requiresOcr` 并复用下游结构化菜谱 Processor。
- [x] Runner 进度按 `extracting → ocr → generating → review` 前进。
- [x] 日志和错误不包含完整 OCR 文本、原图路径、Key 或供应商原始响应。

## 自动化验证

```text
dart format lib test：通过
flutter analyze --no-pub：No issues found
flutter test --no-pub：141 项全部通过
```

自动化测试覆盖 OCR 领域模型、Manifest 严格校验、安装状态、错误映射、取消传播、数量限制、部分结果、文本去重，以及 `extracting → ocr → generating → review` Runner 集成。

## 已知限制

- 本轮不包含 Android/iOS ONNX Runtime 原生桥接、真实模型下载、真实云 OCR 或准确率性能验证。
- Windows 环境不验证 iOS。
