# 当前工作状态

> 本文件是项目当前状态的唯一事实源。每次开始工作必须读取，每次结束工作必须更新。
> 最后更新：2026-07-28

## 当前阶段

**Sprint 0：后端基础能力与核心导入链路建设**

UI 暂缓。当前优先完成 Domain、Application、Data 和 Provider，使后续 Flutter 页面只依赖稳定用例和契约开发。

## 当前主任务

`IMPORT-003` 已完成。下一主任务待建立为 OCR/ASR 与 LLM 结构化菜谱 Processor，先定义 Provider/Processor 契约和可验证的文本输入最小链路，再接入本地 OCR 插件与媒体处理。

## 已完成基线

- Flutter 跨平台工程、OpenAI-compatible 与 Gemini LLM Provider。
- API Base URL、可空 API Key、模型和协议配置；Key 使用系统安全存储。
- Local-first SQLite Schema v2、结构化菜谱 Repository 和 v1 → v2 迁移。
- `IMPORT-001`：持久化导入任务状态机、取消、重试、恢复和 SQLite 存储。
- `IMPORT-002`：统一导入内容模型与 JSON Schema、Adapter Registry、Runner、单执行器 Dispatcher、稳定错误映射和未知异常脱敏。
- `IMPORT-003`：受限 HTTP Transport、小红书/抖音公开内容 Adapter、HTML/Open Graph/JSON-LD 解析和人工粘贴/本地媒体降级。
- Android Debug APK 已通过 ASCII Junction 构建，并在 Android 12 真机安装启动。
- 最近一次自动化验证：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 94 项测试通过。

## 当前实施边界

- 只处理无需登录即可访问的公开内容。
- 不实现登录绕过、验证码绕过、签名逆向、访问控制绕过或反爬规避。
- 平台要求登录、内容不可用或结构变化时，返回稳定错误并引导人工粘贴文本、选择本地图片或选择本地视频。
- UI 不直接访问 SQLite、HTTP Client 或供应商 SDK。
- API Key、Authorization Header、完整 Prompt 和完整模型响应不得写入日志或 Git。
- AI 输出必须经过 Schema 校验，并保留用户确认步骤，不直接覆盖已有菜谱。

## 下一步

1. 在 Backlog 建立 OCR/ASR 与 LLM 结构化菜谱 Processor 主任务并写明验收标准。
2. 定义 OCR、ASR、媒体解析和菜谱结构化生成的 Provider 契约及统一错误模型。
3. 先完成“已有文本 → LLM JSON → Schema 校验 → 菜谱草稿 Repository”的最小可运行链路。
4. 为缺字段、非法 JSON、部分结果、低置信度和取消/超时建立 Fixture 测试。
5. 再接入图片 OCR 与视频 ASR；PaddleOCR 原生桥接继续由 `SPK-002` 真实设备验证。

## 暂停项

- `SPK-001` 其余能力暂缓：系统分享、后台任务、通知和安全存储真机验证。
- `SPK-002` PaddleOCR 原生桥接待后续真机验证。
- `SPK-003` 真实 OpenAI-compatible、Gemini 和本地兼容服务互操作待后续验证。
- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。

## 环境约束

- Windows Flutter 构建继续使用 ASCII Junction：`C:\tmp\ai-recipe-mobile`。
- 代码目录：`code/apps/mobile`。
- 验收记录：根目录 `tests/acceptance/`。
- 进度状态以本文件和 `tracking/BACKLOG.md` 为准。
