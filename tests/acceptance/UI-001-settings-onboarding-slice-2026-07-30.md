# UI-001 设置与独立 onboarding 切片验收记录

- 日期：2026-07-30
- 任务：`UI-001`
- 状态：通过；`UI-001` 总任务继续保持 `DOING`
- 范围：独立 onboarding、Facade 版 LLM 设置、OCR 设置、本地隐私设置与 Profile 导航入口

## 1. 验收范围

本切片继续遵守 `docs/architecture/FLUTTER_BUSINESS_BACKEND_COMPLETION.md` 的前端接线原则：Flutter 页面只访问 `AiRecipeBackendFacade` / Application，不直接访问 Repository、SQLite、SharedPreferences、安全存储或 Provider。

已覆盖：

- onboarding 完成状态与游客/登录身份会话独立持久化。
- 首次游客、已确认游客、已登录用户三种启动行为。
- Profile 返回欢迎页时重置 onboarding 并切回 guest session。
- Profile 的自定义 LLM API、OCR 引擎、隐私与上传权限入口接通真实页面。
- LLM 配置读取、保存、连接测试、密钥清除及稳定错误展示。
- 本地 OCR 模型状态、恢复、安装/删除入口和生产 Manifest 缺失时的诚实降级。
- 浏览历史与文本/图片/视频上传授权，以及历史自动/手动清理。

## 2. Onboarding 与身份行为

独立状态使用本地键：

```text
onboarding_completed_v1
```

验收结果：

1. 首次启动且为 guest、onboarding 未完成时显示欢迎页。
2. 游客继续后同时保存 guest session 和 onboarding completed 状态。
3. 已确认游客重启后直接进入 `AppShell`，不会重复显示欢迎页。
4. authenticated 用户即使 onboarding 尚未完成也直接进入 `AppShell`。
5. Profile 的“返回欢迎页”会先重置 onboarding，再保存 guest session，随后返回欢迎页。
6. `SharedPreferencesAsync` 在 onboarding 首次读写时才创建，组合根构造不再要求测试环境提前注册插件平台。

服务器认证协议、Token、云同步和游客数据合并不在本切片范围内；authenticated 仍只是本地会话元数据，不代表已经接入真实服务器登录。

## 3. LLM 设置与密钥安全

LLM 页面只调用：

```text
loadLlmSettings
saveLlmSettings
testLlmConnection
clearLlmApiKey
```

验收结果：

- 支持 OpenAI-compatible 和 Gemini Adapter。
- 用户只配置协议、API 地址、API Key、模型和 30/60/120 秒超时。
- 已保存 API Key 不以明文回填；页面只显示是否已经保存密钥。
- 编辑其他配置时，空 API Key 会保留现有密钥；用户可显式清空。
- 连接错误使用稳定、脱敏的状态文案，不包含用户输入 Key 或服务端原始敏感响应。
- 测试只使用明显的假 Key，没有提交真实凭据。

## 4. OCR 设置与真实性边界

OCR 页面只调用：

```text
recoverLocalOcrModelInstallation
getLocalOcrModelStatus
installLocalOcrModel
deleteLocalOcrModel
loadLocalSettings
```

验收结果：

- 正式 App 当前未传入生产 OCR Manifest，安装按钮保持禁用并明确提示生产模型清单尚未配置。
- 没有伪造下载 URL、SHA-256、模型大小、已安装状态或运行时可用状态。
- guest 的托管云 OCR 保持不可用。
- authenticated 用户在图片上传权限关闭时，不会被自动开启权限或误导为云 OCR 已可用。
- 真实 PP-OCRv5 模型、真机质量、完整 DB 后处理、方向分类器和 iOS Runtime 继续由 `SPK-002` 跟踪。

## 5. 隐私设置

默认值：

```text
记录浏览历史：true
允许文本上传：true
允许图片上传：false
允许视频上传：false
```

验收结果：

- 页面只通过 Facade 读取和保存设置。
- 关闭浏览历史会自动清空最近浏览记录。
- 用户可通过二次确认手动清空最近浏览记录。
- 设置成功和清理成功使用明确状态反馈。

## 6. 自动化测试

本切片定向测试：

```text
test/application/onboarding_use_cases_test.dart
test/data/device_onboarding_repository_test.dart
test/features/session_gate_test.dart
test/features/llm_settings_page_test.dart
test/features/privacy_settings_page_test.dart
test/features/ocr_settings_page_test.dart
test/features/profile_page_test.dart

24 项全部通过
```

定向测试覆盖 onboarding 状态变化、启动路由、三项 Profile 导航、API Key 脱敏、OCR Manifest 缺失降级和隐私历史清理。

## 7. 质量门结果

```text
flutter analyze --no-pub
No issues found

flutter test --no-pub --concurrency=4
404 项全部通过

git diff --check
通过
```

全量回归首次运行发现 14 项既有测试因 onboarding 偏好实例在组合根构造期提前要求 `SharedPreferencesAsyncPlatform` 而失败。修复为首次读写时延迟创建后，相关定向测试 14 项通过，随后全量 404 项全部通过。

## 8. 非目标与后续

本切片不包含：

- 服务器端登录、云同步、托管 AI/OCR/ASR、配额和云端任务队列。
- 生产 OCR 模型 Manifest 与真实模型下载发布链。
- 真实第三方 LLM 服务和公开平台链接的端到端兼容性验收。
- 导入失败后的完整人工降级输入入口。

本切片验收通过。下一切片补齐导入失败后的人工降级输入入口和真实 Provider 条件下的端到端验收；`UI-001` 在 P0 页面全部覆盖前继续保持 `DOING`。