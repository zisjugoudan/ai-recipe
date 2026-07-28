# APP-002 游客/登录后端能力策略验收

> 日期：2026-07-28
> 状态：通过
> 关联：`APP-002`、`US-001`、`US-002`、`US-003`

## 1. 验收目标

验证会话和能力策略已形成可供后续 Flutter 页面与后端编排直接依赖的稳定 Application Facade，不需要真实登录 UI、云端账号 API 或托管 AI 网络客户端。

## 2. 会话验收

- [x] 首次读取且没有持久化元数据时返回游客会话。
- [x] 继续游客会保存游客状态，不要求手机号、微信或 Apple 账号。
- [x] 接受已验证登录结果时要求非空 userId，并保存非敏感身份元数据。
- [x] 退出登录恢复游客状态，但不操作菜谱、LLM 配置或 OCR 模型。
- [x] 会话序列化不包含 Token、API Key、Cookie 或 Authorization。
- [x] 无效或损坏的持久化数据不会被当作有效登录会话。

## 3. 能力策略验收

- [x] 本地菜谱库和公开链接导入内核对游客与登录用户都可用。
- [x] 自定义 LLM API 对游客与登录用户都可用，但要求 Provider 已配置并就绪。
- [x] 本地 OCR 对游客与登录用户都可用，但要求插件与模型已安装并就绪。
- [x] 平台托管 LLM、云 OCR、托管 ASR 和云保存对游客返回 `signInRequired`。
- [x] 登录用户的托管能力继续映射离线、配额不足和服务不可用状态。
- [x] 能力守卫抛出包含能力与稳定原因码的异常，不泄露内部异常。
- [x] Repository 未知错误统一映射为脱敏 Application 错误。

## 4. 质量命令

```powershell
cd C:\tmp\ai-recipe-mobile
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

附加检查：

```powershell
git diff --check
```

## 5. 验收结果

- `dart format lib test`：通过，94 个 Dart 文件已检查，最终无待格式化变更。
- `flutter analyze --no-pub`：通过，无静态分析问题。
- `flutter test --no-pub`：通过，共 197 项测试；APP-002 新增 21 项。
- 会话元数据只包含 Schema 版本、会话类型、用户 ID、显示名和登录时间；自动化测试确认不包含 Token、API Key、Cookie 或 Authorization。
- 损坏 JSON、未知 Schema、缺失 userId、无效时间和未知字段均拒绝加载。
- 游客、登录用户、自定义 LLM、本地 OCR、托管 AI、云 OCR、托管 ASR 和云同步的能力矩阵已由 Application 测试覆盖。
