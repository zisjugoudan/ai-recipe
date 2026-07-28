# SPK-002：本地 OCR 引擎与插件机制验证

- 状态：DOING
- 关联任务：`SPK-002`、`OCR-001`
- 关联风险：`R-003`、`R-011`、`R-012`、`R-013`、`R-014`
- 首选候选：PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile
- 架构文档：`docs/architecture/OCR_PLUGIN.md`
- 阶段验收：`tests/acceptance/SPK-002-local-ocr-runtime-slice-2026-07-28.md`、`tests/acceptance/SPK-002-ocr-model-install-reliability-2026-07-28.md`

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

模型包生命周期、安装可靠性、Flutter MethodChannel 契约和 Android ONNX Runtime Session 健康检查已经证明阶段路径可行，但真实图片识别、性能、内存、准确率、许可证证据、Manifest 可信发布链和 iOS 路径均未验证。当前只能给出“阶段切片通过”，不能给出最终采用结论；本 Spike 保持 `DOING`。
