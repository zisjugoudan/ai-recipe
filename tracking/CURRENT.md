# 当前工作状态

> 本文件是项目当前状态的唯一事实源。每次开始工作必须读取，每次结束工作必须更新。  
> 最后更新：2026-07-28

## 当前阶段

**阶段：Sprint 0 技术验证进行中**

## 当前目标

继续执行 `SPK-001` Flutter 关键能力基线。统一自定义 LLM API 配置和 OpenAI-compatible/Gemini Provider 切片已经完成，下一步验证 Local-first 数据库、系统分享、后台任务、通知、安全存储真机流程和 OCR 桥接。

## 正在进行

`SPK-001` 保持 `DOING`。当前 Flutter 工程已经能够完成 Android Debug APK 构建和 Android 12 真机启动，但完整 Spike 验证矩阵尚未完成。

短期运维任务 OPS-003 正在执行：将本地 main 首次发布到 GitHub 仓库 zisjugoudan/ai-recipe；远程已确认是空仓库。

## 最近完成

- `OPS-001` 建立本地项目执行体系，验收通过。
- 用户确认移动端统一使用 Flutter，已记录 `ADR-0008`。
- 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile，已记录 `ADR-0009`。
- 用户更正 LLM 配置模型：不区分网络方案，统一填写协议、API Base URL、可空 Key 和模型；`ADR-0010` 已由 `ADR-0011` 取代。
- `OPS-002` 已初始化本地 Git 仓库，默认分支为 `main`；没有远程、提交或推送。
- `DOC-001` 已将 Flutter、OCR、自定义 LLM API 与 Git 状态同步到长期事实源。
- 已创建 `code/apps/mobile` Flutter 工程并实现：
  - OpenAI-compatible Chat Completions Adapter。
  - Gemini native `generateContent` Adapter。
  - 统一配置校验、超时、取消和错误映射。
  - API Key 与普通配置分离，Key 使用 `FlutterSecureStorage`。
  - LLM 设置、连接测试和保存页面。
- 已修正取消令牌分层：`LlmCancellationToken` 位于 Domain 层，不再反向依赖 Provider。
- `dart format lib test` 已完成。
- `flutter analyze` 通过：`No issues found`。
- `flutter test` 通过：21 个测试全部通过。
- Android Debug APK 已在纯 ASCII Junction 构建入口下成功构建；APK 位于 `code/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- Android 12 真机安装和启动通过，应用 PID 未发现错误级 Logcat。
- 验收记录：`tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`。

## 下一步

1. `SPK-001`：验证 SQLite 写入/读取示例 Recipe。
2. `SPK-001`：验证系统分享入口接收 URL。
3. `SPK-001`：验证后台任务、本地通知和安全存储真机写入/覆盖/删除。
4. `SPK-001` / `SPK-002`：建立 OCR Federated plugin / Platform Channel 最小桥接。
5. `SPK-003`：使用真实 OpenAI-compatible、Gemini 和本地兼容服务验证协议兼容性与结构化输出。
6. 在 macOS/iPhone 环境补齐 iOS 构建、Keychain、本地网络权限和 OCR 插件验证。

## 当前阻塞与约束

- 当前 Windows 环境不能完成 iOS 构建和真机测试，需要后续 macOS/iPhone 环境。
- Windows Flutter shader compiler 无法直接在含中文的仓库路径输出 Android 构建产物；本轮通过纯 ASCII Junction 构建。正式 CI 前应迁移到纯 ASCII 路径或建立稳定构建入口。
- PaddleOCR 的模型转换、体积、速度、内存和真机准确率尚未验证。
- OpenAI-compatible 与 Gemini 当前通过可注入 Transport 的本地契约测试；真实 Key/服务兼容性留给 `SPK-003`。
- 真机安全存储写入和删除完整流程尚未验证。

## 当前有效文档

- 永久流程：`AGENTS.md`
- 产品需求：`docs/product/AI食谱应用产品需求文档.md`
- 用户故事：`docs/product/USER_STORIES.md`
- 移动端架构：`docs/architecture/MOBILE_ARCHITECTURE.md`
- OCR 方案：`docs/architecture/OCR_PLUGIN.md`
- LLM 自定义 API 与 Provider 适配：`docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`
- 当前 Sprint：`tracking/sprints/SPRINT-00.md`
- 技术探索：`tracking/SPIKES.md`
- 当前 Spike：`research/spikes/SPK-001-cross-platform-framework.md`
- 当前切片验收：`tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`

## 新会话交接说明

从这里继续时，不要重新比较 Flutter 与 React Native，不要恢复 LAN/VPN/HTTPS 产品模式，也不要重复初始化 Git。统一 LLM 配置固定为“协议 + API Base URL + 可空 Key + 模型”。按 `SPK-001` 剩余验证矩阵继续，所有真实实验数据必须写入 Spike 和验收记录。

