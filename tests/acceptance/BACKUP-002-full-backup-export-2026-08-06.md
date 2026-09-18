# BACKUP-002 / BACKUP-003 备份格式核心与创建全量备份导出验收

- 任务：`BACKUP-002`（备份格式核心与媒体资产契约）、`BACKUP-003`（创建全量备份导出）
- 日期：2026-08-06
- 状态：等待项目负责人验收
- 性质：已实现功能的验收方法（Codex 未执行测试，由项目负责人执行后回传）
- 关联架构：`../../docs/architecture/RECIPE_BACKUP_RESTORE.md`
- 关联方案：`../../解决方案.md`
- 关联走查：`BACKUP-001-recipe-backup-restore-plan-2026-08-06.md`

## 1. 本轮交付边界

本轮实现的是「备份」方向的导出半边（BACKUP-002 格式契约 + BACKUP-003 创建全量备份导出），不含导入（BACKUP-004）、替换/回滚（BACKUP-005）与跨平台规模验收（BACKUP-006）。

已交付代码位置（`code/apps/mobile/`）：

- 领域契约：`lib/domain/backup/backup_archive_constants.dart`、`backup_errors.dart`、`backup_cancellation_token.dart`、`backup_manifest.dart`、`backup_records.dart`、`backup_repository.dart`
- 数据层：`lib/data/backup/sqlite_backup_snapshot_repository.dart`、`device_backup_archive_writer.dart`
- 应用层：`lib/application/backup/backup_export_use_cases.dart`、`lib/application/backend/ai_recipe_backend_facade.dart`
- 组合根：`lib/app/ai_recipe_backend_composition_root.dart`
- UI：`lib/features/backup/backup_page.dart`、「我的」页入口 `lib/features/profile/profile_page.dart`
- 测试：`test/domain/backup_manifest_records_test.dart`、`test/application/backup_export_integration_test.dart`

Codex 未执行：

- 自动测试（`flutter test`）。
- `flutter analyze`、编译或构建。
- 模拟器或真机测试。
- 真实设备上的大库（1000+ 菜谱、多图）性能与后台中断验证（归 `BACKUP-006`）。

## 2. 前置材料

1. 阅读 `docs/architecture/RECIPE_BACKUP_RESTORE.md` 中「导出」「归档格式」「媒体资产契约」章节。
2. 阅读 `解决方案.md` 中备份/恢复章节。
3. 构建并安装当前 Android Debug APK（`flutter build apk --debug` + `adb install -r`）。

## 3. 自动化测试（项目负责人可选的辅助检查）

Codex 已运行以下测试（2026-08-07，含归档复核修复回归），项目负责人可重新执行确认：

```bash
flutter test test/domain/backup_manifest_records_test.dart
flutter test test/application/backup_export_integration_test.dart
flutter test test/features/backup_page_test.dart
```

预期：

- `backup_manifest_records_test.dart`：`BackupArchivePaths.mediaEntryPath` 内容寻址、manifest 严格解析、未知 dataset/未来版本拒绝、`RecipeBackupRecord`/`CategoryBackupRecord` 全字段 roundtrip 全部通过。
- `backup_export_integration_test.dart`：全量导出归档内容（manifest/两个 dataset/media index/去重媒体）、媒体缺失失败与清理、创建前取消不写文件、幂等创建两次全部通过。
- `backup_page_test.dart`：备份页「另存为」出口 4 项（成功复制/取消不提示/失败提示/无最近备份时无入口，注入 fake 回调）。

## 4. 手动验收步骤与预期结果

前置：应用已安装并至少包含以下数据——至少 1 道带封面图与 2 张以上轮播图的正式菜谱、1 个分类、1 道回收站菜谱；或使用空库验证空状态。

### 4.1 入口与预估（默认/空/加载/错误态）

**操作**

1. 进入「我的」页，找到「数据与存储」条目（副标题「创建全量备份（.airecipe-backup）」）。
2. 点击进入「数据与存储」页。

**预期**

- 页面标题「数据与存储」，副标题「创建 .airecipe-backup 备份」。
- 进入时短暂显示「正在统计本地数据…」加载态。
- 随后显示 3 张统计卡：菜谱（含回收站）、分类、图片，以及「预估备份体积」。
- 有菜谱时数字与本地库一致；图片数等于全部菜谱（含回收站）引用的图片路径数。
- 空库时显示「暂无菜谱数据」提示，且「创建全量备份」按钮仍可点击。
- 说明文字明确「不包含冰箱库存、导入任务、设置与 API 密钥」，「回收站中的软删除菜谱也会一并备份」。
- 统计失败（例如数据库不可用）时显示可读错误与「重试」入口。

### 4.2 创建全量备份（成功态 + 进度态）

**操作**

1. 点击「创建全量备份」。
2. 在确认弹窗中核对提示内容（菜谱数、图片数、预估体积），点击「开始备份」。

**预期**

- 弹窗依次显示阶段文案：读取一致性快照 → 校验图片并计算哈希 → 写入备份归档 → 复核备份文件；进度条百分比单调递增，不倒退。
- 执行中「取消」按钮可用；返回键被禁用（`PopScope`）。
- 完成后弹窗自动关闭，页面出现绿色「上次备份已创建」卡片，显示文件名与体积。

### 4.3 备份文件本身（格式核心，BACKUP-002）

**操作**

1. 在应用文档目录的 `backups/` 子目录找到生成的 `.airecipe-backup` 文件（Android 应用私有目录，可通过 `adb shell run-as <package> ls files/backups` 或开发工具查看）。
2. 用 ZIP 工具（如 `unzip -l`）查看内部结构。

**预期**

- 文件扩展名为 `.airecipe-backup`，内部是标准 ZIP。
- 至少包含：`manifest.json`、`data/recipes.v1.ndjson`、`data/categories.v1.ndjson`、`media/index.v1.ndjson`、`media/sha256/` 目录下的媒体文件。
- `manifest.json` 包含 `formatVersion`、Dataset 描述（含各自 schemaVersion）、内容统计（菜谱数含回收站、分类数、媒体数）与时间戳。
- `data/recipes.v1.ndjson` 每行一个 JSON 菜谱对象；被回收站软删除的菜谱也在其中，字段包含食材、步骤、图片引用等，无设备绝对路径（图片以 `media/sha256/<ab>/<hash>.<ext>` 相对键引用）。
- `data/categories.v1.ndjson` 每行一个分类。
- `media/index.v1.ndjson` 每行一个媒体条目：`assetId` 为 SHA-256、含相对路径、文件大小、MIME 类型。
- `media/sha256/` 目录中：若多张图片内容完全相同，只出现 1 个文件（SHA-256 去重）；文件名即内容哈希；同一哈希的 ab 前两位目录一致。
- 归档内所有路径使用相对路径，不存在 `/data/user/...` 之类设备绝对路径。

### 4.4 取消与失败清理（取消态 + 错误态）

**操作**

1. 再次点击「创建全量备份」→「开始备份」，在进度阶段点击「取消」，观察按钮变为「正在取消…」并最终关闭弹窗。
2. 删除某道菜谱引用的图片文件（或在测试库中制造媒体缺失），再次创建备份。

**预期**

- 取消后弹窗关闭，页面回到预估态，出现「备份已取消。」提示；`backups/` 目录不残留 `.partial` 半成品或未命名临时包。
- 媒体缺失/不可读时备份失败：弹窗标题「备份失败」并显示可读中文错误（如媒体缺失），`backups/` 目录不残留半成品；点「知道了」返回后可重试。
- 全部成功后归档均通过「重读复核」，不会交付校验失败的包。

### 4.5 极限内容态（可选，规模数据留给 BACKUP-006）

**操作**

1. 使用超长菜名、大量食材、9 张以上图片的菜谱执行一次备份。

**预期**

- 备份正常完成；NDJSON 行完整可解析；媒体数量与图片实际数一致；不崩溃、不截断。

### 4.6 「另存为」出口（ADR-0036）

**操作**

1. 完成一次成功备份，页面出现「上次备份已创建」卡片（展示文件名、体积、完整文件路径）。
2. 点击「另存为（导出到其他位置）」，在系统文件选择器中选「下载」（或任意可访问目录）保存。
3. 在系统文件管理器（如文件 APP）打开「下载」目录，找到该 `.airecipe-backup` 文件。
4. 再次另存为，在文件选择器中点「取消」。
5. （可选）制造写入失败（如目标空间不足），观察提示。

**预期**

- 另存成功后出现提示：Android 提示「备份已保存到所选位置」（file_picker 在 Android 返回的路径是拼接的伪路径，不展示以避免误导），其他平台提示「备份已另存到：<路径>」；「下载」目录中可见同名 `.airecipe-backup` 文件，体积与备份页显示一致，可正常复制/传输。
- 文件选择器取消时不出现任何提示，页面状态不变。
- 写入失败（如所选位置不可写、源文件缺失）时提示「另存失败，请重试。」，应用不崩溃。
- 未创建过备份时页面不显示另存为入口。

## 5. 通过标准

- [ ] 我的页「数据与存储」入口可进入，预估/空/加载/错误状态齐全。
- [ ] 创建备份全流程成功，阶段进度单调推进，返回键执行中禁用。
- [ ] 生成的 `.airecipe-backup` 内部结构与 4.3 预期一致（ZIP + manifest + NDJSON + 内容寻址媒体 + 相对路径 + 去重）。
- [ ] 取消与媒体缺失失败路径均不残留半成品，错误文案可读。
- [ ] 两次创建同一数据产生两个不同文件名（含时间戳）的完整备份。
- [ ] 空库可创建空备份。
- [ ] 「另存为」能把备份导出到「下载」等可访问位置（4.6）；取消/失败路径提示正确。
- [ ] 自动化测试（第 3 节）通过（若项目负责人执行）。

## 6. 项目负责人回传格式

请复制以下内容回传：

```text
BACKUP-002/003 验收结果：通过 / 需修改

1. 入口与预估（默认/空/加载/错误）：通过 / 需修改（说明）
2. 创建备份成功与进度：通过 / 需修改（说明）
3. 归档结构（4.3 每项）：通过 / 需修改（说明缺失项）
4. 取消与失败清理：通过 / 需修改（说明）
5. 空库/极限内容：通过 / 需修改（说明）
6. 自动化测试结果：执行/未执行；通过 N 项 / 失败 N 项（附失败摘要）
7. 其他：无 / 说明
```

另请回传：

- 1 份真实 `.airecipe-backup` 文件的解压目录树文本（`unzip -l` 或等价输出）。
- `backups/` 目录截图或 `ls` 输出（证明无 `.partial` 残留）。
- 「另存为」结果：已导出到「下载」/ 未验证 / 说明（含文件管理器可见性）。

## 7. 当前限制

- 导入（BACKUP-004）、替换/回滚（BACKUP-005）尚未实现；本验收只覆盖导出。
- 1000+ 菜谱、多图的大库导出性能、后台中断与跨平台恢复归 `BACKUP-006`，本轮不验收。
- 「另存为」出口已实现（ADR-0036），Android SAF 落盘结果待项目负责人按 4.6 真机确认；iOS 未验证。
- 加密未承诺；备份含用户菜谱与图片，方案已提示不要公开分享备份文件。
