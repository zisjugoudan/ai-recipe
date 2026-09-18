# COMMUNITY-001 「加入交流群」验收

- 任务：COMMUNITY-001（P2）
- 日期：2026-08-11
- 状态：VERIFY（等待项目负责人验收）
- 涉及文件：
  - `code/apps/mobile/lib/features/profile/community_page.dart`（新建）
  - `code/apps/mobile/lib/features/profile/profile_page.dart`（新增入口）
  - `code/apps/mobile/pubspec.yaml`（注册 `assets/community/qq_group.jpg`）
  - `code/apps/mobile/assets/community/qq_group.jpg`（源图 `design/assets/交流群.jpg`，1352×2405）

## 验收标准

| 编号 | 验收点 | 前置条件 | 操作步骤 | 预期结果 | 实际结果（负责人回填） | 证据（截图/日志） |
|---|---|---|---|---|---|---|
| 1 | 入口存在 | 应用已登录 | 「我的」页下滑，「支持我们」下方 | 出现「加入交流群」入口（论坛图标，绿底） | 待回填 | 截图 |
| 2 | 页面内容 | 进入交流群页 | 点击「加入交流群」入口 | 页面显示：标题「一起聊下厨那些事」、引导卡片「为什么加入交流群？」、群二维码海报（竖版）、进群提示卡片 | 待回填 | 截图 |
| 3 | 二维码显示正常 | 交流群页 | 查看海报区域 | 群二维码图片完整显示、清晰可辨，无破损图标、无拉伸变形 | 待回填 | 截图 |
| 4 | 全屏预览 | 交流群页 | 点击海报 | 进入黑底全屏预览，支持双指缩放，右上角关闭按钮可返回 | 待回填 | 截图 |
| 5 | 可扫码进群 | 二维码海报清晰 | 用微信/QQ 扫一扫识别海报中的二维码 | 能识别出交流群并加入（或至少识别成功） | 待回填 | 说明 |
| 6 | 弱网/资产缺失 | 资产正常打包 | 不涉及（本地资产） | 离线可正常查看海报（本地资源，无网络请求） | 待回填 | — |
| 7 | 返回导航 | 任意状态 | 页面左上角返回 / 系统返回键 | 正常返回「我的」页，无异常 | 待回填 | — |

## 测试方法（项目负责人执行）

前置条件：`flutter pub get` 后构建 debug APK 安装到 Android 真机/模拟器。

```powershell
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

依次执行上表操作，将「实际结果」与「证据」回填，回传格式：每行验收点给「通过 / 不通过 + 现象描述」。

## 已知限制

- Codex 未执行 `flutter analyze`、构建与真机验证（ADR-0015）。
- 海报为本地静态资产，若未来群二维码变更需替换 `assets/community/qq_group.jpg` 并重新构建。
