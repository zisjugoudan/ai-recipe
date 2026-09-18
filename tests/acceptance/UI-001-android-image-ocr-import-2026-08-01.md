# UI-001 Android 单张截图 OCR 导入切片验收记录

> 验收日期：2026-08-01  
> 任务：`UI-001`  
> 平台范围：Android  
> 结论：Android 系统单图选择入口、取消路径、选择后的稳定安全失败边界及人工降级入口已完成；`UI-001` 总任务继续保持 `DOING`，`SPK-002` 不得标记完成。

## 1. 目标与用户价值

当小红书或抖音公开链接无法读取时，Android 用户可以从系统图片选择器选择一张菜谱截图，并将本地图片交给应用内部业务后端。业务链路固定使用本地 OCR 与用户配置的自有 LLM；在真实 OCR 模型或 LLM 配置缺失时，应用必须稳定失败、给出可操作提示，并保留粘贴正文和手动创建等降级入口。

## 2. 范围与非目标

本切片包含：Android 系统单张图片选择器；失败或已取消任务的截图降级；选择取消、插件错误和 lost-data 恢复；Facade 路线校验；稳定脱敏错误；Android 模拟器、自动测试、构建和 Logcat 验收。

本切片不包含：相机、多图、视频/ASR、云 OCR、托管 LLM、服务器队列、真实 PP-OCRv5/LLM 质量、iOS，以及长期保存原始截图。

## 3. 实现落点

- `code/apps/mobile/lib/features/importing/import_image_picker.dart`
- `code/apps/mobile/lib/features/importing/import_progress_page.dart`
- `code/apps/mobile/lib/application/backend/ai_recipe_backend_facade.dart`
- `code/apps/mobile/pubspec.yaml`
- `code/apps/mobile/pubspec.lock`
- `code/apps/mobile/test/features/import_image_picker_test.dart`
- `code/apps/mobile/test/features/import_progress_page_test.dart`
- `code/apps/mobile/test/application/ai_recipe_backend_facade_test.dart`
- `code/apps/mobile/android/gradle.properties`

页面没有直接访问 OCR Provider、Repository 或 SQLite；图片只经图片选择封装交给 `AiRecipeBackendFacade`。

## 4. 自动化验证

### 定向测试

```text
flutter test --no-pub \
  test/features/import_image_picker_test.dart \
  test/features/import_progress_page_test.dart \
  test/application/ai_recipe_backend_facade_test.dart
```

结果：`43` 项全部通过。

覆盖单图选择/取消/MIME 推断/非图片拒绝、权限和平台错误、lost-data 恢复、页面错误后任务状态与降级入口、Facade 任务/资源/MIME 校验、本地 OCR + 自有 LLM 强制路线，以及 LLM/OCR 能力缺失和 OCR 执行失败的稳定脱敏错误。

### Facade 定向复核

```text
flutter test --no-pub test/application/ai_recipe_backend_facade_test.dart --reporter expanded
```

结果：`19` 项全部通过。

### 静态分析与全量回归

```text
flutter analyze --no-pub
No issues found!

flutter test --no-pub --concurrency=4
447 项全部通过
```

## 5. Android 构建验证

- 设备：`emulator-5554`
- 系统：Android 16 / API 36
- 模型：`sdk_gphone64_x86_64`
- 包名：`com.airecipe.ai_recipe`

首次构建在 `:app:mergeExtDexDebug` 出现 `java.lang.OutOfMemoryError: Java heap space`。原因是 `code/apps/mobile/android/gradle.properties` 带 UTF-8 BOM，首行 `org.gradle.jvmargs=-Xmx8G ...` 未被 Gradle 正确识别，Daemon 实际仅使用 `-Xmx512m`。

移除 BOM、停止旧 Daemon 后执行：

```text
.\android\gradlew.bat --stop
flutter build apk --debug --no-pub
```

构建成功：

```text
C:\tmp\ai-recipe-mobile\build\app\outputs\flutter-apk\app-debug.apk
221239166 bytes
2026-08-01 08:51:49
```

本次 OOM 产生的三个未跟踪 HPROF 文件仍保留在 `code/apps/mobile/android/`，未擅自删除。

## 6. Android 人工验收

测试链接：

```text
https://www.xiaohongshu.com/explore/ui001-android-image-fallback
```

公开测试图片：

```text
/sdcard/Pictures/AiRecipeAcceptance/public-recipe-sample.png
```

### 6.1 系统单图选择器

从已取消的任务点击“上传截图继续”，成功打开：

```text
com.google.android.photopicker/com.android.photopicker.PhotopickerGetContentActivity
```

系统明确显示应用只能访问用户选中的照片。结果：通过。

证据：

- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/01-system-photo-picker.png`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/01-system-photo-picker.xml`

### 6.2 取消选择

在 Photo Picker 中返回后：应用正常恢复；任务仍为 `IMPORT · CANCELLED`；没有选择错误；全部人工降级入口仍可用。结果：通过。

证据：

- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/02-picker-cancelled-return.png`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/02-picker-cancelled-return.xml`

### 6.3 选择图片后的稳定失败

选择图片后成功返回应用。当前设备没有配置自有 LLM，也没有安装真实 OCR 模型。能力检查先检查 `customLlm`，因此实际显示：

```text
请先在 LLM 设置中配置可用的自有 AI 服务。
```

结果：通过。错误可操作，未包含图片路径、API Key 或正文；粘贴正文、上传截图、上传视频、手动创建和返回添加页仍存在。

证据：

- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/03-image-selected-llm-error.png`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/03-image-selected-llm-error.xml`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/04-image-error-fallback-actions.png`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/04-image-error-fallback-actions.xml`

本地 OCR 未安装错误由 Facade 自动测试覆盖：

```text
请先在 OCR 设置中安装并启用本地 OCR 模型。
```

因本轮设备先命中 LLM 未配置，不将该 OCR 文案误写为设备人工验证。

### 6.4 lost-data 恢复边界

lost-data 成功恢复、非图片返回和恢复异常均已通过自动测试。本次没有强制系统回收 Activity 进程，因此只标记“自动化通过”。

## 7. Logcat 与隐私检查

应用进程日志：

```text
LogLines=3
CriticalMatches=0
```

全系统日志：

```text
ScannedLines=1333
CriticalMatches=0
AppPrivacyMatches=0
```

扫描 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter`、`Unhandled Exception`、Flutter Widget 异常、`api key`、`content://` 与 `/data/user/`。未发现崩溃、未处理异常或敏感路径匹配；结束时顶层 Activity 为 `com.airecipe.ai_recipe/.MainActivity`。

证据：

- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/05-app-logcat-after-image-selection.txt`
- `tests/acceptance/artifacts/UI-001-android-image-ocr-import-2026-08-01/06-critical-logcat-scan.txt`

## 8. 验收标准结果

| 验收项 | 结果 | 说明 |
|---|---|---|
| 系统单图选择；取消后任务不变且无错误 | 通过 | API 36 人工验证 |
| 页面只通过 Facade 进入业务流水线 | 通过 | 代码检查与自动测试 |
| 状态/资源/MIME 校验；强制本地 OCR | 通过 | Facade 自动测试 |
| 进度、取消、草稿与 OCR 证据 | 自动化通过，真实链路未验证 | 缺少真实模型和 LLM 配置 |
| 稳定脱敏错误并保留降级入口 | 通过 | 设备验证 LLM 错误；OCR/选择错误由自动测试覆盖 |
| Activity 回收后恢复或稳定错误 | 自动化通过 | 未人工触发进程回收 |
| 新增测试并验证 Android 入口 | 通过 | 43 项定向、447 项全量、系统 Picker 人工验证 |

## 9. AI 质量边界

本轮没有可用的真实 PP-OCRv5 模型、真实自有 LLM API Key 和可授权公开菜谱截图，因此没有生成可评价的真实草稿，也没有向 `tests/ai-quality/AI_QUALITY_LOG.md` 写入虚假成功率。

菜名、食材召回/用量、步骤、低置信度、人工修改数，以及 OCR 延迟、内存和模型体积均未验证。

## 10. 结论与下一步

- Android 单张截图选择入口与稳定安全失败边界完成。
- 真实 PP-OCRv5 + 自有 LLM 的端到端识别仍未验证。
- OCR 未安装错误和 Activity lost-data 恢复只完成自动测试。
- 视频选择/ASR、相机、多图和 iOS 未实现或未验证。
- 服务器端继续暂缓。
- `UI-001` 保持 `DOING`；取得授权配置与公开样本后执行真实截图质量验收，并继续核对剩余 P0 页面。
- `SPK-002` 保持 `TODO`。
