# UI-001 Flutter P0 页面首个切片验收记录

> 验收日期：2026-07-30  
> 任务状态：`DOING`  
> 范围：Flutter 应用主题、会话入口、四 Tab 应用壳及首页/菜谱库/添加/我的首版；`UI-001` 尚未整体完成。

## 1. 验收范围

本次验收确认 HTML 原型已经开始转换为可运行的 Flutter 页面，并且首个切片统一通过 `AiRecipeBackendFacade` 接入已完成的本地业务后端：

- Material 3 应用主题与 HTML 原型颜色 Token。
- `AiRecipeApp` 对设备组合根的创建、持有和关闭。
- 欢迎页、游客继续、登录占位和会话错误重试。
- 首页、菜谱库、添加、我的四 Tab 应用壳。
- 首页聚合、分类摘要、最近浏览、收藏和未完成导入提示。
- 菜谱搜索、分类筛选、新建分类和收藏切换。
- 公开链接导入任务创建与手动菜谱创建。
- 游客/登录身份和本地/自定义 AI/OCR 能力摘要。
- 菜谱详情快速预览 Bottom Sheet。
- 加载、空、错误和长菜名等基础状态。

## 2. 主要实现位置

- `code/apps/mobile/lib/app/app.dart`
- `code/apps/mobile/lib/app/app_theme.dart`
- `code/apps/mobile/lib/features/session/`
- `code/apps/mobile/lib/features/shell/`
- `code/apps/mobile/lib/features/home/`
- `code/apps/mobile/lib/features/library/`
- `code/apps/mobile/lib/features/importing/`
- `code/apps/mobile/lib/features/profile/`
- `code/apps/mobile/lib/shared/widgets/`

## 3. 接线约束验收

- 页面只调用 `AiRecipeBackendFacade` 或接收 Facade 返回的领域对象。
- 页面没有直接访问 SQLite、SharedPreferences、安全存储、Repository 或 Provider。
- 正式运行由 `AiRecipeBackendCompositionRoot.device()` 组装依赖。
- 由应用入口持有组合根生命周期，退出应用树时关闭自有数据库。
- 旧 `LlmSettingsPage` 注入入口仅保留给既有调试和测试，不作为新页面绕过 Facade 的先例。

## 4. 自动化测试

新增 8 项主题与 Widget 测试：

- 欢迎页显示游客入口并触发回调。
- 会话忙碌时登录与游客按钮禁用。
- 会话错误提示与重试回调。
- 空状态 CTA。
- 错误状态重试。
- 菜谱卡片长标题与元数据。
- 菜谱卡片收藏和点击回调。
- HTML 原型主题颜色 Token。

## 5. 质量门

使用 Flutter SDK：`D:\SofeWare\My\FlutterSDK\flutter`，从 ASCII Junction `C:\tmp\ai-recipe-mobile` 执行 Flutter 工具。

已通过：

- `dart analyze code/apps/mobile/lib`：无问题。
- `flutter analyze --no-pub`：无问题。
- 新增 UI 定向测试：8 项全部通过。
- `flutter test --no-pub --concurrency=4`：364 项全部通过。
- `git diff --check`：通过。

## 6. 未完成范围

`UI-001` 保持 `DOING`，下一切片继续实现：

- 正式菜谱详情页。
- 菜谱新建/编辑完整表单。
- 回收站、恢复、永久删除和清空。
- 导入运行进度、取消、重试和恢复。
- AI 草稿确认、低置信度字段和原文证据。
- 烹饪模式与多个计时器。
- Facade 版 LLM、OCR、本地隐私设置。

## 7. 已知限制

- 服务器登录、云同步和服务器 AI 仍未实现，登录按钮当前只显示暂未接入提示。
- 当前会话数据无法区分首次游客和已确认游客，重启后仍会回到欢迎页；后续应新增本地 onboarding 状态。
- 链接添加页当前只创建持久化导入任务，尚未在页面内启动完整流水线或展示实时进度。
- 手动添加当前只填写菜名和简介，食材、步骤、分类和标签由下一编辑页补齐。