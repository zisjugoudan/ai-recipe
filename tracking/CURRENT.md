# 当前工作状态

> 更新时间：2026-07-28

## 当前阶段

后端核心契约与 Application 主链路已形成稳定基线，UI 继续暂缓。当前转入本地 OCR 原生能力验证，使图片型小红书/抖音公开内容可以在移动端离线提取文字，再进入既有 LLM 菜谱生成链路。

## 当前主任务

`SPK-002`：验证 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile 的 Android/iOS 插件与模型下载路径。当前先复核 Spike 与 OCR 插件契约，再实现可测试的模型安装、校验和 Provider 绑定切片。

## 已完成基线

- Flutter 跨平台工程、OpenAI-compatible 与 Gemini LLM Provider。
- API Base URL、可空 API Key、模型和协议配置；Key 使用系统安全存储。
- Local-first SQLite Schema v2、结构化菜谱 Repository 和 v1 → v2 迁移。
- `IMPORT-001`：持久化导入任务状态机、取消、重试、恢复和 SQLite 存储。
- `IMPORT-002`：统一导入内容模型与 JSON Schema、Adapter Registry、Runner、单执行器 Dispatcher、稳定错误映射和未知异常脱敏。
- `IMPORT-003`：受限 HTTP Transport、小红书/抖音公开内容 Adapter、HTML/Open Graph/JSON-LD 解析和人工粘贴/本地媒体降级。
- `AI-002`：受限 Prompt、严格 Schema 校验、Recipe 草稿持久化、取消提交点和真实 SQLite 重开验证。
- `OCR-001`：统一 OCR Provider、严格模型 Manifest、OCR 证据字段、导入预处理、稳定错误和 Runner 集成。
- `ASR-001`：统一 ASR Provider、分段时间证据、媒体限制、部分结果、稳定错误和 Runner 集成。
- `APP-001`：菜谱与分类 CRUD、搜索/收藏/状态/分类筛选、回收站生命周期、稳定错误和游客 SQLite 重开持久化。
- `APP-002`：游客/登录非敏感会话、八类能力矩阵、稳定原因码、SharedPreferences 严格序列化和能力守卫。
- `APP-003`：统一后端 Facade、设备组合根、能力路线、导入 Runner Factory、草稿确认/放弃、登录用户归属和重复确认保护。
- Android Debug APK 已通过 ASCII Junction 构建，并在 Android 12 真机安装启动。
- 最近一次自动化验证：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 217 项测试通过；3 份 JSON Schema 通过 Draft 2020-12 元 Schema 校验。

## APP-003 验收结论

1. 页面后续只需依赖 `AiRecipeBackendFacade`、`access` 和 `recipes`，无需直接访问 SQLite、HTTP Client、Provider SDK 或 API Key。
2. 导入执行计划支持自定义/托管 LLM、本地/云 OCR 和托管 ASR，并在执行入口重新校验能力。
3. 已覆盖 URL → Adapter → OCR/ASR（按需）→ LLM → 草稿 → 用户确认的完整 Fake 端到端链路。
4. 登录用户草稿保存对应 `userId`，游客草稿保持 `userId == null`。
5. 已发布菜谱的确认重试不会重复增加本地版本；放弃草稿采用软删除。
6. 修复 OCR 后进入 ASR 时进度倒退问题：ASR 全局进度使用 61%–64%，保持处理阶段单调推进。

## SPK-002 当前范围

1. 复核 `research/spikes/SPK-002-local-ocr.md` 与 `docs/architecture/OCR_PLUGIN.md`。
2. 明确 Flutter ↔ Android/iOS 原生插件边界、PP-OCRv5 mobile 模型文件、Manifest、SHA-256 校验和安装状态。
3. 实现不依赖 UI 的模型包下载/安装/删除服务与稳定错误。
4. 建立 Android ONNX Runtime 推理最小切片和 Fake/契约测试；iOS 代码可准备，但 Windows 不能宣称真机通过。
5. 将真实本地 OCR Provider 绑定到 APP-003 组合根的 `localOcrBuilder`。

## 当前实施边界

- 只处理无需登录即可访问的公开内容。
- 不实现登录绕过、验证码绕过、签名逆向、访问控制绕过或反爬规避。
- UI 不直接访问 SQLite、HTTP Client 或供应商 SDK。
- API Key、Authorization Header、完整 Prompt、完整模型响应、完整 OCR/ASR 文本和本地原图路径不得写入日志或 Git。
- AI 输出必须经过 Schema 校验，并保留用户确认步骤，不直接覆盖已有菜谱。
- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。

## 下一步

1. 读取并校正 SPK-002 的验收范围、依赖版本和风险。
2. 将 `SPK-002` 更新为 `DOING` 后实施第一个可验证原生 OCR 切片。
3. 运行 Dart/Flutter 测试、Android 构建或原生单元测试，并记录真实限制。
4. 完成后同步验收、风险、变更记录和 GitHub。

## 暂停项

- UI/UX 页面实现暂缓，等待后端核心用例与契约稳定。
- `SPK-001` 其余能力暂缓：系统分享、后台任务、通知和安全存储真机验证。
- `SPK-003` 真实 OpenAI-compatible、Gemini 和本地兼容服务互操作需要真实 API 地址与测试 Key。
- 真实托管 LLM、云 OCR、托管 ASR 和云同步后端尚未实现。

## 环境约束

- Windows Flutter 构建继续使用 ASCII Junction：`C:\tmp\ai-recipe-mobile`。
- 代码目录：`code/apps/mobile`。
- 验收记录：根目录 `tests/acceptance/`。
- 进度状态以本文件和 `tracking/BACKLOG.md` 为准。