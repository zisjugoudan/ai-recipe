# UI-001 完整烹饪模式与多计时器切片验收记录

- 日期：2026-07-30
- 任务：`UI-001`
- 状态：通过；`UI-001` 总任务继续保持 `DOING`
- 范围：`UI-010` 完整烹饪模式、菜谱详情入口、多计时器与会话恢复

## 1. 验收范围

本切片按 `design/prototypes/` 的 `UI-010` 原型实现 Flutter 烹饪模式，并遵守 `docs/architecture/FLUTTER_BUSINESS_BACKEND_COMPLETION.md` 的前端接线原则：页面只访问 `AiRecipeBackendFacade`，不直接访问 Repository、SQLite、SharedPreferences、安全存储或 Provider。

已覆盖：

- 从菜谱详情启动或恢复烹饪会话。
- 当前步骤、步骤进度、大字号说明以及时长、温度、厨具、火候和提示。
- 上一步、下一步、最后一步完成烹饪与二次确认。
- 多个计时器的创建、暂停、继续、提前完成和清除。
- 退出防误触确认，退出页面后活动会话与运行计时器仍持久化保留。
- 页面处于前台时，计时器归零后的状态归并与完成提醒。
- 加载、错误、无步骤、长步骤、小屏幕和多个计时器状态。

## 2. 数据与边界约束

- 运行计时器以持久化的绝对 `endsAt` 计算剩余时间；页面 ticker 只触发显示刷新，不作为业务事实源。
- 当前 `RecipeStep` 不包含食材 ID 列表。页面只展示步骤正文中完整提到名称的菜谱食材；没有匹配时明确提示尚未建立独立步骤—食材关联。
- 当前 `CookingTimer` 不包含步骤 ID 或步骤索引。页面使用稳定标签 `步骤 <stepNumber>` 判断当前步骤是否已经创建计时器。
- 当前只实现页面前台计时结束提醒。退出页面后计时器数据仍保留，但 App 退出后的操作系统后台本地通知不在本切片范围内。

## 3. 自动化测试

新增 `code/apps/mobile/test/features/cooking_mode_page_test.dart`，覆盖：

1. 恢复持久化步骤和多个计时器状态。
2. 上一步/下一步持久化及完整计时器生命周期。
3. 退出确认、取消退出和计时器保留。
4. 最后一步完成会话。
5. 根据绝对 `endsAt` 对过期计时器进行状态归并。
6. 小屏幕、长步骤和多个计时器无布局溢出。

同时更新 `code/apps/mobile/test/features/recipe_detail_page_test.dart`，验证详情页进入正式烹饪模式以及退出后会话仍为活动状态。

## 4. 质量门结果

```text
flutter test --no-pub test/features/cooking_mode_page_test.dart test/features/recipe_detail_page_test.dart
8 项全部通过

flutter analyze --no-pub
No issues found

flutter test --no-pub --concurrency=4
383 项全部通过
```

## 5. 结论与后续

本切片验收通过。下一切片进入 Facade 版 LLM、OCR、本地隐私设置和独立 onboarding 状态；`UI-001` 在所有 P0 页面完成前继续保持 `DOING`。
