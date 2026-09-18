# UI-001 Android 模拟器冒烟验收记录

> 验收日期：2026-07-31  
> 任务：`UI-001`  
> 任务状态：`DOING`  
> 本轮平台范围：仅 Android

## 1. 验收目标与边界

用户已明确要求本轮只验证 Android，因此本记录检查 Flutter P0 本地业务链路在 Android 模拟器上的构建、安装、启动、主要导航、菜谱本地生命周期和设置持久化。

本轮未执行 iOS 构建、模拟器或真机验证，且 iOS 未验证不阻塞本轮 Android 冒烟结论。服务器端鉴权、云同步、平台托管 AI/OCR/ASR、配额、文件存储和服务端任务队列仍按计划暂缓。

## 2. Android 测试环境

| 项目 | 值 |
|---|---|
| 设备序列号 | `emulator-5554` |
| AVD | `Pixel_9a` |
| 模型 | `sdk_gphone64_x86_64` |
| Android 版本 | Android 16 |
| API Level | 36 |
| 分辨率 | 1080 × 2424 |
| Density | 420 |
| 启动状态 | `sys.boot_completed=1` |

设备由 `adb devices` 确认为 `device` 状态。

## 3. 构建、安装与执行方式

Android 集成测试以以下等效方式定向执行：

```powershell
$env:ORG_GRADLE_PROJECT_target-platform='android-x64'
flutter test integration_test/android_smoke_test.dart -d emulator-5554 --no-pub
```

当前机器存在旧 Flutter SDK startup lock，实际验证通过同一 Flutter SDK 的 `flutter_tools.snapshot` 执行，并设置 `FLUTTER_ALREADY_LOCKED=true`；这只是在本机绕过旧锁的运行方式，不改变应用代码或发布配置。

为避免 Debug APK 同时打包多个 ABI 触发 Gradle 内存不足，本次只在测试进程中设置 `ORG_GRADLE_PROJECT_target-platform=android-x64`。正式发布配置未修改，也没有永久限制发布 ABI。

结果：

```text
Built build\app\outputs\flutter-apk\app-debug.apk
安装成功
00:25 +1: All tests passed!
```

## 4. 人工界面检查

已在 Android 模拟器人工检查：

- 欢迎页可以正常显示，并提供游客继续入口。
- 游客进入后四个 Tab 均可访问：首页、菜谱库、添加、我的。
- 首页与菜谱库空状态显示正常。
- 添加页可以进入手动创建菜谱入口。
- 手动编辑器可以正常显示并输入基础菜谱内容。
- 游客个人页能够显示设置入口。

截图资产目录：

```text
tests/acceptance/artifacts/UI-001-android-emulator-2026-07-31/
```

当前目录包含欢迎页、首页、菜谱库空状态、添加页、游客个人页和手动编辑器等截图。集成测试结束后 App 已退出到 Android Launcher 的截图未保留，避免形成误导性验收证据。

## 5. Android 自动化主链结果

集成测试：

```text
integration_test/android_smoke_test.dart
1 项通过
```

自动化完成以下流程：

1. 启动 App。
2. 以游客身份继续。
3. 打开添加 Tab。
4. 进入手动菜谱编辑器。
5. 填写菜名、食材与步骤并保存。
6. 在菜谱库打开菜谱详情。
7. 收藏菜谱。
8. 将菜谱软删除到回收站。
9. 打开游客个人页和设置。
10. 检查 LLM 设置与 API Key 密文输入。
11. 检查 OCR 未配置生产 Manifest 时的真实不可用状态。
12. 开启图片上传权限，退出并重新进入页面验证持久化。
13. 打开回收站并恢复菜谱。
14. 返回菜谱库确认恢复后的菜谱可见。

自动化测试数据：

```text
菜名：Android 冒烟番茄炒蛋
食材：番茄 2 个
步骤：鸡蛋炒熟，番茄炒软后混合调味
```

验收结果：创建、详情、收藏、软删除、回收站恢复和菜谱库刷新链路均通过。

## 6. LLM、OCR 与隐私设置验收

- LLM 设置页支持 OpenAI-compatible 与 Gemini 配置入口。
- 本轮没有输入或保存真实 API Key；自动化仅检查密文输入控件与安全行为。
- API Key 不会从存储中以明文回填到页面。
- OCR 设置页在正式 App 未配置生产 Manifest 时展示真实不可用状态，没有伪造模型下载地址、哈希、大小或可安装状态。
- 图片上传授权可以在隐私设置页修改，并在重新进入页面后保持。
- 本轮没有使用真实云 OCR、真实本地 OCR 模型或真实 LLM Provider。

## 7. 本轮修复与回归

### 7.1 分类加载文案乱码

菜谱编辑器分类加载提示由乱码修复为：

```text
正在读取分类…
```

### 7.2 Android DataStore 测试状态未彻底清理

集成测试初始化改用：

```dart
SharedPreferencesAsync().clear()
```

从而正确清理 Android DataStore 中的 onboarding 和本地设置状态，避免测试受到旧模拟器数据影响。

### 7.3 首页与菜谱库刷新时 Future 从 setState 返回

Android 主链发现首页和菜谱库在 `refreshToken` 更新时把 Future 赋值表达式直接作为 `setState` 回调返回，触发：

```text
setState() callback argument returned a Future.
```

现已改为显式 `void` 块闭包，并新增回归测试：

```text
test/features/home_library_refresh_test.dart
2 项通过
```

回归覆盖首页与菜谱库刷新，并确认刷新过程没有 Flutter exception。

## 8. 日志与质量门

Android Logcat 检查模式：

```text
FATAL EXCEPTION
AndroidRuntime
E/flutter
flutter.*error
```

结果：

```text
NO_MATCHES
```

静态分析与全量测试：

```text
flutter analyze --no-pub
No issues found!

flutter test --no-pub --concurrency=4
427 项全部通过

git diff --check
通过
```

## 9. 未测试范围与限制

- iOS：按用户要求本轮未测试，不影响 Android 冒烟结论。
- 真实 OpenAI-compatible 或 Gemini API 地址与 API Key。
- 真实小红书/抖音公开链接抓取与平台页面变化兼容性。
- 真实 LLM 菜名、食材、用量、步骤与低置信度质量。
- 真实 PP-OCRv5 模型安装、识别准确率、性能和内存。
- 截图/视频媒体选择器、真实视频 ASR 和完整媒体降级链路。
- 服务器端登录、云同步和平台托管 AI/OCR/ASR。

由于没有用户授权的真实 Provider、API Key 和公开平台样本，本轮没有写入 `tests/ai-quality/AI_QUALITY_LOG.md`。

## 10. 结论

Android API 36 模拟器上的 Flutter 本地业务主链冒烟通过，Debug APK 可以构建、安装和启动；游客入口、四 Tab、手动创建、菜谱详情、收藏、软删除、恢复、LLM/OCR/隐私设置均通过自动化或人工检查。Logcat 未发现匹配的崩溃或 Flutter 错误，静态分析无问题，全量 427 项测试通过。

`UI-001` 继续保持 `DOING`，下一步仍是真实 Provider/公开平台样本端到端验收，以及剩余 P0 页面、状态和媒体入口缺口核对。

**本轮 Android 冒烟不代表真实平台解析或真实 AI 输出质量。**