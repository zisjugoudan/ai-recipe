# SPK-002：本地 OCR 引擎与插件机制验证

- 状态：TODO（Android 基础切片已通过；待真实模型与公开样本验收时继续）
- 关联任务：`SPK-002`、`OCR-001`、`OCR-002`
- 关联风险：`R-003`、`R-011`、`R-012`、`R-013`、`R-014`、`R-015`
- 首选候选：PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile
- 架构文档：`docs/architecture/OCR_PLUGIN.md`
- 阶段验收：`tests/acceptance/SPK-002-local-ocr-runtime-slice-2026-07-28.md`、`tests/acceptance/SPK-002-ocr-model-install-reliability-2026-07-28.md`、`tests/acceptance/SPK-002-android-real-ocr-runtime-2026-07-29.md`、`tests/acceptance/OCR-002-secure-remote-image-staging-2026-07-29.md`

## 问题

PaddleOCR PP-OCRv5 mobile 经 ONNX Runtime Mobile 封装后，能否在 iOS 和 Android 上以可下载模型插件方式提供可靠的中文菜谱文字识别？

## 推荐假设

该方案可跨平台复用模型，重点覆盖中文和复杂截图，并支持把模型作为可校验、可升级、可回滚和可删除的数据包。推荐已记录为 `ADR-0009`。若实测出现不可接受的内存、体积、性能或 iOS 集成成本，则降级为云 OCR 或按平台改用原生 OCR。

## 验证目标

- 识别中文食材表、步骤截图和中英文混合文字。
- 记录模型体积、首次加载、单图耗时、峰值内存和准确率。
- 验证 Android/iOS ONNX Runtime 包装和 Flutter federated plugin 调用。
- 验证模型下载、SHA-256 校验、版本升级、回滚、删除、取消、空间预检和旧版本回收。
- 确认 PaddleOCR、模型和依赖授权允许产品使用。
- 给出“采用”“带约束采用”或“拒绝”的实测结论。

## 2026-07-28 阶段切片

### 已完成

- 新增 `DeviceOcrModelPackageService`，支持下载、文件类型限制、大小与 SHA-256 校验、版本安装、健康检查后激活、删除、失败回滚和中断恢复。
- 同一服务实例内按包 ID 串行执行安装、删除和恢复；相同版本并发安装只下载一次，失败操作不会毒化后续队列。
- `active.json`、`state.json` 和 `manifest.json` 使用临时文件原子切换；Windows 目标覆盖失败时先备份旧文件，新文件切换失败会恢复备份。
- 升级期间和失败状态保留上一 `installedVersion`；读取 active 包时校验 Manifest 包 ID、版本和指针一致。
- 新增显式安装取消令牌；取消检查覆盖排队后、创建目录、容量检查、文件下载、每个 chunk、Manifest 写入、staging rename、health check 和 active 切换前。
- 取消后清理 staging，升级场景保留上一 active，并写入 `failureCode = cancelled`；Facade 映射为 `operationCancelled`。
- 同包队列等待期间取消不是立即完成，必须等待前一个同包操作结束后再进入当前操作的取消检查，避免后续操作越过仍在运行的前序操作。
- 下载前空间预检按 Manifest 模型总大小 + 64 MiB 安全余量计算；容量未知时跳过预检，容量不可用或空间不足使用稳定错误。
- Android 新增 `getAvailableStorageBytes`，使用最近存在父目录的 `StatFs.availableBytes`；Dart 新增 `PlatformOcrStorageCapacityProvider`，原生不可用或异常时返回 `null`。
- 成功激活后默认保留 active + 1 个最新 inactive 版本；旧版本回收为 best-effort，异常不能让已激活版本失败。
- 修复激活提交点：`active.json` 写入成功后，状态持久化或观察者回调异常不得删除已激活模型。
- Flutter 原生桥接通道固定为 `ai_recipe/local_ocr`，契约包含 `probe`、`healthCheck`、`recognize`。
- Android 集成 `com.microsoft.onnxruntime:onnxruntime-android:1.20.0`；`healthCheck` 会逐个创建 ONNX Runtime Session 并检查输入输出存在。
- 新增 `PlatformOcrProvider`、`LocalOcrModelUseCases`、Backend Facade 模型管理入口和设备组合根绑定。
- 自动化验证通过：格式化 118 个文件、0 个变化，静态分析无问题，259 项 Flutter 测试全部通过，Android Debug APK 构建成功。

### 尚未完成

- Android `recognize` 固定返回 `inference_not_implemented`。
- `probe` 的 `recognitionSupported` 固定为 `false`，本地 OCR 能力不会被错误标记为可用。
- 未接入真实 PP-OCRv5 mobile 模型、模型转换参数和词典。
- 未实现图片解码、缩放归一化、检测、方向处理、识别、词典解码、阅读顺序和置信度后处理。
- 未取得 Android 真机模型体积、加载耗时、单图耗时、峰值内存和准确率结论。
- iOS 未实现、未构建、未真机验证；iOS 容量查询、取消和旧版本回收均未验证。
- 跨 isolate、多服务实例、跨进程和 OS 文件锁级别的同包互斥尚未完成。
- Manifest 签名、固定公钥、可信索引或其他可信发布链尚未实现。

## 2026-07-29 Android 首阶段真实识别切片

### 已完成

- 将 OCR 模型 Manifest 扩展为 v1/v2：v1 继续兼容安装和 Session 健康检查，v2 必须提供可执行的 `runtimeConfig`。
- Dart、JSON Schema 和 Kotlin 同步定义 PP-OCRv5 Detector/Recognizer 的模型角色、Tensor 名称、归一化、检测尺寸与阈值、识别输入 Shape、词典和 CTC blank index。
- Android 本地 OCR 支持从应用私有文件或 `content://` 安全读取图片，并限制输入字节、图片边长和总像素。
- Detector/Recognizer ONNX Session 按模型路径缓存，已实现 Bitmap 预处理、NCHW Tensor、Detector 推理、概率图阈值与连通域后处理、轴对齐裁剪、Recognizer 推理和 CTC 解码。
- Runtime 能力探测在 ONNX Runtime 可用时报告 `recognitionSupported = true`，修复 Dart Provider 永远无法进入真实识别路径的问题。
- 新增稳定错误：图片过大、权限拒绝、图片源不可用等；错误和日志不包含完整 URL 或本地路径。
- 新增 Kotlin 单元测试，覆盖能力探测、UTF-8/BOM/CRLF 词典、非法词典、Manifest v2 Runtime、缺失角色、不安全相对路径和 CTC 解码。
- 自动化验证：Dart 格式检查 120 个文件无变化，Flutter 静态分析无问题，268 项 Flutter 测试通过，Android app 模块单元测试使用 `--rerun-tasks` 完整重跑通过。

### 该阶段切片当时尚未完成

- 尚未接入和验证真实 PP-OCRv5 mobile ONNX 模型、词典、转换参数与许可证证据。
- Detector 后处理是首阶段简化实现，不是完整 Paddle DB contour、min-area-rect 和 unclip 算法。
- 未实现文字方向分类器；旋转、倾斜文字和复杂布局的准确率未知。
- 未取得 Android 真机模型体积、首次加载、1080p 单图耗时、峰值内存、中文准确率和阅读顺序数据。
- 该阶段切片完成时，公开内容 Adapter 可能提供 HTTPS 远程图片 URL，而原生 OCR 只接受本地私有文件或 `content://`；后续 `OCR-002` 已补齐安全暂存层。
- iOS、跨 isolate/多服务实例/跨进程互斥、Manifest 可信发布链仍未完成。

## 2026-07-29 OCR-002 远程图片安全暂存切片

### 已完成

- 新增 `RemoteStagingOcrProvider`，本地图片直接透传；远程图片在调用本地 OCR 前暂存为本地文件，成功、失败和取消后都会释放。
- 默认与自定义本地 OCR Builder 都在设备组合根中经过暂存包装；云 OCR 保持供应商自行传输，不复用本地暂存层。
- URL 策略只允许 HTTPS，拒绝 userinfo、fragment、控制字符、环回、私网、link-local、CGNAT、文档/保留地址以及混合公网和非公网 DNS 结果。
- 下载器逐跳重新校验 URL 与 DNS，连接固定到已验证 IP，TLS 仍使用原始域名完成 SNI 和证书校验；只支持受限 HTTP/1.0/1.1 响应。
- 支持 Content-Length、chunked 和 connection-close；限制响应头、重定向、字节、连接/TLS/响应/总操作超时，取消会销毁活动连接。
- 仅允许 JPEG、PNG、WebP；MIME 必须与 magic bytes 匹配，并限制图片字节、单边尺寸和总像素。
- 新增 39 项定向测试；全量 Dart 格式检查 130 个文件无变化，Dart/Flutter 静态分析无问题，307 项 Flutter 测试和 Android app 模块单元测试通过。

### 仍待验证

- 自动化下载测试使用可控 DNS、假连接和内存图片，尚未使用真实小红书/抖音公开图片验证防盗链、CDN 重定向、证书链和真机网络行为。
- 真实 PP-OCRv5 mobile 模型、Android 真机性能/内存/准确率、完整 Paddle DB 后处理、方向分类器、iOS、跨进程模型锁和 Manifest 可信发布链仍未完成。
- `OCR-002` 已完成，但不能据此把 `SPK-002` 标记为完成。

## 必测样本

清晰食材列表、长步骤正文、中英文数字单位混排、竖排、倾斜、低对比度、压缩、水印截图和多图批量导入。

## 待记录指标

| 指标 | Android | iOS |
|---|---:|---:|
| 模型下载体积 | 待测 | 待测 |
| 首次加载 | 待测 | 待测 |
| 单张 1080p 耗时 | 待测 | 待测 |
| 峰值内存 | 待测 | 待测 |
| 中文准确率 | 待测 | 待测 |
| 阅读顺序 | 待测 | 待测 |
| 取消、损坏、低内存处理 | 部分覆盖安装取消、模型损坏与安装回滚；真机待测 | 待测 |
| 空间不足与旧版本回收 | Android 基础切片覆盖；真机压力待测 | 待测 |

## 当前结论

模型包生命周期、安装可靠性、Manifest v2 Runtime 契约、Android 首阶段 Detector/Recognizer 推理代码路径和远程 HTTPS 图片安全暂存已经证明工程路径可继续推进。由于尚未使用真实 PP-OCRv5 mobile 模型和真机样本验证，简化 Detector 后处理、方向处理、性能、内存、准确率、许可证证据、Manifest 可信发布链和 iOS 路径仍未验收。当前只能给出“Android 首阶段识别与 OCR-002 安全暂存切片通过”，不能给出最终采用结论；本 Spike 保持 `DOING`。
