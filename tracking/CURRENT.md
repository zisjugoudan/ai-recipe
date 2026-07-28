# 当前工作状态

> 更新时间：2026-07-28

## 当前阶段

后端核心契约与 Application 主链路已形成稳定基线，UI 继续暂缓。当前主线是 `SPK-002` 本地 OCR 原生能力验证；已完成模型包管理、安装可靠性、Flutter 原生桥接契约和 Android ONNX Runtime Session 健康检查，但真实图片识别尚未实现。

## 当前主任务

`SPK-002`（`DOING`）：验证 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile 的 Android/iOS 插件与模型下载路径。当前已完成 Android 基础模型包 Runtime 切片和安装可靠性切片；下一阶段进入真实 PP-OCRv5 mobile 模型、预处理、推理、后处理和真机指标验证。

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
- `SPK-002` 阶段切片：模型包下载、SHA-256/大小校验、安装、激活、删除、失败回滚和中断恢复；同包安装/删除/恢复的同一服务实例内串行队列；安装显式取消、下载前空间预检、旧版本回收和激活提交点保护；Flutter MethodChannel 契约；Android ONNX Runtime Session 健康检查；Application Use Cases、Backend Facade 和设备组合根接线。
- 最近一次自动化验证：`dart format lib test` 共 118 个文件、0 个变化；`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 共 259 项测试通过；Android Debug APK 构建成功。

## SPK-002 阶段验收结论

1. `DeviceOcrModelPackageService` 可按受信任主机下载模型文件，校验文件类型、大小和 SHA-256，并在健康检查成功后激活版本。
2. `active.json`、`state.json` 和安装后的 `manifest.json` 使用临时文件切换；Windows 覆盖失败时使用备份文件回退，失败不会破坏上一 active 版本。
3. 升级的 `downloading`、`verifying` 和 `failed` 状态保留上一 `installedVersion`；中断恢复优先保留状态或 active 版本。
4. 同一服务实例内，同包安装、删除和中断恢复按调用顺序串行执行；相同版本并发安装只下载一次，前一操作失败不会阻塞后续操作；跨 isolate、多服务实例、跨进程和 OS 文件锁仍未完成。
5. 读取 active 包时校验包 ID、版本和 Manifest 一致性；损坏或指针不一致时不返回可用包。
6. Flutter 与原生层使用 `ai_recipe/local_ocr`，定义 `probe`、`healthCheck` 和 `recognize` 三个方法；Dart 侧已覆盖响应解析和稳定错误映射。
7. Android 已集成 `com.microsoft.onnxruntime:onnxruntime-android:1.20.0`；`healthCheck` 能创建每个 ONNX 文件的 Session，并验证至少一个输入和输出。
8. 本地 OCR 模型管理已接入 `LocalOcrModelUseCases`、`AiRecipeBackendFacade` 和设备组合根；Android 容量查询通过 `getAvailableStorageBytes` 接入；能力探测会保持本地 OCR 不可用，直到真实识别能力完成。
9. Android `recognize` 当前固定返回 `inference_not_implemented`，`recognitionSupported` 固定为 `false`，因此本阶段仍不是可用的真实 OCR 识别能力。
10. 安装取消使用显式 `OcrModelInstallCancellationToken`；取消会清理 staging，保留上一 active，并写入 `failureCode = cancelled`。同包队列等待期间取消不是立即完成，必须等待前一个同包操作结束后再在当前操作开始前检查取消。
11. 下载前空间预检按 Manifest 模型总大小 + 64 MiB 安全余量计算；容量未知时跳过预检，容量不可用或空间不足映射为稳定错误。
12. 激活成功后默认保留 active + 1 个最新 inactive 版本；旧版本回收为 best-effort，回收异常不得让已激活包失败。
13. `active.json` 写入是安装提交点；提交点后的状态写入或观察者回调异常不得删除已激活模型。

## 当前实施边界

- 只处理无需登录即可访问的公开内容。
- 不实现登录绕过、验证码绕过、签名逆向、访问控制绕过或反爬规避。
- UI 不直接访问 SQLite、HTTP Client 或供应商 SDK。
- API Key、Authorization Header、完整 Prompt、完整模型响应、完整 OCR/ASR 文本和本地原图路径不得写入日志或 Git。
- AI 输出必须经过 Schema 校验，并保留用户确认步骤，不直接覆盖已有菜谱。
- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。

## 下一步

1. 固化真实 PP-OCRv5 mobile 模型文件清单、转换参数、词典、许可证证据和受信任发布方式。
2. 实现 Android 图片读取与预处理、文本检测、方向处理、文字识别、词典解码、阅读顺序和置信度后处理。
3. 用固定中文菜谱样本验证 Android 真机模型体积、加载耗时、1080p 单图耗时、峰值内存、准确率、取消和损坏模型处理。
4. 补齐跨 isolate、多服务实例、跨进程和 OS 文件锁级别的同包互斥；在 iOS 与真机压力场景验证取消、容量查询和旧版本回收策略。
5. 在 macOS/iPhone 环境实现并验证 iOS ONNX Runtime 桥接；完成前 `SPK-002` 保持 `DOING`。

## 暂停项

- UI/UX 页面实现暂缓，等待后端核心用例与契约稳定。
- `SPK-001` 其余能力暂缓：系统分享、后台任务、通知和安全存储真机验证。
- `SPK-003` 真实 OpenAI-compatible、Gemini 和本地兼容服务互操作需要真实 API 地址与测试 Key。
- 真实托管 LLM、云 OCR、托管 ASR 和云同步后端尚未实现。

## 环境约束

- Windows Flutter 构建固定使用 ASCII Junction：`C:\tmp\ai-recipe-mobile`。直接从中文仓库路径构建可能触发 Flutter Shader Compiler 写入失败。
- 代码目录：`code/apps/mobile`。
- 验收记录：根目录 `tests/acceptance/`。
- 进度状态以本文件和 `tracking/BACKLOG.md` 为准。
