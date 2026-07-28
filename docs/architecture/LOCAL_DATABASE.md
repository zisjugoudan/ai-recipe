# Local-first 菜谱数据库契约

- 状态：v1 基线已实现
- 日期：2026-07-28
- 关联任务：`SPK-001`、`APP-001`
- 关联用户故事：`US-001`、`US-003`、`US-009`

## 1. 本轮范围

当前阶段优先实现领域层、数据层和 Provider，不依赖最终 UI。SQLite v1 负责以下最小闭环：

- 游客和登录用户共用同一套本地数据模型，`userId` 允许为空。
- 菜谱、食材、步骤、分类和菜谱分类关系使用关系表保存。
- 菜谱聚合支持新增、读取、更新、列表、搜索、收藏筛选、软删除、恢复和永久删除。
- 分类支持新增/更新、排序读取和软删除。
- 写入菜谱聚合时，主表、食材、步骤和分类关系必须处于同一事务。
- 使用稳定字符串 ID；上层应传入 UUID，不使用 SQLite 自增 ID 作为同步身份。

本轮不实现标签、来源快照、导入任务、购物清单、云同步、冲突解决和全文索引。这些能力通过后续数据库迁移加入。

## 2. 代码边界

```text
lib/domain/recipe/recipe.dart
  纯 Dart 领域模型和字段校验

lib/domain/recipe/recipe_repository.dart
  Repository 契约，不依赖 SQLite

lib/data/local/app_database.dart
  SQLite 打开、外键配置、Schema 版本和建表

lib/data/sqlite_recipe_repository.dart
  SQLite Repository、事务和行映射
```

Presentation 和页面不得直接执行 SQL。后续 Application 用例只依赖 `RecipeRepository` 与 `RecipeCategoryRepository`。

## 3. Schema v1

### `recipes`

保存菜谱基础字段、状态、收藏、时间、稳定 ID、本地版本和软删除时间。

### `ingredients`

通过 `recipe_id` 关联菜谱，使用 `ON DELETE CASCADE`。数量保留为文本，以支持“适量”“半勺”等非标准表达；替代食材暂存为 JSON 数组，其余字段保持结构化。

### `recipe_steps`

通过 `recipe_id` 关联菜谱，使用 `ON DELETE CASCADE`。`(recipe_id, step_number)` 唯一，防止同一菜谱出现重复步骤序号。

### `recipe_categories`

保存分类名称、封面、排序、本地版本和软删除时间。

### `recipe_category_relations`

使用 `(recipe_id, category_id)` 复合主键，并对两侧启用外键。不存在的分类不能被静默关联。

## 4. 关键不变量

- 菜谱名称、食材名称和步骤说明不能为空。
- 份量和时间不能为负数。
- 置信度只能在 `0..1`。
- 同一菜谱内食材 ID、步骤 ID、步骤序号和分类 ID 不得重复。
- 更新时间不能早于创建时间。
- 菜谱聚合任意子项写入失败时，整次保存回滚。
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

当前搜索覆盖菜名、简介、备注和食材名；正式搜索阶段再评估 SQLite FTS。

## 6. 数据库版本与迁移

- 当前 `schemaVersion = 1`。
- 所有后续 Schema 修改必须提升版本号并提供可重复验证的迁移路径。
- 迁移测试必须至少覆盖：旧库升级、数据保留、失败回滚和重复打开。
- 禁止在正式数据上通过删除数据库代替迁移。

## 7. 验证

自动化测试使用 `sqflite_common_ffi` 和真实 SQLite 临时文件，覆盖：

1. 关闭数据库并重新打开后仍能读取完整菜谱。
2. 更新菜谱时正确替换食材和步骤。
3. 无效分类关系触发外键错误并回滚整个菜谱。
4. 按食材搜索和收藏筛选。
5. 菜谱软删除、恢复和永久删除。
6. 分类排序和分类删除后的关系清理。

验收记录：`tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`。
