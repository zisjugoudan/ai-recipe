# UI-001 导入失败人工降级切片验收记录

> 验收日期：2026-07-31  
> 任务状态：`DOING`  
> 范围：导入失败后的人工降级输入、链接导入入口接线和 Fake Provider 自动化链路；`UI-001` 尚未整体完成。

## 1. 验收范围

本切片落实 `tracking/BACKLOG.md` 中 `PROD-002` 的验收定义，目标是在小红书或抖音公开链接获取失败后，仍为用户提供真实、可操作且不会伪造能力的继续路径。

已覆盖：

- 失败或已取消任务显示“粘贴正文继续”“上传截图继续”“上传视频继续”“手动创建菜谱”四个人工降级入口。
- 可自动重试的失败继续显示“重新解析”；不可自动重试的失败不伪造重试能力。
- 粘贴正文跳过公开内容 Adapter，复用统一菜谱生成 Processor，并保留原任务 ID、链接、平台与尝试次数。
- 空正文、任务状态不合法、Provider 未配置及处理失败均使用稳定错误。
- Provider 不可用时不关闭输入表单，用户已粘贴正文仍保留。
- 图片选择器和真实视频 ASR 尚未接入时，截图/视频入口显示明确的不可用说明。
- 手动创建直接进入既有菜谱编辑页，不依赖 LLM、OCR 或 ASR。
- 添加页输入链接后通过 Facade 创建持久化 queued 任务，并把该任务交给导入进度页。

## 2. 非目标

本切片没有实现：

- 图片或视频媒体选择器。
- 真实视频 ASR Provider。
- 云端 OCR/ASR、平台托管 AI、服务器任务队列或配额。
- 跨设备恢复临时粘贴正文。
- 真实小红书/抖音样本与真实 LLM Provider 的质量验收。

## 3. Domain 与 Application 验收

### ImportTask

`ImportTask.startWithFallback()` 已验证：

- 只允许 `failed` 或 `cancelled` 状态进入人工降级。
- 保持任务 ID、来源链接、来源平台和既有 attempt。
- 状态进入 `running`，阶段进入 `extracting`，进度为 `0.25`。
- 清除终止错误、重试时间和旧结果。
- 人工降级处理被中断后，不会恢复成公开链接抓取队列。

### Use Case 与 Runner

`StartImportTaskWithFallback`、`ImportTaskRunner.runWithContent()` 已验证：

- fallback 启动状态会持久化。
- queued 等非终止状态会被拒绝，且仓库状态不被修改。
- 人工正文不调用公开 Adapter。
- 来源不匹配使用 `ImportContentAdapterException` / `invalidPayload`。
- Processor 请求 retry 时，人工降级不会自动转成公开链接重试。
- fallback 处理过程中仍可取消。

### Facade

`AiRecipeBackendFacade.runImportWithPastedText()` 已验证：

- 正文成功时任务进入 `needsReview`。
- 空正文映射为 `invalidInput`。
- 缺少 Provider 路由映射为 `providerRouteUnavailable`。
- queued 等不合法任务状态优先映射为 `invalidTaskState`，不会被错误描述为 Provider 不可用。
- 错误消息不包含用户正文或测试 API Key。

## 4. Flutter 页面接线验收

### ImportProgressPage

Widget 测试已覆盖：

- 失败和取消状态均显示四个人工降级入口。
- 空正文不会关闭 Bottom Sheet，并显示输入校验。
- Provider 不可用时正文保留，页面显示可操作的 AI 配置提示。
- Fake Provider 成功后打开 AI 草稿确认页。
- 截图和视频入口显示当前能力未接入的真实说明。
- 手动创建回调会被调用。
- 首屏外入口可滚动访问。

### AddRecipePage

新增入口接线测试，已覆盖：

1. 输入小红书链接并提交后，创建 queued 导入任务，来源平台为 Xiaohongshu，调用 `onOpenImportTask(task)` 和 `onDataChanged()`，并可从 Facade 重新读取任务。
2. 空链接不会创建任务，并显示输入校验。

页面仍只通过 `AiRecipeBackendFacade` / Application 接口接线，没有直接访问 SQLite、Repository、SharedPreferences、安全存储或 Provider。

## 5. 自动化测试

核心定向测试：

```text
test/domain/import_task_test.dart
test/application/import_task_use_cases_test.dart
test/application/import_task_runner_test.dart
test/application/ai_recipe_backend_facade_test.dart
test/features/import_progress_page_test.dart

52 项全部通过
```

添加页定向测试：

```text
test/features/add_recipe_page_test.dart

2 项全部通过
```

## 6. 质量门

```text
flutter analyze --no-pub
No issues found!

flutter test --no-pub --concurrency=4
425 项全部通过
```

本轮全量测试基线由 404 项提升至 425 项。

## 7. 平台验证状态

- Android：本切片的 Domain、Application、Facade 和 Flutter Widget 自动化均已通过；本轮未重新执行 Android APK 真机安装，也未使用真实 Provider 做端到端导入。
- iOS：当前 Windows 环境无法执行 iOS 构建与真机验证，状态仍为未验证。
- 跨平台结论：人工降级的 Dart/Flutter 业务逻辑已通过自动化；媒体选择、原生 OCR/ASR 和真实网络 Provider 仍需分别进行 Android/iOS 真机验收。

## 8. AI 质量验收边界

本轮只使用 Fake Provider 验证调用契约、状态流转、页面导航和错误脱敏，不能代表真实模型输出质量。

真实端到端 AI 质量验收未执行，原因是当前环境没有用户授权的：

- 真实 API 地址。
- 真实 API Key。
- 可写入质量日志的小红书或抖音公开测试样本。

因此本轮没有填写菜名、食材召回率、用量正确率、步骤正确性、低置信度有效性或人工修改数。待具备授权配置与样本后，必须按 `tests/ai-quality/AI_QUALITY_LOG.md` 追加真实 Case。

## 9. 已知限制与下一步

- “上传截图继续”尚未接入媒体选择器，不能执行真实 OCR。
- “上传视频继续”尚未接入媒体选择器和真实 ASR Provider。
- 真实 Provider、真实链接和真实样本的完整链路尚未验收。
- 服务器端登录、云同步和托管 AI/OCR/ASR 继续暂缓。
- `UI-001` 保持 `DOING`；下一步是使用用户授权的 Provider 与公开样本执行真实端到端验收，并继续核对剩余 P0 页面缺口。
