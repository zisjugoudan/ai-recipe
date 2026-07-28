# ASR Provider 与导入预处理架构

> 任务：`ASR-001`
> 状态：已完成
> 范围：纯 Dart 领域契约与导入流水线
> 原生/云端实现：后续独立任务

## 1. 目标

让本地 ASR 插件与云端 ASR Adapter 使用同一领域契约，把公开视频或用户选择的本地音视频转成带时间证据的文本片段，再复用结构化菜谱生成 Processor：

```text
ImportContent.media(video/audio)
→ AsrProvider
→ AsrTranscript / AsrTranscriptSegment
→ ImportTextFragment（媒体序号、Provider、语言、起止时间、置信度）
→ 新 ImportContent
→ LlmRecipeGenerationProcessor
```

ASR 只负责转写，不直接判断食材、用量和步骤，也不直接保存 Recipe。

## 2. 本轮范围

- 定义 `AsrProvider`、音视频输入、转写文档、分段时间戳和稳定错误。
- 本地插件与云 API 共用领域输出，不让 UI 依赖供应商 SDK。
- 扩展 `ImportTextFragment` 的可选 ASR 证据字段。
- 实现 ASR 导入预处理器，支持跳过、媒体排序、数量/时长限制、去重、部分结果、取消和错误映射。
- 验证 Runner 的 `extracting → transcribing → generating → review` 状态顺序。

## 3. 非目标

- 不在本轮集成 whisper.cpp、系统语音框架或具体云 ASR 供应商。
- 不下载平台受保护的视频，不绕过登录、验证码、签名或访问控制。
- 不在纯 Dart 层抽取视频音轨、切片、重采样或做声纹识别。
- 不把完整转写文本、媒体本地路径、API Key 或供应商原始响应写入日志。

## 4. Provider 契约

`AsrProvider` 每次转写一个音频或视频输入。输入只允许：

- HTTPS 远程媒体 URL；或
- 应用媒体库中的 `localAssetId`；
- 媒体类型必须为 audio 或 video；
- 可选 MIME、已知时长、语言提示和稳定媒体顺序。

输出 `AsrTranscript`：

- `providerId`、`modelVersion`、`language`；
- 按起始时间和结束时间排序的 `AsrTranscriptSegment`；
- 每段包含 `text`、`startMs`、`endMs`；
- 可选 `confidence` 和 `speakerLabel`；
- 可选总处理耗时和媒体时长；
- 本地计算 `fullText` 和平均置信度。

## 5. 导入预处理规则

- 没有 `requiresAsr` 时跳过 ASR，直接进入下游 Processor。
- 有 `requiresAsr` 但没有 audio/video 媒体时返回非重试 `asrFailed`。
- 默认最多转写 3 个媒体；超出部分不处理并标记 `partialContent`。
- 已知单媒体时长默认不得超过 30 分钟；超限在调用 Provider 前失败。
- 按媒体 `order` 顺序转写；每次调用前后检查取消。
- 每个非空、未重复的 ASR 分段转换成一个 `caption` 文本片段，并保留 Provider、媒体序号、语言、起止时间和置信度。
- 某个媒体失败但其他媒体得到可用分段时，保留成功结果并标记 `partialContent`；全部失败时返回稳定错误。
- 至少得到一个可用分段后移除 `requiresAsr` 和 `missingText`，再调用下游 Processor。

## 6. 稳定错误

| AsrProviderErrorKind | 导入任务错误 | 可重试 |
|---|---|---|
| `cancelled` | `cancelled` | 否 |
| `networkUnavailable` | `networkUnavailable` | 是 |
| `timeout` | `timeout` | 是 |
| `rateLimited`、`unknown` | `asrFailed` | 是 |
| 其他 Provider 错误 | `asrFailed` | 否 |

错误文案最长保留 240 字符并压缩空白。未知异常只返回稳定通用文案。

## 7. 安全边界

- 远程媒体地址必须是 HTTPS；本地媒体只通过应用内部 `localAssetId` 传递。
- 云端 ASR 调用前由产品层明确提示音视频会上传到哪个 Provider。
- Key 只存 Keychain/Keystore，不写 SQLite、日志、备份或同步。
- Provider 不得返回 Authorization Header、签名参数或完整供应商响应。
- 用户仍需在菜谱确认页检查结构化结果，ASR 文本不能直接覆盖已有菜谱。

## 8. 验收入口

- API Schema：`docs/api/import-content.schema.json`
- 自动化测试：`code/apps/mobile/test/domain/asr_models_test.dart`
- Processor 测试：`code/apps/mobile/test/application/asr_enriching_import_content_processor_test.dart`
- Runner 集成：`code/apps/mobile/test/application/asr_recipe_generation_runner_integration_test.dart`
- 验收记录：`tests/acceptance/ASR-001-provider-and-pipeline-2026-07-28.md`

## 9. 自动化验证

- `dart format lib test`：通过，81 个 Dart 文件无需额外修改。
- `flutter analyze --no-pub`：通过，No issues found。
- `flutter test --no-pub`：通过，共 161 项测试。
- `docs/api/import-content.schema.json`：通过 Draft 2020-12 元 Schema 校验。
- Windows 环境未验证 iOS、本地 ASR 引擎、云 ASR 供应商或真机性能。