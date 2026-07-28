## 2026-07-28

### SPK-002 本地 OCR 模型 Runtime 阶段切片

- 新增本地 OCR 模型包服务，支持下载、扩展名限制、大小与 SHA-256 校验、安装、健康检查后激活、删除、失败回滚和中断恢复。
- `active.json`、`state.json` 和 `manifest.json` 使用临时文件原子切换；Windows 覆盖失败时可通过备份恢复，升级失败保留上一 active 与 `installedVersion`。
- Flutter 新增 `ai_recipe/local_ocr` MethodChannel 契约，包含 `probe`、`healthCheck`、`recognize`，并完成响应校验和稳定错误映射。
- Android 集成 ONNX Runtime `1.20.0`，健康检查会创建 ONNX Session 并验证输入输出；`recognize` 仍固定返回 `inference_not_implemented`。
- 新增 `PlatformOcrProvider`、本地模型 Application Use Cases、Backend Facade 管理入口和设备组合根装配。
- `dart format lib test` 无变化，`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 237 项通过，Android Debug APK 构建成功。
- `recognitionSupported` 仍为 `false`；真实 PP-OCRv5 推理、Android 真机性能/准确率和 iOS 路径尚未完成，因此 `SPK-002` 保持 `DOING`。
## 2026-07-28

### APP-003 应用后端组合根与统一门面

- 新增 `AiRecipeBackendFacade`，统一暴露会话、能力、菜谱库、导入任务调度、草稿确认和放弃入口。
- 新增 `ImportExecutionPlan` 与 `ImportTaskRunnerFactory`，按自定义/托管 LLM、本地/云 OCR 和托管 ASR 路线执行能力校验并装配 Provider。
- 新增设备运行时能力仓库与设备组合根，集中管理 SQLite、SharedPreferences、安全 LLM 配置、公开内容 Adapter 和 Provider Builder 生命周期。
- LLM 草稿 Processor 传播当前会话 `userId`：登录用户草稿归属用户，游客草稿保持本地匿名。
- 草稿确认强制发布，已发布菜谱的确认重试不会重复增加本地版本；放弃草稿执行软删除并取消任务。
- 修复 OCR 后进入 ASR 时全局进度从 60% 倒退到 35% 的缺陷，ASR 现固定使用 61%–64% 进度区间并加入回归测试。
- 新增 Facade、组合根、运行时能力、Runner Factory、执行计划和幂等确认测试。
- `dart format lib test` 无额外变化，`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 217 项全部通过。
- `APP-003` 进入 `DONE`；下一项后端主任务转向 `SPK-002` 本地 OCR 原生插件与模型下载验证。
### APP-002 游客/登录会话与后端能力策略

- 新增纯 Dart `AppSession`，区分游客与已认证用户，但不存储或传递认证 Token。
- 新增八类统一能力、运行时就绪状态、稳定不可用原因、能力快照和能力守卫。
- 游客与登录用户都可使用本地菜谱、公开链接导入、自定义 LLM API 和本地 OCR；托管 AI、云 OCR、托管 ASR 与云同步要求登录。
- 新增 `DeviceAppSessionRepository`，SharedPreferences 只保存非敏感会话元数据，并严格拒绝损坏 Schema、未知字段和身份字段不完整的数据。
- Repository 未知异常统一映射为脱敏的 Application 错误；页面后续不得自行拼装权限规则。
- 新增 21 项自动化测试；`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 197 项通过。
- `APP-002` 进入 `DONE`；登录协议、Token 安全仓库、真实托管服务和云同步继续作为独立任务实施。
会影响产品、流程、架构、设计、测试或交付方式的有效变化。代码的细粒度变化以后由版本控制记录。

## 2026-07-28

### APP-001 本地优先菜谱库 Application 用例

- 新增 `RecipeLibraryUseCases`，统一手动创建、详情、更新、筛选、收藏、回收站和分类管理入口。
- UI 后续只依赖 Application Facade，不直接访问 SQLite、HTTP Client 或供应商 SDK。
- 更新使用完整表单快照，保留聚合身份并校验食材/步骤 ID 所属；新子项 ID 由 Application 生成。
- Recipe Repository 新增状态与分类筛选；Category Repository 新增详情、恢复和永久删除。
- 分类软删除只移除菜谱分类关系，恢复不自动恢复历史关系。
- Repository 未知异常统一映射为脱敏的稳定 Application 错误。
- 真实 SQLite 已验证游客 `userId == null` 聚合关闭重开、Unicode 内容、筛选和回收站流程。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 176 项通过，`git diff --check` 通过。
- `APP-001` 进入 `DONE`；下一主任务切换为 `APP-002` 游客模式后端能力策略。

### ASR-001 ASR Provider 与导入预处理

- 新增统一 `AsrProvider`、`AsrMediaInput`、`AsrTranscript`、分段时间戳和稳定错误契约。
- `ImportTextFragment` 新增语言、起止时间和说话人证据字段，JSON Schema 约束起止时间成对出现。
- 新增 ASR 预处理 Decorator，支持跳过、媒体排序、数量/时长限制、分段去重、部分结果、取消和错误映射。
- Runner 已验证 `extracting → transcribing → generating → review`。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 161 项测试通过；相关 Schema 通过 Draft 2020-12 元 Schema 校验。
- `ASR-001` 进入 `DONE`；真实本地/云 ASR Provider、音轨抽取和真机性能保留给后续任务。

### OCR-001 OCR Provider 与导入预处理

- 新增统一 `OcrProvider`、`OcrDocument`、`OcrTextBlock` 和稳定错误契约。
- 新增严格模型 Manifest 与模型安装状态。
- `ImportTextFragment` 新增 `confidence`、`sourceMediaOrder`、`sourceProvider`。
- 新增 OCR 预处理 Decorator，支持跳过、媒体排序、限制、部分结果、去重、取消和错误映射。
- Runner 已验证 `extracting → ocr → generating → review`。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 141 项测试通过。
- `OCR-001` 进入 `DONE`；Android/iOS 原生桥接和模型下载保留给 `SPK-002`。

### AI-002 结构化菜谱生成 Processor

- 新增受限 Prompt，将页面内容视为不可信数据并限制为 40,000 字符。
- 新增纯 JSON / 单 fenced JSON 提取和严格结构化菜谱 Schema 校验。
- 菜谱、食材、步骤 ID、排序、状态、时间戳和版本全部由本地生成，结果只保存为 `RecipeStatus.draft`。
- 标题不再代替 OCR/ASR 正文；标题-only 且需要媒体识别时不调用 LLM，避免幻觉生成。
- 明确 Repository 保存成功后的提交点语义，解决已保存草稿被任务取消后失去引用的竞态。
- 新增真实 SQLite 文件关闭/重开持久化测试，Recipe、Ingredient 和 Step 均可恢复读取。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 113 项测试通过。
- `AI-002` 验收完成并进入 `DONE`；下一主任务切换为 `OCR-001`。

### IMPORT-003 公开内容获取与人工降级

- 新增可注入的受限 HTTP Transport，覆盖超时、取消、有限重定向、平台主机白名单、HTTPS 降级拒绝、响应体上限和 Content-Type 白名单。
- 新增 HTML、Open Graph、JSON-LD、独立 JSON 和纯文本公共元数据解析，支持相对 URL、媒体去重和顺序保持。
- 新增小红书与抖音公开内容 Adapter，统一生成文本片段、图片/视频引用、作者、发布时间和后续 OCR/ASR 警告。
- 登录要求、内容不可用、超时、网络、安全策略和空载荷均映射为稳定且脱敏的项目错误。
- 新增粘贴正文、本地图片和本地视频人工降级路径，不实现登录、验证码、签名、访问控制或反爬绕过。
- 新增 4 个固定 Fixture 和 36 项定向测试；`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 94 项测试通过。
- `IMPORT-003` 验收完成并进入 `DONE`；下一阶段转入 OCR/ASR 与 LLM 结构化菜谱 Processor。

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
