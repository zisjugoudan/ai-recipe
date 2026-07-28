# SPK-003：自定义 LLM API 多协议兼容性验证

- 状态：TODO
- 关联任务：SPK-003、AI-001
- 关联风险：R-005、R-008
- 架构文档：`docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`

## 问题

移动端仅让用户填写 API 地址和 Key 时，如何通过 Provider Adapter 稳定兼容 OpenAI-compatible、Gemini 以及未来其他协议，并提供一致的模型列表、生成、取消和错误反馈？

## 已确定方向

- 产品只有一种自定义 API 配置，不设置 LAN、VPN、HTTPS 等连接模式。
- 用户选择协议类型，填写 API 地址、Key 和模型。
- 网络位置只是用户所填地址的属性；HTTP 显示风险警告，HTTPS 正常使用。
- OpenAI-compatible 与 Gemini 使用独立 Adapter。
- API Key 只进入 Keychain/Keystore；日志不记录 Key、Prompt 或完整响应。

## 成功标准

- 测试连接、模型列表、文本生成和结构化菜谱输出。
- 验证 OpenAI-compatible、Gemini 和至少一个本地兼容服务。
- 验证 URL 规范化、超时、取消、响应体上限和错误映射。
- 验证 401/403、404、429、模型不存在、非 JSON 和响应字段缺失。
- 验证数据库、日志、导出和崩溃报告不泄露 API Key 或 Prompt。

## 与 SPK-001 的边界

`SPK-001` 先创建 Flutter 工程，实现配置模型、可注入 HTTP Transport、OpenAI-compatible/Gemini 请求构造和单元测试。本 Spike 在其基础上连接真实服务并完成兼容性矩阵。

## 当前结论

产品模型已由 `ADR-0011` 更正；真实 Provider 兼容性尚未验证，因此状态保持 `TODO`。
