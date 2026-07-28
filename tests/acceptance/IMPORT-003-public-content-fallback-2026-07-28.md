# IMPORT-003 公开内容获取与人工降级验收

- 日期：2026-07-28
- 状态：通过
- 任务：`IMPORT-003`

## 验收范围

- [x] 可注入 HTTP Transport，不在 Domain/Application 直接依赖 `http.Client`。
- [x] 超时、取消、有限重定向、目标主机校验、响应体上限和 Content-Type 白名单可测试。
- [x] HTTPS 不允许通过重定向降级到 HTTP。
- [x] 小红书公开 Fixture 可提取标题、正文描述和图片。
- [x] 抖音公开 Fixture 可提取标题、作者、视频和封面。
- [x] Open Graph 与 JSON-LD 可合并，URL 去重并保持顺序。
- [x] 登录要求映射为 `authorizationRequired`。
- [x] 已删除或不存在内容映射为 `contentUnavailable`。
- [x] 非法响应、越界重定向、正文超限不暴露正文内容。
- [x] 粘贴文本、本地图片、本地视频可生成统一 `ImportContent`。
- [x] 不实现登录、验证码、签名、访问控制或反爬绕过。
- [x] `dart format lib test` 通过。
- [x] `flutter analyze --no-pub` 通过。
- [x] `flutter test --no-pub` 通过。
- [x] `git diff --check` 通过。

## 自动化结果

- `dart format lib test`：54 个 Dart 文件已检查，无待格式化文件。
- `flutter analyze --no-pub`：通过，`No issues found!`。
- IMPORT-003 定向测试：36 项全部通过。
- `flutter test --no-pub`：94 项全部通过。
- `git diff --check`：通过。

## 实现摘要

- 新增带安全边界的 `HttpImportTransport`，支持可注入客户端、15 秒默认超时、最多 4 次重定向、2 MiB 正文上限、响应流期间取消和 Content-Type 白名单。
- 新增 Open Graph、HTML metadata、JSON-LD、独立 JSON 和纯文本解析，支持相对 URL 解析、URL 去重和顺序保持。
- 新增小红书与抖音公开内容 Adapter，输出统一 `ImportContent`，并将登录要求、内容不可用、超时、网络和非法响应映射为稳定错误。
- 新增粘贴文本、本地图片和本地视频人工降级输入；图片进入 OCR 路径，视频进入 ASR 路径。
- 使用本地固定 Fixture 完成正常、登录要求、内容不可用、异常响应和 Runner 集成回归，不依赖真实平台在线状态。

## 已知限制

- 本轮只提取公开页面暴露的文本和媒体引用，不下载、缓存或转码媒体文件。
- 平台页面结构可能变化；后续需要通过独立样本集和定期兼容性回归跟踪。
- Windows 环境未验证 iOS 网络行为。
