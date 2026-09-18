# 应用后端组合根与主功能统一门面

> 任务：`APP-003`
> 状态：已完成
> 最后更新：2026-08-02

## 1. 目标

将已经完成的会话与能力策略、菜谱库、导入任务状态机、公开内容 Adapter、OCR/ASR 预处理和 LLM 菜谱生成组合为少量稳定的 Application 入口。Flutter 页面和状态管理不得自行读取 SQLite、拼装 Provider、读取 API Key 或直接驱动导入状态机。

```text
Flutter Page / State
        ↓
AiRecipeBackendFacade
        ├── AppAccessUseCases
        ├── RecipeLibraryUseCases
        └── Import Workflow
                ↓
       ImportTaskRunnerFactory
                ↓
公开内容 Adapter → 可选 OCR → 可选 ASR → LLM → 菜谱草稿
```

## 2. 范围

- 统一暴露会话、能力快照和菜谱库用例。
- 创建、读取、筛选、运行、批量调度、取消、重试和恢复导入任务。
- 读取导入任务对应的待确认菜谱草稿。
- 确认草稿时允许提交用户编辑后的完整快照，并将菜谱状态改为已发布。
- 放弃草稿时将草稿移入回收站并取消导入任务。
- 通过导入执行计划选择自定义/托管 LLM、本地/云 OCR、托管 ASR。
- Provider 选择必须先通过 `AppAccessUseCases.requireCapability`。
- 建立设备端组合根，集中创建 SQLite Repository、会话 Repository、公开内容 Adapter 和自定义 LLM Runner。
- 设备运行时能力根据本地 LLM 配置、插件安装状态及未来云端状态统一计算。

## 3. 非目标

- Flutter 页面、路由、状态管理和视觉设计。
- 真实登录协议、Token 安全仓库、游客数据自动上传和云同步。
- 平台托管 LLM、云 OCR、托管 ASR 的真实 HTTP 实现。
- PaddleOCR/ONNX Runtime 原生桥接、模型下载和真机性能验证。
- 登录、验证码、签名、访问控制或反爬绕过。
- 用事务重写现有跨聚合确认流程；本任务通过幂等检查保证失败后可安全重试。

## 4. 统一门面

`AiRecipeBackendFacade` 持有并暴露：

```text
access
recipes
loadSession
loadCapabilities
createImportTask
getImportTask
listImportTasks
runImportTask
runImportWithPastedText
runImportWithLocalImage
dispatchPendingImports
cancelImportTask
retryImportTask
recoverInterruptedImports
getImportDraft
confirmImportDraft
discardImportDraft
```

页面可以直接使用 `access` 和 `recipes` 的既有稳定 API，但不能取得内部 Repository、HTTP Transport、LLM Provider 或 API Key。

## 5. 导入执行计划

```dart
enum ImportLlmRoute { custom, managed }
enum ImportOcrRoute { disabled, local, cloud }
enum ImportAsrRoute { disabled, managed }
```

默认计划为：

- 自定义 LLM。
- OCR 禁用；当内容确实需要 OCR 时返回现有稳定 `ocrFailed`，页面可引导安装插件或选择其他路线。
- ASR 禁用；当内容确实需要 ASR 时返回现有稳定 `asrFailed`，游客可使用粘贴文本或本地媒体降级，登录用户未来可选择托管 ASR。

能力映射：

| 路线 | 所需能力 |
|---|---|
| 公开 URL | `publicContentImport` |
| 自定义 LLM | `customLlm` |
| 托管 LLM | `managedLlm` |
| 本地 OCR | `localOcr` |
| 云 OCR | `cloudOcr` |
| 托管 ASR | `managedAsr` |

能力校验不能依赖 UI 是否隐藏按钮；所有执行入口必须再次校验。
本地图片降级入口 `runImportWithLocalImage` 仅用于失败或已取消任务，接受应用可读取的本地图片资源标识和可选 MIME，强制装配 `ImportOcrRoute.local`，然后复用统一 OCR → LLM → 草稿流水线。它不会切换到云 OCR，也不会把本地绝对路径写入错误消息或业务日志。云图片处理未来必须使用独立入口并显式执行上传隐私校验。

## 6. Provider 与秘密边界

- `LlmConfigRepository` 是读取自定义 LLM 配置和 API Key 的唯一入口。
- API Key 只在 Runner 创建与 Provider 调用期间存在于内存，不作为 Facade 字段、返回值或日志字段公开。
- `ImportTaskRunnerFactory` 是 Application 对 Provider 装配的抽象边界。
- 设备实现支持 OpenAI-compatible 与 Gemini 自定义 LLM；托管能力通过可注入 Builder 保留扩展点。
- OCR/ASR Provider 通过可注入绑定加入处理链；没有绑定时必须返回稳定不可用错误，不能静默跳过用户明确选择的能力。

## 7. 草稿确认与放弃

### 7.1 读取

只有 `needsReview` 或 `completed` 且带有 `resultRecipeId` 的任务可以读取关联菜谱。缺失任务、缺失草稿或状态不允许时返回稳定 Application 错误。

### 7.2 确认

1. 校验任务处于 `needsReview`。
2. 读取持久化草稿。
3. 如果页面提交了编辑快照，保存完整快照；否则保存当前草稿。
4. 强制将菜谱状态改为 `published`。
5. 将任务推进到 `completed`。

如果菜谱已经发布而任务仍是 `needsReview`，重试确认时跳过重复菜谱写入，只完成任务，避免无意义增加本地版本。

### 7.3 放弃

1. 校验任务处于 `needsReview`。
2. 将关联草稿软删除；已经在回收站时视为已完成该步骤。
3. 取消导入任务并清除其草稿逻辑引用。

已完成任务不能放弃。放弃不永久删除草稿，用户仍可从菜谱回收站恢复。

### 7.4 结束失败导入

`cancelImportTask(taskId)` 同时承担运行态取消和失败任务主动结束：

1. `queued`、`running` 和 `needsReview` 继续按既有取消/放弃契约处理。
2. `failed` 允许用户在查看真实错误后主动结束；Facade 复用原任务 ID，将状态持久化为 `cancelled`。
3. 结束操作保留失败任务记录和原诊断信息，不删除任务，不创建替代任务、草稿或正式菜谱。
4. `failed` 在结束前继续计入未完成；`cancelled` 不计入未完成，数据库重开后结果必须保持。
5. 可重试的 `failed` 继续保留 `retryImportTask()` 入口；主动结束与重试由用户明确选择。
6. 未完成任务查询不得通过过滤 `failed` 来掩盖问题。

## 8. 稳定错误

统一门面新增错误只表达页面可处理的业务问题：

- 导入任务或草稿不存在。
- 当前任务状态不允许执行该动作。
- 请求的 Provider 路线没有实现或没有绑定。
- 配置、运行时能力或存储不可用。

错误消息不得包含 SQL、数据库路径、API Key、Authorization、完整 Prompt、完整模型响应、完整 OCR/ASR 文本或本地媒体绝对路径。

### 8.1 导入启动前异常边界

`runImportTask()` 的能力校验、会话读取、Runner 创建与 Runner 执行必须处于同一个 Facade 异常映射边界内。任何步骤在任务进入 `running/fetching` 前失败，都必须返回页面可处理的 `AiRecipeBackendException`，不能以未知异常穿透到进度页。

稳定映射至少覆盖：

- 自定义 LLM 未配置：引导用户到 LLM 设置页配置并保存自有 AI 服务。
- 自定义 LLM 配置不可读：提示检查 LLM 设置后重试。
- 网络不可用：提示检查网络与 LLM 设置。
- 会话或导入设置读取失败：返回存储不可用错误。
- 能力状态读取失败：返回能力暂时无法确认错误。
- Runner 路线未绑定或 Provider 配置不可用：保留 `providerRouteUnavailable` 业务错误。

当任务已经持久化为 `failed` 且包含非空 `errorMessage` 时，交互层必须优先展示任务错误；页面调用栈产生的通用异常只能作为无持久化错误时的兜底，不能与真实任务错误叠加或覆盖它。

## 9. 设备组合根

组合根是唯一允许实例化以下具体实现的位置：

- `AppDatabase`
- `SqliteRecipeRepository`
- `SqliteImportTaskRepository`
- `DeviceAppSessionRepository`
- `DeviceLlmConfigRepository`
- `HttpImportTransport`
- `XiaohongshuPublicContentAdapter`
- `DouyinPublicContentAdapter`
- `LlmProviderFactory`

组合根支持注入测试替身及未来本地 OCR、云 OCR、托管 ASR/LLM Builder。关闭组合根时必须关闭数据库；不负责清理用户配置、模型或菜谱。

## 10. 验收标准

- [x] 页面只需要一个 Facade 即可访问会话、菜谱和导入主链路。
- [x] 游客使用已配置自定义 LLM 可完成公开链接到草稿确认。
- [x] 自定义 LLM 未配置时在执行前被能力策略拒绝。
- [x] 本地 OCR、云 OCR、托管 ASR 和托管 LLM 路线分别校验正确能力。
- [x] 导入任务可以查询、取消、重试和重启恢复。
- [ ] Android 人工确认 failed 页面可通过“结束此导入”持久化为 cancelled，首页未完成数量减少，强停重启后不再恢复；Codex 不代测。
- [x] 草稿读取、确认、重复确认保护和放弃流程有自动化测试。
- [x] 当前登录用户生成的导入草稿带有对应 `userId`；游客保持 `userId == null`。
- [x] API Key 不进入 Facade 返回模型、日志、SharedPreferences 会话或 Git。
- [x] Fake 端到端测试覆盖 URL → Adapter → OCR/ASR（按需）→ LLM → 草稿 → 确认。
- [x] `flutter analyze --no-pub` 和 `flutter test --no-pub` 通过。
## 11. 实施与验证结果

- 已实现 `AiRecipeBackendFacade`、`ImportExecutionPlan`、`ImportTaskRunnerFactory`、设备运行时能力仓库和设备组合根。
- 已验证登录用户与游客的草稿归属、能力前置拒绝、Provider 未绑定错误、草稿确认/放弃和重复确认保护。
- 完整 OCR + ASR 链路发现过一次全局进度倒退：OCR 结束于 60%，ASR 原先从 35% 开始。现已将 ASR 区间固定为 61%–64%，保持 `extracting → OCR → ASR → LLM → review` 单调推进，并加入回归测试。
- `dart format lib test`：105 个文件，无额外格式变化。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub`：217 项全部通过；APP-003 与进度回归相关定向测试共 32 项通过。
- Windows 环境未验收 iOS；真实 PaddleOCR/ONNX Runtime、真实托管 OCR/ASR/LLM 和真实自定义 LLM 服务兼容性仍由后续 Spike 验证。