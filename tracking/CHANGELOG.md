# 项目变更日志

> 记录会影响产品、流程、架构、设计、测试或交付方式的有效变化。代码的细粒度变化以后由版本控制记录。

## 2026-07-27

### 新增

- 创建本地分层项目目录、根目录永久协作规程和完整跟踪文件。
- 创建产品用户故事、设计交付、架构、API、代码和测试目录说明。
- 创建 `docs/architecture/MOBILE_ARCHITECTURE.md`，定义 Flutter 分层、模块边界和游客/登录能力。
- 创建 `docs/architecture/OCR_PLUGIN.md`，定义 PaddleOCR 本地插件、模型包和安全边界。
- 创建并修订 `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`，最终定义统一“协议 + API Base URL + 可空 Key + 模型”配置和 Provider Adapter 契约。
- 初始化本地 Git 仓库，默认分支为 `main`；未配置远程、未提交、未推送。
- 新增 `OPS-002` Git 初始化验收记录。

### 修改

- 产品需求文档迁移到 `docs/product/` 并更新到 v0.3。
- `SPK-001` 从 Flutter/React Native 比选改为 Flutter 关键能力基线验证。
- `SPK-002` 聚焦 PP-OCRv5 mobile + ONNX Runtime Mobile 的真机可行性。
- `SPK-003` 增加 LAN、Tailscale/WireGuard、HTTPS、URL 校验和敏感日志验证。
- 更新 Sprint 00、风险表、代码目录和架构目录说明。
- 更新根目录导航和永久协作规程，移除 Flutter/React Native 二选一与 OCR 未定的过时表述。

### 决策

- 不使用飞书、Notion 等云平台作为项目事实源。
- 移动端统一采用 Flutter，不再进行 React Native 比选（ADR-0008）。
- 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile（ADR-0009）。
- 自定义 LLM 使用统一 API 配置和协议 Adapter；`ADR-0011` 已取代三种网络模式的 `ADR-0010`。

### 验证

- OPS-001 复核通过：本地链接和强制文件缺失数均为 0。
- 本机工具版本已核实：Flutter 3.38.5 stable、Dart 3.10.4、Git 2.51.1.windows.1。
- OPS-002 验收通过：`.git` 存在、当前分支为 `main`、项目 `.gitignore` 生效、远程为空、无首次提交。
- `DOC-001` 验收通过：47 个 Markdown 文件 UTF-8 内容正常，本地链接缺失数为 0，长期事实源已同步。
- OCR 与真实 LLM 服务兼容性仍需 `SPK-002`、`SPK-003` 的真机/真实服务实验，不以本地契约测试替代验收。

### SPK-001 LLM Provider / Android 工程切片

- 创建 `code/apps/mobile` Flutter 工程，实施统一“协议 + API Base URL + 可空 API Key + 模型”的配置页与持久化。
- 实现 OpenAI-compatible Chat Completions 和 Gemini native `generateContent` Adapter。
- API Key 使用 `FlutterSecureStorage`，普通配置使用 `SharedPreferencesAsync`；已保存 Key 不回填明文。
- 实现 URL 校验、超时、取消、常见 HTTP/网络错误映射、HTTP 明文风险与连接测试费用提示。
- 将 `LlmCancellationToken` 移至 Domain 层，消除 Domain 对 Provider 实现层的反向依赖。
- `flutter analyze` 通过：`No issues found`。
- `flutter test` 通过：21 个测试全部通过。
- 发现 Windows Flutter shader compiler 无法直接写入含中文的构建路径；增加 `android.overridePathCheck=true`，并通过纯 ASCII Junction 构建入口完成 Android Debug APK 构建。
- Android 构建结果：`BUILD SUCCESSFUL in 3m 4s`，178 个 actionable tasks；APK 大小 153,817,311 bytes。
- Android 12 真机通过 `adb install --no-streaming -r` 安装并成功启动，应用 PID 未发现错误级 Logcat。
- 新增验收记录 `tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`。
- `SPK-001` 保持 `DOING`：SQLite、分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 尚未完成。

