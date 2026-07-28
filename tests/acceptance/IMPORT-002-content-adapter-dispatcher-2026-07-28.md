# IMPORT-002 内容 Adapter 与单执行器调度验收

- 日期：2026-07-28
- 任务：`IMPORT-002`
- 当前结果：通过
- 工程：`code/apps/mobile`

## 验收范围

验证平台 Adapter 注册表、统一内容模型、导入 Runner、稳定错误映射、取消与重试，以及进程内单执行器 Dispatcher。真实平台 HTTP 获取、OCR、ASR、LLM 调用和 UI 不在本次范围内。

## 验收结果

1. 统一内容拒绝空内容、非 HTTP(S) URL、非法媒体尺寸和负顺序。
2. 文本、媒体按来源顺序归一化，警告自动去重。
3. Adapter 注册表可按小红书/抖音平台分发，并拒绝重复平台注册。
4. Runner 可驱动 `fetching → extracting → OCR/ASR 可选阶段 → generating → needsReview`。
5. Adapter 与 Processor 稳定错误正确映射到 `ImportTaskErrorCode`。
6. 可重试错误使用 30 秒起步、最大 15 分钟的指数退避，并服从最大尝试次数。
7. 取消可落盘为 `cancelled`，批次取消后不会领取后续任务。
8. 未知异常被替换为通用消息，不保存原始异常敏感内容。
9. Dispatcher 按创建时间和 ID 串行执行，单任务失败不阻断后续任务。
10. 同一 Dispatcher 的并发批次被拒绝，`limit` 可限制领取数量。
11. 全量 Flutter 验证通过。

## 执行记录

```text
dart format lib test
Formatted 43 files (0 changed)

flutter analyze --no-pub
No issues found! (ran in 2.7s)

flutter test --no-pub
58 tests passed

git diff --check
passed
```

## 已知限制

- 尚未实现真实小红书/抖音公开页面获取和解析。
- 尚未实现人工粘贴文本、本地图片和本地视频降级接入。
- 尚未实现后台 Isolate、跨进程租约或服务端队列。
- 不持久化原始 HTML、Cookie、Authorization Header、API Key 或敏感完整响应。
- Windows 环境仍不能验证 iOS。
