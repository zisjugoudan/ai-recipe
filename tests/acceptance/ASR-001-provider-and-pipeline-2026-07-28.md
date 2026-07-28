# ASR-001 Provider 与导入预处理验收记录

- 日期：2026-07-28
- 状态：通过
- 任务：`ASR-001`

## 验收范围

- [x] 本地插件与云 ASR 共享同一 `AsrProvider` 输入、输出和错误契约。
- [x] ASR 分段包含文本、起止时间、可选置信度和说话人标签。
- [x] `ImportTextFragment` 可选保留 ASR 语言、起止时间、媒体顺序和 Provider ID。
- [x] 无 `requiresAsr` 时跳过 ASR。
- [x] 需要 ASR 时按媒体顺序转写 audio/video 并把分段补入 `ImportContent`。
- [x] 无媒体、超时长、空结果、取消和 Provider 错误映射为稳定导入错误。
- [x] 媒体数量限制和单媒体失败可产生明确的 `partialContent`。
- [x] 成功后移除 `requiresAsr` 并复用下游结构化菜谱 Processor。
- [x] Runner 进度按 `extracting → transcribing → generating → review` 前进。
- [x] 日志和错误不包含完整转写文本、本地媒体路径、Key 或供应商原始响应。

## 自动化验证

- `dart format lib test`：通过，81 个文件，0 个待格式化修改。
- `flutter analyze --no-pub`：通过，No issues found。
- `flutter test --no-pub`：通过，共 161 项测试。
- `docs/api/import-content.schema.json`：JSON 解析与 Draft 2020-12 元 Schema 校验通过。
- `git diff --check`：通过。
## 已知限制

- 本轮不包含真实本地 ASR 引擎、音轨抽取、云 ASR 供应商实现或真机性能验证。
- Windows 环境不验证 iOS。