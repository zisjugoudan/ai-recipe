# APP-001 本地优先菜谱库后端用例验收

> 日期：2026-07-28
> 状态：通过
> 关联：`APP-001`、`US-003`、`US-009`

## 1. 验收目标

验证菜谱库 Domain、Application 与 Data 层已经形成可供 Flutter UI 直接依赖的稳定后端能力，不依赖登录、云端 AI、OCR/ASR Provider 或具体页面实现。

## 2. 功能验收

- [x] 游客可在没有 LLM、OCR/ASR 和云端服务时创建本地菜谱草稿。
- [x] Application 生成菜谱、食材和步骤 ID，UI 不负责生成领域 ID。
- [x] 更新保留菜谱 ID、`createdAt`、`userId`、`sourceId`，并增加 `localVersion`。
- [x] 更新保留合法子项 ID，并拒绝不属于当前菜谱的食材或步骤 ID。
- [x] 可读取菜谱详情，并将不存在或已删除实体映射为稳定 not-found 异常。
- [x] 菜谱列表支持关键词、收藏、状态、分类和删除范围筛选。
- [x] 可设置或取消收藏。
- [x] 菜谱支持软删除、恢复和永久删除，永久删除仅允许回收站实体。
- [x] 分类支持创建、读取、更新和稳定排序。
- [x] 分类支持软删除、恢复和永久删除，永久删除仅允许回收站实体。
- [x] 删除分类只移除菜谱分类关系，不删除菜谱；恢复分类不自动恢复历史关系。
- [x] 缺失分类和已删除分类在写入菜谱前被拒绝。
- [x] Repository 未知错误不会向 UI 暴露 SQL、路径或其他内部细节。

## 3. 持久化验收

- [x] 使用真实 SQLite 临时文件创建游客分类和菜谱聚合。
- [x] 关闭并重新打开数据库后，完整字段、食材、步骤、分类关系和 `userId == null` 保持不变。
- [x] Unicode 中文内容重开后不损坏。
- [x] SQLite 查询支持状态与分类筛选。
- [x] 分类恢复和永久删除行为可重复验证。

## 4. 质量命令

```powershell
cd C:\tmp\ai-recipe-mobile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

附加检查：

```powershell
git diff --check
```

## 5. 验收结果

- `dart format lib test`：86 个 Dart 文件已检查，无待格式化文件。
- `flutter analyze --no-pub`：通过，0 个问题。
- `flutter test --no-pub`：通过，共 176 项测试。
- APP-001 定向 Application 测试：11 项通过。
- APP-001 SQLite 集成测试：2 项通过。
- SQLite Recipe Repository 定向测试：8 项通过。
- `git diff --check`：通过。
- Dart 新增文件为 UTF-8 无 BOM + LF；Markdown 为 UTF-8 BOM + LF。
- APP-001 相关文件未发现 API Key、Authorization、Bearer、完整 Prompt/模型响应或本地绝对媒体路径。

结论：`APP-001` 验收通过，可以作为后续 Flutter 页面、游客模式和云同步层的稳定本地菜谱库边界。
