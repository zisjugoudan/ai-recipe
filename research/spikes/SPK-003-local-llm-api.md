# SPK-003：自定义 LLM API 多协议兼容性验证

- 状态：VERIFY
- 关联任务：SPK-003、AI-001、AI-003
- 关联风险：R-002、R-005、R-008、R-017
- 架构文档：`docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`
- 质量记录：`tests/ai-quality/AI_QUALITY_LOG.md`

## 问题

移动端只让用户选择协议并填写 API 地址、Key 和模型时，现有 Provider Adapter 能否稳定兼容 OpenAI-compatible、Gemini 以及未来其他协议，并对连接、结构化生成、取消、超时和错误反馈提供一致行为？

## 已确定方向

- 产品只有一种自定义 API 配置，不设置 LAN、VPN、HTTPS 等连接模式。
- 用户选择协议类型，填写 API 地址、Key 和模型；网络位置只是用户所填地址的属性。
- HTTP 地址显示风险警告，HTTPS 地址正常使用。
- OpenAI-compatible 与 Gemini 使用独立 Adapter。
- API Key 只进入 Keychain/Keystore；日志不记录 Key、Authorization、Prompt 全文或完整响应。
- 模型列表是可选能力。只支持手工填写模型名的兼容服务，只要连接和生成链路可用，不因缺少模型列表接口直接判定失败。

## 本轮可用测试条件

- 项目负责人已授权使用一个临时 OpenAI-compatible 服务进行 Android 验证；具体地址与 Key 仅在 App 运行时手工输入，不写入仓库、文档、命令、Fixture、截图或日志。
- 指定模型为纯语言模型，只用于文本连接与文本菜谱生成测试。
- 该模型不能直接理解图片或视频，因此本 Spike 不用它评价 OCR、图片理解、视频理解或 ASR 准确率。
- 可以验证的真实主链是“公开非隐私菜谱正文 → LLM → 严格结构化菜谱 → 草稿确认 → 本地保存”；OCR/ASR 只有在其他 Provider 已把媒体转换成文字后才可复用该 LLM。

## 成功标准

- Android 设置页能够保存非密钥配置、测试连接、清除密钥，并在 App 内完成一次真实文本菜谱生成。
- OpenAI-compatible 真实服务返回内容可通过现有严格 Schema；如带 Markdown fence、额外说明、推理文本或字段差异，必须记录真实响应形态和失败位置。
- 验证 URL 规范化、超时、取消、响应体上限和统一错误映射。
- 验证错误 Key、错误模型或路径的安全错误提示；401/403、404、429、模型不存在、非 JSON 和响应字段缺失可由真实服务与现有 Fixture 组合覆盖。
- 数据库、日志、截图、错误提示、导出与崩溃信息中不出现 API Key、Authorization、Prompt 全文或完整响应。
- 使用公开非隐私样本记录菜名、食材、用量、步骤、低置信度和保存前修改数，并写入 `tests/ai-quality/AI_QUALITY_LOG.md`。
- 给出“采用”“拒绝”或“继续研究”的结论；只有真实证据表明 Adapter 需要修改时才建立 AI-003。

## 测试矩阵

### A. 配置与连接

1. Android 设置页选择 OpenAI-compatible。
2. 运行时手工填写用户授权的临时 API 地址、Key 和模型名。
3. 执行最小连接测试，记录成功/失败、耗时、HTTP 状态分类和稳定错误码，但不记录请求头、完整请求或完整响应。
4. 返回设置页和重启 App，确认 API Key 不明文回填；清除密钥后连接测试应明确提示未配置。

### B. 真实文本菜谱主链

1. 选用不含个人信息、账号信息或受限内容的公开菜谱正文。
2. 从“粘贴正文”进入现有导入流水线，不调用图片理解、OCR 或 ASR。
3. 检查生成结果是否进入严格 Schema，覆盖菜名、简介、份量、时间、难度、食材、用量、步骤、置信度和证据提示。
4. 检查模型是否返回 Markdown fence、额外解释、推理文本、空字段、错误类型或未知字段。
5. 在草稿确认页记录需要人工修改的字段数，保存后重启 App，确认菜谱通过真实 SQLite 持久化。

### C. 错误、超时与取消

1. 使用错误 Key 验证鉴权错误映射，随后立即恢复正确运行时配置，不保存错误凭证。
2. 使用错误模型名或错误路径验证 not found / model unavailable 类错误是否可理解且不泄露服务端原文。
3. 验证请求超时和用户取消；取消后不得提交草稿或留下无法恢复的 running 任务。
4. 非 JSON、字段缺失、过大响应和 429 等不适合故意攻击真实临时服务的场景，继续使用现有 Fixture 覆盖并在验收记录中区分“真实服务”与“自动化模拟”。

### D. 敏感信息扫描与收尾

1. 检查 App 数据库、安全存储之外的本地文件、Flutter/Android Logcat、错误提示、截图和验收记录。
2. 确认没有 API Key、Authorization、Prompt 全文、完整模型响应或用户隐私内容。
3. 测试结束后通过 App 清除临时 Key，并建议项目负责人轮换该临时凭证。
4. 若发生崩溃或失败，只保存脱敏错误码、阶段、耗时和最小复现条件。

## 与其他任务的边界

- `SPK-001` 负责 Flutter 工程和 Provider 基线；本 Spike 负责连接真实服务并完成兼容性矩阵。
- `SPK-002` 负责真实 PaddleOCR 模型、移动端性能和识别质量；本 Spike 不替代 OCR 验收。
- `SPK-004` / `SPK-005` 负责小红书/抖音公开内容获取；本 Spike 首阶段使用人工粘贴的公开正文，避免把平台解析问题与 LLM 兼容性问题混在一起。
- `TEST-001` / `TEST-002` 负责固定公开样本和长期人工评分基线；本 Spike 的真实样本结果应成为其初始数据之一。

## 计划输出

- Android 真实服务验收记录：`tests/acceptance/SPK-003-openai-compatible-android-2026-08-01.md`（执行时创建）。
- AI 质量样本：追加到 `tests/ai-quality/AI_QUALITY_LOG.md`。
- 若需要 Adapter 加固：先新增 `AI-003`，再更新架构契约、代码和回归测试。

## 执行结果（2026-08-01）

- Android OpenAI-compatible 真实连接成功。
- 纯文本长正文通过 `AI-003` 受控规范化和严格 Schema，生成草稿并进入 `needsReview`。
- 草稿写入真实 SQLite，关闭并重新打开数据库后仍可恢复。
- 至少一个真实安全错误路径通过；其他异常继续由 Fixture 覆盖，不伪造真实服务结果。
- Logcat 中临时 Key 标记、`Authorization` 和 `Bearer` 命中数均为 0。
- 临时 API Key 已通过 App 内“清除已保存的 API Key”从安全存储移除。
- 导入取消 CAS、迟到错误抑制和迟到草稿补偿已经通过 SQLite 自动化验证；当前安装构建的运行态取消按钮不可点击，Android 真实点击仍未完成。
- 样本为公开风格人工长正文，不是固定小红书/抖音样本，因此质量字段保持未评分。

验收记录：

- `tests/acceptance/SPK-003-openai-compatible-android-2026-08-01.md`
- `tests/acceptance/BUG-002-import-cancellation-race-2026-08-01.md`

## 当前结论

**首阶段采用 OpenAI-compatible 纯文本主链，完整多协议矩阵继续研究。**

真实连接、结构化生成、草稿保存和 SQLite 恢复已经证明现有方案可用；`AI-003` 的有限包装兼容是必要加固。由于 Android 真实取消、Gemini、局域网兼容服务和 iOS 尚未完成，`SPK-003` 进入 `VERIFY`，不标记为全部完成。
