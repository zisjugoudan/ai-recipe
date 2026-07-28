# 项目变更日志

> 记录会影响产品、流程、架构、设计、测试或交付方式的有效变化。代码的细粒度变化以后由版本控制记录。

## 2026-07-28

### IMPORT-002 内容 Adapter 与单执行器调度内核

- 新增统一导入内容模型和 `docs/api/import-content.schema.json`。
- 新增平台 Adapter 契约、Registry、重复平台注册保护和统一内容不变量。
- 新增导入 Runner，按状态机执行获取、提取、可选 OCR/ASR、LLM 生成和待确认落盘。
- 新增单执行器 Dispatcher，按创建时间顺序调度，支持批次取消、数量限制和单任务失败隔离。
- 新增取消令牌、指数退避、稳定错误映射和未知异常脱敏。
- 明确只获取公开内容，不实现登录、验证码、签名、访问控制或反爬绕过。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 58 项测试通过。
- 下一主任务切换为 `IMPORT-003`：公开内容获取与人工降级。

### IMPORT-001 持久化导入任务内核

- 新增小红书/抖音 URL 校验、平台识别与基础规范化。
- 新增导入任务生命周期、处理阶段、统一错误码、取消、失败、重试和重启恢复领域规则。
- 新增只依赖领域 Repository 的 Application 用例。
- SQLite 升级到 Schema v2，新增 `import_tasks`、恢复索引和 v1 → v2 迁移。
- `result_recipe_id` 明确为跨聚合逻辑引用，不建立会破坏任务状态不变量的 SQLite 外键。
- 修复待确认任务取消时未清理草稿逻辑引用的问题。
- 新增 Domain、Application、SQLite Repository 和迁移测试；`flutter analyze --no-pub` 无问题，41 项测试全部通过。
- `IMPORT-001` 验收完成并进入 `DONE`；下一后端切片为 `IMPORT-002` 内容获取与导入调度内核。

### SPK-001 Local-first SQLite 菜谱数据层

- 新增纯 Dart 菜谱、食材、步骤和分类领域模型及 Repository 契约。
- 新增 SQLite Schema v1，覆盖 `recipes`、`ingredients`、`recipe_steps`、`recipe_categories` 和 `recipe_category_relations`。
- 菜谱聚合新增/更新使用事务，启用外键和级联删除，无效分类关系会使整次保存回滚。
- 支持菜谱持久化读取、列表、文本搜索、收藏筛选、软删除、恢复、永久删除，以及分类排序和软删除。
- 新增 6 个真实 SQLite 临时文件测试；`flutter test` 总计 27 个测试全部通过，`flutter analyze` 无问题。
- 通过纯 ASCII Junction `C:\tmp\ai-recipe-mobile` 再次完成 Android Debug APK 构建。
- 新增架构文档 `docs/architecture/LOCAL_DATABASE.md` 和验收记录 `tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`。
- `SPK-001` 保持 `DOING`；SQLite 验证项已通过，下一步转入 `IMPORT-001` 后端任务状态机和分享 URL 接入。
### GitHub 首次发布

- 新增 `OPS-003`，将本地仓库发布到 GitHub 仓库 `zisjugoudan/ai-recipe`。
- 推送前确认远程仓库没有已有引用，避免覆盖远程历史。
- 创建根提交 `df55ef4 chore: initialize AI recipe project`。
- 配置 `origin` 并将本地 `main` 推送到 `origin/main`，建立默认上游关系。
- Flutter `build/`、Debug APK 和常见本地敏感文件继续由 `.gitignore` 排除。
- 新增验收记录 `tests/acceptance/OPS-003-github-publish-2026-07-28.md`。

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
