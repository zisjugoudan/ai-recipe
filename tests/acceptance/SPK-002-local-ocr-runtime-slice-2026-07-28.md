# SPK-002 本地 OCR Runtime 阶段切片验收记录

> 日期：2026-07-28  
> 状态：阶段切片通过；`SPK-002` 仍为 `DOING`  
> 工程：`code/apps/mobile`  
> Windows 构建入口：`C:	mpi-recipe-mobile`

## 1. 验收范围

本记录只验收无需 UI 的本地 OCR 基础设施切片：

1. 模型包下载、文件限制、大小与 SHA-256 校验。
2. 版本安装、健康检查后激活、删除、失败回滚、中断恢复和同一服务实例内同包串行化。
3. 安装显式取消、下载前空间预检、旧版本回收和激活提交点保护。
4. Flutter MethodChannel 请求/响应和稳定错误契约。
5. Android ONNX Runtime 可加载性与 ONNX Session 健康检查。
6. Application Use Cases、Backend Facade 和设备组合根接线。

本记录不验收真实图片文字识别、性能、准确率或 iOS 可行性。

## 2. 已验证实现

### 2.1 模型包生命周期

- 下载地址必须符合 Manifest 和受信任主机约束。
- 模型文件只允许配置的扩展名，并校验声明大小和 SHA-256。
- 下载和校验使用临时目录；健康检查通过后才激活新版本。
- 安装失败不会替换上一 active 版本。
- 升级的 `downloading`、`verifying` 和 `failed` 状态保留上一 `installedVersion`。
- active 包读取会验证 `active.json`、目录、Manifest 包 ID 和 Manifest 版本一致性。
- `active.json`、`state.json`、`manifest.json` 使用临时文件切换；Windows 覆盖失败时使用备份恢复。
- 中断恢复清理安装临时目录，并优先保留状态或 active 版本。
- 同一服务实例内，同包安装、删除和恢复按调用顺序串行执行；相同版本并发安装只下载一次，前一安装失败不会阻塞后续安装。
- 成功升级后不会遗留 `.tmp-*` 或 `.bak-*` 文件。
- 安装取消会清理 staging，升级场景保留上一 active，并写入 `failureCode = cancelled`。
- 下载前空间预检按 Manifest 模型总大小 + 64 MiB 安全余量计算；容量未知时跳过预检。
- 激活成功后默认保留 active + 1 个最新 inactive 版本；旧版本回收异常不会让已激活版本失败。
- `active.json` 写入成功是安装提交点；提交点后状态写入或观察者回调失败不得删除已激活模型。

### 2.2 Flutter 原生桥接

MethodChannel：

```text
ai_recipe/local_ocr
```

方法：

```text
probe
healthCheck
recognize
getAvailableStorageBytes
```

Dart 侧已验证：

- Runtime 探测响应严格解析。
- Manifest 和模型目录参数传递。
- OCR 文档、文本块、坐标和置信度解析。
- 平台错误映射为稳定 `OcrProviderErrorKind`。
- Runtime 不可用或识别未实现时不会暴露为可用本地 OCR 能力。
- Android 容量查询通过 `PlatformOcrStorageCapacityProvider` 接入，原生不可用或异常时返回 `null`。

### 2.3 Android ONNX Runtime

依赖：

```text
com.microsoft.onnxruntime:onnxruntime-android:1.20.0
```

`healthCheck` 已验证的代码路径：

- 获取 `OrtEnvironment`。
- 校验模型根目录和包内相对路径。
- 对 Manifest 中每个 `.onnx` 文件创建 `OrtSession`。
- Session 必须至少包含一个输入和一个输出。
- 路径、模型缺失、ONNX 错误和 Runtime 错误使用稳定且脱敏的错误码。

### 2.4 应用后端接线

- `LocalOcrModelUseCases` 暴露状态、安装、删除和恢复入口，安装支持取消令牌透传。
- `AiRecipeBackendFacade` 暴露本地 OCR 模型管理，并将包异常映射为稳定后端错误。
- 设备组合根装配模型下载客户端、模型包服务、Runtime Bridge、容量 Provider 和 `PlatformOcrProvider`。
- `recognitionSupported == false` 时，本地 OCR 运行时能力保持不可用。

## 3. 自动化与构建结果

从 `C:	mpi-recipe-mobile` 执行：

```powershell
dart --suppress-analytics format lib test
flutter --suppress-analytics analyze --no-pub
flutter --suppress-analytics test --no-pub
flutter --suppress-analytics build apk --debug
```

结果：

- `dart format`：118 个文件，0 个变化。
- `flutter analyze --no-pub`：`No issues found!`
- `flutter test --no-pub`：259 项全部通过。
- Android Debug APK：成功生成 `build/app/outputs/flutter-apk/app-debug.apk`。
- 模型包服务定向测试覆盖 Manifest、下载、哈希、安装、激活、删除、失败回滚、恢复、同包串行、取消、空间预检、旧版本回收和激活提交点保护等路径。

## 4. 明确未验收

- Android `recognize` 尚未实现，固定返回 `inference_not_implemented`。
- `recognitionSupported` 固定为 `false`。
- 未接入真实 PP-OCRv5 mobile 模型、模型转换参数和词典。
- 未实现图片预处理、文本检测、方向处理、文字识别和词典解码。
- 未取得 Android 真机模型体积、首次加载、1080p 单图耗时、峰值内存、中文准确率和阅读顺序结论。
- iOS 未实现、未构建、未真机验证；iOS 容量查询、取消和回收未验证。
- 跨 isolate、多服务实例、跨进程和 OS 文件锁级别同包互斥未实现。
- Manifest 尚无签名、固定公钥、可信索引或完整可信发布机制。
- 本次只证明 Android APK 能构建，不等于 ONNX 模型已在 Android 真机上完成真实推理。

## 5. 验收结论

模型包生命周期、安装可靠性基础切片、Flutter 原生桥接契约和 Android ONNX Runtime Session 健康检查的阶段切片通过。由于真实 OCR 推理、真机指标、iOS 路径和跨进程互斥均未完成，`SPK-002` 保持 `DOING`，不得对外声明本地 OCR 已完成。
