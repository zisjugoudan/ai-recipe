# 菜谱库 Application 架构

> 任务：`APP-001`
> 状态：完成
> 最后更新：2026-07-28

## 1. 目标

在 Flutter UI 与本地 SQLite 之间建立稳定的 Application 边界。页面和状态管理只能依赖 `RecipeLibraryUseCases`，不得直接访问 SQLite、HTTP Client、LLM、OCR、ASR 或供应商 SDK。

```text
Flutter Page / State
        ↓
RecipeLibraryUseCases
        ↓
RecipeRepository + RecipeCategoryRepository
        ↓
SQLite / 后续云端同步实现
```

该边界首先保证游客在 `userId == null` 时可以完整使用本地菜谱库，并为后续登录后的云同步保留相同领域模型和 Repository 契约。

## 2. 范围

- 手动创建、读取、更新和查询菜谱。
- 收藏、状态、分类、关键词和回收站范围筛选。
- 菜谱软删除、恢复和永久删除。
- 分类创建、读取、更新、排序、软删除、恢复和永久删除。
- 分类删除时移除菜谱与分类的关系，但不删除菜谱。
- SQLite 关闭并重新打开后完整聚合仍可读取。
- Repository 原始异常统一映射为稳定的 Application 异常。

## 3. 非目标

- Flutter 页面、状态管理和视觉设计。
- 登录、账号、云同步和冲突解决。
- 标签 Schema 与标签搜索。
- 分页、FTS 和大数据量性能优化。
- 真实 OCR、ASR、LLM Provider 或平台链接解析。

## 4. 输入模型

`RecipeDraftInput` 表示一次完整表单快照，不是字段级 Patch。调用更新时，未出现在输入中的旧食材、步骤或分类关系会被移除。

### 4.1 菜谱更新规则

- 创建时由 Application 生成菜谱、食材和步骤 ID。
- 更新时已有食材或步骤可携带原 ID；新子项不携带 ID，由 Application 生成。
- 更新拒绝任何不属于当前菜谱的食材或步骤 ID。
- 食材 `sortOrder` 按输入列表从 0 重新编号。
- 步骤 `stepNumber` 按输入列表从 1 重新编号。
- 更新保留 `id`、`createdAt`、`userId` 和 `sourceId`。
- 每次实际写入将 `localVersion` 增加 1。
- 标题必须非空；草稿允许暂时没有食材或步骤。
- 分类 ID 去空白、禁止重复，并且必须指向未删除分类。

### 4.2 分类规则

- 分类名称必须非空，排序值不得小于 0。
- 分类列表按 `sortOrder`、名称、ID 稳定排序。
- 软删除分类时删除全部菜谱分类关系。
- 恢复分类不会自动恢复历史关系，用户需要重新分配。
- 永久删除只能对已经进入回收站的分类执行。

## 5. Application API

`RecipeLibraryUseCases` 提供：

```text
createRecipe
updateRecipe
getRecipe
listRecipes
setRecipeFavorite
softDeleteRecipe
restoreRecipe
permanentlyDeleteRecipe

createCategory
updateCategory
getCategory
listCategories
softDeleteCategory
restoreCategory
permanentlyDeleteCategory
```

删除范围使用：

```dart
enum RecipeLibraryDeletionFilter {
  activeOnly,
  includeDeleted,
  deletedOnly,
}
```

## 6. 稳定错误

UI 只处理以下 Application 异常，不依赖 SQLite 或供应商内部错误：

- `RecipeNotFoundException`
- `RecipeCategoryNotFoundException`
- `RecipeCategoryUnavailableException`
- `RecipeLibraryValidationException`
- `RecipeLibraryIdGenerationException`
- `RecipeLibraryStorageException`

`RecipeLibraryStorageException` 不得暴露 SQL、数据库路径、API Key、Authorization、Prompt、模型响应、OCR/ASR 全文或本地媒体路径。

## 7. Repository 契约

`RecipeRepository.listRecipes` 支持：

- `query`
- `favorite`
- `status`
- `categoryId`
- `includeDeleted`

`RecipeCategoryRepository` 支持分类详情、列表、Upsert、软删除、恢复和永久删除。

当前 `deletedOnly` 由 Application 读取包含已删除数据的集合后过滤。数据量扩大后可增加 Repository 原生删除范围参数，但不得改变现有 UI 契约。

## 8. 游客与登录用户

- 游客创建的菜谱和分类使用 `userId == null`，全部功能保存在本地 SQLite。
- 登录用户后续可以传入 `userId`，但本任务不实现认证、上传或冲突合并。
- AI 服务是否可用不影响手动菜谱库；游客即使没有云端 AI，也必须可以手动创建和维护菜谱。

## 9. 验证策略

### 9.1 Application 单元测试

使用内存 Repository 验证：

- ID 生成、字段标准化与完整快照更新。
- 子项 ID 所属校验。
- 分类可用性校验。
- 搜索、收藏、状态、分类和回收站筛选。
- 菜谱与分类完整回收站生命周期。
- Repository 未知异常脱敏。

### 9.2 SQLite 集成测试

使用 `sqflite_common_ffi` 和真实临时数据库验证：

- 游客聚合关闭数据库并重开后仍完整存在。
- Unicode 菜名、食材、步骤和分类不损坏。
- Application 筛选与 SQLite 查询结果一致。
- 分类删除清理关系，恢复不恢复旧关系。
- 分类和菜谱永久删除规则有效。

## 10. UI 接入约束

后续 Flutter 页面只能注入并调用 `RecipeLibraryUseCases`：

- 不得 import `sqflite`。
- 不得直接实例化 `SqliteRecipeRepository`。
- 不得自行生成领域实体 ID。
- 不得根据 SQLite 错误字符串决定 UI 行为。
- 不得绕过 Application 直接修改 `localVersion`、删除状态或分类关系。

## 11. 实施结果

- `RecipeLibraryUseCases` 已成为菜谱库唯一 Application Facade。
- 内存 Repository 单元测试覆盖输入校验、ID 生成、完整快照更新、筛选、回收站和稳定错误。
- 真实 SQLite 集成测试覆盖游客聚合重开、Unicode、分类关系和查询筛选。
- 2026-07-28 最终验证：`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 176 项通过，`git diff --check` 通过。
