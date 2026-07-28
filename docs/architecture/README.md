# 技术架构目录

本目录存放长期技术架构、模块边界和架构图。完整产品级建议见产品需求文档第 14 章。

## 当前架构原则

- 移动端使用 Flutter，首要支持 iOS 和 Android。
- 本地数据库是客户端主要读取来源；云同步不能成为本地功能前置条件。
- UI 和业务层不直接依赖供应商 SDK。
- LLM、OCR、ASR、链接解析均通过 Provider/Adapter 接口。
- API Key 只能进入系统安全存储。
- 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile，通过 Flutter federated plugin 接入。
- 用户自有 LLM 统一使用“协议类型 + API 地址 + Key + 模型”配置，不把网络拓扑定义为产品模式。

## 已有文档

- [移动端架构基线](MOBILE_ARCHITECTURE.md)
- [OCR Provider 与本地插件方案](OCR_PLUGIN.md)
- [LLM 自定义 API 与 Provider 适配方案](LOCAL_LLM_NETWORK_SECURITY.md)

## 计划文档

- `LOCAL_DATA.md`：本地数据库 Schema、迁移和同步元数据。
- `SYNC_ENGINE.md`：增量同步、软删除和冲突处理。
- `AI_PROVIDER.md`：LLM/ASR Provider 契约。
- `IMPORT_PIPELINE.md`：导入状态机、缓存和重试。

技术选型生效前必须写入 `tracking/DECISIONS.md`；技术可行性仍需通过对应 Spike 的真实环境验证。
