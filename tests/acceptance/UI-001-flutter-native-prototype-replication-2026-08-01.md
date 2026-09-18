# UI-001 Flutter 原生复刻 HTML 原型验收记录

> 日期：2026-08-01  
> 任务：`UI-001`  
> 状态：`VERIFY`  
> 验收平台：Android  
> 视觉事实源：`design/prototypes/index.html`、`design/prototypes/prototype.css`、`design/prototypes/app.js`

## 1. 验收目标

验证实际可运行的 Flutter 应用已经使用原生 Widget 复刻「拾味 · AI 食谱」HTML 高保真原型的视觉语言、页面结构与核心交互层级，并且继续通过 `AiRecipeBackendFacade` / Application 层调用本地业务后端，不通过 WebView 运行 HTML，也不绕开既有业务契约。

## 2. 本轮范围

- 米白纸张背景、深绿主色、低饱和状态色和中文粗体标题层级。
- 像素阶梯缺角卡片、按钮、标签、输入表面和硬边像素阴影。
- 首页 / 菜谱库 / 我的三栏底部导航与右下 Flutter 原生悬浮添加按钮。
- 欢迎、首页、菜谱库、添加/导入、导入进度、导入失败、AI 草稿确认、详情、编辑、烹饪、我的、LLM、OCR、隐私和回收站页面。
- 默认、加载、失败、低置信度、游客和业务完成状态的 Android 页面证据。
- Flutter 静态分析、全量自动测试和 WebView 依赖扫描。

## 3. 明确非目标

- 不验证 iOS 视觉、构建、Keychain 或本地网络行为。
- 不把页面中的 Mock 菜谱、Mock 置信度或 Mock 导入阶段当作真实 AI 质量样本。
- 不验证真实 PP-OCRv5 模型、真实自有 LLM API、真实小红书/抖音公开内容或视频 ASR。
- 不在本任务内扩展 `Recipe` 的来源持久化模型；正式来源 URL/快照契约缺口单独记录在 `tracking/RISKS.md`。

## 4. 实现检查

### 4.1 Flutter 原生实现

已检查 `code/apps/mobile/lib` 与 `code/apps/mobile/pubspec.yaml`，未发现 WebView 相关依赖或源码引用。页面使用 Flutter Widget、`CustomPainter`、`CustomClipper` 和共享像素 UI 组件实现。

主要实现位置：

- `code/apps/mobile/lib/app/app_theme.dart`
- `code/apps/mobile/lib/shared/widgets/pixel_ui.dart`
- `code/apps/mobile/lib/shared/widgets/app_page_header.dart`
- `code/apps/mobile/lib/shared/widgets/app_states.dart`
- `code/apps/mobile/lib/shared/widgets/recipe_card.dart`
- `code/apps/mobile/lib/features/`

### 4.2 业务边界

页面继续通过 `AiRecipeBackendFacade` / Application 层访问会话、菜谱、导入、设置和烹饪能力。未为视觉复刻重写 SQLite、Repository、Provider、OCR/LLM 流水线，也未在页面中直接读取 API Key 或底层持久化。

## 5. Android 截图矩阵

验收设备：

- 设备：`emulator-5554`
- 系统：Android 16 / API 36
- 物理分辨率：1080 × 2424
- 应用包名：`com.airecipe.ai_recipe`

证据目录：`tests/acceptance/artifacts/UI-001-2026-08-01/`

| 页面/状态 | 截图 |
|---|---|
| 欢迎页 | `android-welcome.png` |
| 首页顶部 | `android-home-top.png` |
| 我的 | `android-profile.png` |
| LLM 设置 | `android-llm-settings.png` |
| OCR 设置 | `android-ocr-settings.png` |
| 隐私设置 | `android-privacy-settings.png` |
| 回收站 | `android-trash.png` |
| 添加菜谱/链接导入 | `android-add-recipe.png` |
| 导入处理中 | `android-import-progress.png` |
| 导入失败与人工降级 | `android-import-failure.png` |
| AI 草稿确认 | `android-draft-review.png` |
| 低置信度草稿 | `android-draft-low-confidence.png` |
| 菜谱库 | `android-library.png` |
| 菜谱详情 | `android-recipe-detail.png` |
| 菜谱编辑 | `android-recipe-edit.png` |
| 烹饪模式 | `android-cooking-mode.png` |

人工逐页检查结果：

- 菜谱库包含搜索、排序、筛选、像素菜谱卡、回收站入口、三栏导航和悬浮添加按钮。
- 详情页包含像素 Hero、食材、步骤、来源和底部编辑/复制/删除/开始烹饪操作栏。
- 编辑页包含基础信息、食材行内编辑、步骤区域及取消/保存底栏，当前截图无键盘遮挡。
- 烹饪页使用深绿沉浸背景，包含步骤卡、食材、计时器和上下步操作。
- OCR、隐私错误态按钮统一使用“重试”；草稿页标题统一使用“确认草稿”。

## 6. 自动验证

### 6.1 静态分析

```powershell
cd code/apps/mobile
flutter analyze --no-pub
```

结果：

```text
No issues found! (ran in 61.8s)
```

### 6.2 全量测试

```powershell
cd code/apps/mobile
flutter test --no-pub --concurrency=4
```

结果：

```text
450 tests passed
All tests passed!
```

### 6.3 WebView 扫描

扫描范围：

- `code/apps/mobile/lib`
- `code/apps/mobile/pubspec.yaml`

结果：未发现 WebView 依赖或源码引用。

## 7. 验收结论

`UI-001` 的 Flutter 原生高保真复刻已经完成 Android 实现、自动质量门和 16 张逐页截图矩阵，满足当前切片的实现验收标准，任务从 `DOING` 进入 `VERIFY`。

进入 `DONE` 前仍需项目负责人完成最终视觉确认。若确认中发现间距、字重、颜色、像素缺角或页面层级差异，继续在本任务内修正并更新本记录；真实 OCR/LLM/公开内容质量和 iOS 验收不作为本次 Android 视觉切片的完成条件，仍由对应 Spike/后续任务处理。

## 8. 已知限制与后续

1. iOS 未验证。
2. 截图中的“番茄炒蛋”、食材、步骤和 62%/66% 置信度为 UI 流程 Mock 数据，不属于 `tests/ai-quality/AI_QUALITY_LOG.md` 的真实样本。
3. 真实 PP-OCRv5 模型、真实自有 LLM API 和真实公开内容端到端质量仍未验证。
4. 视频选择/ASR 尚未完成 Android 端到端验收。
5. 字段与 OCR/ASR/原文证据的一一映射、应用重启后的完整原文证据恢复仍未完成。
6. `Recipe` 目前只有 `sourceId`，缺少正式 `sourceUrl` / `canonicalUrl` 或来源快照持久化契约；本轮只展示当前可恢复的来源信息，不扩展领域模型。
