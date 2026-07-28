# 当前工作状态

> 本文件是项目当前状态的唯一事实源。每次开始工作必须读取，每次结束工作必须更新。
> 最后更新：2026-07-28

## 当前阶段

**Sprint 0：后端基础能力与核心导入链路建设**

UI 暂缓。当前优先完成 Domain、Application、Data 和 Provider，使后续 Flutter 页面只依赖稳定用例和契约开发。

## 当前主任务

下一后端任务待开始：`ASR-001`。先建立统一 ASR Provider、音视频转写证据和导入预处理契约，再复用已经完成的结构化菜谱生成 Processor。

## 已完成基线

- Flutter 跨平台工程、OpenAI-compatible 与 Gemini LLM Provider。
- API Base URL、可空 API Key、模型和协议配置；Key 使用系统安全存储。
- Local-first SQLite Schema v2、结构化菜谱 Repository 和 v1 → v2 迁移。
- `IMPORT-001`：持久化导入任务状态机、取消、重试、恢复和 SQLite 存储。
- `IMPORT-002`：统一导入内容模型与 JSON Schema、Adapter Registry、Runner、单执行器 Dispatcher、稳定错误映射和未知异常脱敏。
- `IMPORT-003`：受限 HTTP Transport、小红书/抖音公开内容 Adapter、HTML/Open Graph/JSON-LD 解析和人工粘贴/本地媒体降级。
- `AI-002`：受限 Prompt、严格 Schema 校验、Recipe 草稿持久化、取消提交点和真实 SQLite 重开验证。
- `OCR-001`：统一 OCR Provider、严格模型 Manifest、OCR 证据字段、导入预处理、稳定错误和 Runner 集成。
- Android Debug APK 已通过 ASCII Junction 构建，并在 Android 12 真机安装启动。
- 最近一次自动化验证：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 141 项测试通过。

## 当前实施边界

- 只处理无需登录即可访问的公开内容。
- 不实现登录绕过、验证码绕过、签名逆向、访问控制绕过或反爬规避。
- 平台要求登录、内容不可用或结构变化时，返回稳定错误并引导人工粘贴文本、选择本地图片或选择本地视频。
- UI 不直接访问 SQLite、HTTP Client 或供应商 SDK。
- API Key、Authorization Header、完整 Prompt、完整模型响应、完整 OCR 文本和本地原图路径不得写入日志或 Git。
- AI 输出必须经过 Schema 校验，并保留用户确认步骤，不直接覆盖已有菜谱。

## 下一步

1. 为 `ASR-001` 建立架构、API 契约和验收文档。
2. 定义 ASR Provider 输入、输出、取消、分段时间戳和稳定错误契约。
3. 实现音视频预处理器，将转写结果转换为 `ImportContent.textFragments` 并复用 `LlmRecipeGenerationProcessor`。
4. 覆盖跳过、无媒体、数量/时长限制、部分结果、取消、错误映射和 Runner 集成测试。
5. 保持 `SPK-002` 独立：Android/iOS PaddleOCR 原生桥接、模型下载和真机性能尚未开始。

## 暂停项

- UI/UX 页面实现暂缓，等待后端核心用例与契约稳定。
- `SPK-001` 其余能力暂缓：系统分享、后台任务、通知和安全存储真机验证。
- `SPK-002` PaddleOCR 原生桥接待后续真机验证。
- `SPK-003` 真实 OpenAI-compatible、Gemini 和本地兼容服务互操作待后续验证。
- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。

## 环境约束

- Windows Flutter 构建继续使用 ASCII Junction：`C:\tmp\ai-recipe-mobile`。
- 代码目录：`code/apps/mobile`。
- 验收记录：根目录 `tests/acceptance/`。
- 进度状态以本文件和 `tracking/BACKLOG.md` 为准。
