# 集成与契约测试

本目录计划覆盖：

- Recipe JSON Schema。
- ImportTask 状态机。
- LLM Provider 契约。
- OCR Provider 契约。
- OCR 插件 Manifest。
- 服务端统一错误码。
- 本地数据库迁移。
- 云同步冲突、软删除和重试。

每个 Provider 实现必须通过同一组契约测试，避免只有某个供应商能正常工作。
