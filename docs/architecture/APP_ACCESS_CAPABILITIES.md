# 游客/登录会话与后端能力策略

> 任务：`APP-002`
> 状态：完成
> 日期：2026-07-28
> 关联用户故事：`US-001`、`US-002`、`US-003`

## 1. 目标

建立纯 Dart 的会话与能力判定边界，使后续 Flutter 页面只询问 Application Facade：当前是游客还是登录用户、某项能力是否可用、不可用原因是什么。页面不得自行根据按钮、Provider 配置或登录布尔值拼装权限规则。

本任务落实以下长期规则：

- 游客默认可进入应用并使用本地菜谱库。
- 游客与登录用户都可以使用用户自行配置的 OpenAI-compatible / Gemini 等自定义 LLM API。
- 游客与登录用户都可以使用已安装的本地 OCR 插件。
- 平台托管 LLM、云 OCR、平台托管 ASR、云保存与云同步必须登录，并继续受服务状态、网络和配额约束。
- API Key 与认证 Token 不进入普通会话元数据，也不参与游客数据合并。

## 2. 本任务范围

### 2.1 实现

- 游客与已认证会话的纯 Dart 模型。
- 非敏感会话元数据 Repository 和 SharedPreferences 设备实现。
- 统一能力枚举、运行时依赖状态、判定结果和稳定原因码。
- Application Facade：加载会话、继续游客、接受已验证登录结果、退出登录、读取能力快照和能力守卫。
- 内存单元测试与设备元数据序列化测试。

### 2.2 不实现

- 手机号、微信、Apple、OAuth 等登录页面和认证协议。
- Access Token / Refresh Token 的签发、刷新和安全存储。
- 云端账号 API、菜谱同步、冲突预览和游客数据合并执行。
- 平台托管 AI、云 OCR 或云同步的真实网络客户端。
- 本地 OCR 模型下载和原生推理桥接。

未来 Auth Provider 只有在服务端认证成功后，才可以调用“接受已验证登录结果”用例。持久化的登录身份元数据不是认证凭据，不能替代 Token 校验。

## 3. 代码边界

`lib/domain/access/`

- `AppSession`：游客或已认证用户的非敏感身份上下文。
- `AppSessionRepository`：会话元数据读取与保存契约。
- `AppCapability`：页面和用例可询问的能力集合。
- `AppCapabilityRuntime`：Provider、网络、配额和云服务的当前就绪状态。
- `AppCapabilityRuntimeRepository`：运行时能力状态来源契约。

`lib/application/access/`

- `AppAccessUseCases`：唯一会话与能力 Application Facade。
- 输入校验、稳定错误映射、能力策略和能力守卫。

`lib/data/device_app_session_repository.dart`

- 只使用 SharedPreferences 保存 schema 版本、会话类型、用户 ID、显示名和登录时间。
- 禁止保存 Access Token、Refresh Token、API Key、Cookie 或 Authorization Header。

## 4. 会话模型

| 会话 | userId | 本地数据 | 云端能力 |
|---|---|---|---|
| 游客 | 空 | 使用 `userId == null` 的本地聚合 | 不可用 |
| 已认证 | 非空稳定 ID | 继续使用同一本地数据库 | 按运行时状态可用 |

应用首次运行或会话元数据缺失时默认返回游客，不强迫登录。

退出登录只清除当前登录身份上下文，不删除本地菜谱、分类、自定义 LLM 配置或本地 OCR 模型。

## 5. 能力矩阵

| 能力 | 游客 | 登录用户 | 额外条件 |
|---|---|---|---|
| 本地菜谱库 | 可用 | 可用 | 无 |
| 公开链接导入内核 | 可用 | 可用 | 单条内容仍可能因平台限制降级 |
| 自定义 LLM API | 可用 | 可用 | 已配置且当前就绪 |
| 本地 OCR | 可用 | 可用 | 插件与模型已安装且就绪 |
| 平台托管 LLM | 不可用 | 可用 | 服务、网络和配额就绪 |
| 云 OCR | 不可用 | 可用 | 服务、网络和配额就绪 |
| 平台托管 ASR | 不可用 | 可用 | 服务、网络和配额就绪 |
| 云保存/同步 | 不可用 | 可用 | 同步服务就绪 |

## 6. 稳定不可用原因

- `signInRequired`：需要登录。
- `providerNotConfigured`：自定义 Provider 尚未配置。
- `componentNotInstalled`：本地插件或模型未安装。
- `offline`：运行时报告网络不可用。
- `quotaExceeded`：托管服务配额不足。
- `serviceUnavailable`：服务未启用、维护中或当前不可用。

UI 只能根据稳定原因码选择文案和操作，不得解析异常字符串。

## 7. 安全与隐私

- 会话存储不接受或返回 Token。
- 自定义 LLM API Key 继续由 Keychain / Keystore 保存，不复制到会话数据。
- 能力快照不得包含 API Key、Authorization、完整 Prompt、完整模型响应或 OCR/ASR 原文。
- 游客切换为登录用户时，本任务不自动上传或重写任何本地数据。
- 未知 Repository 异常映射为脱敏 Application 错误。

## 8. 后续接入

- Auth Provider 完成认证后传入稳定 userId；Token 由未来安全认证仓库单独管理。
- 自定义 LLM 配置仓库、本地 OCR 安装状态和云服务健康/配额适配为 `AppCapabilityRuntimeRepository`。
- 云同步和游客数据合并必须建立独立任务、冲突契约和验收记录，不得隐藏在登录动作中执行。

## 9. 实现结果

- 新增 `AppSession`，只表达游客或已认证用户的非敏感身份上下文。
- 新增 `AppCapabilityRuntime`、`AppCapabilityDecision` 和 `AppCapabilitySnapshot`，统一八类能力及六种稳定不可用原因。
- 新增 `AppAccessUseCases`，提供加载会话、继续游客、接受已验证登录结果、退出登录、能力快照和能力守卫。
- 新增 `DeviceAppSessionRepository`，以严格 Schema 将非敏感会话元数据保存到 SharedPreferences；未知字段和损坏数据均拒绝加载。
- SharedPreferences Adapter 可替换为内存实现，自动化测试不依赖真机或平台插件。
- 新增 21 项自动化测试；全量 `flutter test --no-pub` 共 197 项通过，`flutter analyze --no-pub` 无问题。
