# AI 食谱应用

移动端优先、跨平台、本地优先的 AI 食谱管理应用。支持从小红书、抖音等来源导入内容，通过可替换的 OCR、ASR 与 LLM Provider 生成结构化菜谱。

## 开始任何工作前

必须依次阅读：

1. [AGENTS.md](AGENTS.md)
2. [当前进度](tracking/CURRENT.md)
3. [任务清单](tracking/BACKLOG.md)
4. [决策记录](tracking/DECISIONS.md)
5. 当前任务相关的产品、设计、架构和测试文档

## 项目目录

```text
.
├── AGENTS.md                永久协作规程，每次工作必读
├── README.md                项目导航
├── docs/
│   ├── product/             产品需求与用户故事
│   ├── architecture/        技术架构与模块边界
│   └── api/                 API、Schema 与前后端契约
├── tracking/                当前进度、任务、决策、风险和迭代记录
├── design/                  流程、线框、UI 图片、HTML 原型与评审
├── research/                Spike 技术探索和实验结论
├── code/                    移动端、服务端、共享包和开发工具代码
└── tests/                   验收、集成测试、测试样本与 AI 质量记录
```

## 核心文档

- [产品需求文档](docs/product/AI食谱应用产品需求文档.md)
- [用户故事与验收标准](docs/product/USER_STORIES.md)
- [当前工作状态](tracking/CURRENT.md)
- [项目任务清单](tracking/BACKLOG.md)
- [项目决策记录](tracking/DECISIONS.md)
- [风险登记表](tracking/RISKS.md)
- [技术探索清单](tracking/SPIKES.md)
- [设计交付规则](design/README.md)
- [移动端 Flutter 架构](docs/architecture/MOBILE_ARCHITECTURE.md)
- [OCR 插件架构](docs/architecture/OCR_PLUGIN.md)
- [LLM 自定义 API 与 Provider 适配](docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md)
- [代码目录规则](code/README.md)
- [测试策略](tests/README.md)

## 当前阶段

项目执行体系与本地 Git 仓库已初始化，Flutter、OCR 和 LLM Provider 方向已经确定。`SPK-001` 已启动，正在创建最小 Flutter 工程并验证自定义 API Provider，具体状态以 `tracking/CURRENT.md` 为准。
