# SPK-002 Android 本地 OCR 首阶段真实识别验收记录

> 日期：2026-07-29  
> 状态：Android 首阶段识别切片通过；`SPK-002` 仍为 `DOING`  
> 工程：`code/apps/mobile`  
> Windows 验证入口：`C:\tmp\ai-recipe-mobile`

## 1. 目标

将 Android 本地 OCR 从“ONNX Session 可加载”推进到可执行的首阶段识别代码路径，并把模型运行参数固化为可校验的 Manifest v2 契约。

## 2. 验收范围

本记录验收：

1. Manifest v1/v2 兼容规则和 v2 Runtime 配置。
2. Android 应用私有文件与 `content://` 图片读取及输入限制。
3. Detector/Recognizer ONNX Session 缓存、预处理、推理和结果解析。
4. 简化文本检测后处理、轴对齐裁剪、CTC 解码和 `OcrDocument` 输出。
5. Runtime 能力探测、稳定错误映射和自动化测试。

本记录不验收：

- 真实 PP-OCRv5 mobile 模型的准确率、性能、内存或体积。
- 完整 Paddle DB 后处理和方向分类器。
- 远程图片安全下载/暂存。
- iOS 实现或真机结果。
- 跨进程模型包互斥和 Manifest 可信发布链。

## 3. 主要实现

### 3.1 Manifest v2 Runtime 契约

- `schemaVersion = 1`：只支持模型安装和 Session 健康检查，禁止 `runtimeConfig`。
- `schemaVersion = 2`：必须提供 `runtimeConfig`。
- Runtime 配置覆盖 Detector/Recognizer 模型角色、词典角色、Tensor 输入输出名、归一化、检测长边、阈值、最大候选数、unclip 参数、识别 Shape、blank index 和空格策略。
- Dart 和 Kotlin 应用层额外校验 Runtime 引用的角色存在、角色用途不冲突、模型为 `.onnx`、词典为 `.txt`、相对路径不会逃逸模型根目录。

### 3.2 Android 图片边界

- 支持应用私有文件和 `content://`。
- 不接受裸远程 HTTP/HTTPS URL，也不将远程 URL 直接传给原生文件 API。
- 校验输入字节、图片边长和总像素，避免无界解码。
- 图片不可访问、权限拒绝、图片过大和解码失败使用稳定错误码。

### 3.3 推理链

- Detector 与 Recognizer `OrtSession` 按模型绝对路径缓存。
- Detector：图片缩放、颜色顺序、归一化、NCHW Tensor、ONNX 推理、输出概率图读取。
- 检测后处理：概率阈值、连通域、box score、候选限制、边界扩张和轴对齐矩形。
- Recognizer：文本框裁剪、按识别 Shape 缩放/补齐、NCHW Tensor、ONNX 推理。
- CTC：过滤 blank、折叠连续重复 token、映射 UTF-8 词典并计算置信度。
- 输出：按阅读顺序返回 `OcrDocument`、文本块、归一化坐标和置信度。

### 3.4 能力探测

ONNX Runtime 可用时，Android `probe` 返回：

```json
{
  "runtimeAvailable": true,
  "recognitionSupported": true,
  "runtimeVersion": "onnxruntime-android"
}
```

该修复使 Dart `PlatformOcrProvider` 不再因为 `recognitionSupported = false` 永久跳过真实识别。

## 4. 修改文件

主要代码与契约：

- `code/apps/mobile/android/app/build.gradle.kts`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/MainActivity.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/LocalOcrException.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/LocalOcrImageSource.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/LocalOcrMethodHandler.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/OcrDictionary.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/OcrModelPackage.kt`
- `code/apps/mobile/android/app/src/main/kotlin/com/airecipe/ai_recipe/ocr/PaddleOcrEngine.kt`
- `code/apps/mobile/lib/domain/ocr/ocr_model_manifest.dart`
- `code/apps/mobile/lib/domain/ocr/ocr_model_runtime_config.dart`
- `code/apps/mobile/lib/providers/ocr/platform_ocr_runtime_bridge.dart`
- `docs/api/ocr-model-manifest.schema.json`
- `docs/architecture/OCR_PLUGIN.md`

自动化测试：

- `code/apps/mobile/android/app/src/test/kotlin/com/airecipe/ai_recipe/ocr/LocalOcrProbeContractTest.kt`
- `code/apps/mobile/android/app/src/test/kotlin/com/airecipe/ai_recipe/ocr/OcrCtcDecoderTest.kt`
- `code/apps/mobile/android/app/src/test/kotlin/com/airecipe/ai_recipe/ocr/OcrDictionaryTest.kt`
- `code/apps/mobile/android/app/src/test/kotlin/com/airecipe/ai_recipe/ocr/OcrModelPackageTest.kt`
- `code/apps/mobile/test/data/device_ocr_model_package_service_test.dart`
- `code/apps/mobile/test/domain/ocr_model_runtime_config_test.dart`
- `code/apps/mobile/test/providers/platform_ocr_runtime_bridge_test.dart`

## 5. 自动化结果

### 5.1 Dart 格式检查

```powershell
dart format --output=none --set-exit-if-changed lib test
```

结果：120 个文件，0 个变化。

### 5.2 Flutter 静态分析

```powershell
flutter analyze --no-pub
```

结果：`No issues found!`

### 5.3 Flutter 测试

```powershell
flutter test --no-pub
```

结果：268 项全部通过。

### 5.4 Android app 模块测试

为避免 Flutter 依赖插件自己的单元测试干扰，只执行 app 模块，并使用 `--rerun-tasks` 确认不是缓存命中：

```powershell
java -jar <gradle-cli-main-8.14.jar> :app:testDebugUnitTest `
  --rerun-tasks --no-daemon `
  --project-cache-dir E:\AI\ai食谱\.tmp\gradle-project-cache
```

结果：`BUILD SUCCESSFUL`，112 个 Gradle 任务全部执行。

说明：此前执行聚合任务 `testDebugUnitTest` 会进入 `shared_preferences_android` 插件自身测试并失败；该失败不代表 app OCR 测试失败。本次以 `:app:testDebugUnitTest --rerun-tasks` 为 app 模块验收结果。

## 6. 已知限制与风险

1. **未验证真实模型**：当前证明的是代码路径、契约和单元测试，不是 PP-OCRv5 真实识别质量。
2. **检测后处理简化**：当前不是完整 Paddle DB contour/min-area-rect/unclip 实现，不能据此承诺旋转、倾斜、竖排或复杂版面效果。
3. **无方向分类器**：旋转文字可能识别失败或置信度偏低。
4. **远程图片链路未闭环**：公开内容 Adapter 可能产出 HTTPS 图片，而 Android 本地 OCR 只接受私有文件或 `content://`；当前会得到 `image_source_unavailable`，后续由 `OCR-002` 解决。
5. **真机指标为空**：模型体积、首次加载、1080p 单图耗时、峰值内存、准确率和阅读顺序均待测。
6. **iOS 未完成**：Windows 环境不能替代 macOS/iPhone 构建和真机验证。
7. **并发与发布链未完成**：跨 isolate、多服务实例、跨进程文件锁和 Manifest 签名/固定公钥仍待设计。

## 7. 结论

Android 首阶段本地 OCR 识别代码路径、Manifest v2 Runtime 契约、能力探测和自动化测试通过。

这不是最终 OCR 采用验收：真实 PP-OCRv5 模型、真机质量与性能、远程图片暂存、完整后处理、iOS 和发布安全仍未完成。因此 `SPK-002` 继续保持 `DOING`，不得标记为 `DONE`。
