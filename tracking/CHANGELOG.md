## 2026-09-18
### 脱敏后同步全部工作区改动到 GitHub 公开仓库（OPS-005）

- **背景**：远端 `zisjugoudan/ai-recipe` 自 2026-07-28 首次发布后为私有仓库，且只跟踪 261 个文件；应用本体、设计资产、原型、验收记录与 tracking 文档长期只存在于本地（工作区共 6497 项改动，远端落后 15 个提交以上）。项目负责人要求同步到 GitHub 并转为公开，同时先做数据脱敏。
- **脱敏边界（新增 ADR-0043）**：收款码、群二维码属于个人数据；视频工程与堆转储属于含本地环境画面的本地产物；三类内容全部排除，不进入公开仓库。
- **`.gitignore` 新增排除**：
  - `design/assets/收款码/`、`design/assets/交流群.jpg`（源图）
  - `code/apps/mobile/assets/payment/*.jpg`、`code/apps/mobile/assets/community/*.jpg`（应用资产副本）
  - `视频剪辑/`（约 1 GB，含本地开发环境录屏、node_modules 与成片）
  - `.tmp/`、`.trae/`、`.workbuddy/`（工具缓存）
  - `*.hprof`（约 2 GB JVM 堆转储）、`*.dill`、`*.apk`、`*.aab`、`*.ipa`
- **未采用占位图方案**：占位图与真实收款码同路径，提交后本地真实文件会被 git 视为「已跟踪文件的修改」，反而制造误提交风险；排除真实路径可从机制上保证真实收款码无法被 `git add` 命中。
- **克隆补齐说明（新增文件）**：`code/apps/mobile/assets/payment/README.md`、`code/apps/mobile/assets/community/README.md` 说明所需文件名、参考源图尺寸与补齐方式；`pubspec.yaml` 与 `support_page.dart`、`community_page.dart` 代码保持不变。
- **根 `README.md`**：新增「仓库内容边界」章节（排除清单、克隆补齐步骤、第三方角色参考图使用边界），并修正已过时的「当前阶段」描述（原文仍写「UI 继续暂缓」）。
- **`解决方案.md`**：文件清单中的本机绝对路径 `E:\AI\ai食谱\...` 改为仓库相对路径，避免公开仓库泄漏本地环境路径。
- **脱敏校验结果**：`git check-ignore` 对 11 项排除目标逐项校验全部 IGNORED，`assets/payment/README.md` 与 `assets/community/README.md` 未被误伤；全仓库文本扫描（`*.dart`/`*.kt`/`*.java`/`*.md`/`*.yaml`/`*.json`/`*.xml`/`*.txt`/`*.ts`/`*.js`/`*.html`/`*.css`/`*.py`）未匹配 `sk-`、`AIza`、`ghp_`、`github_pat_`、`AKIA`、`xox[baprs]-`、`-----BEGIN ... PRIVATE KEY` 等凭证格式，也未匹配手机号与个人邮箱。仓库中未跟踪任何 `.env`、`key.properties`、Keystore 或 Token 文件。
- **推送与可见性**：工作区改动按主题分批提交并推送到 `origin/main`；随后通过 GitHub API 将仓库可见性由 private 改为 public。
- **已知代价**：全新克隆缺少 `wechat_qr.jpg`、`alipay_qr.jpg`、`qq_group.jpg` 三个被排除的资产，Flutter 构建会报找不到资产，须按两个目录内的 README 补齐；项目负责人本地仓库不受影响。
- **状态**：OPS-005 → VERIFY，等待项目负责人复核公开范围。Codex 未执行 `flutter pub get`/`flutter analyze`/构建/单元测试/真机（ADR-0015），本轮不涉及应用功能行为变更。

## 2026-09-04
### 开发历程分享视频成片(VID-001)

- **分镜 v2 放行后完成 Remotion 工程全部 28 镜实现**,叙事=开发历程(原型踩坑/HTML→Flutter 失真/AI debug 慢/多 Agent 接力),画幅 16:9(1920×1080),时长 440s(7:20),B站技术分享向。
- **修复竖屏录屏横纹问题(核心缺陷)**:根因=Remotion `OffthreadVideo` 对竖屏视频的纹理 stride bug(重编码无法规避);修复=所有视频组件(ClipScene/QuadSplit/OutroScene)切换原生 `<Video>`。2×2 交叉对照帧(stripe2_final.png)验证:OffthreadVideo=花屏、Video=清晰。
- **成片**:`视频剪辑/开发历程分享视频/video/out/promo_final.mp4`(带 BGM,h264+aac,37MB)+ `promo_final-nobgm.mp4`(无 BGM 版)。
- **逐镜头终检**:从成片抽帧视觉核对 12 处关键镜头(四宫格/三卡扇形/需求文档打字机/对比拉杆/架构三件套/翻面对比/5节点流程图/红烧肉草稿/终端/协作光标/合影/已开源),全部通过,无条纹/花屏/遮挡;终检记录 `视频剪辑/开发历程分享视频/tests/终检记录_v1.md`。
- **TTS 配音草稿**:7 段口播 mp3 已生成(`video/public/voice/S0、S3-S8`;S1/S2 因当时 API 请求格式错误未生成),当前成片为字幕+BGM+SFX 方案(不依赖配音),真人旁白可后续替换。
- **已知简化项**:镜 21 终端原分镜为「三终端 3D 排布」,实现为单终端代码窗(内容清晰,待项目负责人确认是否需加强)。
- **状态**:VID-001 → VERIFY,等待项目负责人完整观看验收。

## 2026-08-11
### 烹饪模式进入后整屏空白修复（COOK-001 追加）

- **现象**：进入烹饪模式后整屏只有深绿背景、无任何内容，且**所有菜谱都如此**。debug 日志根因：`BoxConstraints forces an infinite height`，随后一串 `RenderBox was not laid out`。
- **根因**：`_CookingPixelSurface` 使用 `Stack(fit: StackFit.expand)`；而步骤卡/计时卡/计时按钮放在垂直 `ListView`（item 高度无限）中，`expand` 试图撑满无限高度抛错，导致整页布局失败变空白；同时 ListView item 内的 `Column` 未设 `mainAxisSize: min`，也会试图撑满无限高度。
- **修复**（`lib/features/cooking/cooking_mode_page.dart`）：
  - `_CookingPixelSurface` 改用 `LayoutBuilder` 检测 `maxHeight.isInfinite`：无限高度时用 `StackFit.loose`（面板随内容收缩、阴影仍跟随面板），有限高度保持 `StackFit.expand`（不影响底部导航按钮等 tight 场景）。
  - `_CookingStepGroup`（步骤卡）与 `_TimerCard`（计时卡）内的 `Column` 补 `mainAxisSize: MainAxisSize.min`。
- **验证状态**：IDE 诊断无错误。Codex 未执行 `flutter analyze`/`flutter test`/构建/真机（ADR-0015）。等待项目负责人确认烹饪模式能正常显示步骤卡、计时器区与上一步/下一步导航。

### 欢迎页品牌字改用像素字体渲染（UI-WELCOME-001）

- **项目负责人要求**：放弃手工点阵与生成动画，改用像素字体显示「巴食」（此前自绘字形与动画效果不满意）。
- **字体选型**：引入 Fusion Pixel（缝合像素字体，TakWolf，OFL-1.1 可商用，支持简体中文 GB2312，含「巴」「食」）。项目负责人提供字体文件 `fusion-pixel.ttf`。
- **代码变更**：
  - `pubspec.yaml`：新增 `fonts` 注册 `family: FusionPixel` → `assets/fonts/fusion-pixel.ttf`。
  - `lib/features/session/welcome_page.dart`：移除 `_AnimatedPixelTitle` 动画组件与 `_PixelBrandPainter` 手工点阵 painter，改为 `_PixelBrandTitle` 用 `Text` + `fontFamily: FusionPixel` 渲染「巴食」，保留右下立体阴影与「拾味 · AI 菜谱」副标；`welcomeTitle` key、`welcomeBrandSemantics` 语义、漂浮元素布局保持不变。
  - `test/features/welcome_page_test.dart`：「巴食」现为 `Text`，断言 `find.text('巴食')` 由 `findsNothing` 改为 `findsOneWidget`，用例名同步。
- **验证状态**：已用 fontTools 校验字体包含「巴」「食」，family=“Fusion Pixel”。IDE 诊断无错误。Codex 未执行 `flutter pub get`/`flutter analyze`/`flutter test`/构建/真机（ADR-0015）。`UI-WELCOME-001` 继续保持 `VERIFY`，等待项目负责人确认像素字体渲染效果。

### 欢迎页品牌字逐格生成动画（UI-WELCOME-001）

- **项目负责人要求**：既然「巴食」为项目内自绘点阵字，为其增加首尾可衔接的生成动画。
- **确认的方案**：动画形式＝逐格点亮（从无到有）；循环方式＝无缝循环（`AnimationController.repeat()`）。
- **代码变更**（`lib/features/session/welcome_page.dart`）：
  - `_PixelTitle` 改为有状态组件 `_AnimatedPixelTitle`，持有 `AnimationController`（3.6s，`repeat()`），按进度逐格点亮「巴食」。
  - `_PixelBrandPainter` 新增 `progress` 参数，并把两个字形所有像素按固定顺序（巴→食、每字从左到右从上到下）展开为 `_pixelOrder`；绘制时只点亮前 `round(progress * 总格数)` 个像素，每格同时绘制彩色格与右下硬阴影格。
  - 系统开启「减少动态效果」时，在 `didChangeDependencies` 中停止动画并停在完整字形，不产生无限 ticker。
  - 组件结构、语义、`welcomeTitle` key 与布局保持不变。
- **首版调整**：项目负责人反馈动画太突兀、完整字形停留时间不够看不清——改为两阶段循环：阶段一生成（`TweenSequence`，`progress` 0→1 逐格点亮，`easeInOut` 缓动避免生硬，约 2s）+ 阶段二停留（`progress` 保持 1.0，完整字形停留约 1.5s 供阅读），再由 `repeat()` 无缝衔接下一轮。
- **效果调整**：项目负责人反馈「逐格点亮」效果不好看——改为「波纹扩散」：像素改为按「到字形整体中心的距离」从小到大排序点亮，动画从中心向外一圈圈扩散（`easeInOut`），并保留完整字形停留约 1.5s。
- **验证状态**：仅 IDE 诊断无错误；Codex 未执行 `flutter analyze`/`flutter test`/构建/真机（ADR-0015）。`UI-WELCOME-001` 继续保持 `VERIFY`，等待项目负责人确认动画效果与减少动态效果表现。

### 欢迎页手工点阵「巴食」字形修正（UI-WELCOME-001）

- **背景**：项目负责人反馈自绘点阵字形整体不协调、尤其是「巴」字完全不像，要求重排点阵。
- **代码变更**：`lib/features/session/welcome_page.dart` 中 `_PixelBrandPainter` 的 `_ba` 与 `_shi` 点阵重排——
  - 「巴」：上部改为「口」（内有一竖），下部由原先左右两条竖加底横的宽框，改为真正的「竖弯钩」（左侧竖向右弯出、末梢上翘），下窄单钩，辨识度提升。
  - 「食」：重排为顶部人字头 + 中部「良」日框 + 下部「艮」（竖提 + 撇 + 底横 + 点）的结构，比例更协调。
- **第二轮调整**：项目负责人反馈「巴」缺下部、「食」缺一笔后，再次修正——「巴」下半补回完整竖弯钩（左竖下伸 → 底部横 → 末梢上翘），「食」下部「艮」补齐竖 + 横折 + 底横 + 撇 + 点。
- **第三轮调整**：项目负责人仍反馈字形不对。为不再凭记忆盲画，用系统字体（微软雅黑）渲染「巴」「食」并采样 13×13 点阵作为设计蓝本，据此重画——「巴」下半竖弯钩改为更饱满（底部横两行、更宽，钩右移至 col9–10 并更明显），「食」下部「艮」补回右侧竖/横折结构（解决「少一笔」），两字整体更贴近标准字形。
- **第四轮调整**：项目负责人反馈「食」仍不好。以系统字体 16×16「食」字形为蓝本重排「食」点阵——人字头改为舒展撇捺（展开到 col1/col9），中部「良」日框完整，「艮」下部改为干净的竖提 + 底横 + 撇 + 点，避免此前右半笔画错位凌乱。
- **验证状态**：仅改动点阵数据，组件结构、语义、key、尺寸与动画逻辑未变；IDE 诊断无错误。Codex 未执行 `flutter analyze`/`flutter test`/构建/真机（ADR-0015）。`UI-WELCOME-001` 继续保持 `VERIFY`，等待项目负责人确认新字形的辨识度。

### 欢迎页红框区域二次调整（UI-WELCOME-001）

- **背景**：项目负责人进一步指定只参考最新图片红框内的顶部区域，要求五个小元素适配不同设备、「巴食」由 Flutter 自行绘制，并把主插画边框调整为参考图中的像素立体相框；红框外内容和行为保持不变。
- **设计与资产**：将本轮参考图归档为 `design/assets/欢迎页顶部参考-2026-08-11.png`；更新 `design/prototypes/design-docs/UI-001-欢迎页.md`，明确比例布局、手工点阵字、多层相框和 320/430/600px 验收要求。
- **代码变更**：
  - `lib/features/session/welcome_page.dart`：五个漂浮元素改用 `FractionalOffset`、`FractionallySizedBox` 与容器宽度比例计算尺寸、锚点和动画幅度，并为标题区高度、相框厚度、阴影偏移和气泡尺寸设置响应式范围。
  - 「巴食」最终改为 `_PixelBrandPainter` 使用两套 13×13 手工点阵逐格绘制，移除上一版依赖系统字形离屏采样的 `_PixelatedText` / `_PixelatePainter`；新增「巴食」图片语义，便于无障碍识别。
  - 主插画最终改由 `_WelcomeFramePainter` 绘制右下投影、深绿外轮廓、浅色框带、上左高光、下右压暗和内侧压边；气泡尾巴朝上连接插画，并避免右下爱心裁切。
  - 保留特性列表、登录 / 游客入口、隐私说明、错误提示与既有按钮 key/回调行为。
- **测试与验收定义**：更新 `test/features/welcome_page_test.dart`，定义自绘标题与语义、普通文本排除、320/430/600px 自适应、不越界与不遮挡、尺寸随宽度变化、减少动态效果、游客、忙碌和错误重试共 6 项 Widget 测试；重写 `tests/acceptance/UI-WELCOME-001-welcome-page-redesign-2026-08-11.md`，补齐多宽度视觉、默认/加载/错误/离线/权限拒绝/游客/登录与减少动态效果的人工验证步骤。
- **验证状态**：本轮 Codex 未执行 `flutter pub get`、`flutter analyze`、`flutter test`、编译、构建、模拟器或真机测试（ADR-0015）。`UI-WELCOME-001` 保持 `VERIFY`，等待项目负责人确认手工点阵「巴食」的辨识度、漂浮元素在不同宽度下的构图和多层相框与参考图的接近程度。

### 欢迎页按参考图视觉重设计（UI-WELCOME-001）

- **背景**：项目负责人提供参考图与 `design/assets/欢迎页元素/` 素材，要求欢迎页按图中红色框位置重设计，使品牌标题、漂浮元素、主插画相框与副标题气泡与参考图一致。
- **代码变更**：
  - 复制 `design/assets/封面图.png` 与 `design/assets/欢迎页元素/`（叶子、帽子、番茄、胡萝卜、辣椒）到 `code/apps/mobile/assets/welcome/`，并在 `pubspec.yaml` 注册。
  - 重写 `lib/features/session/welcome_page.dart`：品牌标题改为 "巴食"（无空格）并改为**自绘像素字** `_PixelatedText`（`_PixelatePainter` 离屏渲染 `ui.Image` 后按 4px 网格采样 alpha 绘像素方块 + 2.5px 硬边阴影，无字体文件依赖，异步渲染前用普通 Text 占位）；下方新增 "拾味 · AI 菜谱" 小字；漂浮食材元素位置按参考图红色框调整（左上远端厨师帽、左侧中部胡萝卜、左上方番茄、右上方辣椒、右侧中部叶子）并改为**相对定位**（`_FloatingTitle` 用 `Positioned.fill`+`Align`+`Alignment` 归一化坐标，屏幕自适应）；`_PixelBevelFrame` 改为统一深绿色主题像素立体相框（外侧 `AppColors.greenDeep` 4px 粗边、内侧 `AppColors.greenInk` 1px 凹陷阴影线）；`_PixelSpeechBubble` 尾巴偏左指向插画，文字右侧增加红色小爱心。
  - 保留特性列表、登录/游客按钮、隐私说明与错误提示行为；按钮 key（`welcomeLoginButton`/`welcomeGuestButton`/`welcomeRetryButton`）不变。
  - 更新 `test/features/welcome_page_test.dart`，标题断言同步为 "巴食"，并保留封面图、漂浮元素与关键结构 key 的断言。
- **状态**：`UI-WELCOME-001` 进入 `VERIFY`。
- **验证**：`flutter analyze --no-pub lib/features/session/welcome_page.dart test/features/welcome_page_test.dart` 无问题；Codex 未执行 `flutter pub get`、构建、模拟器或真机测试（ADR-0015）。项目负责人应按 `tests/acceptance/UI-WELCOME-001-welcome-page-redesign-2026-08-11.md` 验收。

### 「加入交流群」页（COMMUNITY-001）

- **背景**：Gitee 对仓库 raw 外链有「涉嫌外连滥用」风控（匿名访问被拒，官方申诉不保证解封），项目负责人确认「别人无法访问」，更新分发方案待定（候选：腾讯云 COS/阿里云 OSS、Gitee 发行版附件、蓝奏云）。项目负责人决定先搁置更新分发，新增「加入交流群」入口。
- **代码变更**：
  - `pubspec.yaml`：注册 `assets/community/qq_group.jpg`（源图 `design/assets/交流群.jpg`，1352×2405 竖版海报，153 KB，原图保留不处理）。
  - 新增 `lib/features/profile/community_page.dart`：`CommunityPage`——AppPageHeader「一起聊下厨那些事」+ 引导卡片「为什么加入交流群？」+ 群二维码海报卡片（按源图比例展示，点击进入黑底全屏预览 InteractiveViewer 双指缩放 + 像素关闭按钮）+ 底部进群提示卡片（微信保存后扫一扫 / QQ 长按识别）。
  - `lib/features/profile/profile_page.dart`：「支持我们」下方新增「加入交流群」入口（key `openCommunityTile`，forum 图标绿底）。
- **验证状态**：全项目 IDE 诊断无错误。Codex 未执行 `flutter analyze`/构建/真机（ADR-0015）。`COMMUNITY-001` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/COMMUNITY-001-join-community-2026-08-11.md` 验收：入口存在、海报清晰可扫码、全屏预览可缩放、离线可看。

## 2026-08-11
### Gitee 在线更新（UPDATE-001）

- **项目负责人要求**：新增在线更新功能，使用 Gitee 平台。检查更新页显示当前版本 + 检查更新按钮；有新版本则弹窗提示版本号与更新说明，按钮「以后再说」/「立即升级」。
- **确认的需求（项目负责人选定）**：「立即升级」= 下载 APK 并安装（仅 Android）；入口放「我的」页。数据源 = Gitee 公开仓库（负责人提供 https://gitee.com/eb-Dog/delicious-food，owner=eb-Dog, repo=delicious-food，公开无需 Token）。
- **数据约定**：Release 的 tag_name 为版本号（支持 v 前缀）、body 为更新说明、附件中第一个 .apk 为下载源；`compareAppVersions` 做语义化版本比较（缺省段按 0 补全）。
- **代码变更**：
  - `pubspec.yaml`：新增依赖 `package_info_plus ^8.3.1`（运行时读取当前版本号）。
  - 新增 `lib/domain/update/app_update.dart`：`AppUpdateCheckResult` / `AppReleaseInfo` / `compareAppVersions`。
  - 新增 `lib/features/update/app_update_service.dart`：`checkForUpdate`（GET `releases/latest`，15s 超时，404/非 200/解析失败/网络异常均返回中文错误结果不抛异常）、`downloadApk`（流式下载到临时目录 `ai_recipe_update/`，带进度回调）、`installApk`。
  - 新增 `lib/features/update/update_page.dart`：检查更新页——当前版本卡片（key `currentVersionText`）、「检查更新」按钮（key `checkUpdateButton`）、下载进度条（key `updateDownloadProgress`）、安装中提示、错误提示（key `updateErrorMessage`）、数据来源说明；发现新版本弹出像素风更新弹窗（版本号/当前版本/更新说明 + 「以后再说」/「立即升级」）。
  - 新增 `lib/features/update/apk_installer.dart`：平台通道 `ai_recipe/apk_install`，方法 `installApk`。
  - `lib/features/profile/profile_page.dart`：「数据与存储」下方新增「检查更新」入口（key `openUpdateTile`）→ 跳转 `UpdatePage`。
  - Android 原生：新增 `update/ApkInstallMethodHandler.kt`（FileProvider 暴露 APK + ACTION_VIEW + package-archive mimeType + FLAG_GRANT_READ_URI_PERMISSION 拉起系统安装器）；`MainActivity.kt` 注册通道；`AndroidManifest.xml` 增加 `REQUEST_INSTALL_PACKAGES` 权限、FileProvider（authorities `${applicationId}.updatefileprovider`，`res/xml/update_file_paths.xml`）、queries（INSTALL_PACKAGE / VIEW + package-archive）。
  - 新增单元测试 `test/domain/app_update_test.dart`（版本比较 7 项 + 结果模型 3 项）。
- **验证状态**：全项目 IDE 诊断无错误。Codex 未执行 `flutter pub get`、`flutter analyze`、构建、单元测试与真机（ADR-0015）。`UPDATE-001` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/UPDATE-001-gitee-update-2026-08-11.md` 验收：pub get + analyze 无 error、单元测试通过、「我的」页入口、当前版本显示、无新版提示 / 有新版弹窗 / 立即升级下载安装三场景。

## 2026-08-11
### UPDATE-001 修复（项目负责人反馈）

- **反馈**：检查更新页当前版本显示「未知」；检查更新提示「仓库没有发布任何版本」。
- **根因**：
  1. 「未知」：`PackageInfo.fromPlatform()` 在项目负责人真机上抛异常，被 catch 后版本保持空字符串。
  2. 「仓库没有发布任何版本」：`GET /repos/{owner}/{repo}/releases/latest` 返回 404。404 的三种可能：仓库是私有的（Gitee 匿名 API 一律 404）、仓库还没有任何 Release、路径/仓库名有误。Codex 实测该仓库的 `releases/latest` 与仓库详情接口均返回 404。
- **修复**：
  1. 版本读取改为多重回退：构建时注入（`--dart-define=APP_VERSION=x.y.z`）→ `package_info_plus` → 回退常量 `1.0.0`；页面不再出现「未知」。
  2. `app_update_service.dart`：`releases/latest` 返回 404 时二次请求仓库详情 `/repos/{owner}/{repo}` 区分两种情况——仓库存在（公开可见）→「仓库还没有发布任何版本」；仓库不存在/私有 →「找不到更新仓库，请确认仓库已设为公开且路径正确」。
- **新增测试** `test/features/update_service_test.dart`：新版提示 / 无更新 / 404+仓库存在 / 404+仓库不存在 / 网络异常 / 无 apk 附件 6 项。
- **待项目负责人确认**：仓库是否为公开？是否已创建 Release（含 .apk 附件）？私有仓库匿名 API 会返回 404，需要把仓库改为公开或提供只读 Token（代码未内置 Token，如需再补）。

### UPDATE-001 请求加固 + 函数测试（项目负责人反馈「找不到更新仓库」）

- **反馈**：仓库已有 version.json，但真机检查更新提示「更新未完成，找不到更新仓库」。
- **网络排查结论**：Codex 所在机器到 gitee.com 全部被中间层拦截/污染（公开大仓库 `mirrors/linux` 的 API 也返回 404），无法在本机验证真实 URL；改用逻辑层函数测试。
- **函数测试**：新增 `code/apps/mobile/tool/test_update_parser.py`，用 Python 复刻 Dart 的宽容解析 + 语义化版本比较逻辑，26 项用例全部 PASS（含 v 前缀、缺段补 0、候选键、非法 JSON、版本相等不提示等）。测试中发现并修正一处用例笔误（相等版本应不提示）。
- **Dart 请求加固**（`app_update_service.dart`）：
  1. 请求 version.json 与下载 APK 均带浏览器 UA（`Mozilla/5.0 …Chrome/120`），降低 Gitee 反爬 403 概率。
  2. 分支回退：依次尝试 `master` → `main`，任一 200 即采用。
  3. 状态码细化文案：403 →「检查更新被拒绝（HTTP 403）。请确认仓库已设为公开；若仓库是私有的，需要为应用配置 Gitee 访问令牌。」；404 + 仓库存在 →「仓库里还没有 version.json 更新配置（HTTP 404）…请确认文件已在 master 或 main 分支根目录。」；404 + 仓库不存在 →「找不到更新仓库（HTTP 404）…」。
- **测试新增**：`update_service_test.dart` 增加 403 文案、master→main 分支回退、浏览器 UA 头 3 项（共 11 项）。
- **待项目负责人确认**：仓库是否为公开？若为私有，需把仓库设为公开，或由项目负责人提供只读 Gitee Token 后由 Codex 补 Token 支持。

### UPDATE-001 数据源改为 version.json（项目负责人指定）

- **项目负责人指定**：不再使用 Gitee Release API，改为获取仓库根目录 `https://gitee.com/eb-Dog/delicious-food/blob/master/version.json` 中的配置（实际请求 raw 直链 `…/raw/master/version.json`）。
- **version.json 宽容解析**（`app_update_service.dart` 重写解析）：
  - 版本号（必填）：`version` / `latest_version` / `tag_name` / `latestVersion`。
  - 更新说明：`note` / `changelog` / `update_note` / `release_notes` / `body` / `description`。
  - APK 直链：`apk_url` / `apkUrl` / `download_url` / `downloadUrl` / `url` / `apk` / `apk_link` / `apkLink`。
  - 发布页：`html_url` / `page_url` / `release_page` / `homepage` / `project_url`。
- 404/403 时二次请求仓库详情区分「仓库存在但缺 version.json」与「仓库不存在/私有」。
- 测试 `test/features/update_service_test.dart` 全部改为 version.json 场景（8 项：新版提示/无更新/宽容字段/404+仓库存在/404+仓库不存在/网络异常/无 APK 地址/非法 JSON）。
- 待项目负责人确认 version.json 的实际字段是否在候选键内；若不同，贴出内容后适配。

### LLM 与识图设置结构重分类（SETTINGS-001）

- **项目负责人反馈**：LLM API 设置与识图引擎两个页面的项目需要重新打散排列——多模态 LLM 与普通 LLM 本质都是 LLM；识图引擎的 OCR 与多模态 LLM 都是图片识别能力。
- **确认的结构（项目负责人选定）**：保持「我的」页两个入口——「LLM 模型」与「识图引擎」。
  - 「LLM 模型」入口（`lib/features/llm_settings/llm_settings_page.dart`）：集中管理两类 LLM 配置。
    - **菜谱生成 LLM**（普通文本 LLM，用于结构化生成）——原有内容。
    - **多模态 LLM 图片识别**（独立配置）——从识图引擎页迁入。
    - 两类 LLM 保持各自独立配置（API 地址 / Key / 模型 / 超时分别保存）。
  - 「识图引擎」入口（`lib/features/settings/ocr_settings_page.dart`）：只保留 OCR 相关——图片识别方式（自动 / 仅 OCR / 多模态 LLM）、本地 OCR 模型、云端路线；不再内嵌多模态 LLM 配置表单。
- **代码变更**：
  - 将 `_MultimodalLlmConfigSection`、`_MultimodalTestResultCard`、`_MultimodalDiagnosticCard`、`_DiagnosticStageRow`、`_diagnosticStageLabel`、`_diagnosticMessage` 从 `ocr_settings_page.dart` 移入 `llm_settings_page.dart`。
  - `ocr_settings_page.dart`：删除多模态 LLM 配置调用及上述私有类/函数，并清理 4 个不再使用的 import（llm_settings_use_cases、llm_diagnostic、llm_provider_type、multimodal_llm_provider）；保留图片识别方式选择（含"多模态 LLM"选项，选项配置读取 LLM 页保存的图片识别 LLM）。
  - `llm_settings_page.dart`：新增 3 个 import（llm_diagnostic、multimodal_llm_provider、import_image_picker）；页面标题由「本地 LLM API」改为「LLM 模型」；普通 LLM 区新增「菜谱生成 LLM」区块标题；末尾追加多模态 LLM 配置 section。
  - `profile_page.dart`：入口标题「LLM API 设置」改为「LLM 模型」。
- **验证状态**：IDE 诊断无错误（GetDiagnostics 为空）。Codex 未执行 `flutter analyze`、构建、模拟器或真机测试（ADR-0015）。`SETTINGS-001` 进入 `VERIFY`，等待项目负责人按验收文档构建后核对：LLM 模型页同时包含「菜谱生成 LLM」与「多模态 LLM 图片识别」两个区块、识图引擎页只含 OCR 相关且无多模态配置表单、两类 LLM 配置可独立保存。

## 2026-08-10
### 首页/冰箱/导航图标替换与 12 个默认分类（HOME-001）

- **项目负责人要求**：将冰箱、菜品分类、快速导图图标替换为 `design/assets/icon/home/` 下设计素材，处理背景色并统一尺寸；替换底部导航栏 `nav.png` 图片并分割多个图标。
- **图标处理脚本**：新增 `code/apps/mobile/tool/process_home_icons.py`。
  - 从 `design/assets/icon/home/` 读取源图。
  - 四角采样估计背景色并去底，保留设计素材原始图标颜色。
  - 内容裁切后等比缩放至 64×64 正方形 PNG，使用 nearest-neighbor 保持像素风锐利。
  - `nav.png` 按 4 列 2 行切分，生成 8 张导航图标（home/library/fridge/profile × inactive/active）。
- **生成资产**：`code/apps/mobile/assets/icon/home/`。
  - `fridge/`：冷藏区、冷冻区、常温区、其他区 4 张。
  - `categories/`：主食、家常菜、快手菜、早餐、水产、汤羹、烘焙、甜品、素菜、肉类、轻食、饮品 12 张。
  - `quick/`：链接导入、视频识别、图片识别、手动记账 4 张。
  - `nav/`：home/library/fridge/profile 各 inactive/active 共 8 张。
  - 全部 64×64，单张 < 1 KB。
- **资产注册**：`pubspec.yaml` 已注册 `assets/icon/home/fridge/`、`categories/`、`quick/`、`nav/` 四个目录。
- **UI 组件扩展**：`lib/shared/widgets/pixel_ui.dart`。
  - `PixelTab` 的 `icon`/`selectedIcon` 类型从 `IconData` 放宽为 `Object`。
  - `PixelTabBar._buildIcon` 支持 `IconData` 或任意 `Widget`（如 `Image.asset`），加载失败或未知类型时抛出明确错误。
- **页面接入新图标**：
  - `lib/features/shell/app_shell.dart`：底部导航 4 个 tab 改用 `_NavIcon(Image.asset)`，尺寸 21×21。
  - `lib/features/fridge/fridge_page.dart`：冰箱 4 个分区标题左侧 26×26 图标块改用新图标。
  - `lib/features/home/home_page.dart`：快速导入 4 按钮（18×18）与首页分类横向列表（22×22）改用新图标。
  - `lib/features/library/recipe_library_page.dart`：分类筛选 ChoiceChip 的 avatar（15×15）改用新图标。
- **12 个默认分类**：
  - 新增 `lib/application/recipe/default_recipe_categories.dart`，定义默认分类 ID、名称与图标资产路径，并提供 `categoryIconAsset()` / `defaultCategoryName()` 查询。
  - `lib/application/recipe/recipe_library_use_cases.dart`：`listCategories()` 幂空检查，若分类表无任何记录则自动创建 12 个默认分类。
- **导航栏样式微调（2026-08-11）**：项目负责人反馈选中 tab 不应显示绿色激活方框边框。已移除 `PixelTabBar` 中选中项的 `Border.all` 装饰。随后负责人进一步要求去掉绿色背景，已将 `Material` 颜色从 `AppColors.greenSofter` 改为 `Colors.transparent`；选中态仅通过 asset 图标切换（active/inactive 两套）和深绿文字表达。
- **验证状态**：Codex 未执行 `flutter analyze`、构建、模拟器或真机测试（ADR-0015）。`HOME-001` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/HOME-001-home-icons-and-categories-2026-08-10.md` 验收：静态分析无 error、冷启动显示 12 个默认分类、各页面图标无背景残留、底部导航选中态无背景填充/无边框。


### 非品牌美术资产移除官方 IP（DESIGN-008 v1.3）

- **项目负责人要求**：除品牌用途外，其他图标和插图不再使用官方水豚主厨 IP；最终资产继续以已经落地的「巴食」UI 为视觉事实源，并保持严格二维像素风。
- **IP 使用边界**：`design/assets/IP.png` 只允许用于 App 启动图标、品牌核心符号、欢迎页 Hero、通用菜谱无封面 4 项品牌资产。状态插图 12 条、功能入口 10 条、冰箱 / 库存 10 条、分类 default 12 条，共其他 44 条基础 Prompt 全部禁止上传、参考或生成 IP；导航 8 枚 glyph 与分类 12 张 active 同样禁止 IP。
- **非品牌构图规则**：非品牌资产只用物体、食材和符号表达功能语义，禁止水豚、人物、动物角色、厨师、厨师帽、墨镜、脸、五官、手脚、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。新增统一非品牌母规则，并继续执行正视 / 正交、有限色板、实色块、方形像素台阶及无 3D / 无透视 / 无厚度 / 无渐变 / 无软阴影 / 无抗锯齿约束。
- **已同步文件**：重写 `design/assets/IMAGE2_ICON_PROMPTS.md`、`design/assets/README.md`、`design/assets/prompts/README.md`、导航 / 品牌 / 状态 / 功能入口 / 冰箱库存 / 分类 / active 分组 Prompt 及对应 6 个 `for-ai/*.txt`；新增 ADR-0041，明确本决策收紧 ADR-0039 中较大状态插图可使用 IP 的旧边界，ADR-0039 的正式名称和像素规则、ADR-0040 的 active 状态职责继续有效。
- **验收顺序**：v1.3 首轮回传 `bottom-navigation-glyph-state-proof-v1.3.png`、`category-breakfast-v1.png`、`category-breakfast-active-v1.png`、`state-fridge-empty-v1.png`；四张通过后再继续其他 46 条基础 Prompt 和其余 11 张分类 active。
- **验证状态**：Codex 未调用 Image 2、未生成图片，未执行自动测试、Flutter/Dart 静态分析、构建、模拟器或真机测试；DESIGN-008 保持 `VERIFY`，等待项目负责人按 `tests/acceptance/DESIGN-008-image2-icon-prompts-2026-08-10.md` 回传首轮样张。

### Image 2 严格二维像素美术提示词返工（DESIGN-008）

- **项目负责人反馈**：上一版生成结果过度 3D，不符合已经落地的 UI；同时确认正式 App 名称为「巴食」，`design/assets/IP.png` 是官方 IP。再次生成的导航样张仍存在 3/4 透视、书本厚度、明暗高光和落地阴影，随后项目负责人认可严格二维像素 UI glyph 的返工方向，并要求补齐激活态及其他资产提示词。
- **品牌与渲染边界**：ADR-0039 固定「巴食」为正式产品名；`IP.png` 只控制官方水豚主厨身份，现有 Flutter/HTML UI 控制最终色板、像素密度、阶梯缺角、深墨绿硬描边与右下硬投影；`封面图.png` 只用于理解角色与厨房场景关系。
- **v1.2 导航双状态**：`design/assets/prompts/00-bottom-navigation-icons.md` 现要求首页、菜谱库、冰箱、我的 4 组 / 8 枚 24×24 单色像素 glyph；首轮生成 2×4 确认稿，default 使用 `#8F978F` outline，active 使用 `#476B52` filled / strong，上下两态同外轮廓、尺寸、位置、重心、基线和负空间；不上传 `IP.png`，不包含 `#EDF2EA` 激活容器。
- **v1.2 分类双状态**：新增 `design/assets/prompts/06-active-state-supplements.md`，为家常菜、快手菜、早餐、主食、汤羹、烘焙、甜品、饮品、素菜、肉类、水产、轻食 12 组分类补充 active 通用编辑 Prompt；active 必须基于已通过的 default 原图，只调整 `#476B52` / `#33513C` 深绿色视觉权重，保持轮廓、像素矩阵、位置、基线、描边、硬投影和透明区域不变。
- **状态职责决策**：新增 ADR-0040。导航与默认分类制作独立 default / active；品牌、状态插图、功能入口、冰箱分区、库存和推荐图标不制作独立 active；短暂 pressed / busy / disabled / focus、选中容器、缺失、数量、等级和进度由 Flutter 处理；16–24px 高频操作符号继续使用 Flutter 原生组件。
- **其他美术 Prompt**：品牌 4 项、状态 12 项、功能入口 10 项、冰箱/库存 10 项、分类 default 12 项，共 48 条仍保持独立完整、可直接复制；每条继续执行严格二维像素、有限色板、正交构图、硬边像素和完整 3D/柔滑反向约束。
- **验收顺序**：重写并同步 `tests/acceptance/DESIGN-008-image2-icon-prompts-2026-08-10.md`。首轮只回传导航 2×4、共 8 枚双状态 glyph，以及 `category-breakfast-v1.png` / `category-breakfast-active-v1.png`；早餐两态需 50% 透明叠放无位移、40px 可辨，验证通过后才继续其余 11 组分类 active 和后续代表样张。
- **边界与验证状态**：App 图标不预制系统圆角；透明资产使用纯 `#FF00FF` 背景后本地去背；任一 3D、透视、厚度、渐变、软阴影、平滑抗锯齿或圆润矢量感均整张淘汰。本轮未调用 Image 2、未生成正式图片，未执行自动测试、Flutter/Dart 静态分析、构建、模拟器或真机测试；DESIGN-008 保持 `VERIFY`，等待项目负责人回传样张。

### 应用名称统一为「巴食」（BRAND-001）

- **项目负责人要求**：将应用名称改成「巴食」。按 ADR-0039（正式产品名固定为「巴食」）与 `BRAND-001` 盘点并统一全仓产品可见名称。
- **已修改**：
  - Android：`android/app/src/main/AndroidManifest.xml` 的 `android:label` `ai_recipe` → `巴食`（桌面与应用管理器中显示名）。
  - iOS：`ios/Runner/Info.plist` 的 `CFBundleDisplayName` `Ai Recipe` → `巴食`。
  - Flutter：`lib/app/app.dart` MaterialApp `title` → `巴食`；`lib/features/session/welcome_page.dart` 欢迎页品牌标题「拾 味」→「巴 食」（字距 7 保持原风格，眉题 `TASTE PIXEL · AI RECIPE` 保留）。
  - HTML 原型（视觉事实源）：`design/prototypes/index.html`（页面 title、侧栏 h1）、`app.js`（文件头注释、欢迎页 h1「拾&nbsp;味」→「巴&nbsp;食」、关于页「关于拾味」→「关于巴食」、about toast、字体展示样例）、`prototype.css`（文件头注释）、`README.md`（标题行）、`design-docs/00-目录索引.md`、`design-docs/UI-001-欢迎页.md` 中全部「拾味」→「巴食」。
- **未修改（按 BRAND-001 边界）**：`pubspec.yaml` 的 `name: ai_recipe`（包名）与 description；iOS `CFBundleName`/bundle id（非用户可见标识）；历史验收记录（`tests/acceptance/UI-001-*.md`）、评审文档（`design/reviews/UI-001-html-flutter-gap-analysis-2026-08-01.md`）与 `.workbuddy/memory` 记忆文件；`tracking/BACKLOG.md`/`DECISIONS.md` 中作为任务描述对「拾味」的引用。
- **验证**：Flutter 代码与测试目录均无「拾味」断言；HTML 原型目录已无「拾味」残留。未运行测试/构建/真机（ADR-0015）；等待项目负责人重新构建后确认 Android 桌面应用名与欢迎页品牌标题显示为「巴食」。

### 应用启动图标替换为「巴食」图标（BRAND-002）

- **项目负责人要求**：将应用图标改成 `design/assets/图标.png`。
- **已实施**：
  - 源图 1756×1676 居中裁剪为 1676×1676 正方形，按平台规范 cubic 缩放生成 20 个文件。
  - Android：`android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`（48/72/96/144/192 px，保留透明通道）。
  - iOS：`ios/Runner/Assets.xcassets/AppIcon.appiconset/` 全部 14 个尺寸（20×20@1x ~ 1024×1024@1x），合成纯白底去除 alpha，已验证 PNG color type=2（RGB 无透明，符合 App Store 要求）。
  - 新增一次性生成脚本 `code/apps/mobile/tool/gen_launcher_icons.dart`（`dart run tool/gen_launcher_icons.dart`），便于后续换图复现。
- **验证**：脚本输出尺寸与文件数量核对通过；iOS/Android 图标 PNG color type 字节校验通过。未运行测试/构建/真机（ADR-0015）；等待项目负责人重新构建后在桌面/应用管理器确认新图标。
- **2026-08-10 追加（源图已更新，重新生成）**：项目负责人再次提出「将图标换成 `design/assets/图标.png`」。检查发现源图已于 16:28 更新为 **2048×2048**（旧图为 1756×1676，生成文件时间戳 15:55 早于源图），即需用新源图重新生成。沙箱内 `dart run tool/gen_launcher_icons.dart` 持续无输出超时，改用 PowerShell/System.Drawing 等价脚本重新生成全部 20 个文件（Android 5 个 mipmap 48/72/96/144/192；iOS AppIcon.appiconset 15 个尺寸 20×20@1x ~ 1024×1024@1x），处理策略与 dart 脚本一致（居中裁剪正方形 + HighQualityBicubic 缩放；Android 24bppRGB 输出，iOS 纯白底合成无 alpha）。验证：Android 5 文件均为 24bppRGB 且尺寸正确，iOS 15 文件全部无 alpha，无乱码路径残留文件；`tool/gen_launcher_icons.dart` 注释已同步为 2048×2048。未运行测试/构建/真机（ADR-0015）；等待项目负责人重新构建后在桌面/应用管理器确认新图标。

### 「我的」页新增「支持我们」赞赏页（PROF-001）

- **项目负责人要求**：在「我的」页面添加一个赞赏界面，展示 `design/assets/收款码/` 下的微信、支付宝两张收款码，并带上感谢使用、感谢支持之类的话。
- **已实施**：
  - 收款码打包为应用资产：`assets/payment/wechat_qr.jpg`（源 1213×1213）、`assets/payment/alipay_qr.jpg`（源 1260×1890），`pubspec.yaml` assets 注册（含来源注释）。
  - 新增 `lib/features/profile/support_page.dart` 赞赏页：`AppPageHeader`（感谢你的支持）+ 感谢语卡片（❤ 感谢使用 AI 食谱，赞赏自愿、核心功能永远免费）+「扫码赞赏」两张收款码卡片（按源图比例展示缩略图 + 平台标签 +「点击放大」提示）+ 底部自愿与动力提示；点击收款码进入全屏黑底预览（参考菜谱详情 `_FullscreenImageGallery`：PageView 左右滑动切换 + InteractiveViewer 双指缩放 + 像素风关闭按钮 + 底部平台/页码标签）。
  - 「我的」页（`lib/features/profile/profile_page.dart`）「隐私与数据」区块末尾新增「支持我们」入口（`PixelRowTile`，`openSupportTile` key，爱心图标）。
  - 产品文档 `docs/product/AI食谱应用产品需求文档.md` 4.4「我的」补充「支持我们（赞赏）」条目。
- **验证**：`support_page.dart`、`profile_page.dart` IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人构建后人工验收（入口跳转、收款码显示清晰、放大预览可缩放滑动）。
- **修复（项目负责人运行时报 "No Material widget found"）**：`SupportPage` 是 `Navigator.push` 独立路由，原返回 `SafeArea > ListView` 没有 `Scaffold`，页面内 `_QrCodeCard` 的 `InkWell` 找不到 Material 祖先（"我的"页有 AppShell 的 Scaffold 提供上下文所以不报错）。已在 `SupportPage.build` 外层补 `Scaffold(body: SafeArea(...))`，IDE 诊断通过，等待项目负责人复测。
- **追加（开发者工具隐藏入口 + 头像改程序图标）**：按项目负责人要求——①「我的」页开发者工具区块默认隐藏，新增 `_devToolsVisible` 状态；连续点击头像 6 次（`_onAvatarTap`，1.5 秒窗口内连击，`profileAvatar` key）切换显示/隐藏并 SnackBar 提示；②头像默认人形图标改为程序图标 `assets/brand/app_icon.png`（源图 `design/assets/图标.png`，与启动图标同源，已复制并注册 pubspec），加载失败回退人形图标。产品文档 4.4「我的」补充开发者工具隐藏入口说明。IDE 诊断通过；未运行测试/构建/真机（ADR-0015），等待项目负责人复测。

## 2026-08-09

### 烹饪模式按钮亮色与暗色同长修复（COOK-001 追加）

- **项目负责人反馈**：上一步/下一步与计时器部分的按钮「亮色部分比暗色（阴影）部分短」，要求亮色与暗色一样长。
- **根因**：`cooking_mode_page.dart` 中带像素阴影的 `_CookingPixelSurface`（`_CookingNavButton` 上一步/下一步、`_CookingIconAction` 暂停/继续/完成计时、`_TimerCard` 计时器卡片、当前步骤面板、`_CookingStateIcon` 完成状态大图标、`_CookingMiniButton`）主体底色均为**半透明**（`0x1AFFFFFF` 10% 白、`0x14FFFFFF` 8% 白、`_panel` 6% 白、`_panelStrong` 9% 白）。半透明底叠在深绿背景 `0xFF2D3D33` 上几乎不可见，只有右下偏移的像素阴影（`Color(0x38000000)`）清晰可见，因此视觉上「暗色（阴影）比亮色（主体）长」。
- **补充根因（项目负责人指出）**：真正让阴影比主体宽很多的是 `_CookingPixelSurface` 的 Stack 布局——底部导航按钮被 `Expanded` 包裹、外部约束为 tight（整行宽）时，`Stack` 尺寸 = 整行宽，`Positioned.fill` 的阴影跟随 Stack 被撑满整行，而亮色主体是非定位 child、按内容（Row `mainAxisSize.min`）收缩并贴左上角，于是阴影比主体宽很多（半透明底色只是放大了该现象）。
- **修复**：
  1. 给 `_CookingPixelSurface` 的 Stack 加 `fit: StackFit.expand`，让亮色主体填满整个面板区域，主体 = Stack = 阴影同尺寸，阴影只在右下 2px 露边。
  2. 新增不透明实色常量 `_panelSolid = Color(0xFF41584C)`（比背景亮一档的深绿），实色主体能完整遮住阴影区域，亮色主体与暗色阴影同宽（阴影只在右下 2px 露边）。
  3. 替换全部带阴影的 `_CookingPixelSurface` 半透明底色为 `_panelSolid`：`_CookingNavButton`（次级按钮）、`_CookingIconAction`、`_TimerCard`、当前步骤面板 `currentCookingStepPanel`、`_CookingStateIcon`、`_CookingMiniButton`。
  4. 删除不再使用的 `_panel`/`_panelStrong` 两个半透明常量。
- **验证**：`cooking_mode_page.dart` IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

## 2026-08-07

### 修复慢速 LLM 服务下「最终结构化生成」固定 120 秒超时失败（BUG-008）

- **项目负责人反馈**：链接只有一个图片，单图识别成功（82 秒）后「最终结构化生成」报 `kind=timeout` 失败（耗时 120025ms）。
- **根因**：`LlmConnectionConfig.requestTimeout` 默认 120 秒；两处设置页（LLM 配置页 `llm_settings_page.dart`、识图引擎多模态区 `ocr_settings_page.dart`）的超时档位只有 `30/60/120` 秒，无法调大。用户配置的 LLM 服务响应慢（单图识别就要 82 秒），生成完整菜谱 JSON 超出 120 秒时被 `HttpLlmTransport` 的 `.timeout(request.timeout)` 主动中断，映射为 `ImportTaskErrorCode.timeout`。
- **修复**：
  1. 两处设置页超时档位扩展为 `30/60/120/180/300/600` 秒，慢速本地模型（Ollama/LM Studio 等）可配置更长超时。
  2. 结构化生成（`llm_recipe_generation_processor.dart`）与多模态识别（`multimodal_image_enriching_import_content_processor.dart`）的超时错误文案补充指引：「在 LLM/识图引擎设置中调大『请求超时』后重试」。
  3. **诊断辅助**：LLM 设置页新增「测试结构化生成」区块（key `structuredGenInputField`/`testStructuredGenButton`）——输入任意菜谱文本，走与真实导入完全相同的结构化生成 prompt 与 JSON Schema（复用 `RecipeGenerationPromptBuilder`），展示耗时（毫秒 + 秒）与生成字符数（key `structuredGenElapsedText`），空输入提示不请求（key `structuredGenErrorText`）。新增链路：`LlmSettingsUseCases.testStructuredGeneration` → Facade `testLlmStructuredGeneration`，与 `testConnection` 共用 `_resolveApiKey` 密钥解析。
- **测试**：`llm_settings_page_test` 新增「600 秒档位可选且保存后配置携带 600 秒」「结构化生成测试携带文本并展示耗时」「空输入提示」；`ocr_settings_page_test` 新增「多模态超时档位含 600 秒」；`llm_settings_use_cases_test` 新增 `testStructuredGeneration` 组（成功耗时+系统/用户消息、空文本 invalidInput、Provider 超时脱敏映射）。
- **追加修复（2026-08-07，排查「测试结构化 30 秒、实际导入 120 秒超时」）**：
  4. **根因定位**：`LlmSettingsUseCases._buildConfiguration` 构造测试/保存用 `LlmConnectionConfig` 时未继承已保存的 `reasoningMode`，恒为 fast；「测试结构化生成」的 `RecipeGenerationPromptBuilder.build(content)` 也未传推理模式。若存储配置为 `deep`（PERF-001 深度思考开关，无设置页入口、用户不可见），实际导入 `LlmRecipeGenerationProcessor.process` 会显式传 `config.reasoningMode`（deep）→ Provider 发送 `reasoning_effort: high`，生成耗时成倍增长；测试却始终以 fast 运行（30 秒），造成「测试快、导入慢」的假象。另外确认：测试输入为手输短文本，实际导入 prompt 为「原文 + 整图 OCR 转录全文」（`sourceCharacterCount` 最大 40000 字符），长文本生成耗时显著更高属正常现象，非代码缺陷。
  5. **修复**：`_buildConfiguration` 新增 `reasoningMode: existing?.reasoningMode ?? LlmReasoningMode.fast`（保存/测试均继承存储值）；`testStructuredGeneration` 的 `build(content, reasoningMode: existing?.reasoningMode)` 与导入链路一致；`LlmStructuredGenerationResult` 新增 `reasoningMode` 字段并在设置页耗时文案展示实际生效模式（如「· 模式 fast」，key `structuredGenElapsedText`）。
  6. **测试补充**：`llm_settings_use_cases_test` 新增「已保存 deep 时测试请求与结果均携带 `reasoningMode=deep`」「`saveConfiguration` 保留已保存 deep 不重置为 fast」。
- **文档**：BACKLOG 更新 BUG-008（VERIFY）、CURRENT、验收文档新增用例 7（推理模式显示）/用例 8（真实 OCR 转录文本复现耗时）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/BUG-008-request-timeout-options-2026-08-07.md` 复测。

### 冰箱库存批次编辑页增加删除按钮（FRIDGE-002 补充）

- **项目负责人反馈**：冰箱里已入库的食物无法删除，希望点进去编辑时提供一个删除按钮。
- **实现**：`fridge_batch_edit_page.dart` 编辑态（`_isEditing`）在「保存修改」按钮下方新增红色「删除批次」按钮（key `deleteInventoryBatchButton`，`OutlinedButton.icon`，红色图标/描边）——点击弹出像素风二次确认（`showPixelConfirm`，title「删除批次」、confirmLabel「删除」、confirmColor 红），确认后调用 `AiRecipeBackendFacade.deleteInventoryBatch(batch.id)`，成功后 `pop(true)` 返回库存页并触发刷新；取消或返回键关闭不删除；新增态不显示该按钮；删除/保存期间共用 `_saving` 禁用，失败展示错误横幅。
- **测试**：`fridge_page_test` 新增「新增态无删除按钮 / 编辑态显示删除按钮 / 取消确认保留批次 / 确认删除后批次清单为空」。
- **文档**：BACKLOG 更新 FRIDGE-002（DOING，补充说明）、CURRENT。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人构建 Android 复测。

### 推荐页分组改为「方案A · 像素旗标带」（RECO-001，项目负责人反馈）

- **项目负责人反馈**：参考原型的 HTML，把冰箱推荐的分组改成「方案A」。
- **实现**：对照 `design/prototypes/prototype.css` 的 `.rg-ribbon`（方案A 像素旗标带）把推荐结果分组标题全部替换为旗标带样式：色带（`_GroupRibbon`，实色底 + `PixelCut.sm` 切角 + 3px 硬投影）+ 计数徽标（浅底 `soft` + 深字 `ink` + `PixelCut.xs` 切角）+ 虚线延伸（`_RibbonLinePainter`，同色 6px 色块 + 6px 透明重复）。分组配色（对照方案A语义）：现在就能做=绿、可能可以做=琥珀、库存不足=红、缺 1/缺 2 样=琥珀、优先清库存=蓝。原「缺 N 样」整组折叠功能保留（可折叠分组的旗标带整行可点、右侧箭头指示展开/收起）。删除原 `_GroupTitle`。**微调（2026-08-07）**：旗标带标题底部间距由 6 调到 14，拉开与下方第一张卡片的距离。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### 推荐页「缺 N 样」分组整组折叠（RECO-001，项目负责人反馈）

- **项目负责人反馈**：推荐匹配结果里「缺 N 样」的分组应有一个折叠按钮，可以折叠起来，避免缺食材的菜谱把结果页撑得过长。
- **实现**：`fridge_recommendation_view.dart` 的 `_ResultsSectionState` 新增整组折叠状态 `_collapsed`，`initState` 默认把「缺 1 样」「缺 2 样」置为折叠；`_buildGroup` 新增 `collapsible` 参数（缺 1/缺 2 样置 true），折叠时只显示标题不渲染卡片；`_GroupTitle` 支持 `collapsed`/`onToggle`，整个标题行可点击、右侧箭头指示展开(↑)/收起(↓)。展开后仍保留原有「查看更多」逻辑。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### BUG-009 确认草稿场景 context 生命周期断言崩溃（framework 断言）

- **项目负责人反馈**：识别图片导入后确认草稿时崩溃，日志含 `'framework.dart': _elements.contains(element) is not true` 与 `Looking up a deactivated widget's ancestor is unsafe`，并有系统返回键事件。
- **根因**：`import_draft_review_page.dart` 与 `import_progress_page.dart` 中各 async 方法在 await 后使用 context 做导航/弹窗前，仅用 `if (!mounted) return;`（`State.mounted`）防护。但在路由退场过渡期（用户按返回键、Element 已 deactivate 尚未 dispose）`State.mounted` 仍为 true，此时 `Navigator.of(context)`/`showDialog(context)` 会触发 framework 断言；`context.mounted` 在该窗口为 false，可正确拦截。
- **修复**：将「await 后使用 context 做 push/pop/showDialog」前的判断改为 `if (!context.mounted) return;`：
  - 确认页 `_save`（保存后 pop）、`_discard`（放弃后 pop）。
  - 进度页 `_openReview`（confirmAll pop、单草稿保存后 pop、catch 回退 push/pop）、`_pushReviewPage` 开头、`_showMultiDraftPicker`（拉取多份草稿后 showDialog）。
  - 纯 `setState` 处仍保留 `State.mounted`（无需 context）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测「识别图片导入→确认草稿」在保存/放弃/按返回键时不再崩溃。

### LLM 识别/结构化生成强制保持原文语言（项目负责人反馈）

- **项目负责人反馈**：LLM 在识别时会私自把内容语言改了（例如把中文改写成英文），应强制按所给内容的语言输出，不要私自改。
- **实现**：
  1. `multimodal_image_enriching_import_content_processor.dart` 多模态转录固定提示词 `defaultPrompt` 强化语言约束：除原「不要翻译」外，显式要求「必须保持与图片文字完全相同的语言输出，禁止翻译，禁止改用其他语言；图片是中文就输出中文、是日文就输出日文、是英文就输出英文，不要因为提示词语言而改变输出语言」。
  2. `recipe_generation_prompt.dart` 结构化生成 system prompt 增加语言指令：所有文本字段（标题/简介/备注/食材名与处理/步骤/贴士）必须与用户提供的源文本同语言，禁止把菜谱内容翻译成其他语言（即使指令本身是英文）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人构建 Android 用多语言配图复测。

### 冰箱/我的页隐藏全局添加菜谱 FAB + 推荐页「仅使用已选食材」开关移位

- **项目负责人反馈**：①冰箱和「我的」页面右下角不要显示全局「添加菜谱」FAB；②冰箱推荐部分的「仅使用已选食材」位置不合理，需放到合理位置。
- **实现**：
  1. `app_shell.dart` 全局 `floatingActionButton`（key `addRecipeFab`）改为仅在首页(0)与菜谱库(1)显示（`_selectedIndex <= 1`），冰箱(2)与我的(3)不再显示；冰箱页自身的「添加食材」FAB（`addInventoryBatchFab`，仅库存 tab）保留不受影响。
  2. `fridge_recommendation_view.dart` 把「仅使用已选食材」开关从底部操作栏（推荐按钮上方）移到顶部选择区——紧跟在快捷操作（全部/临期/冷藏/冷冻/清空）之后，作为本次匹配的「范围偏好」，底部操作栏仅保留「一键用全部库存推荐 / 用已选食材推荐（N）」按钮。
  3. **再微调（2026-08-07 项目负责人反馈）**：「仅使用已选食材」开关独占一行、文字左对齐（`MainAxisAlignment.start`）；底部推荐按钮由普通布局改为**悬浮**——`build` 用 `Stack`（`Positioned.fill` 列表铺满 + `Align.bottomCenter` 悬浮按钮），`_buildBottomBar` 带纸张背景 + 顶部细线，列表 `padding.bottom` 由 96 调到 130 避免末项被遮，结果/筛选视窗不再被挤压。
- **文档**：BACKLOG 更新 FRIDGE-002（DOING）、CURRENT。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人构建 Android 复测。

### 烹饪模式无时长步骤自定义计时并同步菜谱（COOK-001）

- **项目负责人反馈**：烹饪界面里有些步骤没有计时，希望加一个自定义的；用户自定义后也要同步到菜谱中。
- **实现**：
  1. 领域 `RecipeLibraryUseCases` 新增 `updateRecipeStepDuration(recipeId, stepId, durationSeconds)`：校验时长 > 0、步骤属于当前菜谱；`Recipe`/`RecipeStep` 不可变且无 copyWith，只重建目标步骤（保留 id/序号/描述/温度/火力/厨具/提示/媒体/置信度），其他步骤原样保留，整体重建 `Recipe`（其余字段从现有复制）并递增 `localVersion` 后 upsert。
  2. `AiRecipeBackendFacade` 透传 `updateRecipeStepDuration`（`_recipeOperation` 包装，异常映射为稳定错误）。
  3. 烹饪模式页：无时长（`durationSeconds` 为 null 或 0）步骤显示「自定义本步计时」按钮（key `customStepTimerButton`，outlined/compact，`_actionBusy` 时禁用）；点击弹出像素风 `_CustomTimerDialog`（分钟/秒两个输入框，key `customTimerMinutesField`/`customTimerSecondsField`，透明 Dialog + `PixelSurface` 切角/描边/投影，控制器随弹窗生命周期释放），确认（key `confirmCustomTimerButton`，文案「开始计时」）返回总秒数、取消（key `cancelCustomTimerButton`）返回 null；`_applyCustomStepDuration` 先 `updateRecipeStepDuration` 同步菜谱，再 `addCookingTimer` 创建「步骤 N」计时器，成功后 SnackBar"已创建计时器，并将时长同步到菜谱。"。
  4. 弹窗校验：分钟/秒非数字或总秒数 ≤ 0 时 SnackBar"请输入大于 0 的时长"且不关闭弹窗。
- **2026-08-07 反馈调整**：删除计时器空态提示「暂无计时器，可为带时长的步骤启动计时。」与无时长步骤提示「本步骤未设置时长，自定义后时长将同步保存到菜谱。」（项目负责人：计时的页面不需要这些提示文案）。
- **测试**：`recipe_library_use_cases_test` 新增 3 项（只更新目标步骤/时长 0 抛异常/步骤不属于菜谱抛异常）；`ai_recipe_backend_facade_test` 新增 2 项（更新时长持久化/非法输入映射 invalidInput）；`cooking_mode_page_test` 新增 3 项（无时长步骤显示自定义按钮且无一键启动/输入 2 分 30 秒确认创建 150 秒计时器并同步菜谱步骤时长与 SnackBar/取消弹窗一切不变）。
- **文档**：产品需求 5.4.4 新增"未设置时长的步骤允许自定义计时并同步保存到菜谱步骤"；DECISIONS 新增 ADR-0037；BACKLOG 新增 COOK-001（VERIFY）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/COOK-001-custom-timer-sync-2026-08-07.md` Android 复测。

### 拍照选图导入直接多模态识别，不再复用链接导入流程（BUG-007 后续修复）

- **项目负责人反馈**：拍照选图导入解析后变成了「从链接导入」，还给出一个本地占位链接（`https://local-image/capture`），期望直接交给多模态 AI 识别图片内容，而不是复用旧的链接导入操作。
- **根因三处**：
  1. `ImportTask.startWithFallback` 只允许 failed/cancelled 用内容运行；拍照选图新建的任务是 queued，facade 允许 queued 但底层 runner 守卫抛 `ImportTaskTransitionException`，导致排队占位任务无法直接用本地图片内容运行。
  2. 导入进度页 `_SourceCard` 无条件显示 `task.normalizedUrl`（占位 URL）和「网页链接」平台标签，用户误以为走了链接导入。
  3. `_resolveLocalImagePlan` 自动（auto）模式默认本地 OCR 优先（ADR-0029 旧规则），与用户期望的「直接多模态识别」不符。
- **修复**：
  1. `startWithFallback` 允许 queued：直接进入 extracting（跳过 fetching，不抓取公开链接），图片/文本内容由 `runImportWithLocalImage` / `runImportWithText` 提供；`runWithContent` 守卫同步放宽。
  2. `_SourceCard` 对占位任务显示真实来源语义（「本地图片导入 / 文本整理导入」），不再暴露内部占位链接。
  3. `_resolveLocalImagePlan` 自动模式改为多模态优先：多模态可用→multimodal，未配置/不可用→回退本地 OCR；用户显式选择某一路时尊重选择（ADR-0029 修订）。
- **测试**：`import_task_test`（queued 可 startWithFallback 进入 running/extracting/0.25）、`import_task_runner_test`（queued 占位任务直接处理内容，阶段序列无 fetching；running 仍拒绝）、`ai_recipe_backend_facade_test`（BackendHarness 新增 `multimodalLlmReadiness`；新增「多模态优先时直接用多模态识别」正面用例 +「多模态不可用时回退本地 OCR」+「识图路由全部不可用→providerRouteUnavailable 且不暴露路径」；queued 允许、running 拒绝）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人 Android 复测。

### 修复首页「拍照选图/剪贴板」导入报「导入任务暂时无法保存，请稍后重试」（BUG-007）

- **项目负责人反馈**：首页快速导入「拍照选图」打开系统选图选择图片后，提示「导入任务暂时无法保存，请稍后重试」，无法创建本地图片导入任务。
- **根因**：`app_database.dart` 的 `import_tasks.source_platform` 列 CHECK 约束只允许 `('xiaohongshu','douyin')`；而本地图片/文本导入使用占位 URL（`https://local-image/capture` / `https://local-text/capture`），经 `ImportSourceLink.parse` 解析后平台值落到 `web`（`import_task.dart` 第 107 行 `_ => web`）。`SqliteImportTaskRepository.upsertTask` 的 insert 违反表约束抛 `DatabaseException`，被 `AiRecipeBackendFacade.createLocalImageImportTask`/`createLocalTextImportTask` 的 `catch (_)` 吞掉并替换为通用文案「导入任务暂时无法保存，请稍后重试。」。影响面不止拍照选图：剪贴板文本导入（`localTextCapturePlaceholderUrl` → web）与通用任意网页链接导入（IMPORT-008，平台=web）创建任务时同样会失败。
- **修复**：
  1. `schemaVersion` 11 → 12；`_createImportTaskSchema` 拆出 `_createImportTaskTable(database, tableName)`（CHECK 约束放宽为 `IN ('xiaohongshu','douyin','web')`），新装用户直接建新约束表。
  2. 新增 `_rebuildImportTasksTable` 作为 v12 迁移：SQLite 不支持 ALTER COLUMN 修改 CHECK 约束，采用「建临时表（新约束）→ 按 `PRAGMA table_info` 与白名单交集复制实际存在列（兼容 v9/v11 前缺 `additional_result_recipe_ids`/`progress_detail` 的旧库，缺失列由 DEFAULT/NULL 兜底）→ 删旧表 → 重命名 → 重建 3 个索引」的幂等迁移；`import_tasks` 无外键依赖，删除重建安全。
  3. 迁移测试 `app_database_v3_migration_test.dart` 新增「migrates v2 data to v12 and allows web platform import tasks」：迁移后 schema 版本为最新、旧 douyin 任务数据不丢失（含 `additional_result_recipe_ids` 默认值兜底），并经由 `SqliteImportTaskRepository.upsertTask` 真实路径写入 `source_platform=web` 任务再读取解析回 web。
- **等待项目负责人复测**：①首页「拍照选图」选图后不再报「导入任务暂时无法保存」，正常进入导入进度页；②「剪贴板」粘贴文本确认后同样正常创建任务；③粘贴普通网页链接（非小红书/抖音）创建任务正常；④升级安装（旧库迁移）后既有历史导入任务数据完好。

### 回收站/测试数据删除性能优化 + 导入完成后主界面刷新（PERF-003 延伸 / BACKUP-004/005）

- **项目负责人反馈**：①回收站的删除太慢；②删除测试数据也很慢；③导入完成后的加载（数据量突然变大）没有 UI 反馈，用户可能以为导入没有成功。
- **根因一（回收站清空/批量删除慢）**：`emptyRecipeTrash` 用 `listRecipes` 全量加载完整菜谱聚合（每条含食材/步骤/图片的 N+1 查询），再逐条 `permanentlyDeleteRecipe`（每条再次全量加载 + 独立事务提交）。回收站 2000 条时需数千次查询与事务。
- **根因二（删除测试数据慢）**：`ProfilePage._clearTestRecipes` 同样全量 `listRecipes()` + 逐条 `softDeleteRecipe` 独立事务，上千条测试菜谱时需上千次提交。
- **根因三（导入后无反馈）**：经排查首页/菜谱库加载期已有 `AppLoadingState` 加载态；真正问题是**从备份导入页返回后主界面从不刷新**（`BackupPage._openImport` 后未触发数据变更通知），用户回到主界面仍看到导入前旧数据，误以为导入失败。
- **修复**：
  1. `RecipeRepository` 新增 `permanentlyDeleteRecipesByIds`：单事务内按 500/批 `WHERE id IN (...)` 删除（SQLite 绑定变量上限 999），依赖 ON DELETE CASCADE 一并清除食材/步骤/图片/分类关系子表；`emptyRecipeTrash` 改走 `listTrashSummaries()` 轻量取 id + 批量删除，2000 条从数千次查询/事务降为 1 次总数查询 + 4 次 IN 删除（同一事务）。
  2. `RecipeRepository` 新增 `softDeleteRecipesByIds`：单事务内 `UPDATE ... SET deleted_at = ?, local_version = local_version + 1 WHERE id IN (...)` 分批软删除；`ProfilePage._clearTestRecipes` 改为 `listRecipeSummaries` keyset 分页收集匹配 id + 批量软删除。
  3. `BackupPage` 新增可选回调 `onDataChanged`：`_openImport` 从导入页返回后调用（刷新主界面/菜谱库/备份页统计）并重新加载预估；`ProfilePage._openBackupPage` 透传回调，导入完成返回后立即看到新数据。
- **新增测试**：
  - `sqlite_recipe_repository_test.dart`：「permanently deletes many recipes in one batch and cascades children」（520 条跨 500 批边界 + 完整子表级联清除验证）；「soft deletes many recipes in one batch across pagination boundary」（520 条软删除 + `listTrashSummaries` 确认全部进入回收站且删除时间一致）。
  - `backup_page_test.dart`：「从备份导入返回后触发 onDataChanged 并重新预估」（进入导入页 → 返回 → 断言 onDataChanged 调用 1 次 + estimateBackup 调用 2 次）。
- **验证**：sqlite_recipe_repository_test 11 项 + 备份模块回归（backup_page / recipe_trash_page / 导入导出集成 / recipe_library_use_cases）32 项全部通过（合计 43 项）；profile_page_test 的 3 项「databaseFactory not initialized」为既有测试基建缺失（缺 `sqfliteFfiInit` 初始化），与本次改动无关，属历史遗留。
- **等待项目负责人复测**：①回收站清空/批量删除大数量（如 2000 条）应秒级完成；②「我的」页清空性能测试菜谱应一次事务完成；③导入大备份后点「完成」返回主界面应立即看到新数据（不再停留旧数据）。

### 备份导入进度反馈增强（BACKUP-004/005）

- **项目负责人反馈**：①导入文件成功后（数据量大）要等一会才显示，加载期缺视觉反馈；②导入大量菜谱时进度一直是 0 然后突然成功，看不到反馈，用户会以为卡住。
- **根因**：`BackupImportProgress` 虽有 processed/total，但全部调用点都没传数（fraction 恒 0）；staging（解压/解析/媒体校验）、媒体复制、SQLite 写库均无逐条进度上报。
- **修复**：
  1. 领域接口新增进度回调：`BackupArchiveStageRequest.onProgress`、`BackupImportMediaWriter.stageMediaToCoverStorage.onProgress`、`BackupImportCommitRepository.applyImport.onProgress`。
  2. `DeviceBackupArchiveReader.stage` 按「菜谱记录 + 分类记录 + 媒体条目」总量逐条上报（预检页进度条实时前进）；`DeviceBackupImportMediaWriter` 按媒体引用数上报；`SqliteBackupImportRepository.applyImport` 按「分类 + 菜谱」逐条上报（写库阶段百分比持续推进）。
  3. `BackupImportUseCases` 桥接：预检 staging、执行 creatingRollback（桥接导出内部进度）/ preparingMedia / applying 各阶段均携带 processed/total。
  4. UI：`PixelProgressBar` 新增 `indeterminate` 参数（无总量阶段显示来回滑动动画，避免停在 0%）；导入页预检阶段卡片加进度条（staging 显示百分比、preflight 显示不确定动画），执行阶段无百分比时文案改为「处理中…」而非「0%」。
- **新增集成测试**：「导入进度逐步上报」——预检与替换执行收集 onProgress，断言存在中间进度（0<fraction<1）、最终到达 100%、同阶段内单调不减。
- **验证**：导入集成测试 6 项 + 备份模块全量回归（domain + 导出集成 + 导入集成 + 备份页）**24 项全部通过**；改动文件 IDE 诊断无问题。
- **等待项目负责人复测**：选择大备份 → 预检页应看到逐步前进的百分比；替换恢复时「创建回滚备份 → 准备图片 → 写入菜谱库」各阶段进度条持续推进，不再停在 0% 后突然完成。

### 备份导入「替换恢复大备份失败无提示、替换后全空」根因修复（BACKUP-004/005）

- **项目负责人复测反馈**：①新增 1 道菜谱→备份→删除→导入该备份，提示冲突→选「替换恢复」→提示完成（加载较慢，完成后仍停在加载页而非直接看到结果）；②替换恢复更早的一份大备份（两千多条，其中约两千条在回收站）时**没有提示完成直接回到了导入页**——用户不知道发生了什么。
- **根因一（替换后全空）**：`BackupImportUseCases._tryRestoreFromRollback` 把**已取消的导入 token** 传入恢复管线，恢复流程第一步（staging）`throwIfCancelled()` 立即中断 → 恢复必然失败 → 菜谱库停留在清库后的空状态。修复：恢复改用内部独立的新令牌 `restoreToken` 完成整个恢复流程。
- **根因二（两步式清库风险，治本）**：原替换流程 `clearLibrary()`（独立事务提交）→ 媒体准备 → `applyImport` 两步之间若进程被杀或失败（非异常捕获），库已空且无法自动恢复。修复：`applyImport` 新增 `clearExisting` 参数（替换模式），在**同一 SQLite 事务内先清空菜谱库范围再写入备份**，整体要么全部成功要么全部回滚。
- **根因三（失败无提示，用户以为"没完成/没反应"）**：审阅页 `_buildReviewing` **不渲染 `_error`**（只有选择文件页渲染），执行抛错回到审阅页后错误不可见。修复：审阅页新增 `if (_error != null)` 渲染 `AppErrorState`；取消/替换失败分别给引导文案（取消→"原数据已自动恢复，请检查菜谱库"；替换失败→提示可到备份目录找 `ai-recipe-rollback-*` 重新导入）。
- **UI 体验（用户建议"完成之后回到主界面就能看到结果，或给一点反馈"）**：执行成功后仍停留在完成摘要页（用户点「完成」返回主界面即见结果），失败/取消在审阅页直接显示错误与下一步指引，不再让用户猜状态。
- **新增集成测试**（`test/application/backup_import_integration_test.dart`，真实 SQLite + 真实 ZIP）：
  1. 「替换执行中取消（模拟中断）：单事务保证清库后、写入前失败时原库完整保留」——用 `_SelfCancellingToken`（第 N 次检查自我取消）确定性模拟事务中途取消，断言抛 `BackupOperationCancelledException` 且原库 1 正 + 1 回收站 + 2 分类 + 封面/画廊文件全部保留。
  2. 「替换导入取消安全：executeImport 收到取消令牌时原库不受影响」。
  3. 既有「替换恢复（大数据）：120 道菜谱含回收站 + 图片，替换后全部真实落库」（复现用户两千条规模，断言 60 正 + 60 回收站 + 封面落盘）。
- **验证**：导入集成测试 5 项全部通过；备份模块全量回归（domain + 导出集成 + 导入集成 + 备份页）**23 项全部通过**。
- **下一步**：请项目负责人用那份 2000+ 条备份重新执行「替换恢复」——现在若再失败，审阅页会直接显示具体失败原因（带回错误码即可精确定位）；若为内存/超时类问题，再评估分批写入等方案。

### 备份导入「替换后全空」调查与合并预检跳过 bug 修复（BACKUP-004）

- 项目负责人反馈：替换恢复导入后菜谱库/首页/回收站全部为空，但预览「新增 > 0」、完成页「写入 > 0」。
- 新增真实 SQLite + 真实 ZIP 集成测试 `test/application/backup_import_integration_test.dart`（`sqfliteFfiInit` + `databaseFactoryFfi` + `AppDatabase(databasePath:)` + 真实 `DeviceBackupArchiveReader/Writer`）：
  1. 「替换恢复」用例：seed（1 空分类 + 1 正式菜谱含封面/2 图/食材/步骤/分类 + 1 软删除菜谱）→ 创建备份 → `clearLibrary` → 替换导入 → 通过 `SqliteRecipeRepository` 读取：正式列表 1 道、回收站 1 道、分类 2 个、完整菜谱食材/步骤/图片落盘/分类关系全部还原。**通过**——证明「写入后读取」链路真实落库可读，替换模式本身在代码层面无问题。
  2. 「合并导入」用例：seed 后创建备份，当前库与备份完全一致。**复现 bug**：`previewImport` 预检计划正确（`addRecipes=0, skipRecipes=2`），但 `executeImport` 返回 `writtenRecipes=2`。
- **根因**：`BackupImportUseCases._resolveMergeRecords` 只按 `plan.conflicts` 决定写入；预检中「同 UUID 同内容 → skip」的记录**不产生 conflict**，执行阶段 `conflict == null` 被当真新增写入（`_upsert` 同 ID 覆盖写，数据不丢但计数错误、语义错误）。
- **修复**：
  - `domain/backup/backup_import_plan.dart`：`BackupImportPlan` 新增 `skippedRecipeIds`/`skippedCategoryIds`（默认空列表，`copyWith` 原样保留）。
  - `application/backup/backup_import_use_cases.dart`：`_buildPlan` 对同内容跳过记录收集 ID 并传入计划；`_resolveMergeRecords` 分类/菜谱循环先跳过 `plan.skipped*Ids` 再处理冲突，其余分支不变（keepCurrent/useBackup/keepBoth/真新增语义保持）。
- 修复后集成测试 2 项全部通过（含新增断言 `writtenRecipes=0`、`writtenCategories=0`、`skippedRecipeIds` 内容）；备份模块回归（导入/导出集成 + 备份页）**10 项全部通过**。
- **「替换后全空」尚未在代码中复现**：已排查读取层（`SqliteRecipeRepository` 列表无 userId 过滤、仅 `deleted_at IS NULL`）、数据库实例（组合根共享单 `ownedDatabase`）、UI/backend 透传（`backup_import_page.dart` → Facade → use cases 无附加处理）、替换失败路径（会回滚媒体并尽力从回滚备份恢复且 UI 报错，与「显示写入成功」矛盾）。最可能剩余差异是备份文件本身数据或用户设备环境，等待项目负责人回传：①创建备份成功摘要的菜谱数量；②是否同一台设备导入；③改用「合并导入」的预览/完成数字。

### 备份「另存为」出口（ADR-0036）

- 项目负责人反馈"备份可以创建了但不知道保存在哪"。备份默认落在应用私有文档目录（Android 普通文件管理器不可见）。
- `backup_page.dart`：「上次备份已创建」区域新增「另存为（导出到其他位置）」按钮，调用 file_picker `saveFile`（Android 走 SAF）把备份写入用户选择位置（如下载）；成功提示「备份已另存到：<路径>」、用户取消不提示、复制失败提示「另存失败，请重试。」；成功摘要展示文件名、体积与完整文件路径。
- `BackupPage` 新增可注入参数（默认行为不变）：`saveBackupFile`（另存为回调，默认 file_picker 实现）、`estimateBackup`（预估回调，默认走 backend 真实预估）、`initialResult`（最近备份结果展示）；上次备份结果区域移到 ListView 底部，独立于预估状态始终展示。
- 复用导入侧 file_picker，无新增依赖。
- 新增 `test/features/backup_page_test.dart` 4 项（成功复制/取消/失败/无结果态，注入 fake 回调）全部通过；备份回归 14 项通过；`flutter analyze` 改动文件无问题。
- **2026-08-07 修复「另存失败」**（项目负责人真机反馈）：根因是 file_picker 8.x 在 Android/iOS 上 `saveFile` 必须传 `bytes` 参数（插件只把传入的 bytes 写入用户所选文件；不传则 Dart 端直接抛 ArgumentError）。修复：`_defaultSaveBackupFile` 改传 `File(sourcePath).readAsBytes()`（移除错误的 `File.copy` 到伪路径）；另因 Android 返回路径是拼接的 `Downloads/<文件名>` 伪路径，Android 上提示改为「备份已保存到所选位置」，其余平台仍显示完整路径。已知限制：bytes 经平台通道整体传输，超大备份（数百 MB）存在传输上限，归 BACKUP-006。
- 等待项目负责人真机确认：创建备份 → 另存为到「下载」→ 系统文件管理器可见该 `.airecipe-backup` 文件。

### 归档复核失败修复（BACKUP-002/003）与回收站加载性能优化（PERF-003）

- **归档复核失败修复**：项目负责人真机创建备份提示「归档复核失败：清单内容不一致」，三个根因已修复：
  1. Dart `List` 未重写 `==`，复核用 List 身份比较 manifest 记录与重读记录恒不等 → `device_backup_archive_writer.dart` 复核改逐字节 `_bytesEqual` 比较。
  2. `expectedCount` 在循环中重复累计 datasets 次数 → 改为 `requiredEntries.length + mediaFiles.length` 只计一次。
  3. `hashedMedia` 按 path 去重导致同内容不同路径媒体被重复归档且清单计数不符 → `backup_export_use_cases.dart` 改 `uniqueMediaBySha` 按 sha256 内容去重（manifest `media.count`/`mediaFiles`/`_buildStatistics` 均用 unique）。
  另将 `backup_archive_constants.dart` 的 `mediaEntryPath` 升级为严格 64 位十六进制校验。
  回归验证：备份领域 + 集成测试（含新增复核/去重用例）**33 项全部通过**；`flutter analyze --no-pub` 本轮改动文件无任何问题。
- **回收站加载性能优化**：项目负责人反馈「回收站加载的太慢了」。根因是回收站页原用 `listRecipes` 全量加载每条菜谱（含食材/步骤/图片，N+1 次查询）。已实施：
  - 领域新增轻量只读模型 `TrashRecipeSummary`（id/title/deletedAt）；`RecipeRepository` 接口新增 `listTrashSummaries()`。
  - `SqliteRecipeRepository` 单条 SQL（`WHERE r.deleted_at IS NOT NULL ORDER BY r.deleted_at DESC, r.id DESC`，只选三列）替代逐条全量加载；UseCase/Facade 透传；`RecipeTrashPage` 改为轻量摘要并显示删除时间；fake 仓库补实现。
  - `PixelFloat` 增加系统减少动态支持（`MediaQuery.disableAnimationsOf` 时停 ticker 直接返回静态子组件，遵循 UI-002「减少动态直达终态」，也避免无限动画让 widget 测试 `pumpAndSettle` 永不结束）。
  - 测试基建补齐：trash 页 Widget 测试需 `sqfliteFfiInit()+databaseFactory=databaseFactoryFfi`（组合根建 AppDatabase）、`SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()`（`DeviceMultimodalLlmConfigRepository` 硬编码构造）、`accessibilityFeaturesTestValue = FakeAccessibilityFeatures(disableAnimations: true)`；`shared_preferences_platform_interface` 加入 dev_dependencies。
  - 验证：trash 页 3 项 + 菜谱库用例/集成共 **19 项全部通过**；`flutter analyze --no-pub` 本轮改动 15 个文件无新增问题（70 个既有 issue 全为历史遗留）。
- 两个修复均等待项目负责人实机复测（创建备份不再报归档复核失败；回收站加载不再卡顿）。

### BACKUP-004/005：备份导入（预检、合并、冲突）与替换恢复/回滚实现

- **交付范围**：完成 `.airecipe-backup` 导入半边（BACKUP-004 + BACKUP-005 执行部分），与既有导出构成完整创建/恢复链路。等待项目负责人按 `tests/acceptance/BACKUP-004-backup-import-2026-08-07.md` 验收。
- **领域契约**（`lib/domain/backup/`）：
  - `backup_import_plan.dart`：`BackupImportMode{merge,replace}`、`BackupConflictKind{sameIdDifferentContent,categoryIdMismatch,possibleDuplicate,missingMedia,currentMediaMissing}`、`BackupConflictResolution{keepCurrent,useBackup,keepBoth}`、`BackupImportConflict`（含 `copyWith`）、`BackupReplaceImpact`（替换删除影响预览）、`BackupImportPlan`（新增/跳过/可能重复/冲突/缺失媒体/媒体体积/兼容性/copyWith）、`BackupImportPayload`。
  - `backup_import_repository.dart`：`BackupImportPreflightRepository`（只读哈希/摘要）、`BackupImportCommitRepository`（applyImport 单事务/clearLibrary/removeOrphanedCoverFiles）、`BackupImportMediaWriter`（媒体落盘/回滚）、`BackupStagedArchive`/`BackupMediaStagedEntry`。
  - `backup_record_hashing.dart`：规范化内容哈希——排除图片设备路径、updatedAt、localVersion，保留 createdAt/deletedAt；`canonicalRecipeHashFromDomain` 使当前库与备份记录可比。
- **数据层**（`lib/data/backup/`）：`device_backup_archive_reader.dart`（ZIP 安全校验：Zip Slip/Bomb/重复路径/非法路径/大小上限 + Manifest 版本兼容 + 逐行 Schema + 媒体 SHA-256 校验；`cleanupSession` 真删会话目录、`cleanupAbandonedSessions` 扫除遗留）；`device_backup_import_media_writer.dart`（staging 媒体复制到菜谱封面存储、失败回滚）；`sqlite_backup_import_repository.dart`（预检只读 + 单事务 applyImport + clearLibrary + 孤儿封面清理）。
- **应用层**（`lib/application/backup/backup_import_use_cases.dart`）：`BackupImportStage{staging,preflight,creatingRollback,preparingMedia,applying,finalizing}`、`previewImport`（staging→预检→ImportPlan，全程只读，失败清理 staging）、`resolveConflict`/`resolveAllConflicts`（纯函数）、`discardPreview`、`executeImport`（合并：keepCurrent/useBackup/keepBoth + 分类/菜谱 ID 映射重写；替换：强制创建并验证 `ai-recipe-rollback-<UTC 时间戳>` 回滚备份→事务清库→写入→孤儿清理，失败回滚媒体并尽力从回滚备份恢复）、`cleanupAbandonedSessions`；预检会话驻留内存、执行后移除。
- **接线**：Facade 新增 `previewBackupImport`/`resolveImportConflict`/`resolveAllImportConflicts`/`discardImportPreview`/`executeBackupImport`/`cleanupAbandonedImportSessions`，复用 `_backupOperation` 稳定错误映射；组合根注入 `DeviceBackupArchiveReader`/`SqliteBackupImportRepository`/`DeviceBackupImportMediaWriter`，staging 默认 `documents/backup-import/`。
- **UI**（`lib/features/backup/backup_import_page.dart` 新文件 + `backup_page.dart` 入口）：备份页「从备份导入」按钮（`openImportButton`）→ 选择文件（`file_picker` 仅 `.airecipe-backup`）→ 预检加载 → 计划审阅（统计卡/合并替换切换/替换范围预览/冲突三态 `PixelSeg`/执行按钮）→ 执行进度（阶段文案+单调进度条+取消）→ 完成摘要（写入/跳过/媒体 + 替换模式回滚备份路径）；不兼容计划禁用执行；替换前 `showPixelConfirm` 二次确认；执行中返回键禁用；页面销毁自动放弃预检会话。
- **依赖**：`file_picker ^3.0.4`（受 SDK 约束的可用版本）。
- **测试代码**：已存在 `test/domain/backup_manifest_records_test.dart`、`test/application/backup_export_integration_test.dart`（未运行，ADR-0015）；导入侧测试未新增（验收以手动为主）。
- 全项目 IDE 诊断无错误（`flutter analyze` 备份相关目录与全 lib 无 error）；未运行测试/构建/真机（ADR-0015）；`BACKUP-004`/`BACKUP-005` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/BACKUP-004-backup-import-2026-08-07.md` 验收。回滚备份保留期限与跨平台规模验收归 `BACKUP-006`（TODO）。

### 构建环境修复：file_picker 升级 + C:\AIM junction + sqlite3 代理下载

- **问题**：`flutter build apk --debug` 在真实项目路径连续失败：
  1. `file_picker 3.0.4`（2020 年）Android 模块无 `namespace`，与项目 AGP 8.11.1 不兼容 → `LibraryVariantBuilderImpl: Namespace not specified`。
  2. `sqlite3 3.5.0` 的 native assets hook 从 `github.com` 下载预编译库，本机无法直连 GitHub（超时）→ `Building assets for package:sqlite3 failed`。
  3. Flutter shader 编译器 `impellerc` 无法写入含中文的路径（`E:\AI\ai食谱\...`）→ `ShaderCompilerException: Could not write file to ...shaders/ink_sparkle.frag`（手动复现确认：英文路径成功、中文路径失败）。
- **修复**：
  1. `file_picker` 升级 `^3.0.4` → `^8.3.0`（解析 8.3.7，自带 `namespace 'com.mr.flutter.plugin.filepicker'`、compileSdk 34、minSdk 21，AGP 8 兼容）。
  2. 发现本机代理 `127.0.0.1:7897`（clash），构建时设置 `HTTP_PROXY`/`HTTPS_PROXY` 使 sqlite3 hook 成功下载并缓存到 `build/`。
  3. 创建持久目录联接 `C:\AIM` → `E:\AI\ai食谱\code\apps\mobile`，flutter 命令一律在 `C:\AIM` 下运行以绕开中文路径。
- **连带修正**：`backup_import_page.dart` 的 `_pickFile` 原用 `FileType.custom + allowedExtensions: ['airecipe-backup']`，该扩展名在 Android 上无法映射 MIME（`FileUtils.getMimeTypes` 返回空数组即报 "Unsupported filter"），已改为 `FileType.any` + 选择后自行校验 `.airecipe-backup` 扩展名（大小写不敏感），非备份文件提示「请选择 .airecipe-backup 备份文件。」。
- **验证**：`cd C:\AIM`（代理已设置）`flutter build apk --debug` 成功产出 `build/app/outputs/flutter-apk/app-debug.apk`；`flutter analyze --no-pub lib\features\backup` 无问题。构建环境说明已写入 `tests/acceptance/BACKUP-004-backup-import-2026-08-07.md` 第 2.1 节。项目负责人后续在 `C:\AIM` 下执行 flutter 命令即可（首次 clean 后需代理）。

## 2026-08-06

### BACKUP-002/003：备份格式核心与创建全量备份导出实现

- **实现范围**：完成 `.airecipe-backup`（标准 ZIP）导出的完整链路，含格式核心契约、一致性快照、媒体 SHA-256 去重归档写入、导出用例、Facade/组合根接线、UI 与测试代码。
- **领域契约**（`lib/domain/backup/`）：`backup_archive_constants.dart`（`backupFormatName='airecipe-backup'`、`backupFormatVersion=1`、`backupMinimumReaderVersion=1`、`BackupArchivePaths` 内容寻址路径、`BackupDatasetName`；容器 formatVersion / Dataset schemaVersion / SQLite schemaVersion 三套独立版本，注释阐明 minimumReaderVersion 与 formatVersion 关系）；`backup_errors.dart`（`BackupErrorCode` 9 类：cancelled/mediaMissing/mediaUnreadable/mediaHashMismatch/dataValidationFailed/archiveWriteFailed/archiveVerificationFailed/formatNotSupported/internalError，`BackupException` 带 retryable）；`backup_cancellation_token.dart`（检查点 `throwIfCancelled`）；`backup_manifest.dart`（严格解析，未知 dataset/未来版本拒绝 → `formatNotSupported`）；`backup_records.dart`（`RecipeBackupRecord`/`CategoryBackupRecord` NDJSON 编码，可空枚举 `_nullableWireEnum`）；`backup_repository.dart`（`BackupSnapshotRepository`/`BackupArchiveWriter` 接口、`BackupMediaRole{cover,gallery,categoryCover}`）。
- **数据层**（`lib/data/backup/`）：`sqlite_backup_snapshot_repository.dart` 单事务加载全部菜谱（含软删除）/分类/图片/关系/食材/步骤；`device_backup_archive_writer.dart` 用 `Isolate.run` 组装 ZIP（不阻塞 UI），`.partial` 写入 → 重读复核（必需条目、dataset 哈希对比 manifest、媒体哈希验证、多余条目计数）→ 原子重命名；失败 `_cleanupBestEffort` 清理半成品；FileSystemException → `archiveWriteFailed`。
- **应用层**（`lib/application/backup/backup_export_use_cases.dart`）：`BackupEstimate`（菜谱/分类/空分类/媒体数/媒体字节/预估总字节）、`BackupExportStage{snapshot,hashing,writing,verifying}`、`BackupExportProgress`、`BackupExportResult`；`createFullBackup` 走一致性快照 → 预估 → 媒体哈希校验 → NDJSON 流式写入 → SHA-256 去重 → manifest → 重读复核 → 原子发布；媒体缺失/不可读/哈希不一致抛对应 `BackupException`；文件名 `ai-recipe-<UTC 时间戳>.airecipe-backup`；取消通过 token 在检查点抛出 `BackupOperationCancelledException`。
- **接线**：`AiRecipeBackendFacade` 新增 `estimateBackup()`/`createFullBackup({cancellationToken,onProgress})`，`BackupException` 映射为 `backupFailed`/`backupCancelled`/`storageUnavailable`；`AiRecipeBackendCompositionRoot` 组装 `BackupExportUseCases`，输出目录默认应用文档目录 `backups/`（`_defaultBackupOutputDirectory`，可注入替换）。
- **UI**（`lib/features/backup/backup_page.dart` + `profile_page.dart` 入口）：「我的 → 数据与存储 → 创建全量备份」；默认/空/加载/进度（阶段文案 + 单调进度条 + 取消）/成功摘要/错误重试/取消清理状态全覆盖；确认弹窗（showPixelConfirm）提示菜谱数/图片数/预估体积；执行中返回键禁用；页面销毁时自动取消进行中备份。
- **测试代码**（未运行，ADR-0015）：`test/domain/backup_manifest_records_test.dart`（manifest 严格解析、内容寻址路径、record roundtrip）；`test/application/backup_export_integration_test.dart`（真实 FFI SQLite 端到端：归档内容/去重/原子发布、媒体缺失失败清理、创建前取消、幂等两次）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；`BACKUP-002`/`BACKUP-003` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/BACKUP-002-full-backup-export-2026-08-06.md` 验收。导入（BACKUP-004）、替换/回滚（BACKUP-005）、跨平台规模（BACKUP-006）未开始。

### BACKUP-002/003 编译错误修复（2026-08-07）

项目负责人 `flutter run` 首次编译失败，IDE 诊断未覆盖到这些文件。已修复并验证：

- `backup_export_use_cases.dart`：`_HashedMedia` 缺少 `sourcePath` 字段（`_mediaFilesToWrite` 需要）——已补字段与构造参数。
- `device_backup_archive_writer.dart`：`ZipFileEncoder` 未导入（实际位于 `package:archive/archive_io.dart`）；且 archive 4.0.9 无 `addFileBytes`，`addFile` 的归档内文件名是位置参数而非 `filename` 命名参数——改为 `addArchiveFile(ArchiveFile.bytes(...))` 写内存字节、`addFile(source, entryPath)` 写磁盘媒体。
- `backup_manifest.dart`：`throw const BackupException(..., '...${dataset.name}...')` const 列表内不允许字符串插值——去掉 `const`。
- `backup_records.dart`：`_ingredientToJson` 中块体 collection-if（`if (c) { 'k': v }`）编译器不支持，改为单元素形式（与同文件 422 行一致）；`IngredientImportance.fromWireName` 只接受非空 `String`——缺失/非字符串时回退 `IngredientImportance.required`。
- `backup_page.dart`：进度弹窗错误按钮误调用父页面 `_loadEstimate`——改为 `onRetryEstimate` 回调传入；并修复 `_creating` 从未置 `true` 的隐藏问题（创建期间按钮禁用、对话框结束后复位）。
- `pubspec.yaml`：`archive` 由传递依赖提升为直接依赖 `^4.0.9`（消除 `depend_on_referenced_packages`），`flutter pub get` 成功。
- 顺带清理：`sqlite_backup_snapshot_repository.dart` 无用 `sqflite` import、`_backupFileName` 文档注释尖括号误判 HTML。
- 验证：`flutter analyze lib/domain/backup lib/data/backup lib/application/backup lib/features/backup` 无任何问题；`flutter analyze lib` 无 error（仅既有文件的历史 warning/info，与备份无关）。Codex 未执行测试/构建/真机（ADR-0015）。

### BACKUP-002/003 运行时异常修复（2026-08-07）

项目负责人真机复现「数据与存储」页加载完成后整页空白，终端报 RenderFlex 高度无界异常。根因与修复：

- [pixel_ui.dart](PixelStatCard)：组件内部固定返回 `Expanded`（水平弹性），但当它被单独放进 Column（ListView 内，纵向高度无界）时，`Expanded` 成为垂直 flex 触发 `RenderFlex children have non-zero flex but incoming height constraints are unbounded`，导致备份页 build 失败整页空白。修复：新增 `expand` 参数（默认 true 保持 Row 内用法兼容），单独使用时传 `expand: false`。
- [backup_page.dart]：单独的「预估备份体积」统计卡传 `expand: false`；同时预估失败/未知状态下「创建全量备份」按钮仍始终可见（创建不依赖预估）。
- [backup_export_use_cases.dart]：`estimate()` 容忍缺失/不可读媒体（按 0 体积计入），预估不再因脏图片路径失败卡进错误态；创建备份时才严格校验失败（符合验收 4.4）。
- 终端同时出现 `multiple heroes share the same tag` 异常：全项目无 Flutter `Hero(` widget，判定来自框架/其他导航场景，非本页致命异常，待真机复测观察。
- 验证：`flutter analyze` 备份相关目录与 pixel_ui 无问题（fridge 目录 9 条警告均为历史遗留）。

### BACKUP-001：全量菜谱备份与恢复方案

- 新增 `docs/architecture/RECIPE_BACKUP_RESTORE.md`，确定 `.airecipe-backup` 标准 ZIP 容器、Manifest、版本化 NDJSON Dataset、SHA-256 内容寻址媒体、Dataset Adapter 和 Migration Registry；不直接复制 SQLite，也不使用巨型 JSON + Base64 图片。
- 明确每次备份全量覆盖正式、草稿、归档、回收站全部菜谱及分类、关系、食材、步骤、标签、收藏、时间/版本/软删除和菜谱图片；库存、购物清单、制作记录、运行中任务/计时器、设置、密钥、模型和缓存不在首版范围。
- 新增默认合并、UUID 冲突不静默覆盖、高级替换前强制回滚备份、staging 安全预检、ImportPlan、两阶段提交、失败清理和未来版本兼容规则。
- 新增 `design/flows/RECIPE_BACKUP_RESTORE_FLOW.md`、US-014、ADR-0034、R-020 和方案走查文件；同步产品需求、文档索引、任务、当前进度和风险。
- 本轮只写方案，没有编写业务代码；未执行自动测试、静态分析、构建、模拟器、真机或真实备份恢复。`BACKUP-001` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/BACKUP-001-recipe-backup-restore-plan-2026-08-06.md` 走查。

### 未完成导入列表支持长按多选删除与全选（并入 IMPORT-009）

- **需求**：用户反馈"未完成的导入要可以长按多选，然后删除，进入选择后有一个全选按钮"。
- **实现**（`import_tasks_page.dart`）：①长按任意任务进入选择模式并选中该项；②选择模式下点按切换选中，全部取消自动退出；③顶部"已选择 N 项"+"全选/取消全选"（全选选中列表全部，取消全选退出选择模式）+ "取消"按钮；④底部浮出批量操作栏"删除所选 (N)"（二次确认，复用 Facade `deleteImportTasks` 批量删除）；⑤选择模式下隐藏单个取消/删除按钮，选中项深绿描边 + 勾选标记（`_SelectionMark`）；⑥底部预留空间避免操作栏遮挡最后一项。
- **放宽删除范围（用户追加需求）**：所有未完成状态（排队/解析中/待确认/失败/已取消）均可删除；`deleteImportTask` 对进行中/待确认任务先走取消流程（中断后台解析），再清理任务关联的全部草稿（主草稿 + 附加草稿，`allResultRecipeIds`，防孤儿草稿），最后永久删除任务记录；批量删除确认弹窗对进行中/待确认任务提示"其中 X 条正在进行或待确认：删除将中断解析并移除已生成的 AI 草稿"，批量操作栏提示"进行中/待确认任务将一并终止"。
- **测试定义**（未运行，ADR-0015）：`import_tasks_page_test.dart` 新增 7 项——长按进入选择模式并选中、点按切换与空选退出、全选/取消全选退出、批量删除已结束任务、批量删除含进行中任务（弹窗提示后果后全部删除）、取消按钮退出选择模式。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；验收方法已补入 `tests/acceptance/IMPORT-009-import-experience-2026-08-03.md`，待项目负责人复测。

### 全项目弹窗风格统一（并入 IMPORT-009 复测项）

- **需求**：用户反馈"弹窗的风格没统一，请调整，其他的弹窗也要统一风格"。
- **方案**：新建共享像素风弹窗组件 `lib/shared/widgets/pixel_dialogs.dart`（`PixelConfirmDialog` 确认弹窗 / `PixelInfoDialog` 信息弹窗 + `showPixelConfirm`/`showPixelInfo` 弹出函数），统一采用基准样式：透明 Dialog + `PixelSurface`（`PixelCut.lg` 切角、`elevation 2`、card 底、墨色 1.5px 描边、16 padding）+ 标题 15px/w900/letterSpacing 1 + 正文 12px/ink2/height 1.55 + 右对齐像素按钮。
- **收敛范围**：①清除全部原生 `AlertDialog`（导入进度/任务列表、回收站、隐私、OCR 设置、草稿确认、菜谱详情/编辑、冰箱批量操作、烹饪模式退出/完成等 12 处）；②删除三个本地重复确认类 `_PixelConfirmDialog`（import_progress_page）、`_LibraryConfirmDialog`（recipe_library_page）、`_DevConfirmDialog`（profile_page），统一改为共享组件；③`recipe_edit_page` 内联"未保存修改"弹窗由旧样式（cut 10/elevation 8/无描边/18px 标题/全宽按钮）对齐基准（lg 切角/墨色描边/15px 标题/右对齐按钮），保留两个测试 Key。
- 保留不动的特殊弹窗（本身已是像素容器且有专门交互）：多草稿选择弹窗 `_MultiDraftPickerDialog`、测试数据进度弹窗 `_GenerateTestDataDialog`、分类输入弹窗 `create_category_dialog`、剪贴板文本输入弹窗 `_PasteTextDialog`（基准样式来源）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；随 IMPORT-009 一起由项目负责人复测弹窗观感与交互。

### 修复：多草稿并发生成偶发“导入失败·不可重试”（IMAGE-002 / IMPORT-010）

- **现象**：3 图导入日志显示分组 `groups=0|1|2 草稿数=3`、第一份草稿生成成功
  （Generate 46188ms）后，整单失败并提示"The import failed unexpectedly.尝试
  1/3·不可重试"。
- **根因**：`_generateDraftsConcurrently`（并发窗口 2）中两个组的 `onProgress`
  并发执行 `_advance`（load→advance→save 非原子）。SQLite 乐观锁
  （`expectedLocalVersion`）在"组 0 与组 1 的 0.65 上报"并发写同一任务时，后写者
  抛 `ImportTaskWriteConflictException`（或进度交错回退抛
  `ImportTaskTransitionException`），被 `_processStartedTask` 的 catch-all 吞成
  `unknown` + 不可重试。日志只有一条 Generate 是因为失败发生在 t0 上报时刻，
  46s 后打印的是仍在飞的 LLM 请求补打日志。
- **修复（两层）**：①处理器源头——`multi_image_draft_split_processor.dart` 的
  `_generateDraftsConcurrently` 增加 `reportChain` 串行队列，所有进度上报严格
  串行执行（单次失败不阻断后续、错误仍传播给调用方），从源头消除并发写；
  ②runner 防御——`import_task_runner.dart` 的 `_advance` 对写冲突/进度倒退做
  有限重试（`_progressWriteRetries=3`），每次基于最新已保存进度取 `max` 兜底，
  保证保存值单调不减；任务已取消时优雅返回取消结果；非并发引起的非法转移仍
  原样抛出。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；待项目负责人复测
  （多草稿并发导入不再失败）。

### 解析过程实时显示当前操作详情（IMPORT-010，进度详情全链路）

- **需求**：用户反馈"在解析的时候也要同步当前的信息——获取到了文案、几张图片、是
  单个草稿还是多个草稿的、正在弄成草稿的叫什么"。
- **领域模型**：`ImportTask` 新增只读展示字段 `progressDetail`（可选文本）；`advance`
  增加可选 `progressDetail` 参数，支持"进度/阶段不变、仅详情变化"时生成新版本
  （不触发进度倒退校验）；`_copy` 用哨兵 `_notProvided` 区分"不传=保留"与"传 null=
  清空"；`startWithFallback`/`fail`/`cancel`/`retry`/`recoverAfterRestart` 清空详情，
  `markNeedsReview`/`reassignResultRecipe`/`complete` 保留最后一次详情。
- **链路透传**：`ImportPipelineProgressCallback` 增加可选位置参数 `[String? detail]`
  （**注意**：Dart 要求回调"重实现处"声明为三位置参数且第三个可选 `[detail]`；两参/三参
  **调用处**均可省略；lib 3 处与 test 6 文件共 29 处已同步调整）；`AdvanceImportTask`、
  runner `_advance`/onProgress 透传 detail；SQLite schema v11 新增
  `import_tasks.progress_detail` 列（幂等迁移），仓库读写同步。
- **处理器上报**：多模态识别"正在识别 N 张图片中的文字/第 x/N 张图片"；多图分组
  "正在分析 N 张图片是否为同一道菜"→"识别为 N 份独立菜谱，正在生成草稿"→生成中
  "正在生成第 x/N 份菜谱草稿"/"第 x/N 份草稿已生成"→"全部草稿已生成，正在收尾"；
  结构化生成"正在整理识别到的内容，生成菜谱草稿"→"AI 已返回草稿，正在校验菜谱
  格式"→"草稿《标题》已生成，正在保存"。
- **UI**：进度页运行中提示行改动态显示 `progressDetail`（无详情时回退原静态文案）。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；待项目负责人复测。

### 多图分组与“最后识别超时”诊断（并入 IMPORT-008 / IMAGE-002）

- **分组已修正**：真机日志 `分组结果 groups=0 | 1 | 2 图数=3 草稿数=3` 确认 LLM
  已正确判定 3 张图为 independent；此前 `groups=0,2,3 草稿数=1` 是 LLM 倾向合并
  所致，已在 `MultiImageDraftSplitProcessor` 增强分组 prompt（逐图检查菜名+配料+
  步骤完整性、仅明显同一道菜分段才合并），并新增 `分组判断原始响应` 日志。
- **“最后识别超时”诊断插桩**：在多模态单图识别（`[AIRecipe][Recognize] 单图识别
  耗时=..ms order=.. uploadBytes=..`）与最终结构化生成
  （`[AIRecipe][Generate] 最终结构化生成耗时=..ms sourceChars=.. reasoningMode=..`
  / 失败 kind 与耗时）两处输出耗时日志，用于定位超时发生在转录还是生成阶段。
- 待项目负责人重新构建 Android，复现一次多图导入并回传含 `Recognize`/`Generate`
  的完整日志。

### WebView 修复：SPA 客户端路由被误判为"页面加载失败"（并入 IMPORT-008）

- **问题**：真机日志显示小红书在进入 EXTRACTING 后，SPA 用 `history.pushState` 跳到
  规范化路径 `item/xxx`（相对 URL，无 scheme），WebView 触发主框架
  `onReceivedError ERROR_UNSUPPORTED_SCHEME(-10)`，被当成致命网络错误 `abort`
  成"页面加载失败"，尽管正文已就绪（probe 显示 img=39/hasContent=true）。
- **修复**：①`onReceivedError`（两版本）仅在 **NAVIGATING** 阶段对主框架错误中止；
  WAITING_CONTENT/EXTRACTING 阶段的主框架导航错误视为 SPA 路由噪音忽略，由提取
  脚本判定内容；②`onPageStarted` 仅在 NAVIGATING 阶段递增 `navigationGeneration`，
  避免 SPA 客户端路由把已发出的探测/提取回调作废导致误判。
- 待项目负责人重新构建 Android 复测小红书/抖音链接导入。

### WebView 内容就绪与平台提取 + 可观测性（《解决方案.md》第二/三阶段，ADR-0033，并入 IMPORT-008）

- **平台 readiness 分流**：`probeContent` 改用 `probeScript(platform, targetId)`，
  新增小红书/抖音/通用三套探测脚本（`PROBE_SCRIPT_XHS/DOUYIN/GENERIC`），返回
  `ready/readyReason/fingerprint/risk/login/gone/targetIdMatch`；小红书命中
  `__INITIAL_STATE__` 或有效正文 DOM、抖音命中 `__RENDER_DATA__`/RENDER_DATA、
  通用优先主正文候选/JSON-LD/正文达标；探测由"有文字即稳定"改为按平台 ready 决策。
- **平台特化提取（ContentExtractor）**：新增 `EXTRACT_SCRIPT_DOUYIN`（解析
  `__RENDER_DATA__` 的 `videoInfoRes.item_list[0]`/`awemeDetail`/`aweme_list[0]`
  标题/描述/作者/封面，回退 DOM/meta）；`EXTRACT_SCRIPT_GENERIC` 优先 JSON-LD
  Recipe/Article（headline/description/recipeIngredient/recipeInstructions/
  articleBody），回退主正文候选再整页文本；小红书/通用/抖音均输出 `fingerprint`。
- **ResultValidator**：`validateResult` 无有效文本且命中登录/验证/删除标记时归为
  `loginWall/verification/gone`，回填 `bodyLength`/`bodyFingerprint`。
- **正文与图片彻底解耦（P0-8 收尾）**：图片阶段 `onReceivedSslError` 与
  `onRenderProcessGone` 只结束配图抓取（`onCurrentImageFailed`/`finishImages`），
  不使已成功正文整单失败；`onReceivedHttpError` 记录主框架 `httpStatusCode`。
- **可观测性（第三阶段）**：`RequestContext` 增加 `redirectCount`/`finalHostPathHash`/
  `httpStatusCode`/`readinessReason`/`bodyFingerprint`/`bodyLength`/`imageAttempted`/
  `imageSucceeded`/`imageFailed`/`imageFailureReasons`/`rendererGoneCount`/
  `finalErrorClassification`/`stageStartedAt`；请求结束输出一行
  `OBS req=.. platform=.. stage=..ms redirect=.. http=.. readiness=.. fp=..
  bodyLen=.. imgAttempt/Ok/Fail=.. imgFailReasons=.. rendererGone=.. final=.. totalMs=..`。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按
  `tests/acceptance/IMPORT-008-webview-readiness-observability-2026-08-06.md`
  Android 真机复测。

### WebView 抓取生命周期与竞态加固（《解决方案.md》第一阶段，ADR-0032，并入 IMPORT-008）

按《解决方案.md》针对 WebView 抓取不稳定实施第一阶段（生命周期与竞态）：

- **RequestContext 请求隔离**：`WebViewFetchMethodHandler.kt` 引入 `RequestContext` 承载每次抓取独立状态；所有异步入口（WebView 回调、evaluateJavascript 回调、Handler 延迟任务、图片写盘 worker）在回调开始处统一校验 `ctx === activeRequest && !ctx.cancelled`；`navigationGeneration`（每次主框架导航递增）/`imageGeneration`（每张图片递增）双代次使旧导航/旧图片迟到回调一律丢弃。
- **新请求正确终止旧请求**：`handleFetchPage` 启动新请求前对旧请求 `terminate(old,"superseded")`（标记取消、取消计时器、stopLoading、清理专属目录、完成旧 result，不显示"网页超时"）。
- **原生取消 API**：通道新增 `cancelFetch`；Dart `WebViewContentFetcher` 增加 `cancel()`，`WebViewImportContentAdapter` 在导入取消令牌触发时调用，原生立即停止导航/JS/图片下载写盘，用户取消记为 `cancelled` 而非超时。
- **真实总超时（P0-4/P0-5）**：以 Dart 传入 timeoutMs 建立请求级绝对 `requestDeadlineMs`，`armDeadline` 取 `min(请求剩余,阶段剩余,单图剩余)` 调度单一 timeouter，阶段/单图不再能累计超过总预算。
- **renderer gone 重建（P0-7）**：`onRenderProcessGone` 后 `destroyWebView()`（移除父容器、stopLoading、destroy、置空），下一次请求重建，错误分类 `rendererGone`。
- **请求专属图片目录**：图片写入 `filesDir/webview-imports/<requestId>/images/`，迟到 worker 只写回旧请求自己的目录；失败/取消/superseded 删除该目录，成功保留供 Dart 读取，dispose 清理全部。
- Dart 侧 `WebViewFetchErrorKind` 新增 `cancelled/superseded/rendererGone` 并映射到 `ImportContentAdapterErrorKind`；测试 Fake 补 `cancel()`。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/IMPORT-008-webview-lifecycle-race-2026-08-06.md` Android 真机复测。

### PERF-002 图片导入链路性能优化（《解决方案.md》第二批，ADR-0031）

按《解决方案.md》实施图片导入链路优化（P0 四项 + 深度思考开关）：

- **任务级图片缓存（消除重复下载）**：新增 `providers/ocr/task_scoped_image_cache.dart` 的 `TaskScopedImageCache`（实现 `OcrRemoteImageStager`），按“升级后的 https URL”缓存下载结果；识别与封面保存共用一次下载，缓存返回的 `StagedOcrImage` dispose 为 no-op，避免消费方提前删除共享文件。`DeviceImportTaskRunnerFactory.create()` 创建缓存并同时注入多模态处理器 stager 与 `LlmRecipeGenerationProcessor.remoteCoverImageStager`，末尾用 `_CacheReleasingProcessor` 在处理器链成功/失败后统一 `disposeAll()`。
- **多模态识别有限并发流水线**：`multimodal_image_enriching_import_content_processor.dart` 串行 `for` 改为并发 2 的 `_runConcurrent` 工作池（图片 1 下载完立即识别、图片 2 同时下载），结果按下标保序；单张识别失败（非取消）折叠为 null，`failedRecognition` 计数标记“部分内容”，不拖垮整批；取消错误原样上抛立即终止；全部失败给出可重试提示。新增 `concurrency` 与 `imageCompressor` 构造参数。
- **识别前压缩重编码**：新增 `application/importing/image_request_compressor.dart` 的 `ImageRequestCompressor`（`image` 包 `decodeImage`→`bakeOrientation` EXIF 修正→超长边按需等比缩放→`encodeJpg` 质量 85）。普通照片长边 2048px；长宽比 ≥2.5 的文字密集截图保留 4096px；压缩失败或体积无收益返回 null 保留原图。只影响上传给识别的字节，磁盘原图（封面用）不改动。
- **深度思考开关（ReasoningMode）**：`llm_models.dart` 新增 `LlmReasoningMode{fast,deep}`、`LlmReasoningCapability`，`LlmGenerationRequest` 增加 `reasoningMode`；`llm_connection_config.dart` 增加 `reasoningMode`（默认 fast，`toJson/fromJson` 用 `_parseReasoningMode` 兼容旧配置）；`llm_provider.dart` 增加 `reasoningCapability`；`openai_compatible_provider.dart` 下发 `reasoning_effort`（deep→high）、`gemini_provider.dart` 下发 `thinkingConfig {includeThoughts:true}`（仅 deep）。图片转录（多模态）始终快速；`multi_image_draft_split_processor.dart` 分组判断显式 `reasoningMode: fast`；`recipe_generation_prompt.dart` 的 `build()` 接收 `reasoningMode`，`llm_recipe_generation_processor.dart` 传 `_config.reasoningMode`（最终结构化跟随用户开关）。
- 依赖：`flutter pub add image:^4.8.0`（含传递依赖 archive/xml/petitparser/posix）。
- 全项目 IDE 诊断无错误；按 ADR-0015 未运行测试/构建/真机；等待项目负责人按 `tests/acceptance/PERF-002-import-pipeline-performance-2026-08-06.md` 复测。`PERF-002` 进入 `VERIFY`，iOS 未验证。

### 冰箱拖拽修复：部分食材无法跨区拖动（状态残留/错配）

项目负责人反馈"有些食材无法拖到另一个区，换一个食材就能拖，拖成功后原来的也能拖"。定位并修复三类真实缺陷（`fridge_page.dart`）：

1. **`_ZoneCard` 缺少稳定 key（根因）**：筛选/折叠导致分区卡数量变化时，Flutter 按位置复用 State，冷冻区会继承冷藏区等其他分区的 `_chipKeys`/`_open`/`_dragOver`/`_insertIndex`——被错误折叠的分区连 DragTarget 都不存在，拖放静默无效；且 `_chipKeys` 错配使插入位置计算失效。已为 `_ZoneCard` 加 `key: ValueKey(zone)` 并补 `super.key`。
2. **会话守卫误拦截**：`if (_committedDragSession == _activeDragSession) return;` 在 `onDragStarted` 未触发（`_activeDragSession` 为 null）时也会拦截，拖放静默失败。已改为"只有会话已存在且已提交"才拦截。
3. **`_applyDrop` 静默放弃**：`_allItems` 被刷新置空（`didUpdateWidget` 重置或失败重载）时 `fromIndex < 0` 直接 return。已改为先重新加载一次再重试，仍找不到才放弃，且不烧掉会话守卫。
4. 新增 `[AIRecipe][Fridge][Drag]` 诊断日志（开始拖拽/分区接收/守卫拦截/未命中重载/无效移动/保存失败/移动成功），便于后续复现时从 Logcat 定位。

全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人重新构建后复测：连续切换筛选后跨区拖动、折叠分区后再拖入、快速连续拖两个食材、同区排序。若仍可复现，回传 Logcat 中 `[AIRecipe][Fridge][Drag]` 行。

### PERF-001 菜谱列表与推荐性能优化（《解决方案.md》第一批，ADR-0030）

按《解决方案.md》实施“快速止血”组合（列表摘要查询 + 分页 + 虚拟化 + 推荐轻量数据 + Isolate + 限量展示 + 防抖与最新请求优先），解决“列表加载几分钟、推荐死机”：

- **列表摘要模型与消除 N+1**：新增 `RecipeSummary`/`RecipeSummaryPage`/`RecipeSort`/`RecipeCursor`（`domain/recipe/recipe.dart`）；`RecipeRepository` 新增 `listRecipeSummaries`（单条 SQL，LEFT JOIN ingredients + GROUP BY 聚合食材数）、`countRecipes`、`countRecipesByCategory`、`getRecipeSummariesByIds`、`listRecipesForRecommendation`（主记录 + 全部食材 2 次 SQL，不含步骤/图片/分类）。`SqliteRecipeRepository` 实现并抽取共享过滤构建器 `_buildListFilter`（listRecipes/摘要/计数同一套条件）。
- **keyset pagination**：updated/created/title 三种排序 + `(timestamp|title, id)` 游标续读，不用 OFFSET；多取一条判断 hasMore；排序由 SQL 承担，前端不再全量排序。
- **虚拟化渲染**：`recipe_library_page.dart` 重写为 `SliverGrid`（40 条/页）+ 滚动到底自动加载下一页 + `_loadGeneration` 防串页；加载期间保留旧列表顶替，不闪整页动画；筛选/刷新后退出选择模式；卡片改用 `RecipeSummaryCard`；打开详情按 id（`onOpenRecipeId`）。首页 `home_page.dart` 改用 `RecipeSummaryCard`，`HomeSnapshot` 改 `List<RecipeSummary>`。
- **首页优化**：`HomeUseCases` 不再全量 `listRecipes`——最近浏览按 id 批量取摘要、分类计数一条 SQL、收藏摘要一条 SQL。
- **推荐轻量数据 + Isolate**：`recommendRecipesFromInventory` 改走 `listRecipesForRecommendation`（约 5001 次 → 2 次 SQL），匹配计算移入 `RecommendationExecutor`——新增 `application/inventory/recommendation_executor.dart`：生产 `IsolateRecommendationExecutor`（`Isolate.run`，Web 回退直算）、测试 `DirectRecommendationExecutor`（FakeAsync 下 Isolate 消息无法被 pumpAndSettle 等待，注入直算避免挂起）；组合根与 `TestBackendHarness` 支持注入。
- **推荐 UI**：`fridge_recommendation_view.dart` 增加 250ms 防抖 + `_requestId` 最新请求优先（旧请求迟到结果丢弃）；`_ResultsSection` 改 StatefulWidget，每组首批 Top 10 + “查看更多（N）”增量展示，“更多缺失”同样支持展开。
- **算法优化（第二批前置）**：`IngredientCanonicalizer` 增加 2048 上限结果缓存（`_cache`）并改为非 const；`IngredientAliasRepository`/`IngredientSpecRepository` 改 Map 索引查找；推荐引擎 `recommend()` 建立家族索引（family→库存键）与上下位子级索引，`_candidateBatches` 由逐键扫描改 O(1) 直取（行为不变）。
- **数据库 v10 迁移**：新增复合索引 `idx_recipes_status_updated_id`、`idx_recipes_favorite_updated_id`、`idx_ingredients_base_recipe`、`idx_relations_category_recipe`（幂等，全新库与升级库都执行）。
- **性能测试**：`recipe_library_perf_test.dart` 新增“摘要第一页 40 条 + 总数、游标翻页读完全部 1000 条、名称排序”测量；新增 `recommendation_perf_test.dart`（1000 道菜谱 + 100 批次纯匹配耗时，正确性断言番茄炒蛋命中）。
- 测试 fake 同步：`MemoryRecipeLibraryRepository`、`MemoryRecipeRepository` 补齐新接口；`inventory_use_cases_test.dart` 去掉 `const InventoryRecommendationUseCases()`。
- **编译修复（flutter run 报错后）**：①`RecipeSummary` 移除 `const` 构造函数（`List.unmodifiable` 不是常量表达式）；②`RecipeLibraryUseCases` 移除 `const`，三个 use case 的 `canonicalizer` 默认参数改为可空 + 构造体内初始化（Dart 要求默认参数值必须为常量，`IngredientCanonicalizer()` 已非 const）；③`RecipeSummaryCard` 补自身 `_coverColor`/`_coverIcon` 静态方法（不能调用 `RecipeCard` 的私有静态成员）。
- 全项目 IDE 诊断无错误；按 ADR-0015 未运行测试/构建/真机；等待项目负责人按 `tests/acceptance/PERF-001-recipe-list-recommendation-performance-2026-08-06.md` 复测并回传性能数据。`PERF-001` 进入 `VERIFY`，iOS 未验证。

## 2026-08-05

### IMAGE-002 实施：多图多模态识别与多草稿（ADR-0029）

- 按项目负责人方向实施 `IMAGE-002`（进入 VERIFY 等待复测）：
  1. **多模态只做文字转录**：`MultimodalImageEnrichingImportContentProcessor.defaultPrompt` 改为“忠实转录图片全部文字”，不再做视觉观察描述；转录产物标记 `sourceType=ocr` 并保留 `sourceMediaOrder` 供按图分组；“图片没有文字”视同空结果。
  2. **多草稿数据契约**：`ImportRecipeDraftResult` 增加 `additionalRecipeIds`；`ImportTask` 增加 `additionalResultRecipeIds`（`markNeedsReview`/`reassignResultRecipe` 支持附加草稿）；SQLite v9 迁移 `import_tasks.additional_result_recipe_ids`（JSON 数组）；`getImportDraft(taskId, recipeId:)` 支持按草稿读取；确认页支持指定草稿，进度页 `needsReview` 多草稿时逐份确认（保存一份即返回，其余保留）。
  3. **分组判断与多草稿生成**：新增 `MultiImageDraftSplitProcessor`——纯文本 LLM 先轻量判断多图关系（independent→每图独立草稿 / combined→合并单草稿 / mixed→按图号分组），按组拆分转录证据逐份调用既有结构化生成，聚合返回多草稿；判断失败回退全部合并，不丢弃内容。
  4. **路由调整**：链接导入 `_resolveDefaultPlan` 的 auto 改为多模态优先（不再自动融合 OCR）；新增 `_resolveLocalImagePlan` 供手动选图/拍照导入——本地 OCR 优先，未安装/不可用时回退多模态转录。
- 新增测试定义：`test/application/multi_image_draft_split_processor_test.dart`（independent/combined/mixed/失败回退/单图直通）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/IMAGE-002-multimodal-multi-image-2026-08-05.md` 复测。
- 已知限制：分组判断失败回退合并；手动图运行期 OCR 识别失败暂不自动换多模态；多图独立时作者正文仅并入第一份草稿。
- **链路修复**：WebView 抓取适配器构建内容时未给含图片内容标记 `requiresOcr`，导致链接导入的图片整体跳过多模态转录（识别处理器直接透传）。已在 `webview_import_content_adapter.dart` 补上 `requiresOcr`（media 非空时），链接图片现在会进入逐张图多模态转录链路。
- **多草稿 UI 与批量确认**（按项目负责人反馈）：`confirmImportDraft` 支持指定 `recipeId` 与 `confirmAll`（发布全部草稿后完成任务，部分确认时任务保持 needsReview）；进度页多草稿时弹选择框（"本次识别到 N 道菜谱"，每项=菜名，点击进入编辑确认，底部"全部确认"一键添加）；确认页保存传递当前草稿 ID。已加 `[AIRecipe][Grouping]` 分组决策日志（groups/草稿数），用于定位多图被合并判定的问题。
- **关键修复（组装顺序反了导致永远单草稿）**：`DeviceImportTaskRunnerFactory` 中分组判断处理器被错误地包在**多模态转录之前**（链为 grouping→multimodal→LLM），分组判断在转录前执行，永远看不到转录片段（图组数恒为 0），因此多图链接永远只产出 1 个草稿、多草稿弹窗不出现。已交换为 **multimodal→grouping→LLM**：先逐张图转录，再分组判断（independent/combined/mixed），最后按组生成多草稿。`ocrAndMultimodal` 融合分支同样修正。
- **关键修复（多图导入失败 "Only queued import tasks can be run. 尝试1/3·不可重试"）**：项目负责人复测多图链接时整单失败。根因有二：
  1. `MultiImageDraftSplitProcessor` 分组循环的进度公式不含组号 `index`：非最后组全部映射到 `[0.6, 0.6+0.3/n]`，最后组直接用下游原始进度（`0.65` 起），组间切换时**进度必然倒退**（如组 0 结束 0.7 → 组 1 起始 0.6），触发任务 `advance()` 的“任务进度不能倒退”校验。已改为每组落在 `[0.6, 0.9]` 的独立子区间（组 i 结束 < 组 i+1 起始），并与上次已上报进度取较大值兜底，保证整体进度单调递增。
  2. `ImportTaskRunner._latestCancellationOrRethrow` 在写冲突/非法转移且任务未取消时抛出误导性消息 `'Only queued import tasks can be run.'`，掩盖了真实错误（如“进度不能倒退”）。已改为接收并**原样重抛原始异常**（仅任务已取消时返回最新取消状态），避免再次掩盖失败根因。
- **多草稿弹窗像素风 + 删除/多选删除**（按项目负责人反馈）：识别多个菜谱的弹窗由 Material `AlertDialog`+`ListTile` 改为像素风（`Dialog` 透明 + `PixelSurface` 墨色切角容器 + 像素按钮，与粘贴文本弹窗一致）；每项支持点击整行进入编辑确认、右侧删除图标单项删除（二次确认，草稿移入回收站可恢复）、左侧勾选框多选后底部"删除所选 (N)"批量删除、"全部确认"一键添加、错误用红色 `PixelNotice` 内联展示。新增后端 `AiRecipeBackendFacade.deleteImportDrafts(taskId, recipeIds)`：只允许 `needsReview` 任务、校验草稿归属、逐个软删除、删除全部则取消任务、只删部分则剩余草稿重排（删主草稿时第一份附加草稿自动提升为主）。
- **修复"点了返回却被添加菜谱"（误添加）**：①多草稿弹窗"全部确认"原本一键发布全部草稿且无确认，误触即批量入库——已加像素风二次确认（"确认全部添加这 N 道菜谱？"）；②从草稿确认页未保存返回后，`_openReview` 原循环会立刻重新弹出多草稿弹窗，用户被反复弹窗纠缠、容易最终误触"全部确认"——已为"全部确认"加二次确认阻断误触（返回行为保持不变：回到弹窗继续处理）。确认页 AppBar 返回本就是 `maybePop`（不保存），保持现状。**随后按项目负责人反馈修正**：点进某草稿确认页再返回时弹窗不应消失——恢复"未保存返回后回到多草稿弹窗继续处理其他草稿"（`task = reloaded` 继续循环），返回本身不添加任何菜谱，误添加防护仍由"全部确认"二次确认承担。
- **多草稿弹窗交互调整（按项目负责人反馈）**：去掉底部"稍后处理"按钮；右上角新增像素风关闭按钮（弹窗唯一退出入口）；点击弹窗空白处不再关闭（`barrierDismissible: false`），并用 `PopScope(canPop: false)` 拦截系统返回键；底部按钮改 `Wrap` 自动换行，修复勾选后"删除所选 (N)"与"全部确认"同时出现时的横向溢出。**另支持长按选择**：长按草稿条目进入选择模式（选中该项），选择模式下点按条目只切换选中、不进确认页，副标题提示当前已选数量，取消全部选中自动退出选择模式；勾选框多选入口保留。**长按失效修复**：原实现用外层 `GestureDetector(onLongPress)` 包住 `PixelSurface`（内部 `InkWell.onTap`），两层识别器在列表内竞争导致长按不稳定触发；改为 `PixelSurface` 新增 `onLongPress` 参数，与 `onTap` 由同一 `InkWell` 处理（Flutter 保证点击/长按互斥且稳定，等同 ListTile 标准做法），共享组件现有调用不受影响。
- **菜谱库长按选择模式（批量操作）**（按项目负责人反馈）：菜谱库网格卡片支持长按进入选择模式——选中项绿色描边 + 半透明覆盖 + 右上角对勾角标；选择模式下点按卡片切换选中、收藏按钮隐藏、"AI 导入"徽标隐藏，取消全部选中自动退出；页头变为"已选择 N 项" + "取消"按钮；底部浮出 `PixelBottomActionBar` 提供"加入收藏"与"删除所选 (N)"（批量软删除有像素风二次确认，移入回收站可恢复）。`RecipeCard` 新增 `onLongPress`/`selected` 参数（列表与网格两种形态都支持选中视觉），首页等既有调用不受影响。
- **菜谱库收藏/读取性能优化**（按项目负责人反馈）：①点收藏不再触发整页刷新与加载动画——改为乐观更新（`_favoriteOverrides` 本地立即切换图标，`RecipeCard` 新增 `favoriteOverride` 优先展示，后端写入失败回滚并提示），收藏成功只刷新首页数据；②菜谱库列表改为"缓存顶替"加载——`_cachedData` 缓存最近成功快照，搜索/排序/分类刷新期间用旧数据继续展示，只有首次无缓存才显示加载动画。
- **菜谱库 1000 条数据读取性能测试**（按项目负责人反馈）：新增 `test/performance/recipe_library_perf_test.dart`——用 `sqflite_common_ffi` 真实 SQLite 插入 1000 条 published mock 菜谱，测量并打印：插入总耗时、`listRecipes()` 全量首次/预热后平均耗时、收藏过滤与关键词搜索耗时；正确性断言（1000 条全量、收藏命中 500、搜索命中 1），耗时不做环境相关硬断言。项目负责人运行：`flutter test --no-pub test/performance/recipe_library_perf_test.dart`。
- **应用内开发者工具：生成/清空 1000 条测试菜谱**（按项目负责人反馈"菜谱中只有五条数据，请加一千条"）："我的"页新增"开发者工具"区——"生成 1000 条测试菜谱"（像素风二次确认 + 进度弹窗，逐条 `createRecipe` 插入标题带"性能测试菜谱"前缀的 published 菜谱，偶数条收藏，生成完成后通过 `onDataChanged` 刷新菜谱库）与"清空测试菜谱"（软删除所有标题前缀匹配菜谱，可进回收站恢复）；`ProfilePage` 新增 `onDataChanged` 回调并由 AppShell 注入。

### BUG-006 实施 P0-1/P0-2：分阶段连接诊断 + OCR / 多模态证据融合

- 按 `docs/architecture/VISION_RECOGNITION_STRATEGY.md` 完成低级工程师实施，`BUG-006` 代码进入 `VERIFY` 前等待项目负责人验收。
- **P0-1 诊断修复**：
  1. 扩展 `LlmProviderErrorKind`：`badRequest`(400/422)、`methodNotAllowed`(405)、`payloadTooLarge`(413)、`unsupportedMediaType`(415)、`providerGatewayTimeout`(408/504)、`modelBusy`(409/423)、`firstByteDeadline`、`bodyIdleDeadline`、`streamNotTerminated`、`imageNotObserved`、`textCapabilityUnconfirmed`；`llm_response_helpers.dart` 按状态码分别映射中文可操作文案。
  2. 新增 domain 诊断模型 `domain/llm/llm_diagnostic.dart`：阶段（configValidation→…→imageAssertion）、阶段记录（result/elapsedMs/httpStatus/messageKey/nextAction）、分层时限（连接 8s/首字节 15s 基础·45s 图片/正文空闲 15s/总时限沿用用户配置）。
  3. `LlmTransport.sendDiagnostic` 新增流式观察实现（`http_llm_transport.dart`）：`StreamIterator` 分别记录响应头、首字节、正文空闲与完成；失败按阶段返回报告而不是统一"超时"；取消抛 cancelled 优先于超时。
  4. 内置 256×256 标准诊断图（`assets/diagnostics/vision_probe_v1.png`，SHA-256 `7D6D7AB2…87902E`）：白底黑字 "AI RECIPE 314" + 右上红色方块；`providers/llm/vision_probe.dart` 内嵌 base64 字节 + 固定提示词 + JSON 断言（文字与红色方块同时通过；大小写/空白/分隔差异容忍）。
  5. `MultimodalLlmProvider.diagnose`（imageProbe=false 基础连接 / true 标准图）；Facade 拆三入口：`checkMultimodalBaseConnection`（视觉专用模型拒绝纯文本时标记"服务与鉴权已通过，文本能力未确认"）、`checkMultimodalImageCapability`（断言失败追加 imageAssertion 阶段）、`testMultimodalImage` 保留；1×1 PNG 占位图删除。
  6. 识图引擎设置页改三入口按钮 + `_MultimodalDiagnosticCard` 分阶段结果卡（阶段/耗时/HTTP/中文 messageKey/建议），不再把全部失败显示为"链接超时"。
- **P0-2 证据融合**：
  1. `ImportTextFragment` 新增 `sourceType`（authorText/ocr/subtitle/asr/visionObservation/inference）；`ImportContentWarning` 新增 `visionIncomplete`/`ocrIncomplete`。
  2. `ImportImageRecognitionRoute.ocrAndMultimodal`（自动融合）；`_resolveDefaultPlan` 的 auto 在 OCR+多模态同时就绪时走融合。
  3. 新增 `VisionFusionImportContentProcessor`：OCR 与多模态独立执行、分别结算；一路失败保留另一路并标记缺失；两路都失败有正文继续、无证据不生成空草稿；冲突按来源保留（不静默覆盖）。
  4. `DeviceImportTaskRunnerFactory` 组装融合链路；`RecipeGenerationPromptBuilder` 片段带 `sourceType` + `sourceTypeNote` 说明来源优先级；草稿确认页证据面板展示来源标签（作者原文/OCR 文字/视觉观察等）。
- 新增测试：`test/providers/vision_probe_test.dart`（断言矩阵）、`test/application/vision_fusion_import_content_processor_test.dart`（部分成功/冲突保留/无证据不生成空草稿）。全项目 IDE 诊断无错误；未运行 Flutter/Dart 测试、静态分析、构建、模拟器、真机或真实 Provider/真实图片质量测试（ADR-0015）；`BUG-006` 进入 `VERIFY` 等待项目负责人按 `tests/acceptance/BUG-006-multimodal-diagnostics-and-vision-fusion-2026-08-05.md` 复测。

### BUG-006 方案：修复多模态测试连接误报超时，OCR / 多模态改为证据融合

- 反馈：项目负责人确认多模态“测试连接”总是显示超时，但实际不是普通网络超时。
- 复盘：旧配置复用修复与 1×1 PNG 图片请求只排除了“测到旧模型”和“纯文本探测”两个因素；真正问题是黑盒总时限把连接、首字节、正文完成、流终止、Provider 408/504、图片协议和响应解析错误统一包装成超时。
- 新增 `docs/architecture/VISION_RECOGNITION_STRATEGY.md`：定义基础连接/标准图片能力/真实图片质量三层测试、分阶段诊断、256×256 标准探针、HTTP/SSE/取消/Schema 分类、OCR/多模态职责和证据融合。
- 更新产品需求、架构索引、`BUG-006`、ADR-0028、`CURRENT.md`，并新增 `tests/acceptance/BUG-006-multimodal-diagnostics-and-vision-fusion-2026-08-05.md`。
- 本轮只提供工程交接方案，未修改应用代码，未执行 Flutter/Dart 测试、静态分析、构建、模拟器、真机或真实 Provider/真实图片质量测试；`BUG-006` 保持 `DOING`，等待低级工程师实施后由项目负责人验收。

### IMAGE-001 修复：多模态"测试连接"仍失败——输出失败原因 + 修复"改模型仍测旧配置"

- 反馈（项目负责人）："还是不行，请输出失败原因"——多模态"测试连接"持续失败，需要 UI 输出具体失败原因，而非固定文案。
- 修复：
  1. **UI 透出具体失败原因**（`ocr_settings_page.dart`）：`_testConnection` 的 `AiRecipeBackendException` 分支直接显示 `error.message`（服务端/Provider 的具体原因：鉴权失败、模型不存在、限流、服务不可用、超时等），不再被 `_connectionFailureMessage(code)` 的固定文案吞掉。
  2. **根因修复：测试连接误用已保存旧配置**（`ai_recipe_backend_facade.dart`）：原实现当表单 `id` 与已保存配置一致时整个复用已保存配置（含旧模型/旧地址/旧超时），用户改表单里的模型后点击"测试连接"仍请求旧模型；若旧模型不支持图片输入，服务端会一直等待直到超时——表现为"改了也没用、一直链接超时"。现改为：已保存配置只用于复用 ID/密钥引用并读取已存 Key，**地址、模型、超时一律以表单当前输入为准**（与 `LlmSettingsUseCases.testConnection` 的 `_buildConfiguration` 行为一致）。
  3. **超时文案可诊断化**：超时错误补充请求目标与提示——"请求超时（已等待 N 秒）。请确认模型「xxx」支持图片输入且服务已加载该模型；必要时可调大'请求超时'或检查 API 地址。"；其余错误直接透出服务端具体原因。
  4. 已存 Key 读取失败时按未填 Key 处理，让 Provider 明确报鉴权错误，不再静默。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）。等待项目负责人重新构建后，把"测试连接"显示的具体失败原文回传以最终确认。

## 2026-08-04

### IMAGE-001 修复：多模态配置区新增"测试识图" + 测试连接/保存按钮转圈问题

- 反馈（项目负责人）：多模态识图也要能测试图片；测试连接点击后一直加载；保存按钮也有同样的加载动画。
- 修复（`ocr_settings_page.dart` + `ai_recipe_backend_facade.dart` + composition root）：
  - 新增 Facade `testMultimodalImage(localPath)`：读配置+Key → 读图片字节 → 校验（8MB/类型）→ 多模态识别 → 返回文本/耗时/模型；错误统一映射（未配置、Key 缺失、超时、网络、认证等）。
  - 多模态配置区新增"测试识图（选一张图片）"按钮 + 结果卡片（识别文本/耗时/模型）+ 红色错误条，真正发送图片验证视觉能力。
  - 状态分离：`_busy`（保存/清 Key，本地操作）与 `_testingConnection`（测试连接，网络请求）互不干扰，测试连接挂起不再让保存按钮转圈。
  - 测试连接改用表单所选超时（不固定 20 秒）：部分本地/代理服务响应较慢（冷启动、排队），固定短超时会误报"链接超时"；等待期间有"正在测试连接…"提示且不影响保存。
  - **再次修复"测试连接"超时（项目负责人反馈：地址/Key 与可用 LLM 一致、仅模型不同仍超时）**：根因是多模态"测试连接"原先发送纯文本请求，而部分视觉模型/中转服务对"无图纯文本请求"长时间不返回导致误报超时；`testMultimodalConnection` 改为发送一张内置 1×1 PNG 占位图发起真正的多模态识别（复用已保存配置与已存 Key，否则用表单输入），验证地址/Key/模型支持图片的真实链路。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）。

### IMAGE-001 识图引擎：图片识别方式可选（OCR / 多模态 LLM）+ 独立多模态配置

- 需求（项目负责人）：链接导入时导入了链接没有提取图片内容；新增多模态 LLM 识别，不改 LLM message，新增一个多模态方式；识别时可选择 OCR 还是多模态 LLM。并确认：OCR 引擎与多模态 LLM 设置放一起，"OCR 引擎"改名"识图引擎"。
- 新增（ADR-0027）：
  - 识图引擎页（原 OCR 引擎页）：顶部"图片识别方式"单选（自动/仅 OCR/多模态 LLM，保存到 `LocalAppSettings.imageRecognitionMode`，SQLite v8 迁移）；中部新增"多模态 LLM 图片识别"独立配置区（Provider/API 地址/模型/Key/超时，独立存储 key，复用 `LlmSettingsUseCases`）。
  - `MultimodalLlmProvider`：OpenAI-compatible（image_url + data URL）与 Gemini（inline_data base64）双实现，纯文本 generate 复用现有 Provider 用于连接测试；图片 8MB/魔数类型校验。
  - `MultimodalImageEnrichingImportContentProcessor`：配图经安全暂存下载/校验 → 读字节 → 多模态识别 → 提取菜谱信息并入证据 → LLM 生成草稿；固定中文提示词；错误统一中文映射。
  - `ImportImageRecognitionRoute {disabled, ocr, multimodal}` 替换 `ImportOcrRoute`；`_resolveDefaultPlan` 按设置+能力自动解析（auto：多模态→OCR→纯文本）；`runImportWithLocalImage` 同步按设置解析。
  - `AppCapability.multimodalLlm` 能力（配置+Key 就绪）；进度阶段文案改"正在识别图片内容"。
  - "我的 → OCR 设置"入口与设置页标题改"识图引擎"。
- 非目标：不改纯文本 LlmMessage/菜谱生成 LLM；不做视频识别。
- 修改/新增文件：`domain/llm/multimodal_llm_provider.dart`、`providers/llm/multimodal_llm_provider_impls.dart`、`data/multimodal_llm_config_repository.dart`、`application/importing/multimodal_image_enriching_import_content_processor.dart`、`import_execution_plan.dart`、`app_capability.dart`、`local_app_settings.dart`(+SQLite v8)、`device_import_task_runner_factory.dart`、`ai_recipe_backend_facade.dart`、`ai_recipe_backend_composition_root.dart`、`ocr_settings_page.dart`、`profile_page.dart`、`import_progress_page.dart` 及测试定义。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；验收方法见 `tests/acceptance/IMAGE-001-vision-engine-2026-08-04.md`，等待项目负责人复测。

### OCR-003 完善：核对全部 OCR 使用点 + 占位任务恢复保护

- 需求（项目负责人）：检查需要使用 OCR 的地方是否真的使用了 OCR，没有就接入，完善功能。
- 核对结果（全部已接入 OCR）：
  1. 链接导入 `runImportTask`：plan 为 null 时 `_resolveDefaultPlan()` 按本地 OCR 能力快照自动启用 `ocr: local`（IMPORT-007）。
  2. 后台调度 `dispatchPendingImports`：同 `_resolveDefaultPlan()`，恢复的图文任务同样走 OCR。
  3. 快速导入"拍照选图"：`createLocalImageImportTask` + `runImportWithLocalImage`（固定 `ocr: local`）。
  4. 失败/取消任务"截图"降级：`runImportWithLocalImage`（OCR）。
  5. OCR 设置页"测试 OCR"。
  - 文本导入（剪贴板/粘贴正文）为纯文本，刻意不启用 OCR；视频走 ASR（managedAsrBuilder 未接入，已知限制）。
- 修复发现缺陷（`ai_recipe_backend_facade.dart`）：`createLocalImageImportTask`/`createLocalTextImportTask` 使用占位 URL（`https://local-image/capture`、`https://local-text/capture`）；若创建后未立即运行、稍后从"未完成导入"列表恢复，原会走公开适配器抓占位链接而失败。现提取占位 URL 常量，`runImportTask` 对占位任务抛出"该导入需要重新提供图片或正文内容，请重新创建导入"。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）。

### OCR-003 修复：测试 OCR 报"inference failed"（识别模型类别数与字典不匹配）

- 反馈（项目负责人）：模型下载安装成功后，测试 OCR 报 `Local OCR Inference failed`。
- 根因：PP-OCRv5 识别模型输出类别数 = 字典行数 + 2（实测 `[1,40,18385]`，字典 18383 行；blank 在类 0，dict 从类 1 起，末尾多一个不映射字符的额外类），而 `PaddleOcrEngine`/`OcrCtcDecoder` 硬编码校验 `classes == symbols.size + 1`（18484），与模型不符，加载/解码时抛 `inference_failed`。
- 修复（`PaddleOcrEngine.kt`）：classes 校验改为范围 `[symbols+1, symbols+2]`（兼容 PP-OCRv4 +1 / PP-OCRv5 +2）；`OcrCtcDecoder` 解码时末尾额外类不映射字符直接跳过该帧（不再抛错）。Kotlin 测试更新：mismatch 用例改 classes=4（超出范围）断言仍拒绝；新增"跳过尾随额外类"用例。
- 已用本机 Python + onnxruntime 对真实模型实测：`blank=0, idx=class-1` 解码可输出中文（如"西红柿炒鸡蛋"样本输出"西…炒鸡蛋"序列），验证类别映射正确。
- 未运行测试/构建/真机（ADR-0015）；等待项目负责人重新构建后复测下载安装 + 测试 OCR。

### OCR-003 修复：模型下载报"download failed"（ModelScope 302 重定向）

- 反馈（项目负责人）：点击下载提示 `OCR model download failed`。
- 根因：ModelScope `resolve` 直链对 GET 返回 302（跳转 `cdn-lfs-cn-1.modelscope.cn` 带签名 CDN），而 `HttpOcrModelDownloadClient` 保持 `followRedirects=false`（防绕过受信主机白名单的安全设计），收到 302 即按非 200 判为 `downloadFailed`。
- 修复（`http_ocr_model_download_client.dart`）：不依赖 http 包自动跟随，改为手动逐跳处理——仅允许 HTTPS 重定向、最多 5 跳、Location 缺失/非法/非 HTTPS 时安全拒绝；最终内容仍按 SHA-256 与字节数双重校验兜底（重定向到非预期主机也会在 checksumMismatch 失败），不破坏原 `followRedirects=false` 测试语义。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人重新运行后复测下载安装。

### OCR-003 本地 OCR 模型包清单接入（真实下载地址）

- 反馈（项目负责人）：附带一个安装的地址吧，现在显示模型尚未发布。
- 根因：`installManifest` 恒为空（`profile_page` 未传），且组合根 `trustedOcrModelHosts` 默认空导致任何下载主机都会被拒。
- 修复：
  - 新建 `lib/app/ocr_model_catalog.dart`：`ocrPpocrV5MobileZhManifest`（schemaVersion 2、PP-OCRv5 mobile zh、ONNX Runtime、Android）+ `ocrTrustedModelHosts`（`www.modelscope.cn`）。
  - 模型来源 RapidAI/RapidOCR 官方 ModelScope 仓库（Apache-2.0），三个文件均为 2026-08-04 真实下载实测：`ch_PP-OCRv5_det_mobile.onnx`（4,819,576 B）、`ch_PP-OCRv5_rec_mobile.onnx`（16,631,306 B）、`ppocrv5_dict.txt`（74,012 B，18383 行，首行全角空格 blank），SHA-256 与字节大小已写入 Manifest，安装时双重校验。
  - 运行时参数与 RapidOCR PP-OCRv5 默认一致（det 960 / rec [3,48,320]、bgr 归一化、blank 0）。
  - `app.dart` 组合根传入 `trustedOcrModelHosts`；`profile_page.dart` 把 Manifest 传入 OCR 设置页，"下载本地模型"按钮恢复可用，不再显示"正式模型包尚未发布"。
- 新增 ADR-0026（模型下载源决策）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测下载安装 + 测试 OCR。

### OCR-003 修复：OCR 引擎页缺少"测试 OCR"入口

- 反馈（项目负责人）：OCR 引擎页没有"测试 OCR"的选项。
- 根因：入口只在"模型包已安装"（`installed`）分支内；正式模型 Manifest 未发布、模型无法安装时永远看不到该按钮。
- 修复（`ocr_settings_page.dart`）："测试 OCR"按钮从 `installed` 分支移出，改为模型包卡片内**常驻显示**（与模型安装状态无关）；点击时若本地 OCR 模型未就绪，不打开图片选择器，按状态给中文引导（未安装→"请先在模型包中下载并安装本地 OCR 模型后再测试"、下载/校验中→"还在下载/校验中…"、安装失败→"请先重试下载后再测试"）；已安装则照常选图识别。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；验收文档 `tests/acceptance/OCR-003-ocr-settings-test-2026-08-04.md` 已同步"入口常驻 + 未安装引导"测试点，等待项目负责人复测。

### OCR-003 OCR 设置页"测试 OCR"：选图识别并输出文本与耗时

- 需求（项目负责人）：在 OCR 测试的地方加一个"测试 OCR"功能——选择一张图片然后识别，输出文本和所用时间。
- `OcrTestResult` 领域模型：`text`/`modelVersion`/`language`/`blockCount`/`durationMs`/`averageConfidence`。
- `AiRecipeBackendFacade.testLocalOcrImage(localPath)`：前置能力检查 + 复用 `localOcrProviderBuilder` 直接识别本地图片（不上传）；错误统一映射为 `AiRecipeBackendException`（模型未安装/不可用/推理失败 → providerRouteUnavailable，超时 → timeout，取消 → operationCancelled，网络不可用 → networkUnavailable，其余 → operationFailed）；`composition_root.dart` 注入本地 OCR Provider 工厂。
- OCR 设置页（模型包已安装分支）："测试 OCR"按钮打开系统图片选择器 → 识别 → 结果卡片（识别文本、耗时 ms、文本块数、平均置信度、模型版本、语言；空文本明确提示）；失败显示红色 `PixelNotice` 稳定中文错误；测试期间按钮防重复点击。
- 修改文件：`ocr_models.dart`、`ai_recipe_backend_facade.dart`、`ai_recipe_backend_composition_root.dart`、`ocr_settings_page.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；验收方法见 `tests/acceptance/OCR-003-ocr-settings-test-2026-08-04.md`，等待项目负责人复测。

### UI-002 菜谱详情：来源链接点击复制 + 图片点击放大左右滑动（第十九轮）

- 项目负责人反馈：①菜谱的来源链接点击后可复制到剪贴板；②点击图片可放大查看，放大后可左右滑动切换图片，保持风格统一。
- ① `_ImportSourceLine` URL 包 `InkWell`，点击 `Clipboard.setData` 复制 `task.normalizedUrl` 并提示"来源链接已复制到剪贴板"（浮动 SnackBar）。
- ② hero 轮播图片点击打开像素风全屏查看器 `_FullscreenImageGallery`——深色背景、`PageView` 左右滑动切换（初始页=点击页）、`InteractiveViewer` 双指缩放、顶部像素风 `PixelIconBtn` 关闭按钮、底部 monospace 页码 "n / N"。
- 修改文件：`code/apps/mobile/lib/features/recipe/recipe_detail_page.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 剪贴板弹窗改像素风（第十八轮）

- 项目负责人反馈：剪贴板的弹窗样式不对，与整个 UI 风格不匹配。
- 修复（`app_shell.dart`）：`_promptPasteText` 由默认 `AlertDialog` 改为像素风弹窗——`Dialog` 透明背景 + `PixelSurface` 容器（pxc-lg 切角 + 墨色 1.5px 描边 + 硬投影），标题 15px/w900/letter-spacing 1px、副标题 tiny、TextField 沿用全局像素输入框主题、取消/开始导入按钮为像素化 OutlinedButton/FilledButton。
- 全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 首页快速导入一行化 + 剪贴板改文本输入导入（第十七轮）

- 项目负责人反馈：①首页快速导入区域要和 HTML 一样，改成一行，描边与“添加按钮”（右下角 FAB）一致；②剪贴板导入应是一个输入框输入文本导入，而不是粘贴链接。
- ① `home_page.dart`：快速导入区去掉 2×2 网格与外层绿底卡，改为 HTML .quick-grid 一行 4 个 quick-btn；`_QuickButton` 改 HTML quick-btn 样式——竖排 36×36 green-softer 图标块（pxc-xs 切角）+ 文字，card 底 + pxc-sm 切角 + 墨色 1.5px inset 描边（与 FAB 添加按钮同款 AppColors.ink）。
- ② 剪贴板改文本输入导入：`app_shell.dart` 点“剪贴板”弹出文本输入框（粘贴/输入正文），确认后创建占位文本任务并立即用文本运行（自有 LLM 整理成菜谱）；新增后端 `createLocalTextImportTask`/`runImportWithText`（允许 queued）、`ImportProgressPage.initialText` + `_runTextFallback`；不再读取系统剪贴板预填链接（移除 Clipboard 读取与 services import）。
- 修改文件：`code/apps/mobile/lib/features/home/home_page.dart`、`code/apps/mobile/lib/features/shell/app_shell.dart`、`code/apps/mobile/lib/features/importing/import_progress_page.dart`、`code/apps/mobile/lib/application/backend/ai_recipe_backend_facade.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### RECO-001 开启"仅使用已选食材"时替代（MAYBE）仍算命中（第十六轮）

- 项目负责人反馈：开启"仅使用已选食材"（strictSelected）时，替代食材（如 牛肉→猪肉）也应算作命中，只是显示仍为"替代 xx→yy"标签。
- 原行为：strictSelected 开启时，冰箱中未选择的食材一律按缺失计（含 MAYBE 替代）。
- 修复（`inventory_use_cases.dart`）：strictSelected 分支增加 `match.verdict != IngredientMatchVerdict.maybe` 条件——MAYBE 替代不因未选择而判缺失，走正常路径（kind=冰箱已有可补选 + verdict=maybe），进入"可能可以做"，标签区仍显示黄色"替代 精瘦肉→猪肉"；NO（规格不符）与 YES 未选择仍按缺失计。
- 补充测试定义：`inventory_use_cases_test.dart` 新增"strictSelected keeps MAYBE substitution as hit"（未选择 + strictSelected 下 精瘦肉 在 maybeNames、不在 missing，kind=inFridgeNotSelected）。未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 推荐卡：缺失灰色 + 移除视为可用/数量确认 + 封面图（第十五轮）

- 项目负责人反馈：①缺失使用灰色；②去掉“视为可用”按钮；③去掉“有该食材，数量是否足够需确认”文本；④匹配的推荐卡片带封面图（参考 HTML）。
- ① 缺失标签 `_tagMiss*` 由琥珀改灰色（bg #E9E8E3 / fg #5F645F / border 45%）；替代（MAYBE）标签独立为黄色 `_tagSub*`（琥珀系）不受影响。
- ② 删除“视为可用”按钮块及 `_ResultsSection`/`_RecommendationCard` 的 `onConfirmMaybe` 参数链、State `_confirmBaseForSession`；`confirmedBases` 字段保留（后端能力，恒空）。
- ③ 删除 `quantityUncertain` 的“有该食材，数量是否足够需确认”展示块。
- ④ 推荐卡头部改 HTML .card 结构：左侧 56×56 封面（有 `coverImage` 显示本地图片、无图回退绿块+菜名图标）+ 右侧标题/tiny + 右侧匹配 conf 标签；新增 `_cardCover`/`_coverIcon`（`dart:io` 加载本地封面）。
- 修改文件：`code/apps/mobile/lib/features/fridge/fridge_recommendation_view.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 推荐页食材样式对齐 HTML + 待确认改黄色替代标签（第十四轮）

- 项目负责人反馈：①推荐部分的食材也要和 HTML 样式一致；②“可以做”的卡片中待确认食材做成黄色标签，如“牛肉滑蛋”需要牛肉但只有猪肉 → 标签“替代 牛肉→猪肉”，去掉“待确认”文本。
- ① 选择区食材 chip `_SelectableChip` 由圆角 Material 卡片改为 HTML .food-chip（平直 + 底部 3px 硬投影 + inset 1.5px 描边 + 食材图标 + 名称/数量 + 状态变体 soon/expired/unknown）；选中态 green-soft 底 + green-deep 描边 + 名称后 ✓；已过期 0.7 透明度；关闭按压水波纹。新增本地 `_InsetRectBorderPainter`。
- ② 快捷按钮 `_ActionChip` 由 OutlinedButton 改为 HTML .chip（平直 card 底 + inset 1.5px 描边、纯文字）。
- ③ 推荐卡片食材标签 `_MiniTag` 重构为 HTML .mini-tag（浅底+深字+1px 描边）：已选命中=绿（--green-soft/--green-ink）、冰箱已有可补选=蓝（--blue-soft/#3D4B5C）、缺失=琥珀（--amber-soft/#75602C）且带数量“缺失 · 鸡腿 400 g”、规格不符=红。
- ④ 待确认（MAYBE）改黄色“替代 xx→yy”标签：`IngredientMatchDetail` 新增 `matchedStockName`（`_BestMatch` 记录命中库存食材名，`_bestMatch` 遍历候选时记录），标签区展示黄色“替代 牛肉→猪肉”；移除原“待确认：…— 原因”文本行，仅保留“视为可用”确认按钮（右对齐）。
- 修改文件：`code/apps/mobile/lib/features/fridge/fridge_recommendation_view.dart`、`code/apps/mobile/lib/application/inventory/inventory_use_cases.dart`、`code/apps/mobile/lib/domain/inventory/inventory_batch.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 冰箱拖拽与逐格冷冻动效：方案实施完成（第十三轮）

- 项目负责人反馈：当前冷冻效果仍像整块横向扫过，长按或拖动过程中还会莫名提前播放动画；期望二维小格一格一格出现，并且只有食材真正放到最终区域后才开始。
- 方案 `design/flows/FRIDGE_DRAG_AND_FROST_ANIMATION_HANDOFF.md`（ADR-0025）已实施（`fridge_page.dart` + `inventory_batch.dart`）：
  - 动画触发与手势彻底分离：新增 `_FrostKind`/`_ArrivalEvent`（dragSessionId/moveEventId/stableItemId/animationKind），到达事件只在“最终目标接收 + 保存成功 + 目标 chip 挂载”后生成一次、消费即删除；删除“名称 + 250ms”去重与 `_pendingFrostAnim`。
  - 每分区单一最终 DragTarget（onMove 算插入序号/onLeave 清高亮/onAccept 提交）+ 会话级一次性提交守卫，杜绝双回调竞态。
  - `AggregatedInventoryItem` 新增 `stableId`（批次 ID 集合）稳定身份，同名多批次/快速连续/重建不串事件。
  - 组件拆分：静态 `_FoodChipView`（无 controller/无 mount 动画/无水波纹）用于拖拽影子与原位占位；正式 `_FoodChip` 只在消费到达事件后播放。
  - 二维逐格 `_FrostGridPainter`：12dp 小格≥2 行、图标侧垂直居中冰核、曼哈顿距离由近到远、每 tick 只切一个完整格子（冷冻逐个出现/解冻严格逆序消失）、550ms；描边/投影/图标离散切换，不再连续 Color.lerp。
  - 同区排序/非冷冻互移/长按/无效释放不播动画；保存失败恢复原位+中文提示；减少动态直接显示最终样式。
- 新增 `tests/acceptance/UI-002-fridge-drag-frost-animation-2026-08-04.md`，覆盖长按、无效释放、经过冷冻区、同区排序、跨区、快速连续拖动、同名批次、页面重建、空分区、保存失败、减少动态和极限内容等 15 个场景。
- 已同步产品需求、US-011、设计索引/UI 交付、UI-002 任务、CURRENT 与 ADR-0025。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；`UI-002` 保持 `DOING`，等待项目负责人按 15 场景验收文档复测。

### UI-002 冰箱页：非冷冻区冰冻样式修复 + 逐格动画阶梯感 + 日期同步补漏（第十二轮）

- 项目负责人复测反馈：①只有冷冻区才应是冰冻样式，其他区都应正常（实测冷藏/常温等区也显示冰蓝）；②动画要"一格一格出现"而不是"直接过去"；③修改日期后仍需要手动刷新才能同步食材信息。
- 修复①：根因是 `_FrostFillPainter` 语义——`freezing=false`（解冻方向）+`progress=0` 时源色=frozenColor，整块画冰蓝；静止态非冷冻 chip 的 `_controller.value = widget.frozen ? 1 : 0` 落成 0。修复：静止态动画进度恒为 1（= 动画已完成、目标色全填充）：冷冻区全冰蓝、非冷冻区全正常；动画只在 `playFrostOnMount`/`didUpdateWidget` 触发时 `forward(from: 0)` 从反方向逐格播放。
- 修复②：格子 8px→16px（`_FrostFillPainter._step`）、动画时长 450ms→900ms，每格跳变清晰，形成"从左往右一格一格变色"而非平滑扫过。
- 修复③：第十一轮 `_localRefresh` 虽触发 `_InventoryView` 重新 `_load()`，但 `_allItems ??=` 只在其为 null 时填充，旧缓存导致仍显示旧数据；`_InventoryView.didUpdateWidget` 在 refreshToken 变化时先置 `_allItems = null` 再加载，立即显示新数据。
- 修改文件：`code/apps/mobile/lib/features/fridge/fridge_page.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人 `flutter run` 复测。

### UI-002 冰箱页：日期同步修复 + 冰冻/解冻逐格变色动画（第十一轮）

- 项目负责人反馈：批次编辑保存日期后界面不立即同步（重新进入才显示新日期）；AnimatedSwitcher 350ms 淡入淡出冰冻/解冻动画实际未生效（看着是直接变色）。
- 修复①日期同步：`_InventoryView` 依赖 AppShell 的 `refreshToken` 链路，批次编辑保存返回后未触发 → `_FridgePageState` 新增 `_localRefresh` 本地计数，`_openBatchEditor`/`_confirmBatchAction` 保存成功后递增并传给 `_InventoryView`（`refreshToken: widget.refreshToken + _localRefresh`），保存后立即重载显示新日期。
- 修复②动画：根因是跨区拖动后 chip 在不同分区被重新构建（新 State 直接落在最终态、无动画起点），淡入淡出无从播放。`_FoodChip` 改 StatefulWidget 自维护 450ms AnimationController；新增 `_FrostFillPainter` 逐格绘制器（8px 一格、`floor(progress×cols)` 从左往右逐格切换源/目标色）；同位置 frozen 变化由 `didUpdateWidget` 捕获播放；跨区新 chip 由 `_pendingFrostAnim`（`_applyDrop` 记录名称+方向）→ `_ZoneCard.frostAnim` → `_FoodChip.playFrostOnMount` 在 initState 播放；描边/投影/图标同步 Color.lerp 过渡。放入冷冻区"正常→冰冻"、移出"冰冻→解冻"。
- 修改文件：`code/apps/mobile/lib/features/fridge/fridge_page.dart`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人 `flutter run` 复测。

### RECO-001 升级：渐进式语义食材系统（ADR-0022）+ 清空菜谱数据

- 项目负责人按《解决方案.md》要求把推荐从"标准 ID + 别名词典"升级为"基础食材 + 属性规格 + 三值匹配"：精瘦肉=pork+精瘦、五花肉=pork+腹部+半肥半瘦、肉末=meat+绞碎；匹配方向不对称（库存更具体满足宽泛要求=YES，库存宽泛面对具体要求=MAYBE，基础/属性冲突=NO）；未收录名称只允许完全相同名称匹配。
- 新增 `domain/ingredient/ingredient_spec.dart`：属性分面枚举（cut/fatLevel/form/processing）、`IngredientSpec`、`IngredientMatchVerdict`、`matchIngredientSpec` 三值判定、`IngredientSpecRepository` 规格词典（基础食材+猪肉/鸡肉规格+通用肉末）、上下位关系表（meat⊃pork/beef/…）。
- `IngredientCanonicalizer` 升级：优先规格条目解析（matchType=spec），`isSameIngredient` 收紧为规格等价（猪肉≠五花肉）。
- 数据库 v6 迁移：`ingredients` 与 `inventory_batches` 增加规格列（base_concept_id/name、cut、fat_level、form、processing、spec_confidence、spec_source），迁移幂等（PRAGMA 检查缺失列）。
- 推荐引擎重构：按基础食材索引+上下位兼容候选、`_bestMatch` 取最优三值、分组新增"可能可以做"与"规格不符"、排序改为 缺失+冲突少→MAYBE少→无不足→临期多→比例高；`confirmedBases` 支持"视为可用"（仅本次会话）。
- 库存录入页渐进式规格：`suggestInventorySpec` 名称→候选规格 chip（不确定/精瘦肉/五花肉/…），可跳过；批次保存时落库规格（用户选择或本地规则回填）。
- 菜谱保存时规格解析落库（`RecipeLibraryUseCases._resolveIngredientSpec`）；草稿确认页未收录食材显示"种类待确认"轻量徽标（`isIngredientNameKnown`）。
- 推荐页 UI：新增"可能可以做"分组；卡片展示"待确认：精瘦肉 — 库存未确认是否为精瘦"+「视为可用」；"规格不符"原因展示。
- 已清空模拟器上菜谱数据（recipes/ingredients/recipe_steps/recipe_images/import_tasks/recipe_recent_views/cooking_* 等表 + 缓存封面图片），保留库存 6 批次、分类 2 与设置，供重新导入验证新解析链路。
- 产品文档 5.8.1/5.8.2 与 DECISIONS（ADR-0022）、RECO-001 验收文档同步更新；新增 canonicalizer/推荐三值匹配测试定义。未运行测试/构建/真机（ADR-0015）；等待项目负责人构建 Android 复测，iOS 未验证。

### RECO-001 修复：AI 导入调料误计缺失 + 库存规格未落库回退（项目负责人复测反馈）

- 复测问题：冰箱库存（瘦肉/豆干）匹配不到已添加的"香干炒肉"菜谱。定位两个根因：
  ① 菜谱把 水/花椒粉/糍粑辣椒/小米辣 等步骤调料解析成食材且不在常备名单 → 缺失 4+ 样 → 整个菜谱被 `missing > 4` 过滤，推荐列表消失。
  ② 库存批次规格未落库（旧构建/未选择规格）时，`_bestMatch` 直接用 `batch.spec`（全空）判定 → 即使名称可解析（瘦肉→pork+lean）也变成"规格未设置"MAYBE。
- 修复：`kStapleSeasonings` 扩展（水/清水/热水/花椒粉/辣椒面/小米辣/糍粑辣椒/五香粉/十三香/蒜末/姜末/白胡椒粉 等）；新增 `_batchEffectiveSpec`：落库规格优先、否则即时解析名称补全规格。
- 补充测试定义：调料不计缺失（香干炒肉只缺青椒）、规格未落库回退解析（瘦肉→瘦肉=YES）。未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### RECO-001 升级：食材家族与模糊匹配 + 菜谱食材要求强度（ADR-0023）

- 按项目负责人《解决方案.md》升级：青椒/辣椒只是实例，方案通用化——**精确匹配依赖标准概念，模糊匹配依赖食材家族和未知属性，替代判断结合菜谱上下文**。
- 新增 `IngredientFamily`（meat/capsicum/mushroom/fish/leafy_vegetable/cheese）与 `kBaseConceptFamilies` 家族映射；`IngredientProcessing` 增加 fresh/dried。
- 词典扩展家族条目：辣椒/青椒/柿子椒(新鲜)/尖椒/小米辣/干辣椒(干制)/彩椒、蘑菇/香菇/平菇/金针菇、鱼/鲈鱼/鲫鱼/草鱼、青菜/小白菜/菠菜/生菜、奶酪/马苏里拉；青椒从别名组移入规格条目（带新鲜属性）。
- `matchIngredientSpec` 升级（ADR-0023）：基础概念不同但**同一家族**且无明确属性冲突 → MAYBE（"同属 X 类，具体规格待确认"）；同一家族但有属性冲突（干辣椒=dried vs 青椒=fresh）→ NO；新增 `firstFacetConflict`。
- 菜谱食材要求强度：`IngredientImportance`（core 菜名核心 / required 必需 / optional 可选）；菜谱保存时按"名称在菜名中出现→core、可选标记→optional"本地解析；推荐按 optional 不计缺失。
- 产品文档 5.8.2、DECISIONS（ADR-0023）、RECO-001 验收文档（3.3 家族复测）同步更新；新增家族匹配/可选不计缺失测试定义。未运行测试/构建/真机（ADR-0015）；等待项目负责人构建 Android 复测，iOS 未验证。

### RECO-001 修复：家族匹配候选查找缺失导致 辣椒→青椒 匹配不到

- 复测问题：库存「辣椒」匹配不到菜谱「青椒」。根因：家族判定（`matchIngredientSpec` 的 MAYBE/NO）只在**候选批次内**执行，但候选查找 `_candidateBatches` 只收“base 相同 / 上下位兼容”，未把**同一家族**的库存（capsicum vs green_pepper）纳入候选 → 候选为空 → 青椒被判为缺失，家族分支从未执行。
- 修复：`_candidateBatches` 增加同一家族判断（`familyOf(stockBase) == familyOf(recipeBase)`），家族批次进入候选后由 `matchIngredientSpec` 判定 MAYBE（辣椒→青椒）或 NO（干辣椒→青椒，加工状态冲突）。
- 已补充的家族测试（辣椒→青椒 MAYBE / 干辣椒→青椒 NO）覆盖该链路。未运行测试/构建/真机（ADR-0015）；等待项目负责人复测。

### UI-002 视觉 1:1 复刻：主题级像素基建（ADR-0024）

- 项目负责人反馈：当前界面“与原型类似但非 1:1”，要求按 `design/prototypes/index.html`/`prototype.css`/`app.js` 复刻；原型有而实际没有的组件/界面按原型风格补齐。
- 本轮完成主题级基建（全局生效，页面逐层对齐后续轮次）：
  - `PixelCutClipper` 改为 CSS 精确阶梯缺角（lg 8px/2px、sm 4px/2px、xs 3px/3px，新增 `PixelCut` 常量档位）。
  - 新增共享组件：`PixelCutShape`（按钮/输入缺角 ShapeBorder）、`PixelDashedDivider`（虚线分隔）、`PixelSectionTitle`（绿色方块分区标题）、`PixelFloat`（steps 阶梯浮动动画）、`PixelTabBar`（等分 tab：选中绿底+深绿 inset 描边+顶部虚线，Key 与旧 NavigationDestination 兼容）。
  - 主题：FilledButton/OutlinedButton/FAB/输入框改为像素缺角 + inset 描边 + 墨色投影；Chip 平直化；scaffold 背景透明。
  - 全局背景：MaterialApp.builder 增加米白渐变 + 8px 圆点纹理（等效 CSS body）。
  - 底部导航替换为 `PixelTabBar`（app_shell）。
  - 空状态 `AppEmptyState` 升级为 CSS .state-box 风格：92px 大图标块 + 硬边阴影 + 浮动动画。
- 未运行测试/构建/真机（ADR-0015）；`flutter run` 后按 `tests/acceptance/UI-002-visual-1v1-2026-08-04.md` 逐页截图对比；等待项目负责人反馈逐页差异后继续逐层对齐。

### RECO-001 优化：食材统一标准 ID + 别名词典（ADR-0021）

- 项目负责人提供《解决方案.md》，要求按"本地标准食材 ID + 系统别名词典 + 匹配需确认 + 搜索/推荐/扣减统一标准化"优化推荐。
- 新增 `IngredientCanonicalizer` + `IngredientAliasRepository`（系统词典：番茄=西红柿=蕃茄、土豆=马铃薯、青椒=柿子椒、玉米=玉蜀黍=苞米、茄子=茄瓜、花生=落花生=长生果）；三层匹配：别名/精确 → 格式标准化（括号/全半角/简繁/数量拆分）→ 未知名称保留待确认；相近食材不默认等价（小番茄≠番茄等）。
- 推荐用例重构：统一标准 ID 匹配、缺 1/缺 2 按标准 ID 去重、数量状态区分（充足/不足/未知）、`strictSelected` 开关、匹配明细（explanation）与"库存不足：还需要 X"、排序（缺失少→无不足→已选命中多→临期多→比例高）。
- 推荐页：新增"仅使用已选食材"开关（默认关闭，已选偏好+冰箱补齐）；新增"库存不足"分组；卡片展示"西红柿 → 番茄（同义词匹配）"式解释与数量状态。
- 库存搜索接入同一标准化器：搜"西红柿"可命中"番茄"。
- Facade `recommendRecipesFromInventory` 支持 `strictSelected`。
- 测试定义已新增（未运行）：标准化器单元测试（别名/格式/相近不误配）与推荐用例新场景（同义词/去重/strictSelected/库存不足/数量未知）。
- 修改文件：新增 `domain/ingredient/ingredient_canonicalizer.dart`；修改 `inventory_use_cases.dart`、`inventory_batch.dart`、`ai_recipe_backend_facade.dart`、`fridge_recommendation_view.dart`、`fridge_page.dart` 及对应测试。未运行测试/构建（ADR-0015）；等待项目负责人 Android 复测。

### FRIDGE-002 / RECO-001 / FRIDGE-003 补强：搜索、删除、推荐自动重算、扣减单位提示

- 项目负责人复测反馈 4 点：①推荐部分选择食材后无法推荐；②烹饪结束自动消耗但单位与实际不同步；③冰箱无法删除；④冰箱无法搜索。
- 已修复：①推荐视图选择/快捷选择变化后自动重算（不再只依赖 CTA），推荐完成与失败均输出 `[AIRecipe][Fridge]` 诊断日志，空结果提示改为“无正式菜谱或食材名称不匹配”的明确说明；②扣减确认以库存批次单位为准（输入框后缀显示批次单位），菜谱用量单位与库存单位不一致时给出“请按库存单位确认数量”提示；③批次展开底部面板新增“删除批次”操作（二次确认，调 `deleteInventoryBatch`）；④库存页新增食材名称搜索框（与筛选叠加过滤，可清空）。
- 修改文件：`fridge_recommendation_view.dart`、`inventory_deduction_page.dart`、`fridge_page.dart`。未运行测试/构建（ADR-0015）；等待项目负责人 Android 复测。

### FRIDGE-002 / RECO-001 / FRIDGE-003 实现：冰箱与按食材推荐首版

- 项目负责人要求：按 `design/UI_HANDOFF.md`（UI-014/015/016）与产品 5.8 / `design/flows/FRIDGE_AND_RECOMMENDATION_FLOW.md` 用 Flutter 复刻冰箱与推荐功能并实现。
- 领域与存储：`InventoryBatch`/`InventoryChange`/`InventorySummary`/`AggregatedInventoryItem` 领域模型；SQLite v5 迁移 `inventory_batches`+`inventory_changes`；`SqliteInventoryRepository`；`InventoryLibraryUseCases`（新增/更新/用完/丢弃/删除/摘要/聚合/扣减）+ `InventoryRecommendationUseCases`（确定性离线匹配：可选食材与常备调味品不计缺失、已过期批次不匹配、数量未知提示需确认、排序 缺失少→临期多→匹配比例高）。
- Facade：`listInventoryBatches/loadInventorySummary/loadAggregatedInventory/create/update/useUp/discard/deleteInventoryBatch/recommendRecipesFromInventory/confirmInventoryConsumption`；组合根注册。
- UI：底部导航改四栏「首页/菜谱库/冰箱/我的」；冰箱页轻拟物分区库存（摘要、临期提醒、8 项筛选、四分区聚合展开批次、五种状态徽标、空态、FAB）；批次新增/编辑页（存放位置跟随分区、数量为空=未知、同名提示）；推荐视图（分区点选、快捷选择全部/临期优先/冷藏/冷冻/清空、CTA 计数、已具备/缺1/缺2/优先清库存/更多缺失折叠、已选命中/冰箱已有·可补选/缺失/临期标记）；烹饪完成自动进入扣减确认页（预计消耗、默认到期更早批次、逐项勾选/改量/换批次、确认才更新并记录 InventoryChange、不做负库存）。
- 测试定义已新增（未运行）：库存用例（创建/摘要/聚合/状态/扣减）、推荐匹配（已选/未选/缺失/可选与常备/过期不匹配）、FridgePage UI（空态/分区显示/新增保存/推荐）。
- 验收文档：`tests/acceptance/FRIDGE-002-inventory-batches-2026-08-04.md`、`RECO-001-recommendation-2026-08-04.md`、`FRIDGE-003-deduction-2026-08-04.md`。缺失项加入购物清单因购物清单模块未实现，本版仅展示缺失。未运行测试/构建（ADR-0015）；iOS 未验证。

### FRIDGE-001 补充规划：冰箱分区 UI 与选择食材推荐

- 项目负责人补充冰箱 UI 方向：库存页应模仿真实冰箱的冷藏区、冷冻区、常温区和其他区，使用轻拟物分区、层架/抽屉和食材 chip / 卡片表达。
- 推荐流程调整为先由用户选择本次想优先使用的库存食材，再匹配本地正式菜谱；支持全部、临期和按分区快捷选择。
- 推荐结果补充分组和卡片规则：已具备 / 现在就能做、缺 1 样、缺 2 样、优先清库存；卡片区分已选命中、冰箱已有但未选择和缺失项，例如只选西红柿也可推荐西红柿炒鸡蛋。
- 下厨后的“自动消耗”统一定义为自动生成预计消耗建议，未确认不得扣减；用户可逐项调整、换批次、取消或跳过。
- 已同步产品需求、用户故事、UI 交付、设计流程、ADR-0020、BACKLOG、CURRENT 和文档走查方法；本轮未修改业务代码，未执行 Flutter/Dart 测试、静态分析、构建、模拟器或真机测试；`FRIDGE-001` 仍为 `VERIFY`，等待项目负责人文档走查。

## 2026-08-03

### FRIDGE-001 规划：冰箱与按食材推荐菜谱

- 一级导航确定为“首页 / 菜谱库 / 冰箱 / 我的”；添加/导入继续使用全局 FAB，购物清单作为二级页面，不增加第五个 Tab。
- 冰箱使用“库存 / 推荐”二级结构；首版库存按批次记录名称、可选数量/单位、分类、存放位置、可选购买/到期日期和备注，支持同名多批次、临期/过期/日期未知/数量未知和用完/丢弃。
- 本地推荐只读取正式菜谱，离线按“现在就能做 / 还差 1～2 样 / 优先清库存”分组；排序优先缺失更少、临期命中更多、匹配比例更高；数量不可判断时明确要求用户确认。
- 缺失项可加入购物清单；下厨后展示预计消耗，由用户逐项确认、调整或取消后才扣减库存；同名多批次默认优先到期更早批次但可修改。
- “用现有食材生成新菜谱”后置为独立 AI 入口，仅在 LLM Provider 可用时开放，结果进入草稿确认，不与本地推荐混排。
- 已同步产品需求、用户故事、UI 交付、设计流程、任务拆分、ADR-0020、R-019、SPK-008 和文档走查方法；新增 FRIDGE-002、RECO-001、FRIDGE-003、RECO-002、DESIGN-005 后续任务。
- 本轮未修改业务代码，未执行 Flutter/Dart 测试、静态分析、构建、模拟器或真机测试；`FRIDGE-001` 进入 `VERIFY`，等待项目负责人文档走查。

### IMPORT-009 实现：导入体验补强（快速导入分流 + 批量导入 + 未完成导入列表 + 进度条/正文去重修复）

- 项目负责人反馈 4 点：①解析时进度条进度为 0 但百分比数字正常；②解析结果正文与简介内容相同；③快速导入任何选项都进"添加菜谱"页，希望支持链接批量导入与未完成导入列表化管理（一键取消/删除）；④快速导入按钮与实际选项无关。
- 已实现：①`PixelProgressBar` 填充条缺 `heightFactor` 导致高度 0，已修；②WebView 提取 description==bodyText 时去重（小红书 desc 即正文）；③快速导入 4 按钮分流：粘贴链接→添加页、剪贴板→读系统剪贴板预填、拍照选图→本地 OCR 图片导入（新任务 `createLocalImageImportTask`，占位链接 `https://local-image/capture`）、手动创建→直接打开编辑器；④批量导入（多链接一次创建多个任务，≥2 个成功后自动进入任务列表）；⑤新增 `ImportTasksPage` 未完成导入列表（排队/解析中/待确认/失败/已取消，单个取消/删除、一键清空已结束，二次确认），首页"有 N 个未完成导入"入口改打开列表；⑥Facade 新增 `deleteImportTask(s)`（仅失败/已取消）与 `createLocalImageImportTask`，`runImportWithLocalImage` 放宽允许 queued。
- 修改/新增文件：`pixel_ui.dart`、`webview_import_content_adapter.dart`、`ai_recipe_backend_facade.dart`、`home_page.dart`、`app_shell.dart`、`add_recipe_page.dart`、`import_progress_page.dart`（initialImage）、新增 `import_tasks_page.dart`；测试定义更新（批量/空链接/任务列表取消删除清空/HomePage 新参数）。
- 验收文档：`tests/acceptance/IMPORT-009-import-experience-2026-08-03.md`。未运行测试/构建（ADR-0015）；等待项目负责人构建 Android 复测。

### IMPORT-008 重构：按高级工程师方向落地 ADR-0019（阶段状态机 + 图片顶层导航取图）

- 项目负责人提交 bug 交接后，高级工程师给出修复方向（`修复方案.md`）：①"网页加载超时"是任务编排与超时定义问题——单一 45s 覆盖导航/DOM 提取/30 图并发下载/Base64/过桥/写盘，无法定位实际阶段；②图片 403 是网络栈问题——继续坚持图片请求由 WebView/Chromium 发起，但**不用 shouldInterceptRequest 抓响应体**（返回 null 拿不到字节、返回 WebResourceResponse 则回到被拒的应用网络栈）；推荐"页面提取文本+图片 URL → 停止加载 → 每张图片作为顶层页面打开 → 同源读取字节 → 单张回传立即写盘"，顶层同源读取需真机 Spike 验证。
- 已记录 ADR-0019（状态机、结果分类、逐张顶层导航取图、移动 UA/正常视口、安全桥、requestId 隔离、小红书不回退直连、隐私与登录态边界）与 SPK-007 Spike（`research/spikes/SPK-007-top-level-image-nav.md`）。
- Kotlin `WebViewFetchMethodHandler` 重构：显式阶段状态机 `NAVIGATING(≤18s) → WAITING_CONTENT(≤12s，DOM 探测) → EXTRACTING(≤5s) → FETCHING_IMAGES(总≤25s/单张≤9s)`；`onPageCommitVisible` 替代 `onPageFinished` 作为主框架提交信号；图片逐张顶层导航取图（路径 A 同源 `fetch(location.href)` 原始字节，路径 B Canvas 导出兜底，≤9 张、逐张写盘、失败继续下一张、12 候选）；结果分类（导航超时/网络/登录墙/风控/无内容/配图部分失败）；请求隔离与取消清理；默认移动 UA + 360×800 视口（decorView 最底层被 Flutter 覆盖）；移除对第三方页面的 `addJavascriptInterface`；日志带 requestId/阶段/耗时且脱敏（不记录完整签名 URL）。
- Dart `WebViewImportContentAdapter`：小红书/抖音平台不再回退远程直连（ADR-0019，避免重复 403 与日志混淆），web 平台保留直连快速路径；测试定义更新（web 回退 / xiaohongshu 不回退 / 错误分类）。
- 验收文档更新为分阶段日志核对（`tests/acceptance/IMPORT-008-webview-import-2026-08-03.md`）。等待项目负责人构建真机按 SPK-007 复测：**正文提取成功时图片失败只能产生"配图部分失败"，不得整体变成"网页加载超时"**。未运行测试/构建（ADR-0015）；iOS 未验证。

### IMPORT-008 补强：浏览器会话取图 403 根因修复（混合内容/CORS/Promise 回调）

- 项目负责人真机复测：WebView 已能提取小红书文本与图片地址（`!nd_dft_wlteh_webp_3` 格式），但配图仍全部 403；Logcat 无 `WebViewFetch` 诊断日志，只有 Dart 侧 `[AIRecipe][RemoteImage]` 403——`fetched.images` 为空，Adapter 回退远程直连。
- 根因（修复前）：① https 小红书页面 JS `fetch` 提取出的 `http://sns-webpic-qc.xhscdn.com/...` 图片被 Chromium 混合内容策略拦截（WebView 默认 `MIXED_CONTENT_NEVER_ALLOW`）；② `fetch(url, {credentials: 'include'})` 跨域时，CDN 返回 `Access-Control-Allow-Origin: *` 会按 CORS 规范被浏览器拒绝（凭证模式必须返回精确源）；③ `evaluateJavascript` 对返回 Promise 的脚本不保证等待，可能拿到空对象导致图片列表为空。
- 修复：JS 下载图片前把 `http://` 统一升级为 `https://`（小红书 CDN 支持 https，已验证）；fetch 不再携带 credentials；改为 `addJavascriptInterface` 注入 `AiRecipeBridge`，页面 JS 下载完成后异步回调 Kotlin 写文件（不依赖 evaluateJavascript 等待 Promise）。
- 增强诊断：`AiRecipeBridge.onImagesDownloaded` 记录回调长度与预览；WebChromeClient 把页面 console（WARN/INFO 下载失败原因）透传到 Logcat；Dart Adapter 回退远程直连前打印 `[AIRecipe][WebView] 浏览器会话未下载成功图片`。
- 修改文件：`WebViewFetchMethodHandler.kt`（JS 脚本/桥/诊断）、`webview_import_content_adapter.dart`（回退诊断日志）。验收文档已更新复测重点（`tests/acceptance/IMPORT-008-webview-import-2026-08-03.md`）。等待项目负责人重新 `flutter run` 后抓取 `WebViewFetch` 标签日志复测。

### IMPORT-008 实现：浏览器内核（WebView）链接导入（Android 首版，DOING）

- Android 首版已实现：`ImportSourcePlatform` 新增 `web`，未知域名归为 web；Kotlin `WebViewFetchMethodHandler`（通道 `ai_recipe/webview_fetch`）后台隐藏 WebView 加载任意网页并注入 JS 从 DOM 提取标题/正文/作者/图片地址，按登录墙/验证码/网络/超时/空内容分类返回；`MainActivity` 注册通道。
- Dart `WebViewContentFetcher` + `WebViewImportContentAdapter` 映射 `ImportContent`（相对路径图片按页面地址解析），组合根为 xiaohongshu/douyin/web 注册 WebView Adapter 替换直连 Adapter，移除 `importTransport` 参数；进度页/确认页/详情页平台标签支持 web。
- 已更新测试定义（未运行）：`ImportSourceLink.parse` 未知域名归为 web；WebView Adapter 成功映射、平台/URL 拒绝、错误分类、空内容失败。
- 验收文档：`tests/acceptance/IMPORT-008-webview-import-2026-08-03.md`。等待项目负责人构建（`flutter run` 真机）复测小红书/抖音/普通网页、登录墙与断网降级、配图下载保存。Codex 沙箱无法构建验证；iOS（WKWebView）暂缓。

### IMPORT-008 立项：链接导入改用内置浏览器内核（WebView）抓取（通用任意网页）

- 项目负责人确认方向：直连下载/解析持续受 CDN 403 与平台风控影响（真机浏览器可打开但 App 请求 403），改为内置浏览器环境（WebView）加载网页并在浏览器环境中保存网页文本与图片，更符合平台访问方式，并为后续其他平台预留通用能力。
- 已确认决策：全面替换直连 Adapter；后台隐藏加载（不引入可见浏览器 UI）；保存网页真实文本与图片（DOM 提取，不做截图 OCR）；架构按通用任意 URL 网页设计。
- 已落文档：产品文档 5.3 更新为“链接导入（浏览器内核抓取，通用网页）”；`ADR-0018` 记录决策、影响与验证方式；`BACKLOG` 新增 `IMPORT-008`（TODO，待验收定义）。
- 待办：IMPORT-008 验收定义与 Android WebView 平台通道 + Dart Adapter 实现；IMPORT-006/007 相关验证并入 WebView 抓取后复测；iOS（WKWebView）暂缓。

### IMPORT-006 补强七：LLM Schema 校验失败诊断日志

- 项目负责人真机复测：20:33 起 `cover_image` 远程 URL 残留已消失（`None`），配图相关修复生效；20:42 新任务在 LLM 生成阶段失败，`schemaInvalid`（进度 65%，不可重试），同一条链接此前多次成功。
- 修复：Schema 校验失败时输出具体校验原因与截断的 AI 响应（`[AIRecipe][Schema] AI JSON 校验失败：<原因> 响应片段=<前 2000 字符>`，脱敏），用于定位 LLM 输出是字段缺失、多余还是格式问题。
- Codex 沙箱构建仍卡死；构建与 Android 真机重测由项目负责人执行。

### IMPORT-006 补强六：真机 403 实锤与拒绝原因诊断

- 项目负责人在真机（华为 DBR-W10，20:00 自建 debug APK）复测：导入成功、草稿生成（`needsReview`），但 `recipe_images` 表为空、草稿 `cover_image` 残留远程 http URL。
- 真机实时 Logcat 确认：全部 6 张配图 `status=403`（`OcrProviderException(invalidResponse status=403)`）。Windows 同网络下相同 URL 与请求头均为 `200`，真机 403 的差异来源待确认。
- 新增诊断：下载客户端在非 200 时读取并输出拒绝响应体前缀（`reason=`，≤512 字节，仅 Logcat），并输出 DNS 解析 IP 与实际连接 IP（`[AIRecipe][RemoteImage]`）。
- 修复：`coverImage` 不再提前写入远程 URL（下载成功前为 null，失败不留远程地址）；残缺图片 URL（`ci.xiaohongshu.com/?imageMogr2/...`）过滤提升到最终 `imageUrls` 层（覆盖 og:image/JSON-LD 来源）。
- 修复编译错误：下载客户端补充 `package:flutter/foundation.dart`（`debugPrint`）。
- **根因确认（20:33 真机复测）**：残缺 URL 已过滤（6→5 张）；DNS 解析到大量 IPv6 在前（如 `2408:8756:2cf6:f014:41::`），客户端此前固定连接解析列表第一个地址（IPv6），CDN IPv6 边缘节点对非浏览器请求返回 403（`reason=` 空）；真机浏览器可正常打开图片。Windows 强制连接同一 IPv6 节点为 `200`，IPv4 节点（58.251.127.109 等）亦为 `200`。
- **修复（地址级故障转移）**：`PinnedHttpsOcrImageDownloadClient._request` 改为 IPv4 优先排序，并对每个解析地址执行独立连接+请求，连接失败或应用层被拒（如 403）时依次尝试下一个地址，全部失败抛最后错误；成功连接地址写入 Logcat。已新增测试定义（未运行）：IPv4 优先、403 故障转移。
- Codex 沙箱构建仍卡死；构建与 Android 真机重测由项目负责人执行。

### IMPORT-006 补强五：配图下载根因实锤（CDN 可访问性）与状态码诊断日志

- 项目负责人复测：配图仍全部未获取（`invalidResponse`），但浏览器打开链接有图片。
- 授权 debug 取证（Logcat、数据库、curl、Dart 栈复现）：
  - 从 App 数据库提取完整图片 URL，确认无截断隐藏的签名参数。
  - Windows（与模拟器同一出口网络）：curl 无头/带浏览器 UA/带小红书 Referer/http/https/强制 IPv4 与不同 CDN 节点均返回 `200`；用 App 同款 Dart `SecureSocket`（BoringSSL 栈）复刻请求同样 `200`。证明 CDN 本身允许无 Cookie 下载，App 下载请求构造无问题。
  - 模拟器：网络状态为 `PARTIAL_CONNECTIVITY`（部分连通）；模拟器内 Chrome 打开 baidu/picsum/小红书图片均无法确认加载成功；toybox netcat 直连 CDN 端口收 0 字节。模拟器环境访问该 CDN 存在网络层问题，是当前失败的主因候选。
  - 结论：根因大概率是模拟器网络环境（而非 App 逻辑或 CDN 防盗链）；真机（真实运营商网络）应与 Windows 一致可下载。最终确认依赖 App 侧真实 HTTP 状态码。
- 修改：`LlmRecipeGenerationProcessor` 配图失败日志输出真实 `statusCode`（`OcrProviderException.status`），URL 截断 160→320；`PublicPageMetadataParser` 过滤 `ci.xiaohongshu.com/?imageMogr2/...` 这类缺图片 ID 的残缺 URL（原本必然下载失败）。
- Codex 环境 `flutter build apk --debug` 卡死无输出（受限沙箱），未完成构建与测试；构建与 Android 重测由项目负责人执行。

### IMPORT-006 补强四：图片下载防盗链适配（浏览器 UA + 来源 Referer）

- 项目负责人复测：分组功能 OK；配图 http→https 升级后错误从 `ArgumentError` 变为 `OcrProviderException(invalidResponse)`，但 6 张仍全部下载失败。
- Logcat 定位：`invalidResponse` 对应下载客户端非 200 状态（4xx），小红书图片 CDN（sns-webpic-qc.xhscdn.com、ci.xiaohongshu.com）对无浏览器 UA/来源 Referer 的裸请求执行防盗链拒绝。
- 修复：`PinnedHttpsOcrImageDownloadClient` 请求头改为浏览器 UA，并按图片域名派生来源 Referer（xhscdn/xiaohongshu → 小红书，douyin/iesdouyin → 抖音），其余域名不发送 Referer；同时保留 HTTPS-only、DNS 公网校验、逐跳重定向复检等全部安全边界。
- 配图下载失败调试日志的 URL 截断放宽到 160 字符，便于继续定位具体图片。

### IMPORT-006 补强三：分组可增删、标题即时刷新、同组归并；配图失败根因定位（http→https）

- 项目负责人反馈：分组已可修改但不能新增/删除；点 chip 后分组标题需滚动才刷新；同分组会出现两个标题；配图仍获取不到。
- 分组级操作：编辑页与确认页的分组标题行新增"删除该分组"按钮（清空该组全部食材分组）；分组输入框提示"输入新名称可创建新分组"，任意新名称即新增分组。
- 即时刷新：食材卡的分组输入框与快捷 chip 变化时回调父级无条件重建（`onGroupChanged`/`onChanged`），分组标题立即更新，不再需要滚动。
- 同组归并：编辑页初始化与确认页加载时按分组稳定排序（同组相邻、组内保持原顺序、未分组置后），避免同一分组出现两个标题。
- 根因定位（项目负责人授权查 Logcat）：`[AIRecipe][CoverImage]` 显示小红书配图 URL 为 `http://sns-webpic-qc.xhscdn.com/...`，被远程图片安全暂存层（HTTPS-only）以 `ArgumentError` 拒绝，6 张全部失败。修复：`LlmRecipeGenerationProcessor` 与 `OcrEnrichingImportContentProcessor` 下载/识别前把 http 图片地址统一升级为 https；调试日志补充异常 kind 便于继续定位。
- 已新增测试定义（未运行）：http 配图 URL 升级 https。

### IMPORT-006 补强二：分组可添加/修改、配图获取失败反馈

- 项目负责人反馈：分组已能显示和拖动，但编辑时分组不能添加/修改；配图仍获取不到且没有任何提示。
- 编辑页与草稿确认页食材卡片的"分组"输入框从展开区提升为常显，并新增常用分组快捷 chip（主料/辅料/腌料/调料/酱汁），点击即填入、也可输入自定义分组；确认页 `_IngredientEditor` 的 `groupName` 改为可编辑控制器。
- `LlmRecipeGenerationProcessor` 配图下载失败时通过 `debugPrint` 输出脱敏调试摘要（`[AIRecipe][CoverImage]`：索引、截断 URL、错误类型），不进入用户可见错误；全部失败时输出汇总行。
- 草稿确认页新增条件提示：会话原文含图片但草稿无本地封面时显示"笔记配图暂未获取（原文包含图片但下载未成功，保存后可在编辑页手动添加封面）"。
- 已新增测试定义（未运行）：确认页配图失败提示、确认页分组 chip 编辑并保存、编辑页分组常显/chip/保存。

### IMPORT-006 补强：草稿确认页展示配图、食材分组展示、编辑页拖拽排序

- 项目负责人反馈：配图没有在草稿确认页展示、AI 识别的食材分组（主料/腌料/调料）编辑时混在一起、食材/步骤不能拖动改顺序。
- 草稿确认页 `_ReviewIntro` 封面区改为 `_DraftCover`：有配图直接显示首图（`Image.file`），多图右下角显示“N 张”徽标，无图回退像素插画；同时修复确认页保存时 `RecipeDraftInput` 未传 `images` 导致配图在保存后被清空的 Bug。
- 草稿确认页食材列表按 `groupName` 分段展示（新增 `_ReviewGroupHeader`），主料/调料等分组不再混在一起。
- 编辑页食材与步骤列表改为 `ReorderableListView`（长按拖动手柄排序），分组连续展示（新增 `_IngredientGroupHeader`）；保留原有上移/下移按钮。
- 已新增测试定义（未运行）：确认页配图展示与保存保留、确认页分组标题、编辑页分组与拖拽列表渲染。

### IMPORT-006 链接导入自动获取公开内容配图作为菜谱封面

- 需求：从链接添加时，如果小红书/抖音笔记有图片，应自动获取这些图片作为菜谱封面。
- 新增领域接口 `RecipeCoverImageStorer`（`copyIn`/`deleteFile`/`deleteContainer`），`DeviceRecipeCoverImageStager` 实现。
- `LlmRecipeGenerationProcessor` 生成草稿时，把 `ImportContent.media` 中带远程地址的图片经 OCR-002 安全暂存（`SecureRemoteOcrImageStager`）下载并校验后复制到 `recipe_covers/<recipeId>/<index>.<ext>`，写入草稿 `images`/`coverImage`（首图即封面），最多 9 张；单张失败 best-effort 跳过，全部失败草稿仍生成，不阻塞导入。
- `SafeImportRecipeDraftDiscarder` 删除草稿时同步清理该草稿封面目录，避免孤儿文件。
- 组合根与 `DeviceImportTaskRunnerFactory` 装配：链接导入（含 IMPORT-007 自动 OCR 路径）的 LLM 处理器注入封面存储与远程暂存。
- 已新增测试定义（未运行）：处理器封面落盘/下载失败降级/无图跳过，Facade 集成草稿本地封面。
- 任务卡 `IMPORT-006` 从 `TODO` 进入 `VERIFY`；产品文档 5.4.1 更新；验收方法 `tests/acceptance/IMPORT-006-remote-covers-2026-08-03.md`。等待项目负责人 Android 复测；iOS 未验证。

### IMPORT-007 链接导入启用本地 OCR：图片与正文整合后交给 AI

- 需求：小红书/抖音图文笔记既有图片又有文字，导入时要把图片 OCR 成文字与正文整合，统一交给 AI 生成菜谱，而不是丢弃图片信息。
- `AiRecipeBackendFacade.runImportTask` / `dispatchPendingImports` 执行计划参数改为可空：为 null 时读取 `AppCapability.localOcr` 能力快照自动解析——OCR 就绪则 `ocr: local`，未就绪或快照不可读则回退纯文本路径（`ocr: disabled`）。
- 图文整合复用既有流水线：`OcrEnrichingImportContentProcessor` + `RemoteStagingOcrProvider`（OCR-002 远程安全暂存 + 本地 OCR），OCR 文本片段与页面正文片段按顺序合并为同一批 `textFragments` 证据，统一交给 `LlmRecipeGenerationProcessor`；无图内容不触发 OCR。
- 降级语义：OCR 未安装时，有正文的图文内容仍可纯文本生成；纯图片内容提示“需要先完成图片文字识别”并引导安装 OCR。
- OCR 链路错误文案中文化：`PlatformOcrProvider`、`OcrEnrichingImportContentProcessor`（固定中文映射）、`RemoteStagingOcrProvider`、`SecureRemoteOcrImageStager` 的用户可见错误全部改为稳定中文，不再透传底层英文。
- 已新增测试定义（未运行）：Facade 自动启用/OCR 未安装降级/纯图片失败提示/无图不触发 OCR，OCR 装饰器稳定中文错误映射。
- 任务卡 `IMPORT-007` 进入 `VERIFY`；新增 `ADR-0017`；产品文档 5.3.3 新增“图文内容的自动整合（本地 OCR）”；验收方法 `tests/acceptance/IMPORT-007-link-import-ocr-2026-08-03.md`。等待项目负责人 Android 复测；iOS 未验证。

## 2026-08-02

### UI-001 界面文案全中文化收尾

- 按项目负责人要求移除界面英文眉题/徽标，全部改为中文：首页日期由 `SATURDAY 08/01` 改为动态中文日期（如“8月2日 周六”），`QUICK IMPORT · 快速导入`、`游客 · GUEST` 等改为纯中文。
- “我的”页移除显眼的“游客模式 · 本地优先”横幅描述，仅保留在游客身份徽标内（`游客 · 本地优先`），不再占据页面主体。
- 中文化范围：首页、我的、菜谱库、回收站、添加菜谱、导入进度、草稿确认、菜谱详情、菜谱编辑、LLM/OCR/隐私设置等页面的 eyebrow 眉题与 PixelBadge 徽标（含 `MY RECIPE ARCHIVE`、`RECIPE DETAIL`、`COVER IMAGES`、`INGREDIENTS`、`STEPS`、`SOURCE`、`API/PLUGIN/LOCAL/READY/CHECK/OFF` 等）。
- 全局扫描确认 UI 层无大写英文界面文本残留；IDE 只读诊断无错误。未运行测试、分析器或构建（`ADR-0015`）。

### IMPORT-005 补强：修复收藏清空封面、支持“设为封面”、列表页显示封面

- 修复 Bug：`setRecipeFavorite` 使用的 `_copyRecipe` 未携带 `images`，点击收藏后菜谱多图被清空、详情页轮播消失；已补传 `images`。
- 编辑页封面区新增“设为封面”：非首图显示“设为封面”按钮，点击后移到列表首位（首图即封面，`coverImage` 同步为第一张）。
- 首页/菜谱库 `RecipeCard`（列表与网格两种布局）有封面时显示真实首图，无图回退原像素图标。
- IDE 只读诊断无错误；未运行测试、分析器、构建或真实相册操作（`ADR-0015`）。等待项目负责人复测。

### IMPORT-005 菜谱多封面图与详情页轮播已实现并进入 Android 验证

- 数据层：`Recipe.images`（多图本地路径）；SQLite 升级到 v4，新增 `recipe_images` 表（外键级联删除）；Repository 读写完成。
- 存储：新增 `DeviceRecipeCoverImageStager`，相册图片复制到应用文档私有目录 `recipe_covers/<containerId>/<index>.<ext>`，校验空文件/20MB/扩展名白名单/容器 ID 防注入，提供单文件与整组清理。
- Facade：新增 `stageCoverImages` / `deleteCoverImage`；编辑页新增“封面图片”分区（`ImportImagePicker.pickMultipleImages` 多选、缩略图、首图“封面”徽标、逐张删除并清理文件）。
- 详情页：`_RecipeHero` 有图时 PageView 轮播 + 指示点，无图回退原像素插画；菜谱副本不复制封面文件（避免共享文件误删）。
- 新增测试定义：编辑页封面区空态/已有图渲染、stager 复制/校验/清理；未运行测试、分析器、构建或真实相册操作。
- 产品文档 5.4.1 新增“封面图”小节；任务卡 `IMPORT-005` 进入 `VERIFY`，导入图文自动带多图另立 `IMPORT-006`（TODO），等待项目负责人 Android 复测；iOS 未验证。

### IMPORT-004 待确认草稿重新生成已实现并进入 Android 验证

- 草稿确认页新增“重新生成”卡片与按钮：二次确认、busy 防重复、“正在重新生成…”。
- `AiRecipeBackendFacade.regenerateImportDraft` 复用会话原文证据，经 `ImportTaskRunner.regenerateWithContent` 重新执行 LLM Processor；不重新抓取、不重新 OCR/ASR。
- 新增领域方法 `ImportTask.reassignResultRecipe` 与 use case `ReassignImportTaskRecipe`：成功时任务 `resultRecipeId` 指向新草稿（保持 `needsReview`、`localVersion` 递增），旧草稿走安全丢弃器 best-effort 清理。
- 失败时任务保持 `needsReview`、旧草稿保留，返回稳定脱敏错误；无会话证据（重启后）时按钮禁用并提示“原始内容已过期，请重新导入”。
- 新增测试定义：Runner（成功替换/非待确认拒绝/失败保留）、Widget（禁用态/确认流程与 LLM 未配置错误）；未运行测试、分析器、构建或真实请求。
- 产品文档新增 5.3.9，任务卡 `IMPORT-004` 进入 `VERIFY`，等待项目负责人 Android 复测；iOS 未验证。

### BUG-003 根因确认：请求被重定向到 /404 安全验证页；新增 /404 识别

- 项目负责人回传调试摘要：`finalPath=/404/sec_AkEqEBfZ`、`status=200`、`ogTitle=false`、`ogImage=false`、`ldjson=0`、`title=小红书`。确认真实请求被小红书安全机制重定向到 `/404/` 安全验证页（`sec_` 风控令牌），并非解析器缺陷。
- 新增 `_throwForSecurityOrNotFound`：`resolvedUri.path` 为 `/404` 或 `/404/...` 时映射为可重试 `networkUnavailable`，文案“平台未返回笔记内容（可能正在执行安全验证，或笔记已失效）…”；检测在判空之前执行，避免 404 壳页被误判为“已获取目标页”。
- 调试摘要补充 `redirect` 重定向计数；调试信息继续仅输出控制台/Logcat，不进入用户可见错误消息。
- 新增测试定义：`/404/sec_` 页映射为可重试 `networkUnavailable`；未运行测试、分析器、构建或真实网络请求。
- `BUG-003` 保持 `VERIFY`，等待项目负责人复测 `/404` 识别文案与平台放行情况；iOS 未验证。

### BUG-003 修复后首测进入“含目标 ID 但无法提取”分支；调试摘要改为仅控制台输出

- 项目负责人安装 `ADR-0016` 修复版后复测：失败文案变为“已获取到该笔记页面，但暂时无法提取有效内容。请稍后重试，或使用“粘贴正文”等方式继续整理。”（尝试 1/3 · 不可重试）。
- 该结果确认真实请求返回了包含目标笔记 ID 的页面，但 `PublicPageMetadataParser` 未提取出任何文本或媒体；排除了“返回推荐 feed 页”假设，根因收窄到解析器对真实页面结构（`__INITIAL_STATE__`/OG/JSON-LD）的字段提取。
- 判空失败时通过 `debugPrint` 向控制台/Logcat 输出一行脱敏调试摘要（`finalHost`、`finalPath` 截断、HTTP 状态、content-type、响应大小、`__INITIAL_STATE__` 存在性、`noteData` 次数、`meta`/`ogTitle`/`ogImage`/`ldjson`、页面 `<title>` 前 24 字符、`targetId`、`hasTarget`）；调试信息不进入用户可见错误消息，也不包含完整正文、Cookie、Authorization、访问令牌或完整查询参数。
- 更新 Adapter 测试定义（错误消息保持纯中文、不泄漏调试文本与正文片段）；未运行测试、分析器、构建或真实网络请求。
- `BUG-003` 保持 `VERIFY`，等待项目负责人回传 Logcat 中 `[AIRecipe][PublicContentAdapter] no usable content:` 行以继续定位解析器；iOS 未验证。

### BUG-003 公开内容“无可用内容”分类修复；BUG-005 确认关闭

- 项目负责人复测确认 `BUG-005` 完整通过（旧 failed 任务可“结束此导入”→“正在结束…”→“解析已取消”，未完成数量 `6 → 5`，强停重启后保持）；该任务保持 `DONE`。
- `BUG-003` 新失败路径已定位：失败不再发生在 LLM 65% Schema，而是 `PublicPageImportContentAdapter.fetch` 的“无文本且无媒体”判空分支；原错误 `The public page did not expose usable text or media.` 对用户不可操作。
- 研究确认：无完整分享参数（`xsec_token`）的 `explore` 链接被平台返回推荐 feed 页，正文不含目标笔记 ID；解析器合法判空。
- 按 `ADR-0016` 实施修复：判空时按响应是否包含目标笔记 ID 分类——包含则提示“已获取到该笔记页面，但暂时无法提取有效内容”（`invalidPayload`，不可重试）；不包含则提示“未获取到目标笔记内容。链接可能已失效、需要登录，或平台临时限制了访问”（`contentUnavailable`，可重试）。
- 扩展页面状态标记：登录墙、内容不存在/已删除、风控/限流（`captcha`、安全验证、访问过于频繁等）分别映射 `authorizationRequired` / `contentUnavailable` / `networkUnavailable`（可重试）。
- 更新 Adapter 测试定义（无内容分类、目标 ID 存在、风控页）与产品文档 5.3.7 错误文案要求；未运行测试、分析器、构建或真实网络请求。
- `BUG-003` 返回 `VERIFY`，等待项目负责人 Android 复测新文案与阶段推进；iOS 未验证。

### BUG-005 Android 验收通过；BUG-003 新失败路径继续修复

- 项目负责人确认 `BUG-005` 完整通过：原 failed 任务显示“结束此导入”，点击后显示“正在结束…”且不可重复点击，最终为“解析已取消”；首页未完成数量 `6 → 5`，强停重启后仍不计入未完成。
- `BUG-005` 更新为 `DONE`，iOS 未验证。
- 新建的小红书任务进入公开内容获取和结构化生成，并离开原 `65%`，但未进入待确认草稿；截图显示 `The public page did not expose usable text or media.`，尝试 `1/3` 且不可重试。
- `BUG-003` 从 `VERIFY` 返回 `DOING`，根因方向调整为公开内容 Adapter 可用内容判定、阶段推进与错误映射。
- 截图已归档到 `tests/acceptance/artifacts/BUG-003-2026-08-02/public-page-no-usable-content.png`；未保存 Key、Cookie、Authorization、完整页面正文、Prompt 或模型响应。


### BUG-003 响应兼容加固与 BUG-005 失败任务收尾进入 Android 验证

- 最新 Android 反馈确认 LLM 设置连接正常，真实小红书样本已进入公开内容获取和 LLM 生成，在生成阶段 `65%` 因“AI 返回的菜谱结构无效”失败；无重复任务、多余草稿或正式菜谱，强停重启后失败状态保持。
- `BUG-003` 已补强生产 Prompt 字段类型和完整合法示例，实现字符串/转义/花括号层级安全的唯一顶层 JSON 提取；多个对象、多个 fence、截断、不平衡 JSON、未知字段和错误类型继续严格拒绝。
- OpenAI-compatible Provider 已显式识别 `finish_reason=length` 和空白 content，并返回稳定脱敏错误；不强制发送第三方可能不兼容的 `response_format`，不保存完整模型响应。
- `BUG-005` 已为 failed 页面增加“结束此导入”和“正在结束…”；操作复用原任务 ID 持久化执行 `failed → cancelled`，保留原失败记录、人工降级入口和可用重试入口，不创建替代任务、草稿或正式菜谱。
- 对 `ImportTask.cancel`、CAS 写入、Facade、草稿清理保护、进度页和首页刷新进行了独立静态审查，未发现 BUG-005 阻断问题；未运行任何测试或构建。
- 产品、用户故事、导入状态机、应用 Facade、验收记录与 AI 质量日志已同步；`BUG-003`、`BUG-005` 均进入 `VERIFY`。
- Codex 未运行测试、Flutter/Dart 分析器、格式化、构建、模拟器、真机或真实网络/API 请求；等待项目负责人 Android 复测，iOS 未验证。

### BUG-003 导入前置错误可观测性修复进入 Android 验证

- 项目负责人反馈：首页未完成入口、原任务恢复、链接一致、去重、最近任务排序、取消减少数量和强停重启持久化均正常；真实小红书样本仍无法完成解析，成功完成后的数量变化尚未验证。
- 截图证据显示任务停在 `queued`、`0%`、“已加入解析队列”，同时显示页面级“解析暂时无法继续，请稍后重试”，说明失败发生在公开内容 HTTP、Parser、LLM 真正执行前或其持久化错误被页面异常覆盖，不能归因于 LLM。
- `AiRecipeBackendFacade.runImportTask` 已将能力校验、会话读取、Runner 创建与执行纳入统一异常边界，并为 LLM 未配置、配置不可读、离线、会话/设置读取失败和能力状态读取失败返回稳定脱敏文案。
- 导入进度页在任务已经持久化为 `failed` 且带有错误时，优先显示任务错误，不再叠加页面级通用错误；新增对应 Facade 与 Widget 测试定义。
- Codex 仅完成代码和测试定义的静态文本复核，未运行测试、分析器、格式化、构建、模拟器、真机或真实网络/API 请求；`BUG-003` 更新为 `VERIFY`，等待项目负责人 Android 复测。iOS 未验证。

### OPS-004 永久测试职责调整

- `AGENTS.md`、`tracking/DECISIONS.md`（ADR-0015）、`tests/README.md` 与 `tests/acceptance/README.md` 已统一规定：Codex 默认不执行自动测试、静态分析、模拟器、真机或人工验收，只负责编写可复现测试方法。
- 项目负责人负责在指定平台执行并反馈；Codex 收到反馈后归档验收结果、AI 质量数据和任务状态。
- 项目负责人反馈前，实现完成的任务保持 `VERIFY`，不得写成 `DONE` 或“测试通过”；历史已有测试结果仍保留为当时事实。
- 当前默认仅提供 Android 验证方法，iOS 未实际执行时明确标记为未验证。

### BUG-004 首页未完成导入入口 Android 验收通过

- 项目负责人在 Android 模拟器确认：点击提示打开原任务，不误入“添加菜谱”页，页面链接一致。
- 点击前后未完成数量保持 `12 → 12`，没有同链接重复任务；多个任务时优先打开最近创建任务。
- 取消后数量减少，强制停止并重启后仍恢复原任务，没有多余草稿、正式菜谱或其他错误文字。
- “成功完成并保存后数量减少”因 `BUG-003` 无法完成真实链接解析而未执行，转由后续端到端导入验收覆盖；不继续阻塞入口缺陷。
- `BUG-004` 更新为 `DONE`；Codex 只归档用户反馈，未执行测试、静态分析、构建、模拟器或真机操作。iOS 未验证。

### BUG-003 真实小红书样本复测仍失败

- 项目负责人在 Android 修复版本使用同一公开 PC webshare 图文样本复测，任务创建、首页恢复和重启持久化正常，但链接内容仍无法解析，未进入有效 AI 生成结果或待确认草稿。
- 没有创建同链接重复任务，也没有额外草稿或正式菜谱。
- 既有脱敏 Fixture 通过不能代表当前真实平台响应；真实失败阶段尚未定位，不能直接归因于 LLM Provider。
- `BUG-003` 从 `VERIFY` 返回 `DOING`；下一步静态检查请求、Adapter、任务状态与页面错误映射链路，并在实现后仅提供项目负责人执行的 Android 测试方法。iOS 未验证。
### BUG-004 首页未完成导入入口修复进入 Android 验证

- 首页顶部“有 N 个未完成的导入”提示新增独立的已有任务打开回调，不再复用“快速导入/添加菜谱”回调。
- 点击提示后把 `HomeSnapshot.unfinishedImportTasks.first` 对应的原任务交给应用壳，并按原 `taskId` 打开既有导入进度页；不会因点击提示调用新建任务流程。
- 多个未完成任务时，当前 P0 优先打开持久化列表中最近创建的一项；完整导入记录列表页不属于本次最小修复。
- 已补充产品行为、用户故事、`BUG-004` 验收定义和 Android 测试方法；修复前截图归档于 `tests/acceptance/artifacts/BUG-004-2026-08-02/before-fix-unfinished-import-screen.png`。
- Codex 未执行任何自动测试、静态分析、模拟器或真机操作；`BUG-004` 进入 `VERIFY`，等待项目负责人按 `tests/acceptance/BUG-004-unfinished-import-resume-2026-08-02.md` 反馈结果。

### BUG-002 取消后的迟到结果覆盖修复进入 Android 验证

- 导入进度页新增任务快照单调应用规则：拒绝更低 `localVersion`；同一任务一旦接受 `cancelled`，默认拒绝之后所有非取消快照，即使迟到结果版本更高。
- 只有用户明确选择文本或图片降级重新开始时才允许从取消态进入新一轮；Runner 证据仅在任务快照被接受时更新，避免状态与证据错配。
- 页面宿主刷新回调改为安全通知，回调异常不再覆盖已经持久化并显示的任务结果；取消、重试和恢复均先应用后端任务状态，再通知宿主。
- 新增 Widget 回归，覆盖宿主刷新异常以及取消后旧轮询/更高版本迟到 `needsReview` 不能覆盖“解析已取消”。
- 页面解析/Adapter/进度页联合定向 37 项、取消持久化/Runner/Facade 后端定向 53 项、全量 480 项全部通过；`flutter analyze --no-pub` 无问题。
- `BUG-002` 进入 `VERIFY`，等待项目负责人 Android 复测迟到 Provider/AI 返回和强停重启；iOS 未验证。

### BUG-003 小红书 PC webshare 导入兼容进入 Android 验证

- 页面元数据解析器支持 `window.__INITIAL_STATE__`、平衡花括号扫描、`noteData.data.noteData` 和字符串外裸 `undefined` 转 `null`。
- 支持标题、描述、作者、发布时间和 `imageList`，兼容 `urlDefault`、`urlPre`、`url`、`urlList`、`urls`、`infoList` 及大中小尺寸 URL 字段，并按优先级选择和精确去重。
- 小红书 Adapter 使用固定 Android Mobile Chrome User-Agent 与中文 `Accept-Language`，保留原始查询字符串及顺序、移除 fragment，且不发送 Cookie 或 Authorization。
- 小红书域名下过滤通用“小红书”/`Xiaohongshu` 站点标题，避免把外壳标题当作笔记标题。
- 新增脱敏 PC webshare HTML Fixture、Parser 和 Adapter 回归；与导入进度页联合定向 37 项、全量 480 项全部通过，静态分析无问题。
- 未执行真实小红书网络请求、真实 API 或 Android 端到端测试；`BUG-003` 进入 `VERIFY`，等待项目负责人使用同一公开样本复测。iOS 未验证。

### BUG-001 分类创建稳定性与文字可读性修复并验收通过

- 新增共享分类创建对话框 `lib/shared/widgets/create_category_dialog.dart`：控制器由 State 持有并在 `dispose()` 释放；校验空名称、超长（30 字）和同名（大小写不敏感）；`_submitted` 标志防重复提交；`Navigator.pop(name)` 同步返回，静态入口 `CreateCategoryDialog.show(context, {required List<String> existingNames})`。
- 菜谱库与菜谱编辑页统一接入共享对话框；`_createCategory` 的 `await _categories` 后补 `if (!mounted) return;`，消除 `use_build_context_synchronously`；删除从未传值的 `autofocus` 参数，消除 `unused_element_parameter`。
- 分类 Chip 前景色修复：确认本 SDK 的 `ChipThemeData.labelStyle` 为静态 `TextStyle?` 且 `TextStyle.color` 为 `Color?`，无法承载按状态切换颜色；最终三态（默认/选中/禁用）统一使用深绿 `AppColors.greenInk`（`#33513C`），经 WCAG 对比度公式验证与纸张米白、卡片底、浅绿底对比度均 ≥ 6.9:1，测试断言不低于 4.5:1。
- 定向测试：菜谱库测试文件新增三态颜色显式性与对比度回归；编辑页测试新增编辑器内创建分类并自动选中回归；快速重复提交测试的第二次点击因对话框同步退场必然 miss，加 `warnIfMissed: false` 并注释说明为预期行为。
- `flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 458 项全部通过。
- 工作区受限沙箱内 `impellerc` 无法写入 `build/` 下 shader 产物（junction 亦被按路径前缀拦截），改在 `C:\Users\Administrator\AppData\Local\Temp\ai-recipe-mobile` 复制项目中完成 Debug APK 构建并验收；工作区 `code/apps/mobile/build` 目录在移除 junction 时删除，后续构建需重建。
- Android API 36 模拟器人工验收：正常创建分类并自动选中、空名称/同名错误提示、force-stop 重启后分类持久化（首页显示 2 个分类）、Chip 选中筛选正确；Logcat 10093 行无 `FATAL EXCEPTION`、`E/flutter`、控制器异常或未处理异常。
- 验收记录 `tests/acceptance/BUG-001-category-creation-stability-2026-08-02.md`，证据归档到 `tests/acceptance/artifacts/BUG-001-2026-08-02/`（4 张截图 + 完整 Logcat）。
- `BUG-001` 从 `TODO` 进入 `DONE`；`UI-001` 保持 `VERIFY`，缺陷已修复并验收，等待项目负责人最终视觉确认。下一步进入 `SPK-003` 真实 LLM 服务验证（需项目负责人提供临时 OpenAI-compatible 纯文本服务的地址与 Key，仅运行时手工输入不落盘）。

## 2026-08-01

### BUG-002 / AI-003 后端收口复核

- 重新执行 `flutter analyze --no-pub`，无问题；重新执行 `flutter test --no-pub --concurrency=4`，475 项全部通过。
- `git diff --check` 通过；仓库文本复扫未发现临时 Key 形态或真实 Provider 主机，唯一长 Key 字面量确认是测试 Fixture。
- 继续检查当前工作树时，导入进度页仍会在任务运行期间禁用取消回调；按项目负责人要求未修改 UI，因此 Android 真实点击取消仍是 `BUG-002` / `AI-003` 的关闭条件。
- 修复架构文档新增段落的尾随空格，不改变业务契约。


### BUG-002、AI-003 与 SPK-003 后端加固进入验证

- 为 ImportTask 增加 `localVersion` CAS 持久化契约和明确写冲突；取消、Runner 结果提交和失败写入在冲突后重新读取最新任务。
- 取消状态优先于后到 Provider 成功、Schema 错误、网络错误或未知异常；迟到成功产生的草稿通过安全丢弃器补偿清理，只删除 ID、来源匹配且仍为草稿的数据。
- 新增 SQLite 真实文件竞态测试，验证取消后数据库重开仍为取消，以及迟到成功不遗留孤立草稿；相关定向测试 53 项、全量 Flutter 测试 475 项全部通过，静态分析无问题。
- `AI-003` 的有限响应规范化通过真实 OpenAI-compatible 纯文本模型验证：生成严格结构化草稿，进入 `needsReview`，SQLite 重开后恢复成功；不保存完整 Prompt 或响应。
- `SPK-003` 首阶段真实连接、安全错误路径和脱敏检查通过；样本不是固定平台质量样本，质量字段保持未评分。
- 临时 API Key 已通过 App 内“清除已保存的 API Key”从安全存储移除；仍建议项目负责人轮换该凭证。
- 当前安装构建在 LLM 运行态仍将“取消解析”显示为不可点击；本轮按要求不修改 UI，Android 真实点击取消继续作为 `VERIFY` 关闭条件。
- 新增验收记录 `tests/acceptance/BUG-002-import-cancellation-race-2026-08-01.md` 与 `tests/acceptance/SPK-003-openai-compatible-android-2026-08-01.md`。

### BUG-001 分类缺陷与 SPK-003 真实 LLM 验证计划

- 项目负责人在 `UI-001` 最终验收中发现分类创建后出现运行时错误、分类文字对比度不足；新增 P0 `BUG-001`，覆盖 Android 异常复现、分类生命周期与重复提交、SQLite 重启持久化、筛选、Chip 多状态颜色和 Widget/Logcat/截图回归。
- 当前仅将输入控制器释放时机列为待证实的调查假设，实施前必须用 Flutter exception 或 Android Logcat 复现确认，不把猜测写成已确认根因。
- `UI-001` 保持 `VERIFY`，但 `BUG-001` 关闭前不得进入 `DONE`；本轮只规划任务，没有修改 Flutter 代码。
- 细化 `SPK-003`：后续使用用户授权的临时 OpenAI-compatible 纯文本服务，先验证 Android 连接、公开正文生成结构化菜谱、严格 Schema、取消/超时、错误映射和敏感信息脱敏；该服务不用于评价 OCR、图片理解或视频理解。
- 临时 API 地址和 Key 仅在 App 运行时手工输入，不写入仓库、文档、命令、Fixture、截图或日志；本轮未调用 API、未持久化凭证。测试结束必须清除 App 安全存储并建议轮换临时凭证。
- 校准 `SPK-001`、`SPK-002` 在 `tracking/SPIKES.md` 和各自 Spike 文档中的状态，使其与任务事实源 `tracking/BACKLOG.md` 一致。

### UI-001 Flutter 原生高保真复刻进入验证

- 将 `design/prototypes/index.html`、`prototype.css`、`app.js` 固化为 Flutter UI 的唯一视觉事实源，并新增 `ADR-0013`；生产页面只使用 Flutter Widget、Painter、Clipper 和 Animation，不使用 WebView 运行 HTML。
- 完成纸张米白色板、深绿主色、像素阶梯缺角、硬边按钮阴影、细描边卡片、等宽眉题、三栏底部导航和右下悬浮添加按钮的共享 Flutter 实现。
- 欢迎、首页、菜谱库、添加/导入、导入进度、导入失败、普通/低置信草稿、详情、编辑、烹饪、我的、LLM、OCR、隐私和回收站共 16 张 Android 截图已归档到 `tests/acceptance/artifacts/UI-001-2026-08-01/`。
- `flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 450 项全部通过；扫描 `code/apps/mobile/lib` 与 `pubspec.yaml` 未发现 WebView 引用。
- 新增正式验收记录 `tests/acceptance/UI-001-flutter-native-prototype-replication-2026-08-01.md`，并将 HTML → Flutter 差异清单从“待截图”更新为逐页证据矩阵。
- `UI-001` 从 `DOING` 进入 `VERIFY`，等待项目负责人最终视觉确认；iOS、真实 PP-OCRv5、真实自有 LLM、真实公开内容和视频 ASR 未在本次视觉切片中验证。
- 发现正式 `Recipe` 仅保存 `sourceId`，缺少来源 URL / canonical URL / 不可变来源快照，已登记 `R-016`，本轮不扩大 UI-001 范围。

### UI-001 Android 单张截图 OCR 导入入口与安全失败边界

- 为失败或已取消的导入任务接入 Android 系统单张图片选择器；用户取消选择时保持原任务状态且不显示错误，页面继续保留粘贴正文、截图、视频、手动创建和返回添加页入口。
- 新增图片选择封装及 Android lost-data 恢复处理，覆盖 MIME 推断、非图片拒绝、权限/平台异常和恢复异常的稳定文案；Flutter 页面只通过 `AiRecipeBackendFacade` 进入业务流水线。
- Facade 本地图片入口校验任务状态、本地资源标识和图片 MIME，强制使用本地 OCR + 用户自有 LLM，不读取图片上传开关，也不调用云 OCR；LLM 未配置、本地 OCR 未安装/不可用和 OCR 失败均映射为稳定脱敏错误。
- 补齐图片选择器、导入进度页和 Facade 测试中的错误路径与 Windows 路径脱敏回归；3 个定向测试文件共 43 项通过，Facade 单文件 19 项通过；`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 447 项全部通过。
- Android 16 / API 36 模拟器人工验证系统 Photo Picker、取消返回和选择图片返回应用。当前设备未配置自有 LLM，实际先显示“请先在 LLM 设置中配置可用的自有 AI 服务”；OCR 未安装错误与 lost-data 恢复仅完成自动测试，不误写为设备人工通过。
- 清空 Logcat 后重放图片选择流程，扫描 1333 行系统日志，未匹配崩溃、未处理异常、API Key、`content://` 或 `/data/user/` 应用隐私信息。
- Android Debug APK 全量构建首次因 `android/gradle.properties` 的 UTF-8 BOM 导致首行 `org.gradle.jvmargs=-Xmx8G` 未生效，Gradle Daemon 实际只使用 `-Xmx512m` 并在 `:app:mergeExtDexDebug` OOM；移除 BOM、停止旧 Daemon 后构建成功。
- 新增验收记录 `tests/acceptance/UI-001-android-image-ocr-import-2026-08-01.md` 与对应截图、UI 层级和 Logcat 证据目录。
- 当前没有真实 PP-OCRv5 模型、真实自有 LLM API Key 和授权公开菜谱样本，因此未评价 OCR/LLM 输出质量，也未向 AI 质量日志写入虚假成功率。视频、相机、多图和 iOS 未实现或未验证；`UI-001` 保持 `DOING`，`SPK-002` 保持 `TODO`。

## 2026-07-31

### UI-001 Android API 36 模拟器冒烟与刷新回归

- 新增 Android `integration_test` 冒烟主链与四 Tab、设置入口稳定 Key，覆盖游客继续、手动创建菜谱、详情、收藏、软删除、回收站恢复、LLM/OCR/隐私设置和设置持久化。
- 集成测试初始化改用 `SharedPreferencesAsync().clear()`，正确清理 Android DataStore 中的 onboarding 和本地设置，避免旧模拟器状态污染测试。
- 修复菜谱编辑器分类加载提示乱码，统一显示“正在读取分类…”；修复首页和菜谱库在 `refreshToken` 更新时从 `setState` 回调返回 Future 的运行时断言，并新增 2 项回归测试。
- Android 16 / API 36 的 Pixel 9a 模拟器上完成 Debug APK 构建、安装与启动；`integration_test/android_smoke_test.dart` 1 项通过。测试进程仅构建 `android-x64` 以避免多 ABI Debug 构建触发 Gradle 内存不足，正式发布配置未修改。
- Logcat 对 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter` 与 Flutter error 模式均无匹配；`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 427 项全部通过；`git diff --check` 通过。
- 新增验收记录 `tests/acceptance/UI-001-android-emulator-smoke-2026-07-31.md` 和 Android 人工截图资产目录 `tests/acceptance/artifacts/UI-001-android-emulator-2026-07-31/`。
- 本轮按用户要求只测试 Android，iOS 未验证且不阻塞本次结果；没有使用真实 API Key、真实 Provider 或公开平台样本，本次冒烟不代表真实平台解析或真实 AI 输出质量，`UI-001` 继续保持 `DOING`。
### UI-001 导入失败人工降级切片

- 为失败或已取消的导入任务补齐“粘贴正文继续”“上传截图继续”“上传视频继续”“手动创建菜谱”四个人工降级入口；可重试任务继续保留重新解析入口。
- 新增 `ImportTask.startWithFallback()`、`StartImportTaskWithFallback`、`ImportTaskRunner.runWithContent()` 和 `AiRecipeBackendFacade.runImportWithPastedText()` 的完整链路。
- 粘贴正文会跳过公开内容 Adapter，保留任务 ID、来源链接、平台和 attempt，复用统一 Processor 进入 AI 草稿确认；人工降级失败或中断不会自动回退到公开链接抓取。
- Facade 在解析 Provider 路由前校验任务状态，queued、running、needsReview 和 completed 等状态稳定映射为 `invalidTaskState`；空正文、Provider 不可用和处理异常均使用脱敏错误，不泄露 API Key 或正文。
- 图片选择器和真实视频 ASR 尚未接入时，截图/视频入口显示真实不可用说明；手动创建直接进入既有菜谱编辑页且不依赖 AI。
- 新增添加页链接入口接线测试：小红书链接会创建并持久化 queued 任务、打开导入任务并触发数据刷新；空链接不会创建任务。
- 核心 5 个定向测试文件共 52 项通过，添加页定向测试 2 项通过；`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 425 项全部通过。
- 新增验收记录 `tests/acceptance/UI-001-import-fallback-slice-2026-07-31.md`。
- 本轮仅完成 Fake Provider 契约和自动化链路验证；因没有用户授权的真实 API 地址、Key 和公开样本，未执行真实端到端 AI 质量验收，`UI-001` 继续保持 `DOING`。
## 2026-07-30

### UI-001 设置与独立 onboarding 切片

- 新增独立于身份会话的本地 onboarding 状态，使用 `onboarding_completed_v1` 持久化首次引导是否完成；首次游客、已确认游客和已登录用户分别进入欢迎页或应用壳。
- 游客继续会保存 guest session 并完成 onboarding；已确认游客重启后直接进入应用壳；已登录用户绕过未完成引导；Profile 可重置 onboarding 并返回欢迎页。
- Profile 已接通自定义 LLM API、OCR 引擎、隐私与上传权限三个真实设置页，不再展示占位提示；页面返回后会刷新能力矩阵。
- LLM 设置页只调用 `AiRecipeBackendFacade`，支持 OpenAI-compatible、Gemini 和 30/60/120 秒超时；API Key 不明文回填，空 Key 保存保留已有密钥，可显式清空，错误状态不包含输入密钥或服务端敏感原文。
- OCR 设置页只调用 Facade 的状态、安装、删除、恢复和本地设置接口；正式 App 未配置生产 Manifest 时禁用安装并明确提示，不伪造模型下载地址、SHA-256、大小或可用状态。
- 隐私设置页接入浏览历史及文本/图片/视频上传权限，关闭浏览历史会自动清空，也支持二次确认后手动清空。
- 全量回归发现组合根构造时 onboarding 偏好适配器提前创建 `SharedPreferencesAsync`，导致无插件平台的既有单元测试失败；已改为首次读写时延迟创建，保持设备运行行为并解除无关组合根测试的构造依赖。
- 7 个定向测试文件共 24 项全部通过；`flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 404 项全部通过；`git diff --check` 通过。
- 本切片验收通过，`UI-001` 继续保持 `DOING`；下一切片为导入失败后的人工降级输入入口和真实 Provider 条件下的端到端验收。
### UI-001 完整烹饪模式与多计时器切片

- 新增深绿色完整烹饪模式，展示当前步骤、步骤进度、时长、温度、厨具、火候和提示，并支持上一步、下一步与完成烹饪。
- 菜谱详情的“开始烹饪”已改为通过 `AiRecipeBackendFacade` 启动或恢复持久化烹饪会话。
- 接入多个持久化计时器的创建、暂停、继续、提前完成与清除；运行计时器以绝对 `endsAt` 为事实源，页面 ticker 仅用于刷新显示。
- 退出烹饪页时增加防误触确认；离开页面后活动会话和运行计时器继续保留。前台计时归零可提示，操作系统后台本地通知尚未实现。
- 不伪造数据关系：步骤食材仅根据正文完整名称匹配；计时器暂以稳定标签 `步骤 <序号>` 关联当前步骤，后续数据模型可再补正式关联字段。
- 新增 6 项烹饪模式 Widget 测试，并更新详情页入口测试；2 个定向测试文件共 8 项通过。
- `flutter analyze --no-pub` 无问题；`flutter test --no-pub --concurrency=4` 共 383 项全部通过。

### UI-001 导入执行进度与 AI 草稿确认切片

- 链接创建持久化导入任务后立即进入执行页；queued 任务自动运行，遗留 running 任务先恢复，页面以 450ms 轮询展示阶段、进度和最终状态。
- 执行页覆盖取消、可重试失败、不可重试失败、恢复、已取消返回、待确认自动跳转以及完成后打开正式菜谱；取消令牌与持久化取消状态共同生效。
- 新增 AI 草稿确认页，可编辑菜名、简介、份量、时间、难度、食材和步骤；保存时保留封面、标签、分类及未编辑的结构化字段，并通过 Facade 发布菜谱、完成任务。
- 低置信度阈值统一为 `< 0.7`，支持逐项标记已核对；放弃草稿要求二次确认并调用 Facade 取消任务、软删除草稿。
- 原始证据区仅展示本次会话保留的文本片段、类型、置信度、时间范围和 Provider；字段与证据尚无一一映射时明确提示，应用不会伪造来源依据。
- 添加页和应用壳已完成导航闭环：导入完成后刷新首页/菜谱库并打开正式菜谱详情。
- 新增 6 项 Widget 测试；`dart analyze lib test`、`flutter analyze --no-pub` 均无问题；全量 `flutter test --no-pub --concurrency=4` 共 377 项全部通过。
- `UI-001` 保持 `DOING`：下一切片为完整烹饪模式，之后接入 LLM、OCR、本地隐私设置和独立 onboarding 状态。
### UI-001 菜谱详情、编辑与回收站切片

- 将菜谱详情快速预览升级为正式页面，完整展示元数据、标签、分类、来源、食材和步骤，并接入收藏、编辑、软删除和烹饪会话准备入口。
- 新增完整菜谱新建/编辑表单，支持分类、标签、份量、时间、难度以及动态食材和步骤；编辑时保留已持久化子项身份。
- 新增回收站页面，支持空状态、恢复、永久删除和清空回收站，破坏性操作均要求确认。
- 新建、编辑、删除和恢复后统一刷新首页与菜谱库；所有页面继续只通过 `AiRecipeBackendFacade` / Application 接线。
- 修复分类加载态在固定高度容器中的布局溢出，并为编辑分区与回收站操作增加稳定测试 Key。
- 新增 7 项 Widget 测试；定向组合测试全部通过；`dart analyze code/apps/mobile/lib code/apps/mobile/test` 和 `flutter analyze --no-pub` 均无问题；全量 `flutter test --no-pub --concurrency=4` 共 371 项全部通过；`git diff --check` 通过。
- `UI-001` 保持 `DOING`：下一切片为导入执行进度和 AI 草稿确认，烹饪模式及 LLM/OCR/隐私设置随后接入。

### UI-001 Flutter P0 页面首个切片

- 按 `design/prototypes/` 的 HTML 原型建立 Material 3 主题，统一纸张、卡片、绿色、琥珀、错误色、输入框、按钮、导航和标签样式。
- 重构应用入口，由 `AiRecipeApp` 持有设备组合根生命周期，并保留旧 LLM 设置调试入口；正式运行统一进入会话门和 `AiRecipeBackendFacade`。
- 新增欢迎/游客入口和四 Tab 应用壳，完成首页、菜谱库、链接导入、手动添加和我的页首版，并提供菜谱详情快速预览。
- 首页、菜谱库、添加和能力状态只调用 Facade/Application，不直接访问 SQLite、SharedPreferences、安全存储、Repository 或 Provider。
- 新增页面标题、加载/空/错误状态和菜谱卡片共享组件；补充欢迎页稳定 Key，便于自动化测试和后续页面驱动。
- 新增 8 项主题与 Widget 测试，覆盖游客入口、忙碌禁用、错误重试、空状态 CTA、错误状态重试、长菜名、菜谱元数据和收藏/点击回调。
- 质量门通过：`dart analyze code/apps/mobile/lib` 无问题，`flutter analyze --no-pub` 无问题，`flutter test --no-pub --concurrency=4` 共 364 项全部通过。
- `UI-001` 保持 `DOING`：正式详情、编辑、回收站、导入进度、AI 草稿确认、烹饪模式以及 LLM/OCR/隐私设置仍待实现。
### APP-004 Flutter 本地业务后端与前端接线契约

- 完成菜谱标签持久化、去重和按标签筛选，并补齐菜谱/分类 CRUD、收藏、搜索、复制、回收站、批量恢复与永久删除的统一 Facade 入口。
- 新增首页与详情聚合用例：首页一次返回最近浏览、分类计数、收藏摘要和未完成导入；详情返回菜谱、有效分类、来源导入任务，并按隐私设置记录浏览历史。
- 新增本地设置领域与 SQLite Repository，支持浏览历史开关、文本/图片/视频上传授权和历史清理；关闭浏览历史时自动清空已有记录。
- 新增烹饪会话、当前步骤和多计时器领域能力，支持计时器暂停、恢复、完成、删除和应用重启恢复；运行计时器以绝对 `endsAt` 计算剩余时间。
- SQLite 升级到 Schema v3，并通过 v1/v2 → v3 迁移测试验证菜谱、分类、食材、步骤、关系和导入任务数据保留以及新表级联清理。
- `AiRecipeBackendFacade` 与设备组合根已覆盖会话、能力、菜谱库、首页、详情、导入、LLM 设置、OCR 管理、本地设置和烹饪模式，Flutter 页面无需直接访问 Repository 或 Provider。
- 修复计时器删除时前后空格 ID 未规范化的问题；修复测试 Fake Repository 的标签参数兼容；Facade 集成测试显式注入 SQLite FFI 内存数据库，避免并发全量测试依赖全局 `databaseFactory`。
- 质量门通过：`dart analyze`、`flutter analyze --no-pub` 均无问题，`flutter test --no-pub --concurrency=4` 共 356 项全部通过，烹饪与 SQLite v3 迁移定向测试共 10 项通过。
- `APP-004` 进入 `DONE`，下一阶段为 `UI-001`：按 `design/prototypes/` HTML 原型实现 Flutter 页面并接入统一 Facade；服务器端继续暂缓。
## 2026-07-29

### OCR-002 远程 HTTPS 图片安全暂存

- 新增本地 OCR 远程图片暂存包装：本地图片直接透传，远程图片先下载到应用私有临时文件，识别完成、失败或取消后统一清理；云 OCR 不经过本地暂存层。
- 新增 HTTPS-only 安全策略，拒绝 userinfo、fragment、控制字符、环回、私网、link-local、CGNAT、文档地址以及混合公网/非公网 DNS 结果。
- 下载连接固定到已经验证的 IP，并使用原始域名执行 Host、TLS SNI 和证书校验；301/302/303/307/308 每一跳都会重新执行 URL 与 DNS 校验。
- 新增受限 HTTP/1.0/1.1 响应读取，覆盖 Content-Length、chunked 与 connection-close；限制响应头、重定向、字节和各阶段超时，拒绝重复敏感 Header、冲突 framing 和不支持的传输编码。
- 暂存器仅接受 JPEG、PNG、WebP，并同时校验 MIME、magic bytes、字节、边长和总像素；稳定错误不暴露源 URL、主机、IP 或本地路径。
- 设备组合根统一包装默认和注入的本地 OCR Builder，并保留可注入暂存器以支持测试；受影响的 Facade 集成测试使用明确的测试暂存器。
- 新增 39 项 OCR-002 定向测试；全量验证为 Dart 格式检查 130 个文件、Dart/Flutter 静态分析无问题、307 项 Flutter 测试通过、Android `:app:testDebugUnitTest --rerun-tasks` 构建成功。
- `OCR-002` 进入 `DONE`；真实公开平台图片端到端联调、真实 PP-OCRv5 模型、真机性能/内存/准确率、完整 Paddle DB 后处理、方向分类器、iOS 和跨进程互斥仍未完成，`SPK-002` 保持 `DOING`。

### SPK-002 Android 本地 OCR 首阶段真实识别切片

- 新增 OCR Manifest v2 Runtime 契约；v1 保持安装/健康检查兼容，v2 明确 Detector、Recognizer、词典、Tensor、归一化、阈值、Shape 和 CTC 参数。
- Android 原生层新增私有文件与 `content://` 图片读取、输入限制、ONNX Session 缓存、Detector/Recognizer 预处理和推理、简化连通域文本框后处理、轴对齐裁剪与 CTC 解码。
- 修复 Runtime 能力探测契约：ONNX Runtime 可用时 `recognitionSupported` 同步为 `true`，使 Dart Provider 能进入识别路径。
- 新增图片过大、权限拒绝、图片源不可用等稳定错误映射，并保持 URL、设备路径和内部异常脱敏。
- 新增 Android 单元测试，覆盖 Runtime probe、词典读取、Manifest v2、路径安全和 CTC 解码。
- 新增 `R-015` 与 `OCR-002`：公开 Adapter 的远程 HTTPS 图片必须经过 SSRF/DNS/重定向/MIME/magic bytes/大小/像素/超时/取消校验后暂存，再交给本地 OCR。
- 自动化验证通过：Dart 格式检查 120 个文件、0 个变化；Flutter 静态分析无问题；268 项 Flutter 测试通过；Android `:app:testDebugUnitTest --rerun-tasks` 构建成功。
- 该阶段切片完成时，真实 PP-OCRv5 mobile 模型、真机性能/内存/准确率、完整 Paddle DB 后处理、方向分类器、iOS、远程图片暂存和跨进程互斥仍未完成；其后的 OCR-002 切片已补齐远程暂存，`SPK-002` 仍保持 `DOING`。

## 2026-07-28

### DESIGN-000 移动端 UI 设计交付文档

- 新增 `design/UI_HANDOFF.md`，作为交付给 UI/UX 或前端的移动端 UI 入口文档。
- 明确 MVP 信息架构、页面树、底部导航、核心页面、AI 导入流程、游客/登录差异、LLM/OCR 设置页和设计验收标准。
- 更新 `design/README.md` 设计入口索引，并在 `tracking/BACKLOG.md` 标记 `DESIGN-000` 已完成；实际线框图和高保真设计仍由 `DESIGN-001` 起继续执行。


### SPK-002 本地 OCR 模型 Runtime 与安装可靠性阶段切片

- 新增本地 OCR 模型包服务，支持下载、扩展名限制、大小与 SHA-256 校验、安装、健康检查后激活、删除、失败回滚和中断恢复。
- 同一服务实例内按模型包串行执行安装、删除和恢复；相同版本并发安装复用已激活结果，失败操作不会阻塞后续队列；跨 isolate、多服务实例、跨进程和 OS 文件锁仍待设计。
- `active.json`、`state.json` 和 `manifest.json` 使用临时文件原子切换；Windows 覆盖失败时可通过备份恢复，升级失败保留上一 active 与 `installedVersion`。
- 新增 `OcrModelInstallCancellationToken`，安装前、容量检查、下载 chunk、Manifest 写入、staging rename、health check 和 active 切换前都会检查取消；取消后清理 staging，保留上一 active，并写入 `failureCode = cancelled`。
- 新增 Android `getAvailableStorageBytes` 和 Dart `PlatformOcrStorageCapacityProvider`；下载前按 Manifest 模型总大小 + 64 MiB 安全余量预检，容量未知时跳过，空间不足映射为稳定 `insufficientStorage`。
- 新增默认 active + 1 inactive 的旧版本回收策略；回收异常为 best-effort，不能让已经激活的新版本失败。
- 修复激活提交点边界：`active.json` 写入成功后，后续状态持久化或观察者回调异常不得删除已激活模型。
- Flutter 新增 `ai_recipe/local_ocr` MethodChannel 契约，包含 `probe`、`healthCheck`、`recognize`，并完成响应校验和稳定错误映射。
- Android 集成 ONNX Runtime `1.20.0`，健康检查会创建 ONNX Session 并验证输入输出；`recognize` 仍固定返回 `inference_not_implemented`，`recognitionSupported` 仍为 `false`。
- 新增 `PlatformOcrProvider`、本地模型 Application Use Cases、Backend Facade 管理入口和设备组合根装配。
- `dart format lib test` 共 118 个文件、0 个变化；`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 共 259 项通过；Android Debug APK 构建成功。
- 真实 PP-OCRv5 推理、Android 真机性能/准确率、iOS 路径、Manifest 签名/可信发布链尚未完成，因此 `SPK-002` 保持 `DOING`。
## 2026-07-28

### APP-003 应用后端组合根与统一门面

- 新增 `AiRecipeBackendFacade`，统一暴露会话、能力、菜谱库、导入任务调度、草稿确认和放弃入口。
- 新增 `ImportExecutionPlan` 与 `ImportTaskRunnerFactory`，按自定义/托管 LLM、本地/云 OCR 和托管 ASR 路线执行能力校验并装配 Provider。
- 新增设备运行时能力仓库与设备组合根，集中管理 SQLite、SharedPreferences、安全 LLM 配置、公开内容 Adapter 和 Provider Builder 生命周期。
- LLM 草稿 Processor 传播当前会话 `userId`：登录用户草稿归属用户，游客草稿保持本地匿名。
- 草稿确认强制发布，已发布菜谱的确认重试不会重复增加本地版本；放弃草稿执行软删除并取消任务。
- 修复 OCR 后进入 ASR 时全局进度从 60% 倒退到 35% 的缺陷，ASR 现固定使用 61%–64% 进度区间并加入回归测试。
- 新增 Facade、组合根、运行时能力、Runner Factory、执行计划和幂等确认测试。
- `dart format lib test` 无额外变化，`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 217 项全部通过。
- `APP-003` 进入 `DONE`；下一项后端主任务转向 `SPK-002` 本地 OCR 原生插件与模型下载验证。
### APP-002 游客/登录会话与后端能力策略

- 新增纯 Dart `AppSession`，区分游客与已认证用户，但不存储或传递认证 Token。
- 新增八类统一能力、运行时就绪状态、稳定不可用原因、能力快照和能力守卫。
- 游客与登录用户都可使用本地菜谱、公开链接导入、自定义 LLM API 和本地 OCR；托管 AI、云 OCR、托管 ASR 与云同步要求登录。
- 新增 `DeviceAppSessionRepository`，SharedPreferences 只保存非敏感会话元数据，并严格拒绝损坏 Schema、未知字段和身份字段不完整的数据。
- Repository 未知异常统一映射为脱敏的 Application 错误；页面后续不得自行拼装权限规则。
- 新增 21 项自动化测试；`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 197 项通过。
- `APP-002` 进入 `DONE`；登录协议、Token 安全仓库、真实托管服务和云同步继续作为独立任务实施。
会影响产品、流程、架构、设计、测试或交付方式的有效变化。代码的细粒度变化以后由版本控制记录。

## 2026-07-28

### APP-001 本地优先菜谱库 Application 用例

- 新增 `RecipeLibraryUseCases`，统一手动创建、详情、更新、筛选、收藏、回收站和分类管理入口。
- UI 后续只依赖 Application Facade，不直接访问 SQLite、HTTP Client 或供应商 SDK。
- 更新使用完整表单快照，保留聚合身份并校验食材/步骤 ID 所属；新子项 ID 由 Application 生成。
- Recipe Repository 新增状态与分类筛选；Category Repository 新增详情、恢复和永久删除。
- 分类软删除只移除菜谱分类关系，恢复不自动恢复历史关系。
- Repository 未知异常统一映射为脱敏的稳定 Application 错误。
- 真实 SQLite 已验证游客 `userId == null` 聚合关闭重开、Unicode 内容、筛选和回收站流程。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 176 项通过，`git diff --check` 通过。
- `APP-001` 进入 `DONE`；下一主任务切换为 `APP-002` 游客模式后端能力策略。

### ASR-001 ASR Provider 与导入预处理

- 新增统一 `AsrProvider`、`AsrMediaInput`、`AsrTranscript`、分段时间戳和稳定错误契约。
- `ImportTextFragment` 新增语言、起止时间和说话人证据字段，JSON Schema 约束起止时间成对出现。
- 新增 ASR 预处理 Decorator，支持跳过、媒体排序、数量/时长限制、分段去重、部分结果、取消和错误映射。
- Runner 已验证 `extracting → transcribing → generating → review`。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 161 项测试通过；相关 Schema 通过 Draft 2020-12 元 Schema 校验。
- `ASR-001` 进入 `DONE`；真实本地/云 ASR Provider、音轨抽取和真机性能保留给后续任务。

### OCR-001 OCR Provider 与导入预处理

- 新增统一 `OcrProvider`、`OcrDocument`、`OcrTextBlock` 和稳定错误契约。
- 新增严格模型 Manifest 与模型安装状态。
- `ImportTextFragment` 新增 `confidence`、`sourceMediaOrder`、`sourceProvider`。
- 新增 OCR 预处理 Decorator，支持跳过、媒体排序、限制、部分结果、去重、取消和错误映射。
- Runner 已验证 `extracting → ocr → generating → review`。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 141 项测试通过。
- `OCR-001` 进入 `DONE`；Android/iOS 原生桥接和模型下载保留给 `SPK-002`。

### AI-002 结构化菜谱生成 Processor

- 新增受限 Prompt，将页面内容视为不可信数据并限制为 40,000 字符。
- 新增纯 JSON / 单 fenced JSON 提取和严格结构化菜谱 Schema 校验。
- 菜谱、食材、步骤 ID、排序、状态、时间戳和版本全部由本地生成，结果只保存为 `RecipeStatus.draft`。
- 标题不再代替 OCR/ASR 正文；标题-only 且需要媒体识别时不调用 LLM，避免幻觉生成。
- 明确 Repository 保存成功后的提交点语义，解决已保存草稿被任务取消后失去引用的竞态。
- 新增真实 SQLite 文件关闭/重开持久化测试，Recipe、Ingredient 和 Step 均可恢复读取。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 113 项测试通过。
- `AI-002` 验收完成并进入 `DONE`；下一主任务切换为 `OCR-001`。

### IMPORT-003 公开内容获取与人工降级

- 新增可注入的受限 HTTP Transport，覆盖超时、取消、有限重定向、平台主机白名单、HTTPS 降级拒绝、响应体上限和 Content-Type 白名单。
- 新增 HTML、Open Graph、JSON-LD、独立 JSON 和纯文本公共元数据解析，支持相对 URL、媒体去重和顺序保持。
- 新增小红书与抖音公开内容 Adapter，统一生成文本片段、图片/视频引用、作者、发布时间和后续 OCR/ASR 警告。
- 登录要求、内容不可用、超时、网络、安全策略和空载荷均映射为稳定且脱敏的项目错误。
- 新增粘贴正文、本地图片和本地视频人工降级路径，不实现登录、验证码、签名、访问控制或反爬绕过。
- 新增 4 个固定 Fixture 和 36 项定向测试；`flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 94 项测试通过。
- `IMPORT-003` 验收完成并进入 `DONE`；下一阶段转入 OCR/ASR 与 LLM 结构化菜谱 Processor。

### IMPORT-002 内容 Adapter 与单执行器调度内核

- 新增统一导入内容模型和 `docs/api/import-content.schema.json`。
- 新增平台 Adapter 契约、Registry、重复平台注册保护和统一内容不变量。
- 新增导入 Runner，按状态机执行获取、提取、可选 OCR/ASR、LLM 生成和待确认落盘。
- 新增单执行器 Dispatcher，按创建时间顺序调度，支持批次取消、数量限制和单任务失败隔离。
- 新增取消令牌、指数退避、稳定错误映射和未知异常脱敏。
- 明确只获取公开内容，不实现登录、验证码、签名、访问控制或反爬绕过。
- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 共 58 项测试通过。
- 下一主任务切换为 `IMPORT-003`：公开内容获取与人工降级。

### IMPORT-001 持久化导入任务内核

- 新增小红书/抖音 URL 校验、平台识别与基础规范化。
- 新增导入任务生命周期、处理阶段、统一错误码、取消、失败、重试和重启恢复领域规则。
- 新增只依赖领域 Repository 的 Application 用例。
- SQLite 升级到 Schema v2，新增 `import_tasks`、恢复索引和 v1 → v2 迁移。
- `result_recipe_id` 明确为跨聚合逻辑引用，不建立会破坏任务状态不变量的 SQLite 外键。
- 修复待确认任务取消时未清理草稿逻辑引用的问题。
- 新增 Domain、Application、SQLite Repository 和迁移测试；`flutter analyze --no-pub` 无问题，41 项测试全部通过。
- `IMPORT-001` 验收完成并进入 `DONE`；下一后端切片为 `IMPORT-002` 内容获取与导入调度内核。

### SPK-001 Local-first SQLite 菜谱数据层

- 新增纯 Dart 菜谱、食材、步骤和分类领域模型及 Repository 契约。
- 新增 SQLite Schema v1，覆盖 `recipes`、`ingredients`、`recipe_steps`、`recipe_categories` 和 `recipe_category_relations`。
- 菜谱聚合新增/更新使用事务，启用外键和级联删除，无效分类关系会使整次保存回滚。
- 支持菜谱持久化读取、列表、文本搜索、收藏筛选、软删除、恢复、永久删除，以及分类排序和软删除。
- 新增 6 个真实 SQLite 临时文件测试；`flutter test` 总计 27 个测试全部通过，`flutter analyze` 无问题。
- 通过纯 ASCII Junction `C:\tmp\ai-recipe-mobile` 再次完成 Android Debug APK 构建。
- 新增架构文档 `docs/architecture/LOCAL_DATABASE.md` 和验收记录 `tests/acceptance/SPK-001-local-recipe-database-2026-07-28.md`。
- `SPK-001` 保持 `DOING`；SQLite 验证项已通过，下一步转入 `IMPORT-001` 后端任务状态机和分享 URL 接入。
### GitHub 首次发布

- 新增 `OPS-003`，将本地仓库发布到 GitHub 仓库 `zisjugoudan/ai-recipe`。
- 推送前确认远程仓库没有已有引用，避免覆盖远程历史。
- 创建根提交 `df55ef4 chore: initialize AI recipe project`。
- 配置 `origin` 并将本地 `main` 推送到 `origin/main`，建立默认上游关系。
- Flutter `build/`、Debug APK 和常见本地敏感文件继续由 `.gitignore` 排除。
- 新增验收记录 `tests/acceptance/OPS-003-github-publish-2026-07-28.md`。

## 2026-07-27

### 新增

- 创建本地分层项目目录、根目录永久协作规程和完整跟踪文件。
- 创建产品用户故事、设计交付、架构、API、代码和测试目录说明。
- 创建 `docs/architecture/MOBILE_ARCHITECTURE.md`，定义 Flutter 分层、模块边界和游客/登录能力。
- 创建 `docs/architecture/OCR_PLUGIN.md`，定义 PaddleOCR 本地插件、模型包和安全边界。
- 创建并修订 `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md`，最终定义统一“协议 + API Base URL + 可空 Key + 模型”配置和 Provider Adapter 契约。
- 初始化本地 Git 仓库，默认分支为 `main`；未配置远程、未提交、未推送。
- 新增 `OPS-002` Git 初始化验收记录。

### 修改

- 产品需求文档迁移到 `docs/product/` 并更新到 v0.3。
- `SPK-001` 从 Flutter/React Native 比选改为 Flutter 关键能力基线验证。
- `SPK-002` 聚焦 PP-OCRv5 mobile + ONNX Runtime Mobile 的真机可行性。
- `SPK-003` 增加 LAN、Tailscale/WireGuard、HTTPS、URL 校验和敏感日志验证。
- 更新 Sprint 00、风险表、代码目录和架构目录说明。
- 更新根目录导航和永久协作规程，移除 Flutter/React Native 二选一与 OCR 未定的过时表述。

### 决策

- 不使用飞书、Notion 等云平台作为项目事实源。
- 移动端统一采用 Flutter，不再进行 React Native 比选（ADR-0008）。
- 本地 OCR 首选 PaddleOCR PP-OCRv5 mobile + ONNX Runtime Mobile（ADR-0009）。
- 自定义 LLM 使用统一 API 配置和协议 Adapter；`ADR-0011` 已取代三种网络模式的 `ADR-0010`。

### 验证

- OPS-001 复核通过：本地链接和强制文件缺失数均为 0。
- 本机工具版本已核实：Flutter 3.38.5 stable、Dart 3.10.4、Git 2.51.1.windows.1。
- OPS-002 验收通过：`.git` 存在、当前分支为 `main`、项目 `.gitignore` 生效、远程为空、无首次提交。
- `DOC-001` 验收通过：47 个 Markdown 文件 UTF-8 内容正常，本地链接缺失数为 0，长期事实源已同步。
- OCR 与真实 LLM 服务兼容性仍需 `SPK-002`、`SPK-003` 的真机/真实服务实验，不以本地契约测试替代验收。

### SPK-001 LLM Provider / Android 工程切片

- 创建 `code/apps/mobile` Flutter 工程，实施统一“协议 + API Base URL + 可空 API Key + 模型”的配置页与持久化。
- 实现 OpenAI-compatible Chat Completions 和 Gemini native `generateContent` Adapter。
- API Key 使用 `FlutterSecureStorage`，普通配置使用 `SharedPreferencesAsync`；已保存 Key 不回填明文。
- 实现 URL 校验、超时、取消、常见 HTTP/网络错误映射、HTTP 明文风险与连接测试费用提示。
- 将 `LlmCancellationToken` 移至 Domain 层，消除 Domain 对 Provider 实现层的反向依赖。
- `flutter analyze` 通过：`No issues found`。
- `flutter test` 通过：21 个测试全部通过。
- 发现 Windows Flutter shader compiler 无法直接写入含中文的构建路径；增加 `android.overridePathCheck=true`，并通过纯 ASCII Junction 构建入口完成 Android Debug APK 构建。
- Android 构建结果：`BUILD SUCCESSFUL in 3m 4s`，178 个 actionable tasks；APK 大小 153,817,311 bytes。
- Android 12 真机通过 `adb install --no-streaming -r` 安装并成功启动，应用 PID 未发现错误级 Logcat。
- 新增验收记录 `tests/acceptance/SPK-001-llm-provider-baseline-2026-07-27.md`。
- `SPK-001` 保持 `DOING`：SQLite、分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 尚未完成。
