# Sprint 00 — 技术可行性与工程边界

- 状态：进行中
- 启动日期：2026-07-27
- 结束日期：待技术验证完成后填写
- Sprint 目标：在创建完整业务代码前，验证 Flutter、本地 OCR 和自定义 LLM API 的关键可行性，并产出可执行架构决策。

## Sprint 成功标准

- Flutter 已确定，并通过最小原型或可复现实验验证关键能力。
- Flutter 能力基线和限制写入 Spike；不再进行 React Native 比选。
- 验证 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile 的 Android/iOS 可行性。
- 验证“协议 + API Base URL + 可空 Key + 模型”配置以及 OpenAI-compatible/Gemini Adapter 的兼容性。
- 确定代码目录、数据层、Provider 接口和插件 Manifest 第一版契约。

## 任务

| ID | 状态 | 产出 |
|---|---|---|
| SPK-001 | DOING | Flutter 关键能力实测报告；LLM Provider/Android 工程切片已通过 |
| SPK-002 | TODO | PaddleOCR 本地插件实验报告 |
| SPK-003 | TODO | 自定义 LLM API 多协议真实服务兼容性报告 |
| ARCH-001 | TODO | Flutter 正式工程骨架 |
| AI-001 | TODO | LLM Provider v1 契约 |
| OCR-001 | TODO | OCR Provider 与插件 Manifest v1 契约 |

## 已完成演示证据

- Flutter Android Debug APK 成功构建。
- Android 12 真机安装并启动。
- OpenAI-compatible/Gemini Adapter 的本地契约测试通过。
- `flutter analyze` 无问题，21 个测试全部通过。

证据：`tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`。

## Sprint 演示待完成

1. 从本地数据库写入并读取一个示例菜谱。
2. 测试一个真实 OpenAI-compatible、Gemini 或本地兼容 LLM API。
3. 对一张中文菜谱截图执行 OCR，或展示明确阻塞证据。
4. 展示系统分享 URL、后台任务、通知和安全存储真机流程。
5. 在 macOS/iPhone 环境补齐 iOS 验证。

## 不在本 Sprint 中

- 完整首页视觉设计。
- 完整小红书、抖音生产级解析。
- 云同步和账号服务。
- 商业化配额和支付。
