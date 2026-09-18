# UI-001 导入执行进度与 AI 草稿确认切片验收记录

> 验收日期：2026-07-30  
> 任务状态：`DOING`  
> 范围：链接导入执行进度、AI 草稿确认及应用壳导航闭环；`UI-001` 尚未整体完成。

## 1. 本切片实现范围

- 添加页创建导入任务后立即打开执行进度页，不再停留在占位成功提示。
- queued 任务自动调用导入流水线；应用异常退出遗留的 running 任务先执行恢复，再根据最新状态继续。
- 执行期间以 450ms 间隔轮询持久化任务，展示当前阶段、进度、尝试次数、错误和阶段时间线。
- 覆盖 queued、running、needsReview、failed、cancelled、completed 六类任务状态。
- running 状态支持取消；失败状态根据 `canRetry` 控制重试入口，并保留恢复入口；取消后可返回；完成后可打开正式菜谱。
- needsReview 自动打开 AI 草稿确认页，保存完成后把正式菜谱返回应用壳，刷新首页和菜谱库并打开菜谱详情。
- 草稿确认页支持编辑菜名、简介、份量、准备时间、烹饪时间、总时间、难度、食材和步骤。
- 支持动态新增、删除食材和步骤；保存时保留未编辑的封面、备注、收藏、状态、分类、标签以及食材/步骤扩展字段。
- 放弃草稿必须二次确认，并通过 Facade 取消导入任务、将草稿软删除到回收站。

## 2. 低置信度与证据规则

- 低置信度阈值固定为 `< 0.7`，等于 `0.7` 不计入低置信度。
- 页面显示低置信度数量、字段置信度百分比，并允许用户标记已核对。
- 若本次执行会话仍持有 `ImportContent`，原始证据区展示文本片段、片段类型、置信度、时间范围和来源 Provider。
- `ImportContent` 尚未持久化；应用重启后可恢复待确认 Recipe 草稿，但完整原文片段可能不可用。
- 当前后端尚未提供字段与证据的一一映射。页面明确展示限制，不把任意原文/OCR/ASR 片段伪装成某个字段的确定来源。

## 3. 前端接线验收

- 页面统一调用 `AiRecipeBackendFacade` / Application 层能力。
- 页面没有直接访问 SQLite、SharedPreferences、安全存储、Repository 或 Provider。
- 自动执行使用 `runImportTask()`，取消、重试和恢复分别使用 Facade 对应入口。
- 草稿读取、确认保存和放弃分别使用 `getImportDraft()`、`confirmImportDraft()` 和 `discardImportDraft()`。
- 页面使用 `ImportCancellationToken` 传递本次执行的取消意图；持久化任务取消保持最终状态来源。

## 4. 主要实现位置

- `code/apps/mobile/lib/features/importing/import_progress_page.dart`
- `code/apps/mobile/lib/features/importing/import_draft_review_page.dart`
- `code/apps/mobile/lib/features/importing/add_recipe_page.dart`
- `code/apps/mobile/lib/features/shell/app_shell.dart`
- `code/apps/mobile/test/features/import_progress_page_test.dart`
- `code/apps/mobile/test/features/import_draft_review_page_test.dart`

## 5. 自动化测试

新增并通过 2 个 Widget 测试文件，共 6 项：

- `import_progress_page_test.dart`：3 项，覆盖可重试/不可重试失败、恢复入口、取消状态返回和 needsReview 自动打开草稿。
- `import_draft_review_page_test.dart`：3 项，覆盖编辑保存、元数据保留、发布与任务完成、放弃确认、回收站软删除和证据限制提示。

定向回归：

```text
flutter test --no-pub \
  test/features/import_progress_page_test.dart \
  test/features/import_draft_review_page_test.dart
```

结果：6 项全部通过。

## 6. 质量门

使用 Flutter SDK：`D:\SofeWare\My\FlutterSDK\flutter`，从 ASCII Junction `C:\tmp\ai-recipe-mobile` 执行 Flutter 工具。

已通过：

- `dart analyze lib test`：无问题。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=4`：共 377 项全部通过。

## 7. 本切片非范围

`UI-001` 保持 `DOING`，本次没有实现：

- 完整烹饪模式和多计时器页面。
- Facade 版 LLM、OCR 和本地隐私设置页面。
- 独立本地 onboarding 状态。
- 字段与原文/OCR/ASR 证据的一一映射持久化。
- 真实登录、云同步、服务器 AI/OCR/ASR、配额和服务器任务队列。

## 8. 已知限制

- 真实链接是否能获取完整图片、视频与正文仍受平台公开可访问性、网络和已配置 Provider 能力影响。
- 运行中任务在生成器提交草稿后进入不可取消提交点，以避免已保存草稿失去任务引用；此时用户取消可能最终以待确认为准。
- 应用重启后可以恢复任务和 Recipe 草稿，但不能恢复本次执行会话中未持久化的完整 `ImportContent` 证据。
- UI 与 OCR/HTML 原型改动仍处于同一未提交工作树，后续不得通过重置或清理覆盖并行交付。