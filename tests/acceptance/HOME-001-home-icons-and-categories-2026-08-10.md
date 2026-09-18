# HOME-001 首页/冰箱/导航图标替换与默认分类验收

> 任务：将冰箱、菜品分类、快速导图图标替换为设计素材，处理背景并统一尺寸；替换底部导航栏图标；添加 12 个默认分类并在首次启动时自动创建。
> 日期：2026-08-10
> 状态：VERIFY（等待项目负责人构建后验收）

---

## 变更摘要

1. **图标处理脚本**：新增 `code/apps/mobile/tool/process_home_icons.py`
   - 从 `design/assets/icon/home/` 读取源图。
   - 四角采样去底，保留原始图标颜色（不再统一染成单色）。
   - 缩放为 64×64 正方形 PNG，保留像素风锐利边缘。
   - `nav.png` 自动切分为 8 张（4 个 tab × inactive/active）。

2. **生成资产**：`code/apps/mobile/assets/icon/home/`
   - `fridge/`：4 张分区图标（冷藏区/冷冻区/常温区/其他区）。
   - `categories/`：12 张默认分类图标（主食/家常菜/快手菜/早餐/水产/汤羹/烘焙/甜品/素菜/肉类/轻食/饮品）。
   - `quick/`：4 张快速导入图标（链接导入/视频识别/图片识别/手动记账）。
   - `nav/`：8 张底部导航图标（home/library/fridge/profile × inactive/active）。

3. **pubspec.yaml**：注册上述 4 个资产目录。

4. **UI 组件扩展**：`lib/shared/widgets/pixel_ui.dart`
   - `PixelTab` 的 `icon`/`selectedIcon` 类型从 `IconData` 扩展为 `Object`。
   - `PixelTabBar` 支持传入 `Widget`（如 `Image.asset`）或 `IconData`。

5. **页面使用新图标**：
   - `lib/features/shell/app_shell.dart`：底部导航 4 个 tab 改用 `_NavIcon(Image.asset)`。
   - `lib/features/fridge/fridge_page.dart`：冰箱 4 个分区标题改用新图标。
   - `lib/features/home/home_page.dart`：快速导入 4 按钮 + 分类横向列表改用新图标。
   - `lib/features/library/recipe_library_page.dart`：分类筛选 chip 改用新图标。

6. **12 个默认分类**：
   - `lib/application/recipe/default_recipe_categories.dart`：定义默认分类 ID、名称与图标资产。
   - `lib/application/recipe/recipe_library_use_cases.dart`：`listCategories()` 时幂空检查，无分类则自动创建 12 个默认分类。

---

## 验收方法

### 前置条件

1. 本地环境已配置 Flutter SDK（>=3.10.4）。
2. 在 `C:\AIM`（junction → `code/apps/mobile`）下执行构建，避免中文路径导致 impellerc 写入失败。
3. 设备/模拟器为 Android（iOS 未验证）。
4. 如首次 `flutter clean` 后构建，需先配置代理 `127.0.0.1:7897` 以下载 sqlite3 hook。

### 构建命令

```powershell
# 在 C:\AIM 下执行
cd C:\AIM
flutter pub get
flutter analyze --no-pub
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

> Codex 未执行上述命令（ADR-0015）。

### 验收步骤

#### A. 图标资产检查

1. 运行脚本生成资产（如源图有更新）：
   ```powershell
   cd E:\AI\ai食谱\code\apps\mobile
   python tool/process_home_icons.py
   ```
2. 确认生成目录与文件：
   - `assets/icon/home/fridge/` 4 张
   - `assets/icon/home/categories/` 12 张
   - `assets/icon/home/quick/` 4 张
   - `assets/icon/home/nav/` 8 张
3. 随机抽查 3~5 张 PNG，确认尺寸为 64×64，文件大小均 < 1 KB。

#### B. 静态分析

1. 运行 `flutter analyze --no-pub`。
2. 预期结果：修改涉及的 7 个 Dart 文件无 error，无新增 warning。
   - `lib/features/home/home_page.dart`
   - `lib/features/fridge/fridge_page.dart`
   - `lib/features/shell/app_shell.dart`
   - `lib/shared/widgets/pixel_ui.dart`
   - `lib/application/recipe/default_recipe_categories.dart`
   - `lib/application/recipe/recipe_library_use_cases.dart`
   - `lib/features/library/recipe_library_page.dart`

#### C. 真机/模拟器视觉验收

1. **冷启动首次进入 App**：
   - 首页「分类」横向列表应显示 12 个默认分类（主食/家常菜/快手菜/早餐/水产/汤羹/烘焙/甜品/素菜/肉类/轻食/饮品）。
   - 每个分类卡片左侧应显示对应像素风图标，无白底/背景残留。
   - 截图并核对分类名称与图标一一对应。

2. **首页快速导入区**：
   - 4 个按钮（粘贴链接/剪贴板/拍照选图/手动创建）应显示新图标。
   - 图标保留原始颜色，无背景色块残留。

3. **底部导航栏**：
   - 4 个 tab（首页/菜谱库/冰箱/我的）均显示新图标。
   - 选中态不显示任何背景填充或边框，仅通过图标/文字颜色变化表达选中。
   - 图标与文字对齐，无拉伸/模糊。

4. **冰箱页**：
   - 切换到「库存」tab。
   - 4 个分区（冷藏区/冷冻区/常温区/其他区）标题左侧显示新图标。
   - 图标风格与快速导入/分类图标一致。

5. **菜谱库页**：
   - 顶部分类筛选 chip 应显示 12 个默认分类。
   - 默认分类 chip 左侧显示对应小图标（15×15）。
   - 自定义分类（如有）不显示图标，仅显示文字。

6. **重复启动/数据保留**：
   - 强停 App 后重新启动。
   - 默认分类不应重复创建；首页/菜谱库分类数量仍为 12 个。

### 预期结果

- 全部图标显示正常，无白底/背景残留。
- 12 个默认分类在首次启动时自动创建，图标与名称对应。
- `flutter analyze --no-pub` 无 error。
- 底部导航选中态无背景填充、无边框，仅通过图标/文字颜色变化表达选中。
- 各页面图标风格统一，尺寸适中，不模糊。

### 失败回传格式

如验收失败，请回传：

1. `flutter analyze --no-pub` 完整输出。
2. 出现问题的页面截图（圈出异常图标）。
3. Logcat 中 `FATAL EXCEPTION`、`AndroidRuntime`、`E/flutter` 相关日志。
4. 复现步骤（从冷启动/强停后/首次安装等）。

---

## 已知限制

- Codex 未执行 `flutter analyze` 与构建（ADR-0015）。
- iOS 未验证；导航栏/图标组件在 iOS 上行为理论上与 Android 一致，但需单独确认。
- 自定义分类暂无图标，显示为纯文字。
- 图标保留设计素材原始颜色；如需统一单色，需后续设计决策。

---

## 关联文件

- `code/apps/mobile/tool/process_home_icons.py`
- `code/apps/mobile/assets/icon/home/`
- `code/apps/mobile/pubspec.yaml`
- `code/apps/mobile/lib/shared/widgets/pixel_ui.dart`
- `code/apps/mobile/lib/features/shell/app_shell.dart`
- `code/apps/mobile/lib/features/home/home_page.dart`
- `code/apps/mobile/lib/features/fridge/fridge_page.dart`
- `code/apps/mobile/lib/features/library/recipe_library_page.dart`
- `code/apps/mobile/lib/application/recipe/default_recipe_categories.dart`
- `code/apps/mobile/lib/application/recipe/recipe_library_use_cases.dart`
