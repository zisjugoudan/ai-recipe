# 结构化菜谱生成 Processor

> 任务：`AI-002`、`AI-003`
> 状态：Processor 已完成；唯一 JSON 提取与第三方兼容响应加固实施中
> 最后更新：2026-08-02

## 1. 目标

把已经获取到的公开页面文字或人工粘贴文字转换为可编辑的本地菜谱草稿：

```text
ImportContent
→ 受限 Prompt
→ LlmProvider
→ JSON 提取
→ Recipe Schema 校验
→ 本地字段生成
→ RecipeRepository
→ ImportRecipeDraftResult
```

生成结果只进入 `RecipeStatus.draft` 和导入任务的“待确认”状态，不直接发布，也不覆盖已有菜谱。

## 2. 实现范围

- 使用 `ImportContent.title`、`description` 和 `textFragments` 作为模型输入。
- 支持 OpenAI-compatible 与 Gemini native 共用现有 `LlmProvider`。
- 支持纯 JSON、单个 Markdown fenced JSON，以及 `AI-003` 允许列表中的受控包装响应。
- 严格校验 `docs/api/recipe-generation.schema.json`。
- 本地生成菜谱、食材、步骤 ID、时间戳、状态和版本。
- 将草稿写入 `RecipeRepository`，返回菜谱 ID。
- 对取消、网络、超时、LLM、Schema 和存储失败使用稳定错误码。

## 3. 非目标

- 本任务不实现图片 OCR、视频 ASR 或媒体下载；只有媒体而无可用正文时必须失败并指向后续能力。
- 不允许模型设置用户、分类、收藏、发布状态、删除状态、版本或时间戳。
- 不在日志中记录 API Key、Authorization、完整 Prompt 或完整模型响应。
- 不自动接受和发布 AI 结果。

## 4. 输入安全

- 页面文字属于不可信数据，放在 user message 的 JSON 数据块中。
- system message 明确要求忽略来源内容中的指令，只提取食谱事实。
- 单次输入文字最多保留 40,000 个 Unicode code unit，超出部分按稳定顺序截断。
- 不把 API Key、连接配置、内部错误或其他本地数据拼入 Prompt。
- 菜谱标题只用于辅助识别，不视为 OCR/ASR 提取出的正文。
- `description` 和非标题类 `textFragments` 才计入 substantive text。
- 当内容标记 `requiresOcr` 或 `requiresAsr` 且没有 substantive text 时，不调用 LLM，分别返回 `ocrFailed` 或 `asrFailed`，避免仅根据标题幻觉生成完整菜谱。
- 完全没有可用文本时同样不调用 LLM。

## 5. 输出契约

模型只能返回 Schema 允许的字段。最小必填字段为：

- `schemaVersion = 1`
- 非空 `title`
- 至少一个非空名称的 `ingredients`
- 至少一个非空描述的 `steps`

置信度必须位于 `0..1`。时长、份量和时间必须是非负整数并受 Schema 上限约束。步骤编号、排序和所有 ID 不信任模型输出，由本地按数组顺序生成。
### 5.1 `AI-003` / `BUG-003` 响应规范化边界

Schema 校验前只允许执行“安全唯一 JSON 载荷提取”，用于兼容第三方 OpenAI-compatible 模型在正确 JSON 外包裹简短说明的常见行为。该层只负责确定唯一对象边界，不修复 JSON、不补字段、不放宽菜谱 Schema。

处理顺序固定为：

1. 先拒绝空响应和超过字符上限的响应。
2. 允许最终 JSON 之前存在一个完整闭合的 `<think>...</think>` 前缀；推理内容受独立大小限制，标签不得重复、嵌套或缺失闭合。
3. 在剩余文本中按字符扫描 JSON 字符串、反斜杠转义与 `{}` 层级，提取唯一一个完整顶层 JSON 对象；JSON 字符串内部的花括号和转义引号不得改变对象边界。
4. 允许唯一对象前后存在普通说明文字，也允许对象位于唯一一个空语言或 `json` Markdown fence 中。
5. 出现第二个完整或未闭合对象、第二组 fence、单个未闭合 fence、对象花括号不平衡或无法确定唯一对象时必须拒绝。
6. 提取出的对象仍由 `jsonDecode` 完整消费，并继续执行根对象、食材对象、步骤对象的未知字段拒绝、必填字段、类型、范围、数组长度和领域模型校验。
7. OpenAI-compatible Provider 若报告 `finish_reason = length`，或 `message.content` 为空白，必须在进入 Schema Parser 前映射为稳定的 `invalidResponse`，不得把截断内容误报为普通字段错误。

必须拒绝并映射为稳定错误的情况包括：

- 多个 JSON 对象、多个 fenced 块或无法唯一确定最终对象的内容。
- 未闭合、重复或嵌套的推理标签。
- 截断 JSON、对象花括号不平衡、语法错误 JSON、超大响应。
- 缺字段、未知字段、错误类型、越界值和模型试图设置本地字段。

兼容层不得使用“第一个 `{` 到最后一个 `}`”的贪婪截取，不得写日志保存原始响应，也不得在异常中拼接响应片段。Prompt、API Key、Authorization 和完整模型响应继续遵守既有脱敏规则。
## 6. 本地字段规则

| Recipe 字段 | 来源 |
|---|---|
| `id` | 注入的 ID Generator |
| `status` | 强制 `draft` |
| `sourceId` | `ImportContent.source.normalizedUrl` |
| `coverImage` | 第一张具有远程 URL 的图片，可空 |
| `favorite` | `false` |
| `categoryIds` | 空列表，等待用户确认页选择 |
| `createdAt` / `updatedAt` | 注入时钟，同一时刻 |
| `localVersion` | `1` |
| 食材 `sortOrder` | 模型数组下标 |
| 步骤 `stepNumber` | 模型数组下标 + 1 |

## 7. 错误映射

| 条件 | ImportTaskErrorCode | 可重试 |
|---|---|---|
| LLM 未授权、限流、服务端、非法响应、未知 | `llmFailed` | 限流/服务端/未知为是，其余否 |
| LLM 网络错误 | `networkUnavailable` | 是 |
| LLM 超时 | `timeout` | 是 |
| 用户取消 | `cancelled` | 否 |
| JSON、字段、类型、范围或领域模型非法 | `schemaInvalid` | 否 |
| Repository 写入失败 | `storageFailure` | 是 |
| 只有待 OCR/ASR 媒体 | `ocrFailed` / `asrFailed` | 否 |

所有错误文案必须稳定、简短且脱敏，不回传完整模型响应。

## 8. 保存提交点、CAS 与取消语义

- Processor 在 `RecipeRepository.upsertRecipe` 前执行取消检查，减少无意义写入。
- 草稿保存成功只是 Recipe 聚合的提交点，不代表导入任务已经进入 `needsReview`；Runner 仍需使用读取时的 `localVersion` 原子提交任务结果。
- 如果 `needsReview` 提交前持久化取消已经获胜，Runner 返回取消结果，并调用安全草稿丢弃器清理迟到草稿。
- 如果失败处理开始前任务已经持久化为取消，后到的 Schema、网络、超时、Provider 或未知错误不得改写取消状态。
- 安全草稿丢弃器只删除结果 ID、来源匹配且仍为 `RecipeStatus.draft` 的菜谱；正式菜谱或被其他流程接管的数据不得删除。
- CAS 冲突后必须重新读取任务再决定取消、返回最新状态或报告冲突，不能依赖旧内存快照。

因此最终一致性规则是：任务取消优先；迟到草稿可补偿；已发布菜谱不可被补偿清理。

## 9. 扩展点

后续 OCR/ASR Processor 只需在进入本 Processor 前把识别文本补入统一内容模型，或通过组合式预处理器生成新的文本片段；菜谱生成 Schema 和 Repository 边界不变。

## 10. 验证结论

- Prompt、Schema Parser、Processor 和 Runner 集成测试通过。
- 标题-only + `requiresOcr` / `requiresAsr` 防幻觉测试通过。
- `AI-003` 覆盖纯 JSON、单一 JSON fence、受控短前言、完整闭合推理前缀和歧义包装拒绝；严格 Schema 和脱敏边界未放宽。
- 真实 OpenAI-compatible 纯文本服务已生成结构化草稿，进入 `needsReview` 并通过 SQLite 重开恢复。
- 取消优先于后到 Schema 错误或成功，迟到草稿补偿删除的 SQLite 集成测试通过。
- 相关定向测试 53 项全部通过；`flutter analyze --no-pub` 无问题；Flutter 全量测试 475 项全部通过。
- Android 运行态取消入口的源码修复已完成；按项目负责人要求，本轮未运行新的分析、测试或 Android 构建，真实点击、迟到响应和重启持久化仍待人工验收。详见 `tests/acceptance/BUG-002-import-cancellation-race-2026-08-01.md`。
