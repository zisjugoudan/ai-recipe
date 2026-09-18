# BUG-002：导入取消竞态验收记录

> 日期：2026-08-01  
> 最后更新：2026-08-02  
> 状态：`VERIFY`  
> 平台：Android（iOS 未验证）  
> 范围：Flutter 应用内部业务后端与导入进度页运行态

## 1. 验收目标

当用户在公开内容获取或 LLM 生成期间取消导入时，持久化的取消状态必须优先于后到的 Provider 成功、Schema 错误、网络错误或未知异常；如果 AI 草稿已经先写入 SQLite，系统必须安全、幂等地清理该草稿，且不得删除已发布菜谱。页面一旦接受取消终态，旧轮询或迟到 Future 也不得将当前页恢复为运行、失败或待确认。

## 2. 已实现

### 2.1 业务后端取消保护

- `ImportTask.localVersion` 作为单调递增的本地并发版本。
- `ImportTaskRepository.upsertTask` 支持 `expectedLocalVersion`，SQLite 使用 `id + local_version` 条件原子更新。
- 旧版本写入抛出 `ImportTaskWriteConflictException`，不再静默覆盖新状态。
- `CancelImportTask` 在冲突后重新读取并按终态幂等处理。
- Runner 在提交 `needsReview` 和写入失败状态前重新读取持久化任务；发现取消后统一返回取消结果。
- 迟到成功已经生成草稿时执行补偿删除。
- `SafeImportRecipeDraftDiscarder` 只删除 ID、来源匹配且仍为草稿的菜谱；正式菜谱和来源不匹配的数据不会被删除。
- Facade 与设备组合根已经接入草稿补偿清理能力。

### 2.2 导入进度页取消保护

- 取消按钮忙碌状态与 AI 请求 `_running` 解耦；获取内容和 AI 生成阶段仍可取消。
- 取消提交期间按钮短暂禁用并显示“正在取消…”，防止重复点击。
- 页面应用任务快照时拒绝更低 `localVersion`。
- 页面一旦接受 `cancelled`，默认拒绝同一任务之后所有非 `cancelled` 快照，即使迟到结果的版本更高。
- 只有用户明确选择文本或图片降级并重新开始时，才允许从取消态进入新一轮执行。
- Runner 返回的证据只在任务快照被接受时更新，避免页面任务状态与证据错配。
- 页面宿主的刷新回调改为安全通知；回调异常不得覆盖已经持久化并显示的真实任务结果。

## 3. 自动化验证

### 3.1 页面与公开内容联合定向

执行：

```text
flutter test --no-pub \
  test/providers/public_page_metadata_parser_test.dart \
  test/providers/public_content_adapters_test.dart \
  test/features/import_progress_page_test.dart
```

结果：37 项全部通过。页面回归覆盖：

1. 宿主刷新回调异常不会替换已经持久化的失败状态。
2. 取消后，旧轮询和版本更高的迟到 `needsReview` 都不能覆盖“解析已取消”。

### 3.2 业务后端取消回归

执行 ImportTask Runner、ImportTask 用例、SQLite ImportTask Repository、Facade 和 SQLite 真实文件取消竞态测试，结果 53 项全部通过。覆盖：

1. Provider 返回前取消，后到 Schema 错误不得覆盖 `cancelled`；关闭并重新打开 SQLite 后仍为取消态。
2. Provider 返回前取消，后到成功生成的草稿被补偿删除；关闭并重新打开 SQLite 后不存在孤立草稿。

### 3.3 全量质量门

- `flutter test --no-pub --concurrency=4`：480 项全部通过。
- `flutter analyze --no-pub`：`No issues found!`。
- 本轮相关 6 个 Dart 文件格式检查：无格式变化。

## 4. Android 已有人工验收

### 2026-08-02 修复前反馈

- 测试阶段：公开内容获取、AI 生成。
- 运行时取消按钮可点击：通过。
- 点击后显示“正在取消…”：通过。
- 取消提交后的即时状态：显示取消成功。
- 等待 Provider/AI 迟到返回后的页面状态：**失败，页面状态再次发生变化**。
- 强制停止并重启后的持久化状态：正常。
- 多余草稿或菜谱：未出现。
- 其他错误文字：无。

该结果证明 SQLite 取消持久化和草稿补偿正常，并定位出页面内状态单调性缺陷。本轮代码和自动化已经修复该缺陷，但尚未进行修复版本 Android 复测。

## 5. Android 修复版本复测清单

由项目负责人分别在“获取内容”和“AI 生成”阶段执行：

- [ ] 运行时取消按钮可点击。
- [ ] 点击后显示“正在取消…”。
- [ ] 取消完成后显示“解析已取消”。
- [ ] 等待 Provider/AI 迟到返回后，页面仍保持“解析已取消”。
- [ ] 强制停止并重启后，任务仍为取消状态。
- [ ] 未产生多余草稿或正式菜谱。
- [ ] 未出现新的错误文字或异常退出。

## 6. 安全检查

- 临时 API Key 已通过 App 的“清除已保存的 API Key”操作从安全存储清除，没有使用 `pm clear` 代替产品流程。
- 已有 Android Logcat 扫描中，临时 Key 标记、`Authorization` 和 `Bearer` 命中数均为 0。
- 仓库文本复扫未发现临时 Key 形态或真实 Provider 主机；`Authorization` / `Bearer` 仅出现在实现、测试与安全说明语义中，唯一长 Key 字面量是测试 Fixture。
- 本记录不保存真实 API 地址、Key、Authorization、完整 Prompt 或完整模型响应。

## 7. 结论

页面取消终态保护、SQLite CAS、取消持久化和草稿补偿均已通过自动化，`BUG-002` 进入 `VERIFY`。当前关闭条件只剩项目负责人完成 Android 修复版本复测，重点确认迟到 Provider/AI 返回后页面状态不再变化；复测通过前不得标记 `DONE`。iOS 未验证。
