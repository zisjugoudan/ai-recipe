# API 与契约目录

本目录用于前端、服务端、本地 Provider 和插件之间的稳定契约。

## 契约优先规则

1. 数据字段和错误行为先写契约，再实现调用方与提供方。
2. Schema 必须有版本号。
3. 不兼容变更必须新增版本或迁移方案。
4. Mock 数据必须符合相同 Schema。
5. API 错误统一映射为项目错误码。
6. 契约测试放在 `tests/integration/`。

## 已建立契约

- `import-task.schema.json`：导入任务 v1，已由 Domain、Application、SQLite v2 和迁移测试验证。

## 计划契约

- `recipe.schema.json`
- `llm-provider.schema.json`
- `ocr-provider.schema.json`
- `ocr-plugin-manifest.schema.json`
- `sync-change.schema.json`
- `error-codes.md`

计划契约在实现和验收完成前不能伪装为稳定 API。