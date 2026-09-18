# 交流群二维码（本地私有资产，不入库）

本目录存放「我的 → 加入交流群」页面使用的群二维码海报。群二维码属于个人数据，已在 `.gitignore` 中排除，**不会进入公开仓库**。

## 构建前需要补齐的文件

`pubspec.yaml` 声明了 `qq_group.jpg`。缺少该文件时 `flutter build` / `flutter run` 会报找不到资产而失败。

| 文件 | 说明 | 参考源图 |
|---|---|---|
| `qq_group.jpg` | 群二维码海报（竖版，约 1352×2405） | `design/assets/交流群.jpg` |

补齐方式：把海报放到本目录并命名为 `qq_group.jpg` 即可。文件存在后 `git status` 不会显示它，因此不会被误提交。

## 提交前检查

不要使用 `git add -f` 强制添加本目录的二维码。渲染逻辑见 `lib/features/profile/community_page.dart`。
