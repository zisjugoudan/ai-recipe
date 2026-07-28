# SPK-001：LLM Provider 与 Android 工程基线验收

- 日期：2026-07-27
- 任务：`SPK-001`
- 验收切片：统一 LLM API 配置、Provider Adapter、Flutter 工程与 Android 启动
- 结论：**当前切片通过；SPK-001 整体继续进行**

## 1. 验收范围

本轮验证项目负责人确认的统一配置流程：

```text
选择接口协议 → 填写 API Base URL → 填写 API Key → 填写模型 → 测试并保存
```

API 地址可以指向本机、局域网、自建服务器或第三方云服务，客户端不把 LAN、VPN、HTTPS 拆成不同产品模式。首版协议范围：

- OpenAI-compatible Chat Completions。
- Gemini native `generateContent`。

本轮同时验证 Flutter Android 工程能够静态分析、运行测试、构建 Debug APK，并在 Android 12 真机安装和启动。

## 2. 测试环境

| 项目 | 实际环境 |
|---|---|
| 操作系统 | Windows，项目工作区 `E:\AI\ai食谱` |
| Flutter | 3.38.5 stable |
| Dart | 3.10.4 |
| Android SDK | 36.1.0 |
| Java | 17 |
| Android 真机 | Android 12，型号 `DBR_W10`，序列号 `S5KBB23710201033` |
| 应用包名 | `com.airecipe.ai_recipe` |
| 应用版本 | `versionCode=1`，`versionName=1.0.0` |

Windows 不能替代 macOS/iPhone 的 iOS 构建和真机验收。

## 3. 实现验收

| 验收项 | 结果 | 证据 |
|---|---|---|
| 统一连接配置 | 通过 | `LlmConnectionConfig` 保存协议、Base URL、模型、超时和 `secretRef` |
| URL 基础校验 | 通过 | 仅允许 HTTP/HTTPS；拒绝 URL 用户名密码、Query 和 Fragment；规范化末尾 `/` |
| API Key 可为空 | 通过 | 无鉴权本地 OpenAI-compatible 服务不会发送 `Authorization` Header |
| API Key 与普通配置分离 | 通过 | 非敏感配置使用 `SharedPreferencesAsync`；Key 使用 `FlutterSecureStorage` |
| 已保存 Key 不回填 | 通过 | 设置页只显示“已有密钥”状态，不读取并展示明文 |
| OpenAI-compatible Adapter | 通过 | 构造 `/chat/completions` 请求、Bearer 鉴权并解析 `choices[0].message.content` |
| Gemini Adapter | 通过 | 构造 `/models/{model}:generateContent`、`x-goog-api-key`、`systemInstruction` 和角色转换 |
| 超时与取消 | 通过 | Transport 支持请求前取消、请求中取消和超时映射 |
| 错误映射 | 通过 | 覆盖 401/403、404、429、5xx、网络错误、非 JSON 和响应字段缺失 |
| 设置页面 | 通过 | 可选择协议、填写名称/Base URL/Key/模型、测试连接并保存 |
| 安全提示 | 通过 | HTTP 明文风险提示；测试请求可能产生费用提示；未加入全局 TLS 忽略 |
| Domain 分层 | 通过 | 取消令牌位于 `lib/domain/llm/`，Domain 不反向依赖 Provider 实现 |

## 4. 自动化验证

在 `code/apps/mobile` 执行：

```powershell
dart format lib test
flutter analyze
flutter test
```

结果：

- `dart format` 完成。
- `flutter analyze`：`No issues found`。
- `flutter test`：21 个测试全部通过。
- 测试使用明显的假 Key，没有调用真实服务，没有记录真实凭据。

测试覆盖配置校验、OpenAI-compatible 请求/响应、Gemini 请求/响应、取消、错误映射和设置页面主要状态。

## 5. Android 构建与真机结果

### 5.1 中文路径问题

Android Gradle Plugin 首先因仓库路径含非 ASCII 字符拒绝构建，因此在 `android/gradle.properties` 增加：

```properties
android.overridePathCheck=true
```

继续构建时，Flutter shader compiler 仍无法向含中文的输出路径写文件。这不是业务代码错误，而是当前 Windows Flutter 工具链对非 ASCII 构建路径的兼容问题。

### 5.2 可复现解决方案

本次在纯 ASCII 路径创建指向 Flutter 工程的 Junction，并从该入口构建：

```text
C:\Users\Administrator\.codex\visualizations\2026\07\27\019fa3cc-3bea-74d2-a186-f788880568ff\ai_recipe_mobile
→ E:\AI\ai食谱\code\apps\mobile
```

通过缓存的 Gradle CLI 执行构建，结果：

```text
BUILD SUCCESSFUL in 3m 4s
178 actionable tasks
```

生成 APK：

```text
E:\AI\ai食谱\code\apps\mobile\build\app\outputs\flutter-apk\app-debug.apk
```

文件大小：153,817,311 bytes。

后续 Windows 开发应迁移到纯 ASCII 仓库路径，或提供稳定的纯 ASCII Junction 构建入口，不应依赖本次临时目录长期存在。

### 5.3 真机安装和启动

普通流式安装超时后，使用以下方式成功安装：

```powershell
adb install --no-streaming -r app-debug.apk
```

真机结果：

- 安装返回 `Success`。
- 应用进程成功启动，PID 为 `27813`。
- `MainActivity` 进入 resumed 状态。
- 检查应用 PID 的错误级 Logcat，没有发现错误输出。

未保留真机截图；本轮验收以安装结果、Activity 状态和 Logcat 为证据。

## 6. 本轮未验证内容

以下项目仍属于 `SPK-001`，因此不能将整个 Spike 标记为完成：

- SQLite 写入和读取 Recipe。
- 系统分享入口接收 URL。
- 后台任务和本地通知。
- 真机 Keystore 保存、覆盖和删除 Key 的完整流程。
- OCR federated plugin / Platform Channel 桥接。
- macOS/iOS 构建、Keychain、本地网络权限和 iPhone 真机。
- 真实 OpenAI-compatible、Gemini 和本地兼容服务调用；该兼容性矩阵由 `SPK-003` 完成。
- LLM 结构化菜谱输出质量和 Schema 兼容性。

## 7. 结论

统一“协议 + API Base URL + API Key + 模型”方案已经形成可运行 Flutter 基线。OpenAI-compatible 与 Gemini 两个 Adapter 的本地契约测试通过，Android Debug APK 已成功构建并在 Android 12 真机安装、启动。

当前结论是：**LLM Provider/Android 工程切片通过，SPK-001 继续研究**。
