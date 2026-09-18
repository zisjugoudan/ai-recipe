# UI-001 菜谱详情、编辑与回收站切片验收记录

> 验收日期：2026-07-30  
> 任务状态：`DOING`  
> 范围：正式菜谱详情页、完整新建/编辑页和回收站；`UI-001` 尚未整体完成。

## 1. 本切片实现范围

- 将菜谱详情快速预览升级为正式页面，展示菜名、描述、份量、准备/烹饪时间、难度、标签、分类、来源、食材和步骤。
- 支持详情页收藏切换、进入编辑、软删除和“开始烹饪”入口。
- 新建/编辑页支持菜名、描述、份量、准备时间、烹饪时间、难度、标签和分类。
- 食材支持动态新增、删除和编辑名称、用量、单位、备注及可选状态。
- 步骤支持动态新增、删除和编辑说明、计时分钟及提示。
- 编辑已有菜谱时保留已持久化的食材和步骤身份；新增子项身份继续由 Application 层分配。
- 回收站支持列表、单条恢复、单条永久删除和清空回收站，并为破坏性操作提供确认。
- 新建、编辑、删除和恢复后刷新首页与菜谱库，避免返回后显示旧数据。
- 修复分类加载态在固定高度容器中的真实布局溢出，替换为紧凑的居中加载行。
- 为编辑分区和回收站操作按钮补充稳定测试 Key。

## 2. 前端接线验收

- 页面统一调用 `AiRecipeBackendFacade` / Application 层能力。
- 页面没有直接访问 SQLite、SharedPreferences、安全存储、Repository 或 Provider。
- 详情使用 Facade 详情聚合，并通过 Facade 记录收藏、删除和烹饪会话操作。
- 新建和编辑使用 Facade 菜谱库入口，不在页面中复制领域持久化规则。
- 回收站使用 Facade 查询、恢复、永久删除和清空入口。

## 3. 主要实现位置

- `code/apps/mobile/lib/features/recipe/recipe_detail_page.dart`
- `code/apps/mobile/lib/features/recipe/recipe_edit_page.dart`
- `code/apps/mobile/lib/features/trash/recipe_trash_page.dart`
- `code/apps/mobile/lib/features/shell/app_shell.dart`
- `code/apps/mobile/lib/features/importing/add_recipe_page.dart`
- `code/apps/mobile/lib/features/profile/profile_page.dart`

## 4. 自动化测试

新增并通过 3 个 Widget 测试文件，共 7 项：

- `recipe_edit_page_test.dart`：2 项，覆盖新建校验、动态食材/步骤保存、编辑回填和子项身份保留。
- `recipe_detail_page_test.dart`：2 项，覆盖详情内容、可选食材文案、烹饪会话准备、收藏、编辑入口和软删除确认。
- `recipe_trash_page_test.dart`：3 项，覆盖空状态、恢复、永久删除及清空确认。

定向组合回归：

```text
flutter test --no-pub   test/features/recipe_edit_page_test.dart   test/features/recipe_detail_page_test.dart   test/features/recipe_trash_page_test.dart   --concurrency=1
```

结果：7 项全部通过。

## 5. 质量门

使用 Flutter SDK：`D:\SofeWare\My\FlutterSDK\flutter`，从 ASCII Junction `C:\tmp\ai-recipe-mobile` 执行 Flutter 工具。

已通过：

- `dart format code/apps/mobile/lib code/apps/mobile/test`：共格式化 173 个文件，其中 3 个文件发生格式调整。
- `dart analyze code/apps/mobile/lib code/apps/mobile/test`：无问题。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=4`：共 371 项全部通过。
- `git diff --check`：通过。

## 6. 本切片非范围

`UI-001` 保持 `DOING`，本次没有实现：

- 链接导入实时执行进度、取消、重试、恢复和失败降级页面。
- AI 草稿确认、低置信度字段和原文证据交互。
- 完整烹饪模式和多计时器页面。
- Facade 版 LLM、OCR 和本地隐私设置页面。
- 独立本地 onboarding 状态。
- 真实登录、云同步、服务器 AI/OCR/ASR 和服务器任务队列。

## 7. 已知限制

- “开始烹饪”当前只创建或恢复烹饪会话并显示“烹饪会话已准备”，尚未跳转到完整烹饪模式。
- 链接导入当前只创建持久化导入任务，尚未在 UI 内启动完整解析流水线。
- 登录按钮仍是服务器能力未接入的占位行为；游客本地数据和自定义 LLM/OCR 路线不受影响。
- UI 与 OCR/HTML 原型改动仍处于同一未提交工作树，后续不得通过重置或清理覆盖并行交付。
