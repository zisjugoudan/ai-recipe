# SPK-002 本地 OCR Runtime 阶段切片验收记录

> 日期：2026-07-28  
> 状态：阶段切片通过；`SPK-002` 仍为 `DOING`  
> 工程：`code/apps/mobile`  
> Windows 构建入口：`C:\tmp\ai-recipe-mobile`

## 1. 验收范围

本记录只验收无需 UI 的本地 OCR 基础设施切片：

1. 模型包下载、文件限制、大小与 SHA-256 校验。
2. 版本安装、健康检查后激活、删除、失败回滚、中断恢复和同包进程内串行化。
3. Flutter MethodChannel 请求/响应和稳定错误契约。
4. Android ONNX Runtime 可加载性与 ONNX Session 健康检查。
5. Application Use Cases、Backend Facade 和设备组合根接线。

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
```

Dart 侧已验证：

- Runtime 探测响应严格解析。
- Manifest 和模型目录参数传递。
- OCR 文档、文本块、坐标和置信度解析。
- 平台错误映射为稳定 `OcrProviderErrorKind`。
- Runtime 不可用或识别未实现时不会暴露为可用本地 OCR 能力。

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

- `LocalOcrModelUseCases` 暴露状态、安装、删除和恢复入口。
- `AiRecipeBackendFacade` 暴露本地 OCR 模型管理，并将包异常映射为稳定后端错误。
- 设备组合根装配模型下载客户端、模型包服务、Runtime Bridge 和 `PlatformOcrProvider`。
- `recognitionSupported == false` 时，本地 OCR 运行时能力保持不可用。

## 3. 自动化与构建结果

从 `C:\tmp\ai-recipe-mobile` 执行：

```powershell
dart --suppress-analytics format lib test
flutter --suppress-analytics analyze --no-pub
flutter --suppress-analytics test --no-pub
flutter --suppress-analytics build apk --debug
```

结果：

- `dart format`：116 个文件，0 个变化。
- `flutter analyze --no-pub`：`No issues found!`
- `flutter test --no-pub`：244 项全部通过。
- Android Debug APK：成功生成 `build/app/outputs/flutter-apk/app-debug.apk`。
- 模型包服务定向测试：13 项通过，覆盖同包并发安装复用、失败后续跑、删除/恢复等待、升级失败保留 active/installedVersion、成功升级清理临时文件、Manifest 包 ID 不一致拒绝等路径。

## 4. 明确未验收

- Android `recognize` 尚未实现，固定返回 `inference_not_implemented`。
- `recognitionSupported` 固定为 `false`。
- 未接入真实 PP-OCRv5 mobile 模型、模型转换参数和词典。
- 未实现图片预处理、文本检测、方向处理、文字识别和词典解码。
- 未取得 Android 真机模型体积、首次加载、1080p 单图耗时、峰值内存、中文准确率和阅读顺序结论。
- iOS 未实现、未构建、未真机验证。
- 跨 isolate/进程同包互斥、显式取消、磁盘空间预检和旧版本回收未实现。
- Manifest 尚无签名或完整可信发布机制。
- 本次只证明 Android APK 能构建，不等于 ONNX 模型已在 Android 真机上完成真实推理。

## 5. 验收结论

模型包生命周期、Flutter 原生桥接契约和 Android ONNX Runtime Session 健康检查的阶段切片通过。由于真实 OCR 推理、真机指标和 iOS 路径均未完成，`SPK-002` 保持 `DOING`，不得对外声明本地 OCR 已完成。
