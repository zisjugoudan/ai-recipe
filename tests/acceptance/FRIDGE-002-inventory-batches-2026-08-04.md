# FRIDGE-002：冰箱库存批次管理

> 日期：2026-08-04
> 状态：`DOING`（代码与测试定义已完成，等待项目负责人构建 Android 复测）
> 平台：Android（iOS 未验证）
> 关联：FRIDGE-001、US-011、DESIGN-005、UI-014/015

## 1. 用户价值

像管理真实冰箱一样维护家中食材库存：按冷藏/冷冻/常温/其他分区存放同名多批次，支持数量、日期、临期/过期状态、筛选、用完/丢弃，全程本地离线可用。

## 2. 已实现

- **领域**：`InventoryBatch`（名称/数量/单位/分类/区域/购买与到期日/备注/状态）、`InventoryChange`、`InventorySummary`、`AggregatedInventoryItem`；派生状态 正常/临期(3 天)/已过期/未设置日期/数量未知。
- **存储**：SQLite v5 迁移 `inventory_batches` + `inventory_changes` + `SqliteInventoryRepository`；测试用内存仓库。
- **应用**：`InventoryLibraryUseCases`（新增/更新/用完/丢弃/删除/摘要/聚合）；Facade 方法 `listInventoryBatches/loadInventorySummary/loadAggregatedInventory/createInventoryBatch/updateInventoryBatch/useUpInventoryBatch/discardInventoryBatch/deleteInventoryBatch`。
- **UI**：底部导航改四栏「首页/菜谱库/冰箱/我的」；冰箱页库存视图：四项摘要、临期提醒、8 项筛选（全部/临期/已过期/数量未知/冷藏/冷冻/常温/其他）、四分区卡片（聚合食材 chip + 展开具体批次）、空冰箱与空分区引导、右下 FAB 添加食材；批次新增/编辑页（存放位置跟随分区、数量为空=数量未知不写 0、同名批次提示、未保存离开二次确认）。

## 3. Android 人工复测步骤

1. `flutter run` 真机，底部导航应出现 4 项（首页/菜谱库/冰箱/我的）。
2. 进入冰箱 → 空态 → 点「添加第一样食材」→ 填写名称/数量/单位/分类/存放位置/日期/备注 → 保存 → 列表显示对应分区。
3. 再添加一个同名食材（不同到期日）→ 同名食材 chip 显示"共 X · 2 批次"，点击展开可见两个批次。
4. 给食材设置 2 天内到期 → 显示"临期"徽标，顶部出现临期提醒；设置已过期日期 → "已过期"徽标。
5. 筛选：临期/已过期/数量未知/各分区 → 列表与分区正确过滤。
6. 展开批次 → 标记用完/丢弃 → 确认后从可用列表消失，摘要数字更新。
7. 数量留空保存 → 显示"数量未知"徽标，不显示 0。

## 4. 回传模板

```text
FRIDGE-002 Android 真机复测

1. 四栏导航是否出现冰箱：
2. 空态与添加流程是否正常：
3. 同名多批次聚合与展开是否正常：
4. 临期/过期/数量未知徽标与筛选是否正确：
5. 用完/丢弃及摘要更新是否正常：
6. 是否出现任何异常崩溃或英文错误：
```

## 5. 验证边界

Codex 不执行自动测试/构建/真机（ADR-0015）。等待项目负责人 Android 复测；iOS 未验证。
