# AI-002 结构化菜谱生成 Processor 验收记录

- 日期：2026-07-28
- 状态：通过
- 任务：`AI-002`

## 验收范围

- [x] 已有文本构建受限 Prompt，来源文本按 40,000 字符上限稳定截断。
- [x] 页面文本被明确视为不可信数据，不可改变系统输出契约。
- [x] 支持纯 JSON 和单个 Markdown fenced JSON。
- [x] 严格校验必填字段、字段类型、长度、范围、数组数量和未知字段。
- [x] 本地生成 Recipe/Ingredient/Step ID、排序、状态、时间戳和版本。
- [x] 草稿以 `RecipeStatus.draft` 写入 Repository，并返回真实 Recipe ID。
- [x] 用户、分类、收藏、发布/删除状态和本地版本不能由模型指定。
- [x] LLM、网络、超时、取消、Schema 和存储失败映射为稳定错误。
- [x] 完整 Prompt、API Key 和完整模型响应不写日志或验收文件。
- [x] Runner 集成测试确认导入任务进入待确认且草稿已保存。
- [x] 标题-only 且需要 OCR/ASR 时不调用 LLM，避免根据标题幻觉生成菜谱。
- [x] Repository 保存成功后的取消不会把任务改写为 cancelled，草稿不会失去任务引用。
- [x] 真实 SQLite 文件关闭并重新打开后，Recipe、Ingredient 和 Step 草稿仍可读取。

## 自动化验证

```text
dart format lib test：通过
flutter analyze --no-pub：No issues found
flutter test --no-pub：113 项全部通过
```

覆盖内容包括 Prompt 构造、JSON 提取、严格 Schema、错误映射、取消、保存失败、Runner 状态迁移、提交点竞态和真实 SQLite 重开持久化。

## 已知限制

- 本轮不包含 OCR、ASR 和真实 LLM 服务兼容性验证。
- Windows 环境不验证 iOS。
