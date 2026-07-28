# LLM 自定义 API 与 Provider 适配方案

- 状态：已生效，首个实现纳入 `SPK-001`
- 日期：2026-07-27
- 关联决策：`ADR-0011`（取代 `ADR-0010`）
- 关联任务：`SPK-001`、`SPK-003`、`AI-001`

## 1. 产品定义

移动端连接用户自有 LLM 时只有一种配置方案：

```text
选择接口协议 → 填写 API 地址 → 填写 API Key → 选择或填写模型 → 测试并保存
```

API 地址可以指向本机、局域网、远程服务器或第三方云服务，但这些只是地址所在位置，不是产品中的不同连接模式。应用不要求用户理解 LAN、VPN、反向代理等网络拓扑，也不分别维护安全模式。

不同供应商的请求路径、鉴权 Header、请求体和响应解析由 Provider Adapter 处理。页面和业务用例只依赖统一 `LlmProvider`。

## 2. 首版协议适配器

### 2.1 OpenAI-compatible

用于 OpenAI 以及提供兼容接口的本地或云端服务。适配器负责：

- 使用 `Authorization: Bearer <API Key>`。
- 基于用户填写的 Base URL 构造模型列表和 Chat Completions 路径。
- 将统一消息转换为 `messages`。
- 从 `choices[].message.content` 读取文本。
- 映射 401/403、404、429、超时、取消和无效响应。

### 2.2 Gemini native

用于 Gemini 原生 REST 协议。适配器负责：

- 使用 `x-goog-api-key` Header。
- 构造 `models/{model}:generateContent` 路径。
- 将统一消息转换为 `contents[].parts[]`。
- 从 `candidates[].content.parts[]` 读取文本。
- 映射 Gemini 错误结构到统一错误类型。

### 2.3 后续扩展

Anthropic、OpenAI Responses API、Ollama 原生协议或其他供应商可以新增 Adapter，但不能把供应商判断散落到页面、菜谱解析或导入流程中。支持 OpenAI-compatible 的本地服务优先直接使用该适配器。

## 3. 配置模型

```json
{
  "id": "uuid",
  "name": "我的模型",
  "providerType": "openai_compatible",
  "baseUrl": "https://example.com/v1",
  "secretRef": "llm-config-uuid",
  "model": "user-selected-model",
  "requestTimeoutMs": 120000
}
```

用户界面的核心输入是协议类型、API 地址和 API Key。模型优先从接口获取；接口不支持模型列表时允许手动填写。API Key 本身不进入普通配置对象，只保存 `secretRef`。

## 4. 统一接口

```text
LlmProvider
├── testConnection(config)
├── listModels(config)
├── generateText(config, request)
├── generateStructured(config, request, schema)
├── getCapabilities(config)
└── cancel(requestId)
```

统一请求至少包含 system prompt、user prompt、模型、温度、最大输出长度、结构化输出要求和取消信号。统一响应至少包含文本、模型、供应商请求 ID、Token 用量、耗时和原始响应是否通过结构校验。

## 5. URL 与网络规则

1. API 地址只接受 `http` 或 `https`，拒绝内嵌用户名和密码。
2. Base URL 统一去除末尾 `/`，路径由 Adapter 追加，避免页面拼接供应商路径。
3. HTTPS 正常使用；HTTP 允许用于用户明确填写的本地或自建接口，但保存和测试时显示明文传输警告。
4. 禁止自动忽略 TLS 证书错误，也不允许 HTTPS 自动降级重定向到 HTTP。
5. 请求必须有连接/总超时、取消能力和响应体大小上限。
6. 网络不可达、超时、鉴权失败、限流、模型不存在和响应格式错误映射到统一错误。

## 6. 密钥与日志

- API Key 只进入 iOS Keychain / Android Keystore 封装的安全存储。
- 数据库只保存 `secretRef`，不保存密钥正文。
- 密钥不进入云同步、导出、普通备份、剪贴板历史、日志或崩溃报告。
- 设置页重新打开时只显示“已保存”或末尾少量字符，不回填完整密钥。
- HTTP 请求日志必须移除 Authorization、`x-goog-api-key`、Prompt 和完整响应。

## 7. 配置与测试流程

1. 用户选择 OpenAI-compatible、Gemini 或未来的其他协议。
2. 应用提供该协议的默认 API 地址，用户可覆盖。
3. 用户填写 API Key；本地无鉴权接口允许留空。
4. 应用尝试获取模型列表；失败时允许手动填写模型。
5. 发送最小生成请求并展示成功、耗时或明确错误。
6. 测试通过后保存普通配置和安全存储中的 Key。

## 8. SPK-001 首个实现范围

- 创建 Flutter 最小工程。
- 实现配置模型、统一请求/响应和错误类型。
- 实现 OpenAI-compatible 与 Gemini Adapter 的请求构造和响应解析。
- 实现 API 地址、Key、模型输入的最小配置页面。
- 使用可注入 HTTP Transport 编写不需要真实 Key 的单元测试。
- 安全存储、Android 真机网络和其他 Flutter 能力继续在 `SPK-001` 中逐项验证。

## 9. SPK-003 后续验证范围

`SPK-003` 不再比较三种网络拓扑，而是验证不同 Provider 规则和真实服务兼容性：

- OpenAI 官方或兼容接口。
- Gemini 原生接口。
- 至少一个本地 OpenAI-compatible 服务。
- 模型列表不支持、Key 为空、401/403、404、429、超时、取消、非 JSON 和响应字段缺失。
- 结构化菜谱输出以及 API Key/Prompt 不进入持久化和日志。

## 10. 官方协议参考

- OpenAI API Reference：<https://platform.openai.com/docs/api-reference>
- Gemini OpenAI compatibility：<https://ai.google.dev/gemini-api/docs/openai>
- Gemini generateContent REST：<https://ai.google.dev/api/generate-content>
- Flutter Networking：<https://docs.flutter.dev/cookbook/networking/send-data>
