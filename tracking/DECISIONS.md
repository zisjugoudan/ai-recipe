# 项目决策记录

> 这里只记录已经确认并对后续有约束力的决定。尚未确认的问题放入任务、风险或 Spike。

## 决策索引

| ID | 日期 | 状态 | 决策 |
|---|---|---|---|
| ADR-0001 | 2026-07-27 | 生效 | 项目协作、文档和进度全部以本地仓库为事实源 |
| ADR-0002 | 2026-07-27 | 生效 | 项目采用移动端优先、跨平台方向，首要支持 iOS 与 Android |
| ADR-0003 | 2026-07-27 | 生效 | 核心数据采用 Local-first；游客可完整使用本地核心功能 |
| ADR-0004 | 2026-07-27 | 生效 | 游客不可使用平台托管 AI 或平台云同步，但可使用本地/自有 API |
| ADR-0005 | 2026-07-27 | 生效 | LLM、OCR、ASR 和链接解析采用 Provider/Adapter 抽象 |
| ADR-0006 | 2026-07-27 | 生效 | 任何需求变更先改事实源文档，再改任务、设计、代码和测试 |
| ADR-0007 | 2026-07-27 | 生效 | UI 设计允许使用本地图片、SVG、Markdown 或可离线 HTML 原型 |
| ADR-0008 | 2026-07-27 | 生效 | 移动端统一采用 Flutter，不再进行 React Native 比选 |
| ADR-0009 | 2026-07-27 | 生效 | 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile |
| ADR-0010 | 2026-07-27 | 被替代 | 曾将 LAN、私有 VPN 与 HTTPS 定义为三种产品连接模式，已由 ADR-0011 更正 |
| ADR-0011 | 2026-07-27 | 生效 | 自定义 LLM 统一使用协议类型、API 地址、Key 与模型配置，供应商差异由 Adapter 处理 |

---

## ADR-0001：本地仓库作为协作事实源

### 背景

当前团队由项目负责人和 Codex 组成，不需要依赖云端项目管理或设计协作平台。

### 决策

产品、进度、设计、技术探索、代码和测试全部保存在项目目录；聊天只负责提出请求和说明结果。

### 影响

- 新会话可以通过本地文档恢复上下文。
- 所有有效决定必须落盘。
- 不得用云平台链接替代本地交付文件。

---

## ADR-0002 至 ADR-0005

详细产品约束见 `docs/product/AI食谱应用产品需求文档.md` 的第 2.2、5.13、5.15 和 14 章。数据库、同步策略和具体工程依赖仍需对应 Spike/任务验证后另建 ADR。

---

## ADR-0008：移动端统一采用 Flutter

- 日期：2026-07-27
- 状态：生效
- 关联任务：SPK-001、ARCH-001

### 背景

产品以移动端为主，需要同时支持 iOS 和 Android，并具备 Local-first、分享入口、后台任务、安全存储、本地 OCR 插件和自定义 API 能力。项目负责人已明确选择 Flutter。

### 决策

移动客户端统一使用 Flutter，不再投入时间进行 React Native 二选一。`SPK-001` 改为 Flutter 关键能力基线验证，负责发现平台阻塞，而不是重新决定框架。

### 原因

- 与用户明确技术方向一致。
- Dart/Flutter 可共享大部分业务、领域和 UI 代码。
- Platform Channels 与 federated plugin 能隔离必要的 iOS/Android 原生能力。
- 当前开发机已安装 Flutter 3.38.5 stable 和 Dart 3.10.4。

### 影响与代价

- 需要维护少量 Swift/Objective-C 与 Kotlin/Java 插件代码。
- Windows 无法完成 iOS 构建，必须在后续 macOS/iPhone 环境补验。
- 不能因为框架已选定而跳过分享、后台任务、通知、安全存储和 OCR 桥接实测。

### 验证方式

执行 `SPK-001` 和 `ARCH-001`，验收标准见 `docs/architecture/MOBILE_ARCHITECTURE.md`。

---

## ADR-0009：本地 OCR 首选 PaddleOCR PP-OCRv5 mobile

- 日期：2026-07-27
- 状态：生效
- 关联任务：SPK-002、OCR-001

### 背景

输入包含中文菜谱截图、食材列表、中英文单位、长步骤和平台水印。游客应能在不调用云服务的情况下使用 OCR，模型还需按需安装、升级和删除。

### 候选方案

- PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile。
- 系统原生/Google ML Kit OCR。
- 仅使用云 OCR。

### 决策

首选 PaddleOCR PP-OCRv5 mobile，并使用 ONNX Runtime Mobile 在 Android/iOS 推理；通过 Flutter federated plugin 暴露统一 `OcrProvider`。模型作为带 Manifest 和 SHA-256 的资源包按需下载。

### 原因

更贴合中文、长文本和复杂截图；两端可复用模型；支持离线和游客模式；不把业务层绑定到单一平台或云供应商。

### 影响与代价

需要承担模型转换、前后处理、原生运行时和设备优化成本。`SPK-002` 若证明内存、速度、体积或 iOS 集成不可接受，必须更新本 ADR；系统/ML Kit 是 MVP 降级候选。

### 验证方式

执行 `SPK-002` 的 Android/iOS 性能、准确率、模型下载和异常测试，细节见 `docs/architecture/OCR_PLUGIN.md`。

---

## ADR-0010：本地 LLM 的三种网络连接模式

- 日期：2026-07-27
- 状态：被 `ADR-0011` 取代
- 关联任务：SPK-003、AI-001

### 背景

游客不能使用平台托管 AI，但可以连接电脑、NAS 或家庭服务器上的 Ollama/OpenAI-compatible API。移动网络存在局域网权限、明文 HTTP、网络隔离、动态 IP、证书和密钥泄露风险。

### 决策

1. `lan_http`：同一局域网私网地址，用户显式开启不安全 HTTP。
2. `private_network`：Tailscale/WireGuard 等加密私有网络，作为远程访问首选。
3. `https`：带认证的 HTTPS 反向代理，面向高级自托管用户。

业务协议优先采用 OpenAI-compatible API；Ollama 原生 API 通过 Adapter 支持。禁止默认允许公网 HTTP，禁止建议用户裸露 Ollama 端口。

### 原因

LAN 降低 MVP 门槛；私有网络兼顾远程访问和加密；HTTPS 适合已有 NAS/域名基础设施的用户。

### 影响与代价

客户端需要 URL 分类、DNS 解析复核、重定向限制、超时/取消和敏感日志过滤。iOS/Android 分别处理本地网络和明文策略。API Key 只能进入 Keychain/Keystore。

### 验证方式

执行 `SPK-003`，按 `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md` 完成真机实验。

---

## ADR-0011：自定义 LLM 使用单一 API 配置与协议 Adapter

- 日期：2026-07-27
- 状态：生效
- 关联任务：SPK-001、SPK-003、AI-001
- 取代：ADR-0010

### 背景

项目负责人明确：移动端不需要让用户选择 LAN、VPN 或 HTTPS 等网络方案。用户只需要配置 API 地址和 Key；OpenAI、Gemini 等接口差异由应用内部适配。

### 决策

自定义 LLM 的统一配置为协议类型、API Base URL、API Key 和模型。API 地址所在网络不形成不同产品模式。首版实现 OpenAI-compatible 与 Gemini Adapter，页面和菜谱业务只依赖统一 `LlmProvider`。

### 原因

这符合用户心智，减少配置复杂度，并将供应商路径、鉴权、请求体和响应格式差异隔离在可测试的 Adapter 中。

### 影响与代价

需要为每种协议维护独立 Adapter 和契约测试。HTTP 地址仍需显示明文风险；API Key 仍只能存入 Keychain/Keystore。原先针对三种网络拓扑的产品配置和验收项全部取消。

### 验证方式

`SPK-001` 实现 Flutter 基础骨架和两个 Adapter 的单元测试；`SPK-003` 使用真实服务完成多协议兼容性矩阵。

---

## 新决策模板

```markdown
## ADR-XXXX：决策标题

- 日期：YYYY-MM-DD
- 状态：提议 / 生效 / 废弃 / 被替代
- 关联任务：TASK-ID

### 背景
### 候选方案
### 决策
### 原因
### 影响与代价
### 验证方式
```
