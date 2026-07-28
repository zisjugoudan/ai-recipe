# Local-first 数据库与迁移契约

- 状态：Schema v2 已实现并通过迁移验收
- 日期：2026-07-28
- 关联任务：`SPK-001`、`APP-001`、`IMPORT-001`
- 关联用户故事：`US-001`、`US-003`、`US-009`

## 1. 当前范围

当前阶段优先实现领域层、Application 和数据层，不依赖最终 UI。SQLite v2 已覆盖：

- 游客和登录用户共用同一套本地数据模型，`userId` 允许为空。
- 菜谱、食材、步骤、分类和菜谱分类关系使用关系表保存。
- 菜谱聚合支持新增、读取、更新、列表、搜索、收藏筛选、软删除、恢复和永久删除。
- 分类支持新增/更新、排序读取和软删除。
- 写入菜谱聚合时，主表、食材、步骤和分类关系处于同一事务。
- 导入任务支持持久化、状态筛选、可恢复任务查询、软删除和永久删除。
- 使用稳定字符串 ID；上层应传入 UUID，不使用 SQLite 自增 ID 作为同步身份。

当前仍不实现标签、来源快照、购物清单、云同步、冲突解决和全文索引。这些能力通过后续数据库迁移加入。

## 2. 代码边界

```text
lib/domain/recipe/
  菜谱领域模型与 Repository 契约

lib/domain/importing/
  导入任务状态机与 Repository 契约

lib/application/importing/
  导入任务用例，不依赖 SQLite

lib/data/local/app_database.dart
  SQLite 打开、外键配置、Schema 版本、建表与迁移

lib/data/sqlite_recipe_repository.dart
lib/data/sqlite_import_task_repository.dart
  SQLite Repository、事务和行映射
```

Presentation 和页面不得直接执行 SQL。Application 只依赖领域 Repository。

## 3. Schema v2

### 菜谱聚合表（Schema v1 建立）

- `recipes`：菜谱基础字段、状态、收藏、时间、稳定 ID、本地版本和软删除时间。
- `ingredients`：通过 `recipe_id` 关联菜谱并使用 `ON DELETE CASCADE`；数量保留为文本。
- `recipe_steps`：通过 `recipe_id` 关联菜谱并使用 `ON DELETE CASCADE`；`(recipe_id, step_number)` 唯一。
- `recipe_categories`：分类名称、封面、排序、本地版本和软删除时间。
- `recipe_category_relations`：使用 `(recipe_id, category_id)` 复合主键，并对两侧启用外键。

### `import_tasks`（Schema v2 新增）

保存链接来源、生命周期、处理阶段、进度、重试、统一错误、结果逻辑引用、时间、本地版本和软删除时间。

`result_recipe_id` 是导入任务到菜谱聚合的逻辑引用，首版不建立 SQLite 外键。原因是数据库级 `ON DELETE SET NULL` 会破坏 `needsReview/completed` 必须包含结果菜谱 ID 的领域不变量；删除语义和一致性由后续 Application 用例显式维护。

任务表禁止保存 API Key、Cookie、完整 Provider 请求或原始敏感响应。

## 4. 关键不变量

- 菜谱名称、食材名称和步骤说明不能为空。
- 份量和时间不能为负数；置信度只能在 `0..1`。
- 同一菜谱内食材 ID、步骤 ID、步骤序号和分类 ID 不得重复。
- 菜谱聚合任意子项写入失败时，整次保存回滚。
- 导入任务状态与阶段必须一致，进度和处理阶段只能单调推进。
- `needsReview` 与 `completed` 导入任务必须包含 `resultRecipeId`。
- 默认查询不返回软删除实体；回收站流程必须显式使用 `includeDeleted`。
- 删除分类会移除现有菜谱分类关系，不删除菜谱。

## 5. Repository 契约

`RecipeRepository`：

- `upsertRecipe`
- `getRecipeById`
- `listRecipes`
- `softDeleteRecipe`
- `restoreRecipe`
- `permanentlyDeleteRecipe`

`RecipeCategoryRepository`：

- `upsertCategory`
- `listCategories`
- `softDeleteCategory`

`ImportTaskRepository`：

- `upsertTask`
- `getTaskById`
- `listTasks`
- `listRecoverableTasks`
- `softDeleteTask`
- `permanentlyDeleteTask`

当前菜谱搜索覆盖菜名、简介、备注和食材名；正式搜索阶段再评估 SQLite FTS。

## 6. 数据库版本与迁移

- 当前 `schemaVersion = 2`。
- 新安装直接创建菜谱表、导入任务表和全部索引。
- v1 → v2 只新增 `import_tasks` 及索引，不修改或删除旧菜谱数据。
- 所有后续 Schema 修改必须提升版本号并提供可重复验证的迁移路径。
- 迁移测试至少覆盖旧库升级、数据保留、升级后新表可写和 `PRAGMA user_version`。
- 禁止在正式数据上通过删除数据库代替迁移。

## 7. 验证

自动化测试使用 `sqflite_common_ffi` 和真实 SQLite 临时文件，覆盖：

1. 菜谱关闭数据库并重新打开后的完整持久化。
2. 菜谱更新、搜索、收藏筛选、软删除、恢复和永久删除。
3. 无效分类关系触发外键错误并回滚整个菜谱。
4. 导入任务关闭重开后保留失败、重试和时间字段。
5. 可恢复任务筛选、状态筛选、软删除排除和永久删除。
6. Schema v1 → v2 后旧菜谱保留、`import_tasks` 可写且数据库版本为 2。

验收记录：

- `tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`
- `tests/acceptance/IMPORT-001-import-task-state-machine-2026-07-28.md`