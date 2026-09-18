# APP-004 Flutter 本地业务后端验收记录

> 验收日期：2026-07-30  
> 任务状态：`DONE`  
> 范围：Flutter 应用内部本地业务后端与前端接线契约；服务器端不在本次范围内。

## 1. 验收范围

本次验收确认 Flutter 页面所需的 P0 本地业务能力已经通过 Domain、Application、Repository、Facade 和设备组合根形成稳定调用链，数据由本地 SQLite/安全配置存储持久化。主要能力包括：

- 菜谱标签保存、去重与标签筛选。
- 菜谱和分类 CRUD、收藏、搜索、复制、回收站、批量恢复与永久删除。
- 首页聚合：最近浏览、分类计数、收藏摘要、未完成导入任务。
- 详情聚合：菜谱、有效分类、来源导入任务和最近浏览记录。
- 浏览历史与文本/图片/视频上传隐私设置。
- 烹饪会话、当前步骤和多个持久化计时器。
- LLM 设置的读取、保存、清除密钥和连接测试接线。
- OCR 本地模型状态、安装、删除和恢复接线。
- SQLite Schema v3 以及 v1/v2 → v3 迁移。
- `AiRecipeBackendFacade` 作为 Flutter UI 的统一业务入口。

## 2. 主要实现位置

- `code/apps/mobile/lib/application/backend/ai_recipe_backend_facade.dart`
- `code/apps/mobile/lib/app/ai_recipe_backend_composition_root.dart`
- `code/apps/mobile/lib/application/home/home_use_cases.dart`
- `code/apps/mobile/lib/application/recipe/recipe_detail_use_cases.dart`
- `code/apps/mobile/lib/application/recipe/recipe_library_use_cases.dart`
- `code/apps/mobile/lib/application/settings/local_app_settings_use_cases.dart`
- `code/apps/mobile/lib/application/cooking/cooking_use_cases.dart`
- `code/apps/mobile/lib/data/local/app_database.dart`
- `code/apps/mobile/lib/data/sqlite_recipe_repository.dart`
- `code/apps/mobile/lib/data/sqlite_recipe_activity_repository.dart`
- `code/apps/mobile/lib/data/sqlite_local_app_settings_repository.dart`
- `code/apps/mobile/lib/data/sqlite_cooking_repository.dart`

## 3. 数据与迁移验收

- 数据库版本为 Schema v3。
- v1 → v3、v2 → v3 迁移均保留菜谱、分类、食材、步骤、关系和导入任务数据。
- 新增活动记录、本地设置、烹饪会话和计时器表可正常创建与读写。
- 外键保持开启，菜谱永久删除后相关本地业务数据按契约级联清理。
- 关闭浏览历史时会立即清空历史，后续打开详情不再写入记录。
- 运行中的计时器使用绝对 `endsAt` 恢复，不依赖页面进程持续计数。

## 4. 质量门

使用 Flutter SDK：`D:\SofeWare\My\FlutterSDK\flutter`。

当前机器直接启动 Flutter CLI 可能受启动锁和 SDK 缓存权限影响，因此验收使用同一 SDK 的 `flutter_tools.snapshot` 入口，并为 `APPDATA`、`USERPROFILE` 使用仓库内隔离目录；没有结束现有 Dart/Flutter 进程。

已通过：

- `dart analyze`：无问题。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=4`：356 项全部通过。
- `test/application/cooking_use_cases_test.dart` 与 `test/data/app_database_v3_migration_test.dart`：10 项全部通过。
- `git diff --check`：通过。

## 5. 非目标与已知限制

本次不包含：

- 真实登录和服务端鉴权。
- 云同步、云存储和游客数据合并。
- 平台托管 AI/OCR/ASR、配额和服务器任务队列。
- 购物清单、导出/备份、周菜单、营养统计和家庭共享。
- 真实 PP-OCRv5 模型质量、完整 DB 后处理、方向分类器和 iOS Runtime；因此 `SPK-002` 不能标为完成。
- 真实第三方 LLM/公开平台内容的端到端兼容性矩阵。

## 6. 前端交接

下一任务为 `UI-001`。Flutter 页面应：

1. 以 `docs/architecture/FLUTTER_BUSINESS_BACKEND_COMPLETION.md` 的页面矩阵为接线依据。
2. 只调用 `AiRecipeBackendFacade` 或更窄的 Application 接口。
3. 不直接访问 SQLite、SharedPreferences、安全存储、Repository 或 Provider。
4. 以 `design/prototypes/` HTML 原型为视觉与交互输入，并覆盖正常、加载、空、错误和极限状态。
5. 对每个页面切片增加 Widget 测试，并保留本次本地业务后端回归测试。
