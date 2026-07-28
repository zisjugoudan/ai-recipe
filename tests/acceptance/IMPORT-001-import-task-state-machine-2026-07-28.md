# IMPORT-001 导入任务状态机验收记录

- 日期：2026-07-28
- 任务：`IMPORT-001`
- 当前结果：通过
- 工程：`code/apps/mobile`

## 验收范围

本记录验收导入任务的领域状态机、Application 用例、SQLite v2 持久化和 v1 → v2 迁移，不验收真实小红书/抖音解析、OCR、ASR、LLM、后台调度、系统分享或 UI。

## 验收结果

1. 小红书和抖音 HTTP(S) 链接可以创建排队任务；非法 URL 和不支持的平台被拒绝。
2. 任务可以按规则开始、单调推进、进入待确认并完成。
3. 阶段倒退、进度倒退、终态继续变更会失败。
4. 失败任务只有在允许重试且剩余次数足够时才能重试。
5. 取消幂等；待确认任务取消时清理草稿逻辑引用；已完成任务不能取消。
6. 应用重启后，遗留运行任务重新排队；达到次数上限时转为不可自动重试失败。
7. SQLite 关闭重开后任务字段完整保留。
8. 可恢复任务查询只返回未删除且符合调度条件的任务。
9. Schema v1 升级到 v2 后旧菜谱保留，`import_tasks` 可用，数据库版本为 2。
10. `result_recipe_id` 按跨聚合逻辑引用保存，不建立会破坏状态不变量的 SQLite 外键。
11. 格式化、静态分析和全部 Flutter 测试通过。

## 自动化验证

```text
dart format lib test
33 files checked, 0 files changed

flutter analyze --no-pub
No issues found

flutter test --no-pub
41 tests passed

git diff --check
passed
```

## 已知非目标

- 不向任务表写入 API Key、Cookie 或完整 Provider 请求。
- 不在本轮建立真实网络抓取或规避平台访问控制的实现。
- Windows 环境不验收 iOS 数据库行为。
- 调度器并发抢占和跨进程租约由后续任务单独设计。