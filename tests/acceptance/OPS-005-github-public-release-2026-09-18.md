# OPS-005：脱敏后同步工作区改动到 GitHub 公开仓库

- 日期：2026-09-18
- 任务：`OPS-005`
- 关联决策：`tracking/DECISIONS.md`（ADR-0043）
- 状态：`VERIFY`，等待项目负责人复核

## 目标与范围

把本地工作区的全部项目改动同步到 `origin`（`https://github.com/zisjugoudan/ai-recipe.git`），并在同步前完成数据脱敏，最后把仓库可见性由 private 改为 public。

**范围内**：`.gitignore` 排除规则、就地补齐说明文档、根 README 内容边界、本机绝对路径清理、工作区提交与推送、仓库可见性变更。

**不在范围内**：任何应用功能、业务逻辑、`pubspec.yaml` 依赖或页面行为变更；`flutter pub get`/`analyze`/构建/测试/真机验证（ADR-0015，由项目负责人执行）；`视频剪辑/` 与 `VID-001` 成片的分发方案。

## 前置条件

1. 已安装 Git，且对 `zisjugoudan/ai-recipe` 具备写权限。
2. 本地代理可用（本机为 `http://127.0.0.1:7897`），Git 已配置 `http.proxy`/`https.proxy`。
3. 项目负责人确认收款码、群二维码、录屏素材与堆转储**不需要**出现在公开仓库中。

## 已实施的改动

| 文件 | 改动 |
|---|---|
| `.gitignore` | 新增排除：收款码、群二维码、`视频剪辑/`、`.tmp/`、`.trae/`、`.workbuddy/`、`*.hprof`、`*.dill`、`*.apk`、`*.aab`、`*.ipa` |
| `code/apps/mobile/assets/payment/README.md` | 新增，说明 `wechat_qr.jpg`/`alipay_qr.jpg` 的补齐方式 |
| `code/apps/mobile/assets/community/README.md` | 新增，说明 `qq_group.jpg` 的补齐方式 |
| `README.md` | 新增「仓库内容边界」章节；修正过时的「当前阶段」描述 |
| `解决方案.md` | 本机绝对路径改为仓库相对路径 |
| `tracking/BACKLOG.md` | 新增 `OPS-005` 任务 |
| `tracking/DECISIONS.md` | 新增 ADR-0043 |
| `tracking/CURRENT.md`、`tracking/CHANGELOG.md` | 记录本轮进度与变更 |
| `tests/acceptance/OPS-003-github-publish-2026-07-28.md` | 追加修订说明：根提交 SHA 因邮箱改写而失效 |
| git 历史（全部 20 个提交） | 作者/提交者邮箱由项目负责人原 QQ 邮箱（原值不在仓库内记录）改写为 GitHub noreply 地址 |

## 验收步骤与预期结果

### 步骤 1：确认脱敏规则生效

在仓库根目录执行：

```bash
git check-ignore -v \
  "design/assets/收款码/微信.jpg" \
  "design/assets/收款码/支付宝.jpg" \
  "design/assets/交流群.jpg" \
  "code/apps/mobile/assets/payment/wechat_qr.jpg" \
  "code/apps/mobile/assets/payment/alipay_qr.jpg" \
  "code/apps/mobile/assets/community/qq_group.jpg" \
  "视频剪辑/原始素材/b站.mp4" \
  "code/apps/mobile/android/java_pid38884.hprof" \
  ".tmp/bug002-add-page.png" \
  ".trae/documents/home-icons-plan.md" \
  "design/.workbuddy/memory/2026-08-04.md"
```

预期：11 项全部输出命中的 ignore 规则。

```bash
git check-ignore -q "code/apps/mobile/assets/payment/README.md" && echo BAD || echo ok
```

预期：输出 `ok`（说明文件未被误伤）。

### 步骤 2：确认工作区无遗漏的敏感内容

```bash
git status --porcelain --ignored=no
```

预期：不再出现收款码、群二维码、`视频剪辑/`、`.hprof`、`.tmp/`、`.trae/` 路径。

```bash
git grep -nE '(sk-[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{30,}|ghp_[A-Za-z0-9]{30,}|github_pat_|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)' HEAD
```

预期：无输出。

### 步骤 3：确认远端已同步

```bash
git fetch origin && git log --oneline origin/main -3
```

预期：`origin/main` 指向本轮最新提交，且 `git status -sb` 显示本地 `main` 与 `origin/main` 一致。

### 步骤 4：确认远端文件树不含排除项

```bash
git ls-tree -r origin/main --name-only | grep -E '收款码|交流群|payment/.*\.jpg|community/.*\.jpg|视频剪辑|\.hprof|^\.tmp/|^\.trae/' 
```

预期：无输出。

### 步骤 5：确认仓库可见性为 public

浏览器打开 `https://github.com/zisjugoudan/ai-recipe`，或用 API：

```bash
curl -s https://api.github.com/repos/zisjugoudan/ai-recipe | grep -E '"(private|visibility)"'
```

预期：`"private": false`、`"visibility": "public"`。匿名（未登录浏览器）打开仓库首页可正常看到文件列表。

### 步骤 6：确认提交者身份已脱敏

```bash
git log --format='%ae | %ce' | sort | uniq -c
```

预期：只出现 `83538532+zisjugoudan@users.noreply.github.com`，不再出现任何个人邮箱。原值只存在于本地备份分支 `backup/pre-email-desensitize` 的提交记录中，不在仓库内容里。

```bash
git diff backup/pre-email-desensitize main --stat
```

预期：无输出（说明改写只动了邮箱字段，提交内容未变）。该分支为本地备份，不会推送。

### 步骤 7：确认克隆补齐流程可用

在空目录执行：

```bash
git clone https://github.com/zisjugoudan/ai-recipe.git ai-recipe-check
cd ai-recipe-check
cat code/apps/mobile/assets/payment/README.md
```

预期：能读到补齐说明；`code/apps/mobile/assets/payment/` 下只有 `README.md`。

## 执行结果（Codex 本轮已执行，供项目负责人复核）

| 项目 | 实际结果 |
|---|---|
| 提交分组 | 5 个主题提交：脱敏配置 → 文档与验收 → 设计资产 → 应用实现（含测试） → 原生与资产与构建配置 |
| 推送方式 | 因历史改写，使用 `git push --force-with-lease origin main`；首次因大数据量断连，调整 `http.postBuffer`/`http.version`/`http.lowSpeedTime` 后成功 |
| 推送结果 | `+ 32a0583...3747a14 main -> main (forced update)` |
| 远端文件总数 | 660 |
| 远端脱敏校验 | `git ls-tree -r origin/main` 中不含收款码、群二维码、`视频剪辑/`、`*.hprof`、`.tmp/`、`.trae/`、`.workbuddy` |
| 提交邮箱 | 全部提交作者与提交者均为 `83538532+zisjugoudan@users.noreply.github.com` |
| 仓库可见性 | GitHub API 返回 `"private": false`、`"visibility": "public"`；匿名访问仓库页面返回 `Public` 标记；`raw.githubusercontent.com` 匿名读取 `README.md` 与 `.gitignore` 均返回 200 |
| 本地备份 | 分支 `backup/pre-email-desensitize` 保留改写前的历史（含旧邮箱），未推送，待项目负责人确认后可删除 |

## 需要回传的结果

项目负责人复核后请回传：

1. 步骤 1 的 11 项 check-ignore 输出（命中规则或未命中）。
2. 步骤 2 的两条命令输出。
3. 步骤 3 的 `origin/main` 最新 3 条提交，以及 `git status -sb` 的同步状态。
4. 步骤 4 的输出（无输出即为通过）。
5. 步骤 5 的 `private`/`visibility` 字段值，以及匿名访问仓库首页是否可见。
6. 步骤 6 的邮箱统计与 `git diff` 输出。
7. 步骤 7 的克隆结果。
8. 明确结论：是否接受「全新克隆需手动补齐三个私有资产才能构建」这一代价；若不接受，请说明希望改用哪种替代方案。
9. 明确结论：是否确认邮箱改写结果无误、可以删除本地备份分支 `backup/pre-email-desensitize`；如不希望保留 noreply 邮箱，请说明希望改回或改用哪个地址。

## 边界说明

- Codex 本轮未运行 `flutter pub get`、`flutter analyze`、`flutter test`、编译、构建、模拟器或真机测试（ADR-0015）。
- 本轮不改变任何应用功能行为，因此不产生新的 UI 状态或 AI 质量数据。
- 若后续需要公开分享 `视频剪辑/` 成片或设计源图，必须另建不含个人数据的分发渠道，不能直接放开本轮的忽略规则。
