# OPS-003：GitHub 首次发布验收

- 日期：2026-07-28
- 任务：`OPS-003`
- 结论：通过

## 验收范围

将本地 Git 仓库首次发布到项目负责人提供的 GitHub 仓库 `zisjugoudan/ai-recipe`，并建立后续默认推送关系。

## 验收项

| 验收项 | 结果 | 证据 |
|---|---|---|
| 远程仓库预检 | 通过 | 首次推送前 `git ls-remote` 无引用，确认远程为空 |
| 本地首次提交 | 通过 | 根提交 `df55ef4 chore: initialize AI recipe project` |
| 远程地址 | 通过 | `origin` 指向 `https://github.com/zisjugoudan/ai-recipe.git` |
| 主分支推送 | 通过 | 本地 `main` 已推送为 `origin/main` |
| 上游关系 | 通过 | 本地 `main` 已设置跟踪 `origin/main` |
| 构建产物排除 | 通过 | Flutter `build/` 和 Debug APK 由 `.gitignore` 排除 |
| 敏感文件预检 | 通过 | 暂存文件名未发现常见密钥文件；文本未匹配明显 API Key、Token 或私钥格式 |

## 后续操作

常规同步使用：

```powershell
git add -A
git commit -m "描述本次修改"
git push
```

任何真实 API Key、Token、证书、Keystore、环境变量文件和用户隐私数据都不得提交到远程仓库。

## 后续修订记录

- **2026-09-18（OPS-005）**：为公开仓库做脱敏时，全部历史提交的作者与提交者邮箱由 `2282781933@qq.com` 改写为 GitHub noreply 地址 `83538532+zisjugoudan@users.noreply.github.com`，因此本记录中引用的根提交 SHA `df55ef4` 已失效，新的根提交为 `5d1e326 chore: initialize AI recipe project`。提交内容与提交时间未变，仅邮箱字段被改写。改写前的历史保留在本地分支 `backup/pre-email-desensitize`，未推送到远程。详见 ADR-0043。
