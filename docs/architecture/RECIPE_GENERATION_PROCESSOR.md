# 结构化菜谱生成 Processor

> 任务：`AI-002`  
> 状态：已完成  
> 日期：2026-07-28

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
- 支持纯 JSON 和单个 Markdown fenced JSON 响应。
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

## 8. 保存提交点与取消语义

- 在调用 `RecipeRepository.upsertRecipe` 前进行最后一次取消检查。
- Repository 保存成功且 Processor 返回后，视为本次草稿生成的提交点。
- 提交点之后 Runner 不再把任务改写为 `cancelled`，而是继续进入 `needsReview`。
- 该规则保证不会出现“草稿已经持久化，但导入任务被取消并失去草稿引用”的孤立数据。

## 9. 扩展点

后续 OCR/ASR Processor 只需在进入本 Processor 前把识别文本补入统一内容模型，或通过组合式预处理器生成新的文本片段；菜谱生成 Schema 和 Repository 边界不变。

## 10. 验证结论

- Prompt、Schema Parser、Processor 和 Runner 集成测试通过。
- 标题-only + `requiresOcr` / `requiresAsr` 防幻觉测试通过。
- 保存完成后取消到达的提交点竞态测试通过。
- 真实 SQLite 文件关闭并重新打开后，Recipe、Ingredient 和 Step 草稿仍可读取。
- `flutter analyze --no-pub` 无问题。
- `flutter test --no-pub` 共 113 项测试通过。
