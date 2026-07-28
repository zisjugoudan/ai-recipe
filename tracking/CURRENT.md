# 当前工作状态

> 本文件是项目当前状态的唯一事实源。每次开始工作必须读取，每次结束工作必须更新。  
> 最后更新：2026-07-28

## 当前阶段

**阶段：Sprint 0 技术验证与后端基础能力建设进行中**

## 当前目标

按照“后端能力优先、UI 后置”的顺序继续执行 P0 后端能力。统一 LLM Provider、Local-first SQLite 菜谱 Repository 和持久化导入任务状态机已完成，下一步建立平台内容获取/提取 Adapter 与导入调度接口，再接系统分享、OCR、ASR 和结构化菜谱生成。

## 正在进行

`SPK-001` 保持 `DOING`，`IMPORT-001` 已完成。LLM Provider、Local-first SQLite Schema v2、持久化导入任务状态机、Android Debug APK 构建和 Android 12 真机启动已通过；系统分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 仍待验证。


## 最近完成

- `OPS-001` 建立本地项目执行体系，验收通过。
- 用户确认移动端统一使用 Flutter，已记录 `ADR-0008`。
- 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile，已记录 `ADR-0009`。
- 用户更正 LLM 配置模型：不区分网络方案，统一填写协议、API Base URL、可空 Key 和模型；`ADR-0010` 已由 `ADR-0011` 取代。
- `OPS-002` 已初始化本地 Git 仓库，默认分支为 `main`；没有远程、提交或推送。
- `OPS-003` 已完成 GitHub 首次发布：`origin` 指向 `zisjugoudan/ai-recipe`，本地 `main` 跟踪 `origin/main`；根提交为 `df55ef4`。
- `DOC-001` 已将 Flutter、OCR、自定义 LLM API 与 Git 状态同步到长期事实源。
- 已创建 `code/apps/mobile` Flutter 工程并实现：
  - OpenAI-compatible Chat Completions Adapter。
  - Gemini native `generateContent` Adapter。
  - 统一配置校验、超时、取消和错误映射。
  - API Key 与普通配置分离，Key 使用 `FlutterSecureStorage`。
  - LLM 设置、连接测试和保存页面。
  - Local-first SQLite Schema v1 与菜谱 Repository。
  - 结构化 `Recipe`、`Ingredient`、`RecipeStep`、`RecipeCategory` 领域模型。
  - 菜谱、食材、步骤、分类、分类关系五张关系表。
  - 聚合事务写入、关闭重开持久化、更新、搜索、收藏筛选、软删除、恢复和永久删除。
  - 外键失败时整次菜谱保存回滚。
- 已修正取消令牌分层：`LlmCancellationToken` 位于 Domain 层，不再反向依赖 Provider。
- `dart format lib test` 已完成。
- `flutter analyze` 通过：`No issues found`。
- `flutter test --no-pub` 通过：41 个测试全部通过，覆盖 LLM Provider、菜谱 SQLite、导入任务 Domain/Application/SQLite 和 v1 → v2 迁移。
- 新增 SQLite 后 Android Debug APK 仍在纯 ASCII Junction 构建入口下成功构建；APK 位于 `code/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- Android 12 真机安装和启动通过，应用 PID 未发现错误级 Logcat。
- `IMPORT-001` 已实现小红书/抖音 URL 识别、任务状态机、取消/重试/恢复、Application 用例、SQLite v2 持久化和迁移。
- 验收记录：
  - `tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`
  - `tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`
  - `tests/acceptance/IMPORT-001-import-task-state-machine-2026-07-28.md`

## 下一步

1. `IMPORT-002`：定义平台内容获取、统一提取结果、Adapter 注册表和可测试的导入调度接口。
2. `IMPORT-003`：实现合规的公开内容获取路径和失败降级，不实现登录绕过或反爬规避。
3. `SPK-001`：验证 Android/iOS 系统分享入口接收 URL，并把输入交给 `CreateImportTask`。
4. `SPK-001` / `SPK-002`：建立 OCR Federated plugin / Platform Channel 最小桥接。
5. `SPK-003`：使用真实 OpenAI-compatible、Gemini 和本地兼容服务验证协议兼容性与结构化菜谱输出。
6. `APP-001`：补齐菜谱 Application 用例，再由前端接入菜谱库、分类和详情页面。
7. 在 macOS/iPhone 环境补齐 iOS 构建、Keychain、本地网络权限和 OCR 插件验证。

## 当前阻塞与约束

- 当前 Windows 环境不能完成 iOS 构建和真机测试，需要后续 macOS/iPhone 环境。
- Windows Flutter shader compiler 无法直接在含中文的仓库路径输出 Android 构建产物；当前通过 `C:\tmp\ai-recipe-mobile` 纯 ASCII Junction 构建。正式 CI 前应迁移到纯 ASCII 路径或建立稳定构建入口。
- PaddleOCR 的模型转换、体积、速度、内存和真机准确率尚未验证。
- OpenAI-compatible 与 Gemini 当前通过可注入 Transport 的本地契约测试；真实 Key/服务兼容性留给 `SPK-003`。
- 真机安全存储写入和删除完整流程尚未验证。
- SQLite 当前为 Schema v2；标签、来源快照、购物清单和同步元数据尚未加入。
- 导入调度器尚未实现并发抢占/租约；在该契约完成前只允许单执行器驱动任务。

## 当前有效文档

- 永久流程：`AGENTS.md`
- 产品需求：`docs/product/AI食谱应用产品需求文档.md`
- 用户故事：`docs/product/USER_STORIES.md`
- 移动端架构：`docs/architecture/MOBILE_ARCHITECTURE.md`
- Local-first 数据库：`docs/architecture/LOCAL_DATABASE.md`
- 导入任务流水线：`docs/architecture/IMPORT_PIPELINE.md`
- OCR 方案：`docs/architecture/OCR_PLUGIN.md`
- LLM 自定义 API 与 Provider 适配：`docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`
- 当前 Sprint：`tracking/sprints/SPRINT-00.md`
- 技术探索：`tracking/SPIKES.md`
- 当前 Spike：`research/spikes/SPK-001-cross-platform-framework.md`
- 当前 SQLite 验收：`tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`
- GitHub 首次发布验收：`tests/acceptance/OPS-003-github-publish-2026-07-28.md`

## 新会话交接说明

从这里继续时，不要重新比较 Flutter 与 React Native，不要恢复 LAN/VPN/HTTPS 产品模式，也不要重复初始化 Git 或重新创建远程仓库。统一 LLM 配置固定为“协议 + API Base URL + 可空 Key + 模型”。当前执行顺序是后端能力优先、UI 后置；先继续 `IMPORT-002` 内容获取与单执行器调度内核，`SPK-001` 剩余真机能力按后端优先顺序推进，所有真实实验数据必须写入 Spike 和验收记录。
