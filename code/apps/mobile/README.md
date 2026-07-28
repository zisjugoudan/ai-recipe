# AI 食谱移动端

当前目录是 `SPK-001` 的 Flutter 验证工程，也是后续正式移动端工程的候选基线。

## 当前已实现

- Android / iOS Flutter 工程骨架。
- 统一的自定义 LLM API 配置：协议类型、API Base URL、API Key、模型。
- OpenAI-compatible Chat Completions Adapter。
- Gemini native `generateContent` Adapter。
- API Key 与普通配置分离：Key 使用 Keychain/Keystore，普通配置只保存 `secretRef`。
- 连接测试、HTTP 明文风险提示、统一错误映射、超时与取消令牌基础能力。
- Provider 请求构造、响应解析、配置校验和设置页 Widget 测试。
- Local-first SQLite Schema v2、菜谱聚合 Repository 和 v1 → v2 迁移。
- 可持久化的链接导入任务状态机、Application 用例、取消、重试和重启恢复。

## 本地运行

```powershell
cd code/apps/mobile
flutter pub get
flutter run
```

## 质量检查

```powershell
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

## Windows 中文路径构建说明

当前仓库路径包含中文。Android Gradle Plugin 的路径检查已通过 `android.overridePathCheck=true` 处理，但 Flutter shader compiler 在 Windows 上仍可能无法向含中文的输出路径写文件。

本轮验证通过纯 ASCII Junction 指向本工程后成功构建。后续 Windows 开发建议将仓库放到纯 ASCII 绝对路径，或建立稳定的纯 ASCII Junction 构建入口；不要依赖验收时创建的临时 Junction 长期存在。

Debug APK 已成功生成并在 Android 12 真机安装、启动。详细记录见仓库根目录：

`tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`
## 安全约束

- 不得将真实 API Key、Token、Authorization Header、Prompt 或完整模型响应提交到 Git 或写入日志。
- API Key 输入框不会回填已经保存的明文 Key。
- `http://` 地址仅用于可信本地网络或本地服务；它可能暴露 Key 和请求内容，优先使用 HTTPS。
- Android 验证工程暂时允许 cleartext HTTP，以覆盖本地 OpenAI-compatible 服务；生产发布前必须重新评估网络安全配置。
- 不允许通过自定义证书回调忽略 TLS 错误。

## 当前限制

- Windows 环境不能完成 iOS 构建、Keychain、本地网络权限和 iPhone 真机验证。
- iOS 仅加入本地网络用途说明和 `NSAllowsLocalNetworking`；任意局域网 IP 的明文 HTTP 行为仍需在 macOS/iPhone 上实测，不能视为已通过。
- 尚未验证系统分享、后台任务、本地通知、OCR 原生桥接和真实 LLM 服务兼容性。
- 设置页当前保存一个活动配置；多配置管理、模型列表读取和菜谱结构化输出属于后续任务。

进度与结论以仓库根目录的 `tracking/CURRENT.md` 和 `research/spikes/SPK-001-cross-platform-framework.md` 为准。

