# SETTINGS-001 LLM 与识图设置结构重分类验收

> 任务：按项目负责人要求重新打散排列 LLM API 设置与识图引擎两个页面。
> 日期：2026-08-11
> 状态：VERIFY（等待项目负责人构建后验收）

## 变更摘要

**确认结构（项目负责人选定）**：「我的」页保持两个入口。

### 1. 「LLM 模型」入口
文件：`code/apps/mobile/lib/features/llm_settings/llm_settings_page.dart`
- 页面标题由「本地 LLM API」改为「LLM 模型」。
- 集中两类 LLM 配置：
  - **菜谱生成 LLM**（普通文本 LLM，用于结构化生成）——原有内容，新增「菜谱生成 LLM」区块标题。
  - **多模态 LLM 图片识别**（独立配置）——从识图引擎页迁入。
- 两类 LLM 各自独立配置（API 地址 / Key / 模型 / 请求超时分别保存）。

### 2. 「识图引擎」入口
文件：`code/apps/mobile/lib/features/settings/ocr_settings_page.dart`
- 只保留 OCR 相关：
  - 图片识别方式（自动 / 仅 OCR / 多模态 LLM）选择
  - 本地 OCR 模型（当前 OCR 路线 / 模型包 / 测试 / 安装 / 删除）
  - 云端路线与隐私边界
- **移除**多模态 LLM 配置表单（迁至「LLM 模型」页）。

### 3. 「我的」页入口
文件：`code/apps/mobile/lib/features/profile/profile_page.dart`
- 入口标题「LLM API 设置」改为「LLM 模型」；识图引擎入口保持不变。

## 代码移动明细

从 `ocr_settings_page.dart` 移入 `llm_settings_page.dart` 的私有类/函数（共 6 项，逻辑与注释原样保留）：
- `_MultimodalLlmConfigSection`（含 `_MultimodalLlmConfigSectionState`）
- `_MultimodalTestResultCard`
- `_MultimodalDiagnosticCard`
- `_DiagnosticStageRow`
- `_diagnosticStageLabel`
- `_diagnosticMessage`

Import 调整：
- `ocr_settings_page.dart` 删除 4 个：llm_settings_use_cases、llm_diagnostic、llm_provider_type、multimodal_llm_provider
- `llm_settings_page.dart` 新增 3 个：llm_diagnostic、multimodal_llm_provider、import_image_picker

## 验收方法

### 前置条件
1. Flutter SDK 已配置；在 `C:\AIM`（junction → `code/apps/mobile`）下构建避免中文路径问题。
2. Android 设备/模拟器（iOS 未验证）。

### 构建命令（Codex 未执行，ADR-0015）
```powershell
cd C:\AIM
flutter pub get
flutter analyze --no-pub
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

### 验收步骤

#### A. 静态分析
1. 运行 `flutter analyze --no-pub`。
2. 预期：`llm_settings_page.dart`、`ocr_settings_page.dart`、`profile_page.dart` 无 error、无 unused import、无未定义符号。

#### B. 真机/模拟器视觉与交互验收

1. **「我的」页入口**
   - 存在两个 AI 相关入口：「LLM 模型」与「识图引擎」。
   - 「LLM API 设置」字样已不存在。

2. **「LLM 模型」页**
   - 顶部 appBar 标题为「LLM 模型」。
   - 页面上部为「菜谱生成 LLM」区块：服务商与地址、密钥与模型、请求超时、测试连接、测试结构化生成。
   - 页面下部为「多模态 LLM 图片识别」区块：Provider 类型、API Base URL、API Key、模型名称、请求超时、检查基础连接、检查图片能力（标准诊断图）、用我的图片测试。
   - 两个区块的配置字段独立，各自有独立的保存按钮（菜谱生成 LLM 用底部「保存配置」，多模态 LLM 用「保存配置」按钮）。
   - 在「菜谱生成 LLM」填入并保存一个配置，再在「多模态 LLM 图片识别」填入并保存另一个配置，确认互不影响、均可成功保存。

3. **「识图引擎」页**
   - 顶部 appBar 标题为「识图引擎」。
   - 页面包含：图片识别方式（自动 / 仅 OCR / 多模态 LLM）、当前 OCR 路线、模型包、云端路线、隐私边界。
   - **页面中不再出现多模态 LLM 配置表单**（Provider 类型 / API Key / 模型等字段不应出现在本页）。
   - 图片识别方式选择「多模态 LLM」时，仍可使用「LLM 模型」页配置的图片识别 LLM（可先保存配置再回来选择并测试）。
   - 本地 OCR 的下载/安装/测试/删除功能正常。

### 预期结果
- 两个入口、两个页面结构符合上述说明。
- `flutter analyze --no-pub` 无 error。
- 两类 LLM 配置可独立保存、互不干扰。
- 识图引擎页不含多模态 LLM 配置表单。

### 失败回传格式
1. `flutter analyze --no-pub` 完整输出。
2. 问题页面截图。
3. Logcat 中 `FATAL EXCEPTION` / `E/flutter` 相关日志。
4. 复现步骤。

## 已知限制
- Codex 未执行 `flutter analyze` 与构建（ADR-0015）。
- iOS 未验证。
- 多模态 LLM 配置从识图引擎页迁出后，若用户此前未在 LLM 模型页保存过图片识别 LLM，识图引擎页选择「多模态 LLM」时仍需先去 LLM 模型页配置。

## 关联文件
- `code/apps/mobile/lib/features/llm_settings/llm_settings_page.dart`
- `code/apps/mobile/lib/features/settings/ocr_settings_page.dart`
- `code/apps/mobile/lib/features/profile/profile_page.dart`
