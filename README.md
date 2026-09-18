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

## 仓库内容边界

本仓库可以公开，因此个人数据与本地产物不进入版本库。

已排除的内容（仅保留在本地）：

| 内容 | 原因 |
|---|---|
| `design/assets/收款码/`、`code/apps/mobile/assets/payment/*.jpg` | 微信 / 支付宝收款码属于个人数据 |
| `design/assets/交流群.jpg`、`code/apps/mobile/assets/community/*.jpg` | 群二维码属于个人数据 |
| `视频剪辑/` | 录屏素材含本地开发环境画面，且体积超过 1 GB |
| `*.hprof`、`.tmp/`、`.trae/`、`.workbuddy/`、构建产物 | 本地产物与工具缓存 |

克隆后需要自行补齐的资产：`code/apps/mobile/assets/payment/` 与 `code/apps/mobile/assets/community/` 下的收款码和群二维码已被排除，缺少时 Flutter 构建会报找不到资产。文件名与补齐方式见这两个目录内的 `README.md`。

第三方内容边界：`design/assets/IP.png` 与 `design/assets/封面图.png` 是本项目水豚主厨角色的身份参考图，可用于哪些资产见 [design/assets/README.md](design/assets/README.md)。

## 当前阶段

Flutter 本地业务后端、HTML 原型到 Flutter 的视觉复刻、冰箱库存与推荐、导入链路、备份恢复等主链路均已实现，正处于逐项真机验收阶段；iOS 全程未验证。当前主线是 `SPK-002` 本地 OCR 原生能力验证；Android 模型包 Runtime 与安装可靠性基础切片已通过，真实 OCR 推理、真机指标、iOS 和跨进程互斥仍待完成。

具体状态以 [tracking/CURRENT.md](tracking/CURRENT.md) 为准。
