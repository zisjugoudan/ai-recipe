# Flutter 本地业务后端完成清单

> 任务：`APP-004`  
> 状态：已完成（2026-07-30）  
> 目标：先完成 Flutter 应用内部的本地业务后端，服务器端能力继续暂缓；随后依据 `design/prototypes/` 的 HTML 原型实现 Flutter UI。

## 1. 目标

在不依赖服务器的前提下，为移动端 P0 页面提供稳定、可测试、可持久化的 Flutter Application/Facade API。页面不得直接访问 SQLite、SharedPreferences、安全存储或 Provider。

## 2. 范围与非目标

### 本任务范围

- 游客/外部已验证登录会话切换与能力查询。
- 菜谱、分类、收藏、标签、搜索、复制和回收站。
- 首页与菜谱详情聚合查询、最近浏览。
- 公开链接导入任务、导入历史和草稿确认。
- 自定义 LLM 配置的读取、保存、清除密钥和连接测试。
- 本地 OCR 模型状态与安装管理的 Facade 接线。
- 烹饪会话、当前步骤和多个持久化计时器。
- 本地隐私与历史记录设置。
- SQLite v1/v2 到 v3 的数据迁移与级联清理。
- 面向 Flutter UI 的统一 `AiRecipeBackendFacade` 和设备组合根。

### 非目标

- 真实登录、云同步、平台托管 AI/OCR/ASR 和服务器任务队列。
- P1/P2：购物清单、数据导出/云备份、周菜单、营养统计、家庭共享。
- OCR/ASR 的真实模型质量与 iOS Runtime 验收。
- Flutter 页面和视觉实现；本任务只提供前端接线契约。

## 3. UI 到业务后端矩阵

| UI 页面/功能 | Facade / Application 入口 | 完成情况 |
|---|---|---|
| 欢迎页 / 游客继续 | `loadSession`、`continueAsGuest`、`acceptVerifiedSession`、`signOut`、`loadCapabilities` | 已完成 |
| 首页 | `loadHome`：最近菜谱、分类计数、收藏、未完成导入一次聚合返回 | 已完成 |
| 菜谱库 | `listRecipes`、`createRecipe`、`updateRecipe`、`setRecipeFavorite`、标签筛选、复制 | 已完成 |
| 菜谱详情 | `openRecipeDetail`：详情、有效分类、来源导入任务；按设置记录最近浏览 | 已完成 |
| 编辑/手动创建 | `createRecipe`、`updateRecipe`、`copyRecipe` | 已完成 |
| 回收站 | `listRecipes` / `listCategories` 的删除筛选、恢复、永久删除、批量处理、清空 | 已完成 |
| 链接导入/进度/确认 | 既有导入任务、运行、取消、重试、恢复、草稿确认/放弃 | 已完成基线 |
| LLM 设置 | `loadLlmSettings`、`saveLlmSettings`、`testLlmConnection`、`clearLlmApiKey` | 已完成 |
| OCR 设置 | `getLocalOcrModelStatus`、安装、删除、恢复 | 已完成接线；真实模型验收另跟踪 |
| 隐私与上传设置 | `loadLocalSettings`、`saveLocalSettings`、`clearRecipeHistory` | 已完成 |
| 烹饪模式 | `startOrResumeCooking`、步骤切换、多个计时器、暂停/恢复/完成、结束会话 | 已完成 |

## 4. P0 完成标准

- [x] Recipe 支持标签并可按标签搜索，标签保存时去重且大小写不敏感筛选。
- [x] Facade 覆盖会话、菜谱、分类、导入、OCR、烹饪、本地设置和 LLM 设置；页面无需取得底层 Repository。
- [x] 首页一次聚合查询可获得最近菜谱、分类计数、收藏摘要和未完成导入。
- [x] 打开详情可按隐私设置记录最近浏览；关闭浏览历史时自动清空，且可手动清空。
- [x] 烹饪会话和多个计时器持久化到 SQLite，应用重启后恢复；运行计时器使用 `endsAt` 绝对截止时间计算剩余时间。
- [x] 本地隐私设置可表达是否允许上传图片、视频和文本。
- [x] SQLite Schema v1/v2 升级到 v3 不丢失菜谱、分类、食材、步骤、关系和导入任务数据。
- [x] 新增 Domain、Application、Repository、Facade、迁移和接线路径均有测试。
- [x] `dart analyze` 通过。
- [x] `flutter analyze --no-pub` 通过。
- [x] `flutter test --no-pub` 通过。
- [x] `git diff --check` 通过。

## 5. 前端接线原则

1. 页面只持有 `AiRecipeBackendFacade` 或更窄的 Application 接口。
2. UI 状态使用稳定领域状态/异常类型，不解析异常字符串。
3. API Key 只能作为保存/测试命令输入；读取配置时只返回 `hasStoredApiKey`，不回填明文。
4. 计时器使用 `endsAt` 推导剩余时间，不能依赖页面常驻的每秒自减值作为事实源。
5. 首页和详情使用聚合 DTO，避免页面串行读取多个 Repository 并自行拼装业务规则。
6. 游客可使用本地菜谱库和本地能力；登录状态仍只是本地已验证会话元数据，不代表已接入服务器。

## 6. 验收证据

验收记录：`tests/acceptance/APP-004-flutter-local-business-backend-2026-07-30.md`

2026-07-30 质量门：

- `dart analyze`：通过，无问题。
- `flutter analyze --no-pub`：通过，无问题。
- `flutter test --no-pub --concurrency=4`：356 项测试全部通过。
- 定向烹饪与 SQLite v3 迁移测试：10 项全部通过。
- `git diff --check`：通过。

Flutter CLI 直接入口在当前机器受启动锁/SDK 缓存权限影响；验收使用同一 Flutter SDK 的 `flutter_tools.snapshot` 直接入口，并显式设置隔离的 `APPDATA`、`USERPROFILE`，不结束现有 Dart/Flutter 进程。

## 7. 后续边界

APP-004 完成后，下一阶段可以开始将 `design/prototypes/` 的 HTML 原型逐页转为 Flutter 页面，并以本文件第 5 节作为接线约束。服务器端登录、云同步、云端 AI/OCR/ASR、配额和任务队列不因 APP-004 完成而自动进入实现范围。