# BUG-001 分类创建异常与文字可读性修复验收记录

> 验收日期：2026-08-02  
> 任务：`BUG-001`  
> 平台范围：Android（iOS 明确未验证且不阻塞本次修复）  
> 结论：分类创建生命周期、重复提交、错误边界与分类 Chip 文字可读性修复完成；自动测试 458 项全绿、`flutter analyze` 无问题、Android API 36 模拟器人工验收通过，Logcat 无崩溃或未处理异常。

## 1. 目标与用户价值

用户可以稳定创建、查看和选择菜谱分类，不会因运行时异常中断，也不会因文字与背景对比度不足而无法辨认分类。缺陷源于 Android 验收时发现的分类创建异常与分类 Chip 文字对比度不足。

## 2. 范围与非目标

本任务包含：菜谱库与菜谱编辑页共享的分类创建弹窗；输入控制器生命周期；空名称、同名、超长名称与快速重复提交的错误边界；分类 Chip 未选中/选中/禁用状态的前景色；Widget 回归测试；Android 模拟器人工验收。

本任务不包含：重构分类领域模型、SQLite Schema 或 `AiRecipeBackendFacade`；调整 HTML 原型整体视觉体系；服务器同步；iOS 验收。

## 3. 实现落点

- `code/apps/mobile/lib/shared/widgets/create_category_dialog.dart`（新增）
  - 控制器由 State 持有并在 `dispose()` 释放，Dialog 退场动画结束后才卸载，避免关闭动画期间访问已释放控制器。
  - 提交前校验：空/仅空白 → “请输入分类名称。”；超长（>30）→ “分类名称不能超过 30 个字符。”；同名（大小写与首尾空白不敏感）→ “已存在同名分类。”。
  - `_submitted` 标记阻止按钮与回车竞态的快速重复提交。
- `code/apps/mobile/lib/features/library/recipe_library_page.dart`：分类创建改用共享对话框，创建后刷新、反馈与 `mounted` 保护。
- `code/apps/mobile/lib/features/recipe/recipe_edit_page.dart`：分类创建改用共享对话框；`await` 后增加 `mounted` 保护；新分类使用 `maxOrder + 1` 作为 `sortOrder`。
- `code/apps/mobile/lib/app/app_theme.dart`：分类 Chip 文字前景色显式指定为 `AppColors.greenInk`（与纸张米白/卡片/浅绿底对比度均 ≥ 6.9:1，满足 WCAG AA 4.5:1），`checkmarkColor` 同步为深绿；不依赖 Material 自动推导。
- `code/apps/mobile/test/features/recipe_library_page_test.dart`：新增 7 项回归（正常创建、空/空白拒绝、同名拒绝、超长截断、快速重复提交、分类筛选、三态颜色与对比度）。
- `code/apps/mobile/test/features/recipe_edit_page_test.dart`：新增编辑器内创建分类并自动选中回归。

## 4. 自动化验证

### 定向测试

```text
flutter test --no-pub \
  test/features/recipe_library_page_test.dart \
  test/features/recipe_edit_page_test.dart \
  test/app_theme_test.dart
```

结果：`14` 项全部通过。

### 静态分析

```text
flutter analyze --no-pub
No issues found!
```

### 全量回归

```text
flutter test --no-pub --concurrency=4
```

结果：`458` 项全部通过（基线 450 项，新增 8 项 BUG-001 回归）。共享 Chip 样式修改未对菜谱标签、筛选项及其他页面造成回退。

## 5. Android 模拟器人工验收

环境：Android API 36 模拟器（`sdk_gphone64_x86_64`），Debug APK 构建安装。

### 5.1 正常创建

1. 菜谱库点击“新建分类”chip，弹窗显示“NEW CATEGORY / 新建分类”、名称输入框、取消/创建按钮。
2. 输入 `QuickDinner`，点击“创建”。
3. 结果：弹窗关闭，分类筛选区立即出现 `QuickDinner` chip，页面显示“分类已创建。”反馈；应用无异常。

截图：`artifacts/BUG-001-2026-08-02/02-dialog-filled.png`、`03-library-after-create.png`。

### 5.2 异常输入

| 场景 | 结果 |
|---|---|
| 空名称提交 | 内联错误“请输入分类名称。”，弹窗保持打开 |
| 输入与既有分类同名 `QuickDinner` | 内联错误“已存在同名分类。”，弹窗保持打开 |

### 5.3 重启持久化

强制停止并重启应用后：首页“分类”显示 2 个分类，菜谱库筛选区 `QuickDinner` chip 仍在，证明走真实 SQLite 持久化而非页面内存。

### 5.4 分类筛选与选中态

点击 `QuickDinner` chip 后：chip 进入选中态（selected=true），列表过滤为该分类下的菜谱（新分类为空，显示“还没有菜谱”空状态）。筛选行为正确。

### 5.5 Logcat 检查

全量抓取 10093 行 Logcat，扫描结果：

- `FATAL EXCEPTION`：无匹配。
- `E/flutter`：无匹配。
- `TextEditingController` / `was used after being disposed`：无匹配。
- `FlutterError` / `Unhandled Exception`：无匹配（仅系统 BestClock 网络时间警告，与应用无关）。
- `AndroidRuntime`：仅 uiautomator 正常启动记录。
- 应用崩溃（`am_crash`/`am_anr`）：无匹配。

原始日志：`artifacts/BUG-001-2026-08-02/05-full-logcat.txt`。

## 6. 验收标准逐条对照

| # | 验收标准 | 结果 |
|---|---|---|
| 1 | Android 创建分类无未处理异常、无 `E/flutter`、无崩溃 | 通过（5.1、5.5） |
| 2 | 单次提交只创建一条，显示成功反馈，新分类立即出现在筛选列表 | 通过（5.1） |
| 3 | 筛选结果正确；重启后分类仍存在（真实 SQLite 持久化） | 通过（5.3、5.4） |
| 4 | 空名称、重复名称、仅空白、超长和快速重复提交显示稳定错误或被安全阻止 | 通过（5.2；仅空白/超长/重复提交由 Widget 测试覆盖） |
| 5 | Chip 三态显式设置前景色，对比度 ≥ 4.5:1，保持纸张米白与深绿体系 | 通过（主题显式 `greenInk`，测试计算与 paper/card/greenSoft 对比度 ≥ 6.9:1） |
| 6 | 共享 Chip 样式对标签、筛选项和其他页面无回退 | 通过（全量 458 项回归） |
| 7 | 新增 Widget 回归，`takeException()` 为空，新分类与反馈可见 | 通过（recipe_library_page_test 7 项） |
| 8 | Android 模拟器人工验收 + 截图 + Flutter/Logcat + 验收记录；iOS 记录为未验证 | 通过（本记录；iOS 未验证） |
| 9 | BUG-001 通过后重跑 UI-001 分类相关视觉验收 | 本次人工验收已覆盖分类创建弹窗、筛选 Chip 选中态与空状态，UI-001 分类视觉复验按规程执行 |

## 7. 限制与下一步

- iOS 未验证，不阻塞本次 Android 修复结论。
- 快速重复提交的真机精确双击场景未人工复现（提交为同步 `pop`），由 Widget 测试覆盖。
- 分类 Chip 文字颜色采用静态 `greenInk`（本 SDK `ChipThemeData.labelStyle` 为静态 `TextStyle`，无法表达按状态切换的颜色）；三态均使用同一显式颜色且对比度达标。
- 下一步按用户实施顺序进入 `SPK-003`：Android 真实 OpenAI-compatible 纯文本服务验证。
