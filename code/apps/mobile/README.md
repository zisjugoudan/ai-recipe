# AI 食谱移动端

当前目录是 `SPK-001` 的 Flutter 验证工程，也是后续正式移动端工程的候选基线。

## 当前已实现

- Android / iOS Flutter 工程骨架。
- 统一的自定义 LLM API 配置：协议类型、API Base URL、API Key、模型。
- OpenAI-compatible Chat Completions Adapter。
- Gemini native `generateContent` Adapter。
- API Key 与普通配置分离：Key 使用 Keychain/Keystore，普通配置只保存 `secretRef`。
- 连接测试、HTTP 明文风险提示、统一错误映射、超时与取消令牌基础能力。
- Provider 请求构造、响应解析、配置校验和设置页 Widget 测试。
- Local-first SQLite Schema v3、菜谱聚合 Repository、本地业务表和 v1/v2 → v3 迁移。
- APP-001 菜谱库 Application Facade：手动 CRUD、搜索/收藏/状态/分类筛选、菜谱与分类回收站、稳定错误和游客重开持久化。
- APP-002 游客/登录会话与能力策略：非敏感会话元数据、八类能力矩阵、稳定不可用原因、SharedPreferences 严格序列化和能力守卫。
- APP-003 应用后端统一门面：统一会话、能力、菜谱库和导入工作流，按执行计划装配自定义/托管 LLM、本地/云 OCR 与托管 ASR，并支持草稿确认、放弃和重复确认保护。
- APP-004 Flutter 本地业务后端：菜谱标签、首页/详情聚合、最近浏览、菜谱/分类完整生命周期、本地隐私设置、烹饪会话与多计时器，以及 LLM/OCR/导入统一 Facade 接线。
- 设备组合根集中装配 SQLite、会话、LLM 配置、公开内容 Adapter、Runner Factory 与 Provider Builder；页面无需接触 Repository、Provider 或 API Key。
- 可持久化的链接导入任务状态机、Application 用例、取消、重试和重启恢复。
- IMPORT-002 统一导入内容模型与 JSON Schema。
- 平台 Adapter Registry、导入 Runner 和单执行器 Dispatcher。
- 稳定错误映射、任务取消、指数退避、批次失败隔离和未知异常脱敏。
- IMPORT-003 公开内容 HTTP Transport、小红书/抖音公共元数据 Adapter、HTML/JSON-LD 解析和人工粘贴/本地媒体降级。
- AI-002 受限 Prompt、严格结构化菜谱 Schema、草稿持久化、错误映射和保存提交点。
- OCR-001 统一 OCR Provider、严格模型 Manifest、OCR 证据字段和导入预处理流水线。
- SPK-002 阶段切片：本地 OCR 模型包下载/校验/安装/激活/删除/恢复、同一服务实例内串行队列、显式取消、Android 空间预检、旧版本回收；Manifest v2 Runtime 契约；Android 私有文件/`content://` 图片解码、Detector/Recognizer ONNX 推理、简化文本框后处理、裁剪与 CTC 解码；以及 Application/Facade/组合根接线。
- OCR-002 远程图片暂存：HTTPS-only、全量 DNS 公网校验、固定已验证 IP 连接、逐跳重定向复检、TLS 主机名校验、受限 HTTP 响应、JPEG/PNG/WebP 内容校验、字节/边长/像素限制、超时/取消和临时文件清理。
- ASR-001 统一 ASR Provider、分段时间证据、音视频限制、部分结果和导入预处理流水线。
- 2026-07-30 APP-004 质量门：`dart analyze` 与 `flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 356 项测试通过。既有 Android `:app:testDebugUnitTest --rerun-tasks` 验证保持通过。

## 本地运行

```powershell
cd code/apps/mobile
flutter pub get
flutter run
```

## 质量检查

```powershell
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

## Windows 中文路径构建说明

当前仓库路径包含中文。Android Gradle Plugin 的路径检查已通过 `android.overridePathCheck=true` 处理，但 Flutter shader compiler 在 Windows 上仍可能无法向含中文的输出路径写文件。

本轮验证固定从 `C:\tmp\ai-recipe-mobile` 纯 ASCII Junction 构建并成功生成 APK。后续 Windows 开发必须继续使用该入口，或将仓库迁移到纯 ASCII 绝对路径；直接从当前中文路径构建可能触发 Flutter Shader Compiler 写入失败。

Debug APK 已成功生成并在 Android 12 真机安装、启动。详细记录见仓库根目录：

`tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`

本地 OCR 阶段验收见：

`tests/acceptance/SPK-002-local-ocr-runtime-slice-2026-07-28.md`

`tests/acceptance/SPK-002-ocr-model-install-reliability-2026-07-28.md`

`tests/acceptance/SPK-002-android-real-ocr-runtime-2026-07-29.md`

`tests/acceptance/OCR-002-secure-remote-image-staging-2026-07-29.md`

Flutter 本地业务后端验收见：

`tests/acceptance/APP-004-flutter-local-business-backend-2026-07-30.md`

## 安全约束

- 不得将真实 API Key、Token、Authorization Header、Prompt 或完整模型响应提交到 Git 或写入日志。
- API Key 输入框不会回填已经保存的明文 Key。
- `http://` 地址仅用于可信本地网络或本地服务；它可能暴露 Key 和请求内容，优先使用 HTTPS。
- Android 验证工程暂时允许 cleartext HTTP，以覆盖本地 OpenAI-compatible 服务；生产发布前必须重新评估网络安全配置。
- 不允许通过自定义证书回调忽略 TLS 错误。

## 当前限制

- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。
- iOS 仅加入本地网络用途说明和 `NSAllowsLocalNetworking`；任意局域网 IP 的明文 HTTP 行为仍需在 macOS/iPhone 上实测，不能视为已通过。
- 尚未验证系统分享、后台任务、本地通知和真实 LLM 服务兼容性。OCR 原生桥接已完成 Android 首阶段 Detector/Recognizer 推理代码路径，但尚未通过真实 PP-OCRv5 模型和真机样本验证。
- 设置页当前保存一个活动配置；多配置管理和模型列表读取属于后续任务。
- 已支持从已有文本、OCR 或 ASR 结果生成结构化菜谱草稿；Android `recognize` 已实现首阶段检测、裁剪、识别和 CTC 解码，远程 HTTPS 图片也可经过安全暂存后进入本地 OCR。但尚未验证真实 PP-OCRv5 模型、完整 DB 后处理、方向分类器、真实公开平台图片端到端链路、iOS、跨进程互斥、真实 ASR Provider 和真实 LLM 服务兼容性。

进度与结论以仓库根目录的 `tracking/CURRENT.md`、`research/spikes/SPK-001-cross-platform-framework.md` 和 `research/spikes/SPK-002-local-ocr.md` 为准。
