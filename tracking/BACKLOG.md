# 项目任务清单

> 状态只使用：`TODO`、`DOING`、`BLOCKED`、`VERIFY`、`DONE`、`CANCELLED`。  
> 原则上同一时间只有一个主任务处于 `DOING`。

## 当前任务

| ID | 优先级 | 状态 | 任务 | 验收摘要 | 关联文档 |
|---|---|---|---|---|---|
| OPS-001 | P0 | DONE | 建立本地项目执行体系 | 目录分离；根目录必读规程；进度、任务、决策、风险、设计、测试模板可用 | `AGENTS.md` |
| OPS-002 | P0 | DONE | 初始化本地 Git 仓库 | `main` 分支可用；忽略规则生效；无远程和首次提交；验收记录完成 | `tests/acceptance/OPS-002-git-init-2026-07-27.md` |
| OPS-003 | P0 | DOING | 发布项目到 GitHub | 关联 zisjugoudan/ai-recipe；创建首次提交并推送 main；验证远程分支和敏感文件排除 | 	racking/CHANGELOG.md |
| DOC-001 | P0 | DONE | 同步本轮技术方向到长期事实源 | 产品、流程、架构、任务与验收文档一致；Markdown 编码和链接检查通过 | `tests/acceptance/DOC-001-technical-direction-sync-2026-07-27.md` |
| SPK-001 | P0 | DOING | Flutter 关键能力基线验证 | LLM Provider、21 项测试、Android APK 构建与真机启动已通过；数据库、分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 仍待验证 | `research/spikes/SPK-001-cross-platform-framework.md` |
| SPK-002 | P0 | TODO | PaddleOCR 本地引擎与插件验证 | Android/iOS 至少各验证一条 PP-OCRv5 mobile + ONNX Runtime 可行路径及模型下载流程 | `research/spikes/SPK-002-local-ocr.md` |
| SPK-003 | P0 | TODO | 自定义 LLM API 多协议兼容性验证 | 验证 OpenAI-compatible、Gemini、本地兼容服务、超时、取消和结构化输出 | `research/spikes/SPK-003-local-llm-api.md` |
| ARCH-001 | P0 | TODO | 确定移动端架构与代码结构 | 按 Flutter 架构基线初始化可运行工程 | `docs/architecture/MOBILE_ARCHITECTURE.md` |
| APP-001 | P0 | TODO | 创建本地优先菜谱库骨架 | iOS/Android 可运行；本地数据库可创建并读取菜谱 | `docs/product/USER_STORIES.md` |
| APP-002 | P0 | TODO | 实现游客模式 | 无登录完成本地菜谱核心流程 | `docs/product/USER_STORIES.md` |
| IMPORT-001 | P0 | TODO | 定义导入任务状态机 | 状态、错误、取消、重试和恢复契约明确 | `docs/api/README.md` |
| AI-001 | P0 | TODO | 定义 LLM Provider 接口 | OpenAI-compatible 和 Ollama 可接入统一接口 | `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md` |
| OCR-001 | P0 | TODO | 定义 OCR Provider 与插件 Manifest | PaddleOCR 本地插件和自有云 OCR 使用统一输出 | `docs/architecture/OCR_PLUGIN.md` |

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


