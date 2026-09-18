# SPK-001：Flutter 关键能力基线验证

- 状态：BLOCKED（Android 基础切片已通过；待分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 验证条件解除后继续）
- 启动日期：2026-07-27
- 关联任务：SPK-001、ARCH-001
- 关联风险：R-004、R-005、R-008、R-011
- 决策前提：用户已通过 `ADR-0008` 指定 Flutter，不再进行 React Native 比选

## 问题

Flutter 在本项目的 Local-first 数据库、系统分享、后台任务、安全存储、本地 OCR 插件和自定义 API 场景中，是否存在阻止首版交付的兼容性或维护成本问题？

## 成功标准

- 建立最小 Flutter 项目或可复现实验。
- 验证 SQLite、分享入口、后台任务、本地通知、安全存储和原生插件桥接。
- 实现统一的自定义 API 配置，并验证 OpenAI-compatible/Gemini 请求构造、取消、超时和错误映射。
- 记录 Android/iOS 差异、包体积、开发体验和测试方式。
- 输出“通过”“带约束通过”或“阻塞”的结论。

## 非目标

- 不重新比较 Flutter 与 React Native。
- 不在本 Spike 中完成生产级链接解析、完整菜谱业务或云同步。
- 不用 Fake/单元测试替代 `SPK-003` 的真实 LLM 服务兼容性验证。

## 测试环境

| 项目 | 环境 |
|---|---|
| Flutter | 3.38.5 stable |
| Dart | 3.10.4 |
| Android SDK | 36.1.0 |
| Java | 17 |
| 主开发系统 | Windows |
| Android 真机 | Android 12，`DBR_W10` |
| iOS | 当前无 macOS/iPhone 验证环境 |

## 验证矩阵

| 能力 | 状态 | 当前结果 | 后续动作 |
|---|---|---|---|
| Flutter 工程骨架 | 通过 | Android/iOS 工程已创建；Android Debug APK 可构建 | 后续由 `ARCH-001` 决定正式骨架迁移范围 |
| Android 真机启动 | 通过 | Android 12 安装成功，Activity resumed，应用 PID 无错误级日志 | 后续补 UI 和完整功能走查 |
| 统一 LLM 配置 | 通过 | 协议、Base URL、可空 Key、模型、测试并保存已实现 | `SPK-003` 使用真实服务验证 |
| OpenAI-compatible Adapter | 通过（契约测试） | Chat Completions 请求、鉴权、解析和错误映射通过 | 验证不同兼容服务的路径与响应差异 |
| Gemini Adapter | 通过（契约测试） | `generateContent` 请求、角色转换、鉴权和解析通过 | 使用 Gemini 真实服务验证 |
| 超时与取消 | 通过（本地测试） | Transport 支持超时、请求前取消和请求中取消 | 真机弱网补验 |
| 安全存储封装 | 部分通过 | 代码使用 `FlutterSecureStorage`，Key 与普通配置分离 | 真机验证保存、覆盖、删除和重装行为 |
| SQLite | 通过 | Schema v1、事务、聚合 Repository、持久化重开和软删除测试通过 | 后续按业务任务扩展导入任务、标签、同步和迁移 |
| 系统分享 URL | 未验证 | 尚未实现实验 | Android/iOS 接收分享链接 |
| 后台任务 | 未验证 | 尚未实现实验 | 验证任务恢复、限制和失败场景 |
| 本地通知 | 未验证 | 尚未实现实验 | 验证权限与任务结果通知 |
| OCR 原生桥接 | 未验证 | 尚未实现 Federated plugin / Platform Channel 实验 | 与 `SPK-002` 联动 |
| iOS 构建与真机 | 阻塞于环境 | Windows 不能执行 | 在 macOS/iPhone 环境补验 |

## 已实施的 LLM Provider 基线

统一配置流程：

```text
选择接口协议 → 填写 API Base URL → 填写 API Key → 填写模型 → 测试并保存
```

实现内容：

- `LlmConnectionConfig` 只接受 HTTP/HTTPS，拒绝 URL 内嵌凭据、Query 和 Fragment。
- API Key 允许为空，支持无鉴权本地 OpenAI-compatible 服务。
- 非敏感配置存入 `SharedPreferencesAsync`，Key 存入 `FlutterSecureStorage`。
- OpenAI-compatible 使用 `POST {baseUrl}/chat/completions`；完整端点不会重复追加路径。
- Gemini 使用 `POST {baseUrl}/models/{model}:generateContent`，并完成 system/assistant 角色转换。
- Transport 覆盖超时、取消、网络错误和常见 HTTP 状态映射。
- 设置页覆盖协议、名称、Base URL、Key、模型、连接测试、保存和安全提示。
- `LlmCancellationToken` 位于 Domain 层，避免 Domain 反向依赖 Provider。

## 实验步骤和结果

在 `code/apps/mobile` 执行：

```powershell
dart format lib test
flutter analyze
flutter test
```

结果：

- `flutter analyze`：`No issues found`。
- `flutter test`：27 个测试全部通过，其中新增 6 个 SQLite Repository 测试。
- SQLite 测试使用真实临时数据库文件，覆盖关闭重开、聚合更新、事务回滚、搜索、收藏、软删除、恢复、永久删除和分类关系清理。
- LLM 测试没有使用真实 API Key，也没有调用真实 LLM 服务。

Android 构建：

- Android Gradle Plugin 对中文路径检查通过 `android.overridePathCheck=true` 绕过。
- Flutter shader compiler 仍无法直接写入含中文的构建路径。
- 通过纯 ASCII Junction 指向同一工程后构建成功：`BUILD SUCCESSFUL in 3m 4s`，178 个 actionable tasks。
- APK 位于 `code/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`，大小 153,817,311 bytes。
- 使用 `adb install --no-streaming -r` 在 Android 12 真机安装成功。
- `MainActivity` 成功进入 resumed 状态，应用 PID 的错误级 Logcat 为空。

详细证据见 `tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`。

## 已实施的 Local-first SQLite 基线

实现内容：

- 新增纯 Dart 菜谱领域模型和 Repository 接口，UI 不直接依赖 SQLite。
- SQLite Schema v1 包含菜谱、食材、步骤、分类和菜谱分类关系。
- 启用外键与级联删除；菜谱聚合写入使用单一事务。
- 支持新增/更新、按 ID 读取、列表、文本搜索、收藏筛选、软删除、恢复和永久删除。
- 支持分类写入、排序读取和软删除；删除分类时清理关系但保留菜谱。
- 任意子项或分类关系写入失败会回滚整次菜谱保存。

详细设计见 `docs/architecture/LOCAL_DATABASE.md`，验收证据见 `tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`。

## 失败与限制

1. Windows Flutter 工具链在仓库绝对路径含中文时存在 shader 输出失败；当前通过纯 ASCII Junction 构建。长期应迁移到纯 ASCII 路径或提供稳定的本地构建入口。
2. 首次流式 `adb install -r` 超时；`--no-streaming` 安装成功但耗时较长。
3. Windows 不能验证 iOS 构建、Keychain、本地网络权限和 iPhone 行为。
4. Provider 测试为可注入 Transport 的本地契约测试，不代表所有真实兼容服务已经通过。
5. 尚未验证系统分享、后台任务、通知、OCR 桥接和安全存储真机完整流程。

## 当前结论

**继续研究。**

Flutter 的 LLM Provider、Local-first SQLite 和 Android 工程切片已通过，没有发现阻止继续开发的业务代码问题；但 `SPK-001` 的分享、后台任务、通知、安全存储真机流程、OCR 桥接和 iOS 矩阵尚未完成，因此状态保持 `DOING`。

## 对产品、架构和排期的影响

- `ADR-0011` 的统一 API 配置可作为后续设置页和 AI 流水线的正式基线。
- Provider Adapter 可以继续扩展新协议，不需要为网络拓扑建立不同产品模式。
- Windows/Android 开发可继续；iOS 验收必须单独排入 macOS/iPhone 环境。
- 中文仓库路径会增加 Android 构建失败风险，应在正式持续集成前处理。

## 后续任务

1. `IMPORT-001`：定义链接导入任务状态机、错误、取消、重试、恢复和 SQLite 持久化。
2. `SPK-001`：系统分享 URL 接收，并将 URL 交给导入任务用例。
3. `SPK-001`：后台任务、本地通知和安全存储真机写删。
4. `SPK-001` / `SPK-002`：OCR Federated plugin / Platform Channel 桥接。
5. `SPK-003`：真实 OpenAI-compatible、Gemini 和本地兼容服务矩阵。
6. macOS/iPhone：补齐 iOS 构建和权限验证。
