# UPDATE-001 验收方法：Gitee 在线更新

- 任务：`UPDATE-001`（Gitee 在线更新）
- 日期：2026-08-11
- 状态：`VERIFY`（实现完成，待项目负责人验证）
- 相关决策：数据源为 Gitee 公开仓库 `https://gitee.com/eb-Dog/delicious-food`（owner=eb-Dog, repo=delicious-food）根目录的 **`version.json`**（raw 直链 `…/raw/master/version.json`）。**2026-08-11 项目负责人指定不用 Release API，改用 version.json**。解析采用宽容候选键（见下）。

## version.json 格式（支持以下候选键，取第一个非空值）

```json
{
  "version": "1.1.0",
  "note": "本次更新的说明文字",
  "apk_url": "https://…/app-1.1.0.apk",
  "html_url": "https://gitee.com/eb-Dog/delicious-food"
}
```

- 版本号（必填）：`version` / `latest_version` / `tag_name` / `latestVersion`
- 更新说明：`note` / `changelog` / `update_note` / `release_notes` / `body` / `description`
- APK 直链：`apk_url` / `apkUrl` / `download_url` / `downloadUrl` / `url` / `apk` / `apk_link` / `apkLink`
- 发布页（可选）：`html_url` / `page_url` / `release_page` / `homepage` / `project_url`

## 前置条件

- 在 `C:\AIM`（junction → `code/apps/mobile`）执行：

```powershell
flutter pub get
flutter analyze --no-pub
flutter test test\domain\app_update_test.dart test\features\update_service_test.dart
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

- `flutter analyze` 结果：无 error（warning 可接受）。

## 验收步骤与预期结果

### 1. 入口与页面

| 步骤 | 预期 |
|---|---|
| 打开应用 → 「我的」页 | 在「数据与存储」下方看到「检查更新」入口行 |
| 点击「检查更新」 | 进入检查更新页，顶部标题「检查更新」，卡片显示「当前版本」与版本号（应显示 1.0.0） |

### 2. 检查更新（无新版本场景）

| 步骤 | 预期 |
|---|---|
| 保持 Gitee 仓库 Release 不高于当前版本 | 点击「检查更新」→ 按钮短暂显示「正在检查…」→ 提示「当前已是最新版本（1.0.0）」 |
| 断网后点击「检查更新」 | 页面显示错误提示「网络暂时不可用，无法检查更新。」 |
| 仓库公开存在但无 version.json | 404 后二次检查仓库详情 → 提示「仓库里还没有 version.json 更新配置，暂时无法检查更新。」 |
| 仓库不存在或为私有 | 提示「找不到更新仓库，请确认仓库已设为公开且路径正确。」 |

### 2.1 修复后版本显示（2026-08-11）

| 步骤 | 预期 |
|---|---|
| 进入检查更新页 | 当前版本卡片**不再显示「未知」**：优先显示构建注入版本（`--dart-define=APP_VERSION`）、其次运行时版本、最后回退 `1.0.0` |
| 用 `flutter build apk --debug --dart-define=APP_VERSION=1.0.1` 构建 | 页面显示 1.0.1（验证注入优先级） |

### 2.2 待项目负责人确认（影响 404 根因）

- 仓库 `https://gitee.com/eb-Dog/delicious-food` 是否**公开**？（私有仓库匿名读取一律返回 404/403，需改为公开或提供只读 Token）
- 仓库 `master` 分支是否已放 **`version.json`**？若未放，`raw/master/version.json` 返回 404 属正常。
- `version.json` 的字段名是否在上方候选键内？若不同，请贴出文件内容以便适配。

### 3. 检查更新（有新版本场景）

| 步骤 | 预期 |
|---|---|
| 在仓库 master 分支的 version.json 中把版本号改为高于当前版本（如 `"version": "1.1.0"`），并写好 `note` 与 `apk_url` | 点击「检查更新」→ 弹出更新弹窗，显示新版本号、当前版本号、更新说明正文 |
| 点击「以后再说」 | 弹窗关闭，不下载，页面停留 |
| 再次点击「检查更新」并点击「立即升级」 | 页面出现下载进度条与百分比，下载完成后提示「正在打开系统安装器」 |
| 系统安装器出现后 | 确认安装；若未授权「安装未知应用」，系统引导授权后安装成功；桌面出现新版本图标 |

### 4. 无 APK 下载地址场景（可选）

| 步骤 | 预期 |
|---|---|
| version.json 只写版本号与说明、不写 apk 下载地址 | 弹窗正常显示；点「立即升级」→ 提示「该版本没有提供安装包，请前往发布页手动下载。」 |

## 回传格式

请在验证后回传：

1. `flutter analyze` 是否有 error（有则贴出）。
2. 单元测试是否全部通过。
3. 无新版提示 / 有新版弹窗 / 下载安装 三个场景的实际结果与截图。
4. Android 版本与真机型号。

## Codex 未执行项

- Codex 未运行 `flutter pub get`、`flutter analyze`、构建、单元测试与真机验证（ADR-0015）。上述命令需项目负责人在本地执行。
