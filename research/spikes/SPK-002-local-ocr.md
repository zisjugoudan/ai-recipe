# SPK-002：本地 OCR 引擎与插件机制验证

- 状态：DOING
- 关联任务：`SPK-002`、`OCR-001`
- 关联风险：`R-003`、`R-011`、`R-012`、`R-013`、`R-014`
- 首选候选：PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile
- 架构文档：`docs/architecture/OCR_PLUGIN.md`
- 阶段验收：`tests/acceptance/SPK-002-local-ocr-runtime-slice-2026-07-28.md`

## 问题

PaddleOCR PP-OCRv5 mobile 经 ONNX Runtime Mobile 封装后，能否在 iOS 和 Android 上以可下载模型插件方式提供可靠的中文菜谱文字识别？

## 推荐假设

该方案可跨平台复用模型，重点覆盖中文和复杂截图，并支持把模型作为可校验、可升级、可回滚和可删除的数据包。推荐已记录为 `ADR-0009`。若实测出现不可接受的内存、体积、性能或 iOS 集成问题，必须更新 ADR 并评估系统 ML Kit 或云 OCR 降级方案。

## 成功标准

- 识别中文食材表、步骤截图和中英文混合文字。
- 记录模型体积、首次加载、单图耗时、峰值内存和准确率。
- 验证 Android/iOS ONNX Runtime 包装和 Flutter federated plugin 调用。
- 验证模型下载、SHA-256 校验、版本升级、回滚和删除。
- 确认 PaddleOCR、模型和依赖授权允许产品使用。
- 给出“采用”“带约束采用”或“拒绝”的实测结论。

## 2026-07-28 阶段切片

### 已完成

- 新增 `DeviceOcrModelPackageService`，支持下载、文件类型限制、大小与 SHA-256 校验、版本安装、健康检查后激活、删除、失败回滚和中断恢复。
- `active.json`、`state.json` 和 `manifest.json` 使用临时文件原子切换；Windows 目标覆盖失败时先备份旧文件，新文件切换失败会恢复备份。
- 升级期间和失败状态保留上一 `installedVersion`；读取 active 包时校验 Manifest 包 ID与版本和指针一致。
- Flutter 原生桥接通道固定为 `ai_recipe/local_ocr`，契约包含 `probe`、`healthCheck`、`recognize`。
- Android 集成 `com.microsoft.onnxruntime:onnxruntime-android:1.20.0`；`healthCheck` 会逐个创建 ONNX Runtime Session 并检查输入输出存在。
- 新增 `PlatformOcrProvider`、`LocalOcrModelUseCases`、Backend Facade 模型管理入口和设备组合根绑定。
- 自动化验证通过：格式化无变化、静态分析无问题、237 项 Flutter 测试全部通过、Android Debug APK 构建成功。

### 尚未完成

- Android `recognize` 固定返回 `inference_not_implemented`。
- `probe` 的 `recognitionSupported` 固定为 `false`，本地 OCR 能力不会被错误标记为可用。
- 未接入真实 PP-OCRv5 mobile 模型、模型转换参数和词典。
- 未实现图片解码、缩放归一化、检测、方向处理、识别、词典解码、阅读顺序和置信度后处理。
- 未取得 Android 真机模型体积、加载耗时、单图耗时、峰值内存和准确率结论。
- iOS 未实现、未构建、未真机验证。
- 同包并发安装锁、显式取消、磁盘空间预检、旧版本保留/回收和 Manifest 签名/可信发布机制尚未完成。

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
| 取消、损坏、低内存处理 | 部分覆盖模型损坏与安装回滚；真机待测 | 待测 |

## 当前结论

模型包生命周期、Flutter MethodChannel 契约和 Android ONNX Runtime Session 健康检查已经证明阶段路径可行，但真实图片识别、性能、内存、准确率、许可证证据和 iOS 路径均未验证。当前只能给出“阶段切片通过”，不能给出最终采用结论；本 Spike 保持 `DOING`。
