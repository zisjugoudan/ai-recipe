# SPK-001 Local-first 菜谱数据库验收记录

- 日期：2026-07-28
- 任务：`SPK-001`、`APP-001`
- 结果：通过（SQLite 基线切片）
- 工程：`code/apps/mobile`

## 验收范围

本记录只验收 Local-first 菜谱数据库和 Repository，不代表 `APP-001` 页面或完整菜谱库已经完成。

## 已实现

- 新增纯 Dart `Recipe`、`Ingredient`、`RecipeStep`、`RecipeCategory` 领域模型和字段约束。
- 新增 `RecipeRepository`、`RecipeCategoryRepository` 接口。
- 新增 SQLite Schema v1：
  - `recipes`
  - `ingredients`
  - `recipe_steps`
  - `recipe_categories`
  - `recipe_category_relations`
- Android/iOS 运行依赖使用 `sqflite`；测试使用 `sqflite_common_ffi`。
- 启用 SQLite 外键和级联删除。
- 菜谱聚合保存使用单一事务。
- 支持持久化读取、更新、列表、文本搜索、收藏筛选、软删除、恢复和永久删除。
- 支持分类写入、排序读取和软删除。

## 自动化验证

在 `code/apps/mobile` 执行：

```text
dart format lib test
flutter analyze
flutter test
```

结果：

- 格式化完成。
- `flutter analyze`：`No issues found`。
- `flutter test`：27 个测试全部通过，其中新增 6 个 SQLite Repository 测试。
- 测试使用真实 SQLite 临时文件，并验证关闭/重新打开后的数据持久性。
- 无效分类外键导致事务失败，菜谱主记录和子记录均未残留。

## Android 构建验证

通过已校验的纯 ASCII Junction `C:\tmp\ai-recipe-mobile` 执行：

```text
flutter build apk --debug
```

结果：构建成功。

APK：`code/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`

## 已知限制

- 当前未把 Repository 接入最终页面；符合“后端能力优先，UI 后置”的本轮范围。
- 尚未实现标签、导入来源、导入任务、购物清单、云同步和数据库升级迁移。
- 当前搜索使用 `LIKE`，尚未引入 SQLite FTS。
- iOS 仍需在 macOS/iPhone 环境验证真实构建和数据库文件行为。

## 结论

SQLite、事务、关系结构和 Repository 分层没有发现阻止 Flutter 继续开发的问题。`SPK-001` 的 SQLite 验证项可标记为通过；完整 Spike 仍需继续验证分享入口、后台任务、通知、安全存储真机、OCR 桥接和 iOS。
