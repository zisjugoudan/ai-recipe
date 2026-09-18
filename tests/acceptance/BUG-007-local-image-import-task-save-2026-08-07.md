# BUG-007 首页快速导入「拍照选图/剪贴板」导入修复与直接多模态识别验收

> 日期：2026-08-07
> 状态：VERIFY（等待项目负责人复测）
> 关联：`tracking/BACKLOG.md`（BUG-007）、`tracking/CHANGELOG.md`（2026-08-07）、
> `tracking/DECISIONS.md`（ADR-0029 修订）

## 背景与目标

### 问题一：导入任务无法保存

项目负责人反馈：首页快速导入「拍照选图」打开系统选图并选择图片后，提示
「导入任务暂时无法保存，请稍后重试」，无法创建本地图片导入任务。

根因：`import_tasks.source_platform` 的 SQLite CHECK 约束只允许
`('xiaohongshu','douyin')`，而本地图片/文本导入使用占位 URL
（`https://local-image/capture` / `https://local-text/capture`），经
`ImportSourceLink.parse` 解析后的平台值为 `web`。写入任务时违反表约束抛
`DatabaseException`，被 `AiRecipeBackendFacade` 的 catch 吞掉并替换为通用文案
「导入任务暂时无法保存，请稍后重试。」。

修复：SQLite schema v11 → v12，表重建迁移把约束放宽为
`IN ('xiaohongshu','douyin','web')`（SQLite 不支持 ALTER COLUMN 修改 CHECK
约束，采用「建临时表 → 复制实际列数据 → 删旧表 → 重命名 → 重建索引」的幂等
迁移，兼容 v9 之前缺少新列的旧库）；新装用户直接使用新约束建表。

### 问题二：拍照选图被当作「从链接导入」，且暴露本地占位链接

项目负责人反馈：拍照选图导入解析后变成了「从链接导入」，还给出一个本地占位链接
（`https://local-image/capture`），期望**直接交给多模态 AI 识别图片内容**，
而不是复用旧的链接导入操作。

三处根因与修复：

1. **排队占位任务无法用本地内容运行**：`ImportTask.startWithFallback` 与
   `ImportTaskRunner.runWithContent` 只允许 failed/cancelled 用内容运行；拍照选图
   新建的是 queued 占位任务，会抛 `ImportTaskTransitionException`。修复：允许
   queued，直接进入 extracting（跳过 fetching，不抓取公开链接），图片/文本内容由
   `runImportWithLocalImage` / `runImportWithText` 注入。
2. **进度页暴露假链接**：`_SourceCard` 无条件显示 `task.normalizedUrl`（占位 URL）
   与「网页链接」标签。修复：占位任务显示真实来源语义（「本地图片导入 /
   文本整理导入」），不暴露内部占位链接。
3. **识图方式与期望不符**：`_resolveLocalImagePlan` 自动（auto）模式默认本地 OCR
   优先（ADR-0029 旧规则）。修复：改为**多模态优先**——多模态可用直接多模态识别
   （视觉理解 + 文字转录），未配置/不可用时回退本地 OCR；用户显式选择某一路时
   尊重选择（ADR-0029 修订）。

## 前置条件

1. 重新构建并安装 Android 版本（本次有 SQLite schema **v12 表重建迁移**，
   **首次启动会自动迁移，不需要清数据**；如要验证升级迁移，请用安装过旧版本的
   设备直接覆盖安装，不要清空应用数据）。
2. 建议先制造一条旧版本数据用于升级验证：在升级前用旧版本创建一个小红书/抖音
   链接导入任务（不必完成，创建后立即返回首页），再升级安装。
3. （可选）准备一张含菜谱信息的图片、一段菜谱文本、一个普通网页链接。
4. 复测「直接多模态识别」时，请在「我的 → 识图引擎」确认多模态 LLM 已配置可用
   （否则预期回退本地 OCR 或给出识图引擎引导提示）。

## 复测用例

### 用例 1：拍照选图不再报「导入任务暂时无法保存」

**步骤**：首页 → 快速导入「拍照选图」→ 系统选图选择一张图片 → 回到 App。

**预期结果**：

- **不再弹出「导入任务暂时无法保存，请稍后重试」**。
- 正常进入导入进度页（后续是否因多模态未配置 / LLM 未配置而提示对应引导，属于
  既有行为，不影响本用例结论；只要不再报「暂时无法保存」即通过）。
- 返回首页后「有 N 个未完成导入」数量增加 1（任务已真实持久化）。

**回传**：选图后进入进度页的截图 + 首页未完成数量截图（如有）。

### 用例 2：拍照选图显示「本地图片导入」，不再显示网页链接/占位 URL

**步骤**：首页 → 快速导入「拍照选图」→ 选一张图 → 进入导入进度页，查看来源卡片。

**预期结果**：

- 来源卡片标题为「本地图片导入」、副标题类似「已选择本地图片，直接识别图片内容」、
  徽标为「图片」，图标为图片样式。
- **不出现**「网页链接」平台标签，**不出现** `https://local-image/capture` 之类
  的本地占位链接。

**回传**：进度页来源卡截图。

### 用例 3：拍照选图默认直接交给多模态 AI 识别（多模态可用时）

**步骤**（前提：识图引擎中多模态 LLM 已配置可用）→ 首页 → 快速导入「拍照选图」
→ 选一张含菜谱文字/信息的图片 → 观察进度页阶段文案。

**预期结果**：

- 进度阶段进入「正在识别图片内容」等图片识别阶段（不再走「正在获取公开内容 /
  正在抓取网页」的链接导入阶段）。
- 草稿确认页的证据面板显示来自图片识别的文字证据（多模态转录或 OCR）。
- 若多模态不可用，则回退本地 OCR（能识别则显示 OCR 证据；本地 OCR 也未安装则
  给出「请检查识图引擎设置」引导），属预期回退而非报错。

**回传**：进度页阶段文案截图 + 草稿确认页证据面板截图 + 实际识图方式说明
（多模态 / OCR / 引导提示）。

### 用例 4：剪贴板文本输入导入可正常创建任务

**步骤**：首页 → 快速导入「剪贴板」→ 粘贴一段菜谱文本 → 确认。

**预期结果**：

- 不报「导入任务暂时无法保存」，正常进入导入进度页。
- 来源卡片显示「文本整理导入」，不显示占位 URL。
- 首页「有 N 个未完成导入」数量增加 1。

**回传**：确认后进入进度页的截图。

### 用例 5：通用网页链接（非小红书/抖音）可正常创建任务

**步骤**：首页 → 快速导入「粘贴链接」→ 粘贴一个普通网页链接（任意非小红书/抖音
网站，如 `https://example.com/...`）→ 创建。

**预期结果**：

- 不报「导入任务暂时无法保存」，正常创建任务（解析阶段能否成功取决于页面内容与
  IMPORT-008 WebView 链路，不在本用例范围；只要任务创建成功即通过）。

**回传**：创建后任务列表/进度页截图。

### 用例 6：升级迁移后旧任务数据完好

**步骤**：按「前置条件 2」升级安装后，打开首页 → 点「有 N 个未完成导入」进入
未完成导入列表。

**预期结果**：

- 升级前创建的小红书/抖音任务仍在列表中，状态不变（排队/失败/待确认等），可打开
  继续处理。
- 升级前已有的历史导入任务数据未丢失（无空列表、无数据异常）。

**回传**：未完成导入列表截图。

## 需要回传的内容

1. 上述各用例的实际结果（通过/失败 + 截图）。
2. 若仍出现「导入任务暂时无法保存」，请回传当时的 Logcat 片段（可先执行
   `adb logcat | grep -iE "sqlite|database|import"` 复现时抓取）。
3. 若升级后旧任务缺失或状态异常，请描述具体现象。
4. 用例 3 的实际识图方式（多模态 / OCR / 引导提示）与草稿证据面板截图。

## 非目标（本轮不验证）

- 拍照选图后续的多模态 / OCR 识别 / LLM 生成**质量**（属 SPK-002 / IMAGE-001 等）。
- 剪贴板文本整理的 AI 生成质量。
- 通用网页链接的抓取成功与否（属 IMPORT-008）。
- iOS 平台（未验证，不阻塞本轮结论）。

## （可选）自动化验证

以下命令需在 `C:\AIM`（junction → `code/apps/mobile`）下执行；若环境不便可跳过，
以真机用例为准：

```text
flutter test test/data/app_database_v3_migration_test.dart
flutter test test/domain/import_task_test.dart
flutter test test/application/import_task_runner_test.dart
flutter test test/application/ai_recipe_backend_facade_test.dart
```

预期：

- `app_database_v3_migration_test.dart` 含新增用例「migrates v2 data to v12 and
  allows web platform import tasks」。
- `import_task_test.dart`：queued 任务可 `startWithFallback`（进入
  running/extracting/0.25），running 状态仍拒绝。
- `import_task_runner_test.dart`：queued 占位任务经 `runWithContent` 直接处理内容
  （阶段序列 extracting→ocr→generating→review，无 fetching）；running 仍拒绝。
- `ai_recipe_backend_facade_test.dart`：新增「多模态优先时直接用多模态识别」正面
  用例 +「多模态不可用时回退本地 OCR」+「识图路由全不可用 → providerRouteUnavailable
  且不暴露路径」；queued 允许、running 拒绝。
