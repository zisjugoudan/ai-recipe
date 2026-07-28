# APP-003 应用后端统一门面验收

> 日期：2026-07-28
> 状态：通过
> 关联：`APP-003`、`IMPORT-001`、`IMPORT-002`、`AI-002`、`OCR-001`、`ASR-001`、`APP-001`、`APP-002`

## 1. 验收目标

验证 Flutter 页面无需直接访问 Repository、SQLite、HTTP Transport、LLM/OCR/ASR Provider 或 API Key，即可通过统一后端门面完成会话、菜谱库和 AI 链接导入主流程。

## 2. 门面与装配

- [x] 统一 Facade 暴露会话、能力、菜谱库和导入工作流。
- [x] 设备组合根集中创建 SQLite、会话、LLM 配置、公开内容 Adapter 与自定义 LLM Runner。
- [x] Provider 扩展通过 Runner Factory/Builder 注入，不在页面或 Facade 中写供应商分支。
- [x] 关闭组合根会释放数据库，不会删除用户数据或配置。

## 3. 能力与安全

- [x] 创建公开链接任务要求 `publicContentImport`。
- [x] 自定义/托管 LLM、本地/云 OCR、托管 ASR 分别要求对应能力。
- [x] 自定义 LLM 配置从安全仓库读取，API Key 不出现在门面返回值和持久化会话中。
- [x] 未配置、未安装、未登录、离线、配额不足和服务不可用继续保留稳定原因码。
- [x] 未绑定 Provider 返回稳定脱敏错误，不静默降级为其他付费或云端能力。

## 4. 导入工作流

- [x] 支持创建、读取、筛选、运行、批量调度、取消、重试和恢复任务。
- [x] 支持读取待确认草稿。
- [x] 确认草稿时保存用户编辑后的完整快照，强制发布并完成任务。
- [x] 确认中途失败后可幂等重试，不重复增加已发布菜谱版本。
- [x] 放弃草稿时执行软删除并取消任务；已软删除草稿可安全重试。
- [x] 登录用户生成的草稿带 userId，游客草稿 userId 为空。

## 5. 端到端测试

- [x] 公开文本链接 → 自定义 LLM → 草稿 → 确认。
- [x] 需要图片识别的链接 → 本地 OCR → LLM → 草稿 → 确认。
- [x] 需要语音识别的链接 → 托管 ASR → LLM → 草稿 → 确认。
- [x] 能力不可用时 Provider 不被调用。
- [x] Provider、存储和未知错误不会泄露敏感内部信息。

## 6. 质量命令

```powershell
cd C:\tmp\ai-recipe-mobile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

附加检查：

```powershell
git diff --check
git status --short
git diff --stat
```

## 7. 验收结果

APP-003 验收通过。

- `AiRecipeBackendFacade` 和设备组合根已成为页面可依赖的稳定后端入口。
- 已覆盖游客/登录草稿归属、能力拒绝、Provider 路由、草稿确认/放弃、重复确认幂等保护和数据库生命周期。
- 完整链路已覆盖公开 URL → Adapter → OCR → ASR → LLM → 草稿 → 确认。
- 修复 OCR 后进入 ASR 时进度从 60% 倒退到 35% 的问题；ASR 现使用 61%–64% 的全局进度区间。
- `dart format lib test`：105 个文件，无额外格式变化。
- `flutter analyze --no-pub`：`No issues found`。
- `flutter test --no-pub`：217 项全部通过。
- APP-003 与 ASR 进度回归相关定向测试：32 项全部通过。
- `git diff --check`、Git 状态与敏感信息检查在提交前执行并记录。

已知未验收项：Windows 无法验收 iOS；PaddleOCR/ONNX Runtime 原生插件、真实托管 OCR/ASR/LLM、真实 OpenAI-compatible/Gemini/本地兼容服务仍分别由 `SPK-002`、`SPK-003` 和后续服务任务验证。