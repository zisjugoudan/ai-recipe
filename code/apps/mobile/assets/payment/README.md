# 赞赏收款码（本地私有资产，不入库）

本目录存放「我的 → 支持我们」赞赏页使用的微信 / 支付宝收款码。收款码属于个人数据，已在 `.gitignore` 中排除，**不会进入公开仓库**。

## 构建前需要补齐的文件

`pubspec.yaml` 声明了以下两个资产。缺少其中任何一个，`flutter build` / `flutter run` 会报找不到资产而失败：

| 文件 | 说明 | 参考源图 |
|---|---|---|
| `wechat_qr.jpg` | 微信收款码 | `design/assets/收款码/微信.jpg`（1213×1213） |
| `alipay_qr.jpg` | 支付宝收款码 | `design/assets/收款码/支付宝.jpg`（1260×1890） |

补齐方式：把两张收款码放到本目录并按上表命名即可。文件存在后 `git status` 不会显示它们，因此不会被误提交。

## 只想跑通构建、没有收款码时

按上表文件名放入任意两张 JPG 图片占位即可（例如纯色图），赞赏页能正常渲染，只是扫码无效。

## 提交前检查

不要使用 `git add -f` 强制添加本目录的收款码。渲染逻辑见 `lib/features/profile/support_page.dart`，页面生成入口见 `lib/features/profile/profile_page.dart`。
