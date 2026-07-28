# 项目任务清单

> 状态只使用：`TODO`、`DOING`、`BLOCKED`、`VERIFY`、`DONE`、`CANCELLED`。
> 原则上同一时间只有一个主任务处于 `DOING`。

## 当前任务

| ID | 优先级 | 状态 | 任务 | 验收摘要 | 关联文档 |
|---|---|---|---|---|---|
| OPS-001 | P0 | DONE | 建立本地项目执行体系 | 目录分离；根目录必读规程；进度、任务、决策、风险、设计、测试模板可用 | `AGENTS.md` |
| OPS-002 | P0 | DONE | 初始化本地 Git 仓库 | `main` 分支可用；忽略规则生效；无远程和首次提交；验收记录完成 | `tests/acceptance/OPS-002-git-init-2026-07-27.md` |
| OPS-003 | P0 | DONE | 发布项目到 GitHub | `origin` 已关联 `zisjugoudan/ai-recipe`；首次提交和 `main` 推送完成；上游与敏感文件排除已验证 | `tests/acceptance/OPS-003-github-publish-2026-07-28.md` |
| DOC-001 | P0 | DONE | 同步本轮技术方向到长期事实源 | 产品、流程、架构、任务与验收文档一致；Markdown 编码和链接检查通过 | `tests/acceptance/DOC-001-technical-direction-sync-2026-07-27.md` |
| SPK-001 | P0 | BLOCKED | Flutter 关键能力基线验证 | LLM Provider、SQLite v2、41 项测试和 Android APK 已通过；分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 仍待验证 | `research/spikes/SPK-001-cross-platform-framework.md` |
| SPK-002 | P0 | DOING | PaddleOCR 本地引擎与插件验证 | 模型包管理、同包进程内串行队列、MethodChannel、Android ONNX Session 健康检查和 244 项测试已通过；真实识别、真机指标与 iOS 仍待完成 | `research/spikes/SPK-002-local-ocr.md` |
| SPK-003 | P0 | TODO | 自定义 LLM API 多协议兼容性验证 | 验证 OpenAI-compatible、Gemini、本地兼容服务、超时、取消和结构化输出 | `research/spikes/SPK-003-local-llm-api.md` |
| ARCH-001 | P0 | TODO | 确定移动端架构与代码结构 | 按 Flutter 架构基线初始化可运行工程 | `docs/architecture/MOBILE_ARCHITECTURE.md` |
| APP-001 | P0 | DONE | 创建本地优先菜谱库后端用例 | 菜谱/分类 CRUD、筛选、回收站、稳定错误和游客 SQLite 重开已通过 176 项全量测试 | `docs/architecture/RECIPE_LIBRARY_APPLICATION.md` |
| APP-002 | P0 | DONE | 实现游客模式后端能力策略 | 会话元数据、八类能力矩阵、稳定原因码、能力守卫和 SharedPreferences 严格序列化已通过 197 项全量测试 | `docs/architecture/APP_ACCESS_CAPABILITIES.md` |
| APP-003 | P0 | DONE | 建立应用后端组合根与主功能统一门面 | 统一 Facade、设备组合根、能力路线、草稿确认/放弃、重复确认保护和完整导入链路已通过 217 项全量测试 | `docs/architecture/APPLICATION_BACKEND_FACADE.md` |
| IMPORT-001 | P0 | DONE | 定义导入任务状态机 | 状态、错误、取消、重试、重启恢复、SQLite v2 迁移和 Application 用例已通过 41 项全量测试 | `docs/architecture/IMPORT_PIPELINE.md` |
| IMPORT-002 | P0 | DONE | 定义内容获取与导入调度内核 | 统一内容 Schema、Adapter Registry、Runner、单执行器 Dispatcher、取消和稳定错误映射已通过自动化验收 | `docs/architecture/IMPORT_CONTENT_ADAPTER.md` |
| IMPORT-003 | P0 | DONE | 实现公开内容获取与降级 | 小红书/抖音公开 Fixture、受限 HTTP Transport、稳定错误映射和人工粘贴/媒体降级已通过 94 项全量测试 | `docs/architecture/PUBLIC_CONTENT_IMPORT.md` |
| AI-001 | P0 | DONE | 定义 LLM Provider 接口 | OpenAI-compatible 与 Gemini native 已通过统一接口、配置校验、错误映射和 Fixture 测试 | `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md` |
| AI-002 | P0 | DONE | 实现结构化菜谱生成 Processor | 受限 Prompt、严格 Schema、草稿持久化、取消提交点和真实 SQLite 重开验证已通过 113 项全量测试 | `docs/architecture/RECIPE_GENERATION_PROCESSOR.md` |
| OCR-001 | P0 | DONE | 定义 OCR Provider 与插件 Manifest | 统一 Provider、严格 Manifest、OCR 证据字段和导入预处理流水线已通过 141 项全量测试 | `docs/architecture/OCR_PLUGIN.md` |
| ASR-001 | P0 | DONE | 定义 ASR Provider 与导入预处理流水线 | 统一 Provider、时间证据、媒体限制、部分结果、错误映射和 Runner 集成已通过 161 项全量测试 | `docs/architecture/ASR_PROVIDER.md` |

## 待细化产品任务

| ID | 优先级 | 状态 | 任务 |
|---|---|---|---|
| PROD-001 | P0 | TODO | 补齐首页、分类和菜谱详情的逐页面验收标准 |
| PROD-002 | P0 | TODO | 补齐链接导入失败及降级流程的文案和状态 |
| DESIGN-001 | P0 | TODO | 绘制链接导入低保真全流程 |
| DESIGN-002 | P0 | TODO | 绘制首页、菜谱详情、编辑和烹饪模式线框图 |
| TEST-001 | P0 | TODO | 建立第一批小红书/抖音公开测试样本 |
| TEST-002 | P0 | TODO | 建立 AI 菜谱解析人工评分基线 |

## 完成定义

任务进入 `DONE` 前必须满足验收、测试记录、文档同步、已知缺陷说明和当前状态更新。
