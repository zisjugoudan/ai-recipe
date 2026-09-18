# OCR-003：OCR 设置页"测试 OCR"——选图识别并输出文本与耗时

> 日期：2026-08-04
> 状态：`VERIFY`（Android 已实现，等待项目负责人复测；iOS 未验证）
> 平台：Android
> 关联：`OCR-001`、`OCR-002`、`IMPORT-007`、`SPK-002`、`ADR-0015`

## 1. 用户价值

在"我的 → OCR 引擎"页，用户可以直接选一张本地图片做识别，直观验证本地 OCR 是否可用、识别文本是否正确，并看到单次识别耗时，避免"装好模型但不知道好不好用"的黑盒状态。

## 2. 已实现

- `OcrTestResult` 领域模型：识别文本 `text`、`modelVersion`、`language`、文本块数 `blockCount`、耗时 `durationMs`（毫秒）、平均置信度 `averageConfidence`（可为空）。
- `AiRecipeBackendFacade.testLocalOcrImage(localPath)`：
  - 前置能力检查 `AppCapability.localOcr`，未配置 Provider 或能力缺失时报稳定中文错误；
  - 复用 `localOcrProviderBuilder`（composition root 注入的本地 OCR Provider 工厂）直接识别本地图片（`OcrImageInput(localAssetId:)`，不上传图片）；
  - 错误统一映射为 `AiRecipeBackendException`：模型未安装/不可用/推理失败 → `providerRouteUnavailable`，超时 → `timeout`，取消 → `operationCancelled`，网络不可用 → `networkUnavailable`，其余 → `operationFailed`。
- OCR 设置页（"测试 OCR"入口常驻，不依赖模型安装状态）：
  - "测试 OCR"按钮在模型包卡片内始终显示；本地 OCR 模型已安装时点击打开系统图片选择器（复用 `DeviceImportImagePicker`），选中后开始识别，按钮切换为加载态"正在识别…"；
  - 识别成功：显示结果卡片 `_OcrTestResultCard`——识别文本（空结果明确提示"这张图片里没有识别出文字"）、耗时、文本块数、平均置信度、模型版本、语言；
  - 识别失败：显示红色 `PixelNotice` 错误条，文案来自 Facade 稳定中文错误；
  - 模型未安装/下载中/安装失败时点击，不开图片选择器，按状态给出中文引导提示（如"请先在模型包中下载并安装本地 OCR 模型后再测试"）；
  - 重复测试自动清空上次结果，测试期间按钮防重复点击。
- 修改文件：`code/apps/mobile/lib/domain/ocr/ocr_models.dart`、`code/apps/mobile/lib/application/backend/ai_recipe_backend_facade.dart`、`code/apps/mobile/lib/app/ai_recipe_backend_composition_root.dart`、`code/apps/mobile/lib/features/settings/ocr_settings_page.dart`。

## 3. 已知限制

- 真实 PP-OCRv5 模型质量、性能与准确率仍未验证（`SPK-002`）；耗时、置信度与文本正确性以真机实测为准。
- 测试入口只出现在"模型包已安装"分支；未安装时先下载安装模型包。
- 图片选择器被取消时不产生错误提示，直接返回原页面。
- iOS 未验证（本地 OCR Runtime 未实现）。

## 4. Android 人工复测步骤

### 4.1 前置条件

1. 安装包含 `OCR-003` 的 Android 构建。
2. 在"我的 → OCR 引擎"页，模型包卡片应显示"下载本地模型"按钮（不再显示"正式模型包尚未发布"）；点击下载 PP-OCRv5 mobile 模型（约 21.5 MB，来源 RapidAI/RapidOCR 官方 ModelScope 仓库，安装时校验 SHA-256 与字节大小），完成后状态显示 INSTALLED / 就绪。
3. 准备一张包含清晰中文文字的图片（建议是带菜名、食材、步骤的菜谱截图）。

### 4.2 操作步骤（成功分支）

1. 进入"我的 → OCR 引擎"，在模型包卡片下方找到"测试 OCR"按钮。
2. 点击"测试 OCR"，系统图片选择器打开；选择准备好的菜谱截图。
3. 按钮变为"正在识别…"，识别完成后展示结果卡片。
4. 记录结果卡片中的：识别文本、耗时（ms）、文本块数、平均置信度、模型版本、语言。
5. 对照原图检查识别文本的准确性：菜名、食材、用量、步骤是否正确，多行文本是否按阅读顺序拼接。

### 4.3 操作步骤（取消/未安装/错误分支）

1. 点击"测试 OCR"后在系统选择器直接返回，确认回到 OCR 设置页且无报错弹窗。
2. 模型未安装（或删除模型后）点击"测试 OCR"：确认不打开图片选择器，提示"请先在模型包中下载并安装本地 OCR 模型后再测试"等中文引导，且"测试 OCR"按钮仍可见。
3. 下载中/安装失败状态下点击，确认分别提示"还在下载/校验中…"与"安装失败，请先重试下载后再测试"。

### 4.4 预期结果

- 选择图片后成功输出识别文本与耗时；文本准确性以真机实测为准。
- 失败路径均显示稳定中文错误，不泄露本地绝对路径或底层英文。
- 全程不上传图片（本地 OCR 直接在设备内识别）。

### 4.5 回传模板

```text
OCR-003 Android 复测

1. 测试按钮是否在"模型包已安装"分支出现并可点击：
2. 选择图片后是否输出识别文本与耗时（ms）：
3. 识别文本与原文对照：菜名/食材/用量/步骤准确性如何（识别错几处、需人工修改几处）：
4. 文本块数、平均置信度、模型版本、语言是否展示：
5. 选择器取消返回是否无报错：
6. 模型未安装/删除后：按钮是否仍可见，点击是否给中文引导提示：
7. 是否出现任何底层英文错误：
8. 其他问题：
```

## 5. 验证边界

Codex 不执行自动测试、分析器、格式化、构建、模拟器、真机或真实 OCR 请求（`ADR-0015`）。本文件是项目负责人可直接执行的 Android 测试方法；实现代码与测试定义已完成，等待项目负责人复测反馈后归档，并按 `tests/ai-quality/AI_QUALITY_LOG.md` 记录真实样本质量。
