# 项目任务清单

> 状态只使用：`TODO`、`DOING`、`BLOCKED`、`VERIFY`、`DONE`、`CANCELLED`。
> 原则上同一时间只有一个主任务处于 `DOING`。

## 当前任务

| ID | 优先级 | 状态 | 任务 | 验收摘要 | 关联文档 |
|---|---|---|---|---|---|
| OPS-001 | P0 | DONE | 建立本地项目执行体系 | 目录分离；根目录必读规程；进度、任务、决策、风险、设计、测试模板可用 | `AGENTS.md` |
| OPS-002 | P0 | DONE | 初始化本地 Git 仓库 | `main` 分支可用；忽略规则生效；无远程和首次提交；验收记录完成 | `tests/acceptance/OPS-002-git-init-2026-07-27.md` |
| OPS-003 | P0 | DONE | 发布项目到 GitHub | `origin` 已关联 `zisjugoudan/ai-recipe`；首次提交和 `main` 推送完成；上游与敏感文件排除已验证 | `tests/acceptance/OPS-003-github-publish-2026-07-28.md` |
| OPS-004 | P0 | DONE | 调整永久测试协作流程 | Codex 不默认代测；每次提供可复现测试方法；项目负责人执行并反馈，Codex 归档后再关闭任务 | `AGENTS.md`、`tracking/DECISIONS.md`（ADR-0015） |
| OPS-005 | P0 | VERIFY | 脱敏后同步全部工作区改动到 GitHub 公开仓库 | 收款码、群二维码、视频工程、堆转储与工具缓存被 `.gitignore` 排除且逐项校验为 IGNORED；文本扫描无硬编码密钥与个人信息；工作区改动已提交并推送到 `origin/main`；仓库可见性为 public；克隆后缺少私有资产有明确补齐说明 | `tests/acceptance/OPS-005-github-public-release-2026-09-18.md`、`tracking/DECISIONS.md`（ADR-0043） |
| DOC-001 | P0 | DONE | 同步本轮技术方向到长期事实源 | 产品、流程、架构、任务与验收文档一致；Markdown 编码和链接检查通过 | `tests/acceptance/DOC-001-technical-direction-sync-2026-07-27.md` |
| SPK-001 | P0 | BLOCKED | Flutter 关键能力基线验证 | LLM Provider、SQLite v2、41 项测试和 Android APK 已通过；分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 仍待验证 | `research/spikes/SPK-001-cross-platform-framework.md` |
| SPK-002 | P0 | TODO | PaddleOCR 本地引擎与插件验证 | Manifest v2、Android 私有文件/Content URI 解码、Detector/Recognizer 推理、简化检测后处理、CTC 解码、能力探测、稳定错误和远程 HTTPS 图片安全暂存已通过自动化测试；真实模型真机指标、完整 DB 后处理、方向分类器、iOS 与跨进程互斥仍待完成 | `research/spikes/SPK-002-local-ocr.md` |
| SPK-003 | P0 | VERIFY | 自定义 LLM API 多协议兼容性 | OpenAI-compatible Android 首阶段真实连接、结构化生成和 SQLite 恢复通过；Key 已清除；真实取消、Gemini、局域网服务和 iOS 待验证 | `research/spikes/SPK-003-local-llm-api.md` |
| ARCH-001 | P0 | DONE | 确定移动端架构与代码结构 | 按 Flutter 架构基线初始化可运行工程 | `docs/architecture/MOBILE_ARCHITECTURE.md` |
| BACKUP-001 | P0 | DONE | 设计全量菜谱备份与恢复方案 | 全量边界、版本化归档、导入预检、冲突与回滚方案已通过项目负责人走查（2026-08-06，7 项走查维度全部通过，附 3 项实施前细化建议） | `docs/architecture/RECIPE_BACKUP_RESTORE.md`、`design/flows/RECIPE_BACKUP_RESTORE_FLOW.md`、`tests/acceptance/BACKUP-001-recipe-backup-restore-plan-2026-08-06.md` |
| BACKUP-002 | P0 | VERIFY | 备份格式核心与媒体资产契约 | `.airecipe-backup`（标准 ZIP）内 manifest + 版本化 NDJSON Dataset + `media/sha256/` 内容寻址媒体；三套独立版本；严格序列化校验；SHA-256 作为 mediaAssetId；归档不依赖设备绝对路径；媒体缺失/不可读/哈希失败时备份必须失败。实现已完成：领域契约 + 单事务快照 + Isolate ZIP 写入器 + 重读复核/原子发布/失败清理；domain 与真实 SQLite 集成测试已运行 **33 项全部通过**（2026-08-07 修复"归档复核失败：清单内容不一致"——List 身份比较改逐字节比较、条目计数重复累计修正、媒体改按 sha256 内容去重后回归）。等待项目负责人验收 | `docs/architecture/RECIPE_BACKUP_RESTORE.md`、`tests/acceptance/BACKUP-002-full-backup-export-2026-08-06.md` |
| BACKUP-003 | P0 | VERIFY | 创建全量备份导出 | 一致性快照 → 统计空间预估 → 数据关系与媒体校验 → NDJSON 流式写入 → SHA-256 去重 → Manifest → 重读归档复核 → 原子发布；失败清理半成品；取消可重试；我的页「数据与存储」入口与创建备份 UI（默认/空/加载/进度/取消/成功摘要/失败清理）。实现已完成：`BackupExportUseCases` + Facade/组合根接线 + `BackupPage` 状态全覆盖；端到端集成测试已运行 **33 项全部通过**（含新增归档复核/媒体内容去重用例，2026-08-07 回归）；「另存为」出口已实现（ADR-0036：成功后可把备份导出到用户选择位置并展示完整路径，`backup_page_test.dart` 4 项通过）。等待项目负责人验收 | `docs/architecture/RECIPE_BACKUP_RESTORE.md`、`tests/acceptance/BACKUP-002-full-backup-export-2026-08-06.md` |
| BACKUP-004 | P0 | VERIFY | 备份导入：预检、合并与冲突 | ZIP 安全校验（Zip Slip/Bomb/重复路径/非法路径/大小上限）→ Manifest 与版本兼容 → 数据与媒体哈希校验 → Schema 迁移 → ImportPlan → 默认合并（同 UUID 一致跳过、同 UUID 不同冲突处理、仅名称相似不自动合并）→ 两阶段提交与失败清理。实现已完成：领域导入契约（ImportPlan/冲突/规范化哈希）+ `DeviceBackupArchiveReader`（staging+安全校验）+ `SqliteBackupImportRepository` + `BackupImportUseCases`（预检只读→合并/替换执行→失败回滚）+ Facade/组合根接线 + 导入页（选择文件→预检→策略→执行→完成）+ staging 清理账本。**2026-08-07 修复合并预检「相同记录被当作新增写入」bug**（集成测试 `test/application/backup_import_integration_test.dart` 复现）：`_resolveMergeRecords` 只按 conflicts 判断，预检标为「同 UUID 同内容跳过」的记录无 conflict 被当真新增写入；修复为 `BackupImportPlan` 新增 `skippedRecipeIds/skippedCategoryIds`，`_buildPlan` 收集、`_resolveMergeRecords` 跳过。**2026-08-07 再修「替换恢复大备份失败无提示、替换后全空」**（项目负责人复测）：①`_tryRestoreFromRollback` 误传已取消导入 token → 恢复第一步即中断 → 库停在清库后空状态，改内部独立 `restoreToken`；②`applyImport` 新增 `clearExisting` 参数（替换模式同一 SQLite 事务内清库+写入，原子回滚）替代两步式清库；③审阅页渲染 `_error`（失败不再无提示）+ 取消/替换失败引导文案。备份模块测试（domain + 导入/导出集成 + 备份页）**23 项全部通过**。**2026-08-07 导入返回主界面刷新**（项目负责人反馈"导入完成后加载数据量突增无 UI 反馈，用户以为导入失败"）：`BackupPage` 新增可选回调 `onDataChanged`，`_openImport` 从导入页返回后触发（刷新主界面/菜谱库/备份页统计）并重载预估，`ProfilePage._openBackupPage` 透传；`backup_page_test` 新增「导入返回后触发 onDataChanged 并重新预估」。等待项目负责人验收 | `docs/architecture/RECIPE_BACKUP_RESTORE.md`、`design/flows/RECIPE_BACKUP_RESTORE_FLOW.md`、`tests/acceptance/BACKUP-004-backup-import-2026-08-07.md` |
| BACKUP-005 | P0 | VERIFY | 替换恢复与回滚 | 高级替换模式：全包预检、删除影响预览、强制创建并验证回滚备份、二次确认；失败显示"当前库未改变"或"已从回滚备份恢复"；启动时清理未完成回滚与 staging。实现已完成（随 BACKUP-004 一并验收）：替换范围预览 + 强制创建并验证 `ai-recipe-rollback-<时间戳>` 回滚备份 + `applyImport(clearExisting: true)` 单事务清库+写入（原子，失败整体回滚原库保留）+ 孤儿图片清理 + 失败回滚本次媒体并尽力从回滚备份恢复（恢复用独立令牌，不再继承已取消导入 token）；回滚备份保留期限待 BACKUP-006 定值 | `docs/architecture/RECIPE_BACKUP_RESTORE.md`、`design/flows/RECIPE_BACKUP_RESTORE_FLOW.md`、`tests/acceptance/BACKUP-004-backup-import-2026-08-07.md` |
| BACKUP-006 | P0 | TODO | 跨平台与规模验收 | Android/iOS 实机创建与恢复；超大库（1000+ 菜谱、多图）导出性能与内存；损坏包、未来版本、空间不足故障路径验收；回滚备份保留期限定值 | `tests/acceptance/BACKUP-002-full-backup-export-2026-08-06.md` |
| APP-001 | P0 | DONE | 创建本地优先菜谱库后端用例 | 菜谱/分类 CRUD、筛选、回收站、稳定错误和游客 SQLite 重开已通过 176 项全量测试 | `docs/architecture/RECIPE_LIBRARY_APPLICATION.md` |
| APP-002 | P0 | DONE | 实现游客模式后端能力策略 | 会话元数据、八类能力矩阵、稳定原因码、能力守卫和 SharedPreferences 严格序列化已通过 197 项全量测试 | `docs/architecture/APP_ACCESS_CAPABILITIES.md` |
| APP-003 | P0 | DONE | 建立应用后端组合根与主功能统一门面 | 统一 Facade、设备组合根、能力路线、草稿确认/放弃、重复确认保护和完整导入链路已通过 217 项全量测试 | `docs/architecture/APPLICATION_BACKEND_FACADE.md` |
| APP-004 | P0 | DONE | 完成 Flutter 本地业务后端与前端接线契约 | 标签、首页/详情聚合、浏览历史、菜谱/分类完整生命周期、烹饪会话与多计时器、本地设置、LLM/OCR 接线、SQLite v3 迁移和统一 Facade 已完成；356 项全量测试通过 | `docs/architecture/FLUTTER_BUSINESS_BACKEND_COMPLETION.md` |
| UI-001 | P0 | VERIFY | 按 HTML 原型实现 Flutter P0 页面并接入本地业务后端 | Flutter 原生高保真复刻、三栏导航、FAB、像素组件和 16 张 Android 页面截图已完成；分类创建异常与对比度缺陷已由 `BUG-001` 修复并通过验收，等待项目负责人对 BUG-001 修复后的最终视觉确认。真实 OCR/LLM、视频和 iOS 由后续任务验证 | `design/prototypes/`、`design/reviews/UI-001-html-flutter-gap-analysis-2026-08-01.md`、`tests/acceptance/UI-001-flutter-native-prototype-replication-2026-08-01.md`、`tests/acceptance/BUG-001-category-creation-stability-2026-08-02.md` |
| `UPDATE-001` | P1 | `VERIFY` | Gitee 在线更新：检查更新页显示当前版本 + 检查更新按钮；有新版时弹窗展示版本号/更新说明，按钮「以后再说」/「立即升级」；仅 Android，下载 APK 并调系统安装器安装；「我的」页新增入口 | Gitee 公开仓库 eb-Dog/delicious-food 已确认；实现完成待项目负责人按验收文档验证 | `tests/acceptance/UPDATE-001-gitee-update-2026-08-11.md` |
| `SETTINGS-001` | P1 | `VERIFY` | LLM 与识图设置结构重分类 | 「我的」页两个入口：①「LLM 模型」集中菜谱生成 LLM（普通）+ 多模态 LLM 图片识别（独立配置）；②「识图引擎」仅保留 OCR（图片识别方式/本地 OCR 模型/云端路线），移除多模态配置表单。已移动 6 个私有类/函数、清理/新增 import、改标题。IDE 诊断无错误；Codex 未执行 analyze/构建（ADR-0015），等待验收 | `tests/acceptance/SETTINGS-001-llm-ocr-restructure-2026-08-11.md` |
| `HOME-001` | P1 | `VERIFY` | 替换首页/冰箱/导航图标并添加 12 个默认分类 | 已实施：①Python 脚本处理设计素材去底/保留原色/64x64 统一；②生成 fridge 4 张/categories 12 张/quick 4 张/nav 8 张；③pubspec.yaml 注册；④PixelTab/PixelTabBar 支持 Widget 图标；⑤app_shell/首页/冰箱/菜谱库改用新图标；⑥定义 12 个默认分类并在 `listCategories` 时幂空自动创建。2026-08-11 追加：移除底部导航栏选中态的绿色激活方框边框与绿色背景填充，选中态仅通过 active/inactive 图标和文字颜色表达。Codex 未执行 flutter analyze/构建（ADR-0015），等待项目负责人验收 | `tests/acceptance/HOME-001-home-icons-and-categories-2026-08-10.md`、`code/apps/mobile/tool/process_home_icons.py` |
| `COMMUNITY-001` | P2 | `VERIFY` | 「我的」页新增「加入交流群」入口，展示群二维码海报 | 已实施：①`assets/community/qq_group.jpg`（源图 design/assets/交流群.jpg，1352×2405）注册；②新建 `CommunityPage`（引导卡片 + 群二维码海报 + 全屏预览 + 进群提示）；③「我的」页「支持我们」下方新增入口。IDE 诊断无错误；Codex 未执行 flutter analyze/构建（ADR-0015），等待项目负责人验收 | `tests/acceptance/COMMUNITY-001-join-community-2026-08-11.md` |
| BUG-001 | P0 | DONE | 修复分类创建异常与分类文字可读性 | Android 创建分类不再出现未处理异常；分类持久化、筛选和异常输入稳定；分类 Chip 各状态文字对比清晰；新增 Widget 回归与 Android 验收证据 | `tests/acceptance/BUG-001-category-creation-stability-2026-08-02.md` |
| BUG-002 | P0 | VERIFY | 修复导入取消被后到 AI 结果覆盖的竞态 | 页面取消终态保护、低版本拒绝、迟到结果/证据隔离和安全宿主刷新已实现；37 项联合定向、53 项后端定向、480 项全量测试及静态分析通过，等待 Android 复测迟到响应与重启流程 | `docs/architecture/IMPORT_PIPELINE.md`、`tests/acceptance/BUG-002-import-cancellation-race-2026-08-01.md` |
| BUG-003 | P0 | VERIFY | 修复小红书公开链接无法产出可用公开内容 | Android 新复测已离开 65%，但真实无完整分享参数的链接被平台重定向到推荐页，解析不到目标内容；已按“响应是否包含目标笔记 ID”分类判空错误（含目标 ID 不可重试、不含则 contentUnavailable 可重试），扩展登录/不可用/风控标记并本地化为中文可操作文案，等待 Android 复测 | `docs/architecture/RECIPE_GENERATION_PROCESSOR.md`、`docs/architecture/IMPORT_PIPELINE.md`、`tests/acceptance/BUG-003-xiaohongshu-public-link-2026-08-02.md`、`tracking/DECISIONS.md`（ADR-0016） |
| BUG-005 | P0 | DONE | 允许用户主动结束不可重试的失败导入 | Android 已确认原 failed 任务可执行“结束此导入”→“正在结束…”→“解析已取消”，首页未完成数量 `6 → 5`，强停重启后仍不计入未完成 | `docs/architecture/IMPORT_PIPELINE.md`、`docs/architecture/APPLICATION_BACKEND_FACADE.md`、`tests/acceptance/BUG-005-failed-import-dismiss-2026-08-02.md` |
| BUG-006 | P0 | VERIFY | 修复多模态测试连接误报超时，并将 OCR / 多模态改为证据融合 | 已实施：P0-1 分阶段诊断（流式 Transport 观察响应头/首字节/正文空闲，连接 8s/首字节 15s·45s/空闲 15s 分层时限，HTTP 405/413/415/408/504/409/423/400/422 与首字节/正文空闲/SSE/取消/图片断言分类）+ 三入口（检查基础连接/检查图片能力标准 256×256 图断言/用我的图片测试）+ 设置页分阶段结果卡；P0-2 证据融合（ImportTextFragment.sourceType、ImportImageRecognitionRoute.ocrAndMultimodal、VisionFusionImportContentProcessor 独立执行/部分成功/无证据不生成空草稿、Prompt 带来源标记、确认页来源标签）。新增 vision_probe/融合处理器测试。全项目 IDE 诊断无错误，未运行测试/构建/真机（ADR-0015），等待项目负责人复测 | `docs/architecture/VISION_RECOGNITION_STRATEGY.md`、`tracking/DECISIONS.md`（ADR-0028）、`tests/acceptance/BUG-006-multimodal-diagnostics-and-vision-fusion-2026-08-05.md` |
| IMAGE-002 | P0 | VERIFY | 多图多模态识别与多草稿：多模态只转录图片文字，纯 LLM 判断独立/合成并分组生成 | 按 ADR-0029 已实施：多模态提示词改“忠实转录图片文字”（sourceType=ocr + sourceMediaOrder 分组）；`ImportRecipeDraftResult`/`ImportTask` 支持多草稿（SQLite v9 新列 JSON 数组，确认页指定草稿、进度页逐份确认）；新增 `MultiImageDraftSplitProcessor` 分组判断（independent→多草稿 / combined→单草稿 / mixed→按图号分组，失败回退合并）；链接与手动图片均默认多模态优先、多模态未配置/不可用时回退本地 OCR（2026-08-07 修订 `_resolveLocalImagePlan`，原为手动图 OCR 优先）。**已修两条关键缺陷**：①组装顺序反了（grouping 包在 multimodal 前导致图组数恒 0、永远单草稿），已交换为 multimodal→grouping→LLM；②分组循环进度公式不含组号导致组间进度倒退、触发"任务进度不能倒退"→被 `_latestCancellationOrRethrow` 掩盖成 "Only queued import tasks can be run." 整单失败，已改为每组独立子区间单调递增 + 原始异常不再掩盖。**已按项目负责人反馈重做多草稿弹窗**：像素风容器（替换 Material AlertDialog），支持点击整行进编辑确认、右侧删除图标单项删除（二次确认、回收站可恢复）、勾选框多选 + 底部"删除所选 (N)"批量删除、全部确认；新增 `deleteImportDrafts`（部分删除剩余草稿重排、删光取消任务）。新增 grouping 测试。全项目 IDE 诊断无错误，未运行测试/构建/真机（ADR-0015），等待项目负责人复测多图独立多草稿/合成单草稿 | `docs/architecture/VISION_RECOGNITION_STRATEGY.md`（第 15 章）、`tracking/DECISIONS.md`（ADR-0029）、`tests/acceptance/IMAGE-002-multimodal-multi-image-2026-08-05.md` |
| IMPORT-010 | P0 | VERIFY | 解析过程实时显示当前操作详情（progressDetail 全链路） | `ImportTask` 新增展示字段 `progressDetail`（advance 支持"仅详情变化"生成新版本、`_copy` 哨兵模式区分保留/清空）；`ImportPipelineProgressCallback` 增加可选 `[String? detail]`（旧两参回调兼容）；`AdvanceImportTask`/runner 透传；SQLite v11 迁移 `progress_detail` 列 + 仓库读写；各处理器上报（多模态"正在识别第 x/N 张图片"、分组"识别为 N 份独立菜谱"、生成"正在生成第 x/N 份菜谱草稿/草稿《标题》已生成"）；进度页动态显示详情。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测（复测中偶发"导入失败·不可重试"已修复：多草稿并发生成上报改为 `reportChain` 串行队列 + runner `_advance` 写冲突/进度倒退有限重试，见 CHANGELOG 2026-08-06） | `解决方案.md`、`tests/acceptance/IMPORT-010-progress-detail-2026-08-06.md` |
| BUG-004 | P0 | DONE | 修复首页未完成导入入口错误进入新建任务 | 2026-08-02 Android 实测通过：按原任务 ID 打开最近创建任务，不误入新建页，数量 12→12、无重复任务，取消后数量减少，强停重启可恢复；成功完成路径因 BUG-003 阻塞未执行，iOS 未验证 | `docs/product/USER_STORIES.md`、`tests/acceptance/BUG-004-unfinished-import-resume-2026-08-02.md` |
| IMPORT-001 | P0 | DONE | 定义导入任务状态机 | 状态、错误、取消、重试、重启恢复、SQLite v2 迁移和 Application 用例已通过 41 项全量测试 | `docs/architecture/IMPORT_PIPELINE.md` |
| IMPORT-002 | P0 | DONE | 定义内容获取与导入调度内核 | 统一内容 Schema、Adapter Registry、Runner、单执行器 Dispatcher、取消和稳定错误映射已通过自动化验收 | `docs/architecture/IMPORT_CONTENT_ADAPTER.md` |
| IMPORT-003 | P0 | DONE | 实现公开内容获取与降级 | 小红书/抖音公开 Fixture、受限 HTTP Transport、稳定错误映射和人工粘贴/媒体降级已通过 94 项全量测试 | `docs/architecture/PUBLIC_CONTENT_IMPORT.md` |
| IMPORT-004 | P0 | VERIFY | 支持待确认草稿重新生成 | 草稿确认页新增“重新生成”按钮，复用会话原文证据重新调用 LLM 并安全替换旧草稿；失败保留旧草稿；无会话证据时禁用并提示；等待 Android 复测 | `docs/architecture/IMPORT_PIPELINE.md`、`docs/architecture/APPLICATION_BACKEND_FACADE.md`、`tests/acceptance/IMPORT-004-regenerate-import-draft-2026-08-02.md` |
| IMPORT-005 | P0 | VERIFY | 菜谱多封面图与详情页轮播 | 编辑页可从相册多选图片复制到应用私有目录，详情页顶部轮播展示（无图回退像素插画）；SQLite v4 新增 recipe_images；等待 Android 复测 | `docs/architecture/RECIPE_LIBRARY_APPLICATION.md`、`tests/acceptance/IMPORT-005-recipe-cover-images-2026-08-02.md` |
| IMPORT-006 | P0 | VERIFY | 导入图文自动带多张封面图 | 链接导入生成草稿时自动把公开内容配图经安全暂存下载到菜谱私有封面目录并写入草稿 `images`/`coverImage`，详情页轮播展示；单张失败 best-effort 跳过、全部失败草稿仍生成；丢弃草稿同步清理封面目录；等待 Android 复测 | `docs/architecture/IMPORT_PIPELINE.md`、`docs/architecture/RECIPE_LIBRARY_APPLICATION.md`、`tests/acceptance/IMPORT-006-remote-covers-2026-08-03.md` |
| IMPORT-007 | P0 | VERIFY | 链接导入启用本地 OCR：图片与正文整合后交给 AI 生成菜谱 | 小红书/抖音图文链接导入时，本地 OCR 能力就绪则自动启用 `ocr: local`：图片经远程安全暂存后识别成文字，与页面正文文本整合为同一批证据交给 LLM 生成草稿；OCR 未安装时回退纯文本路径（有文字的图文仍可生成，纯图片内容提示先安装 OCR 模型）；等待 Android 复测 | `docs/architecture/IMPORT_PIPELINE.md`、`docs/architecture/APPLICATION_BACKEND_FACADE.md`、`tests/acceptance/IMPORT-007-link-import-ocr-2026-08-03.md` |
| IMPORT-008 | P0 | DOING | 链接导入改用内置浏览器内核（WebView）抓取网页文本与图片，通用任意网页 | 按 ADR-0018/ADR-0019：后台隐藏 WebView 加载任意 URL 网页，显式阶段状态机（NAVIGATING→WAITING_CONTENT→EXTRACTING→FETCHING_IMAGES）提取文本与图片地址，图片逐张顶层导航取图（同源 fetch + Canvas 兜底）；复用 `ImportContent` 领域模型与 OCR/LLM/草稿流程；登录墙/验证码/空内容/加载失败分类给出中文提示与降级入口；Android 平台通道先行，iOS（WKWebView）暂缓。Android 重构版已实现（状态机/逐张取图/移动 UA/移除 JS 桥/小红书不回退直连），**顶层图片同源读取需 SPK-007 真机 Spike 前置验证**，等待项目负责人构建真机分阶段复测。**竞态与生命周期加固（《解决方案.md》第一阶段，ADR-0032）已合入**：RequestContext 请求隔离（请求/导航/图片三套 generation）、新请求 superseded 终止旧请求、cancelFetch 原生取消、Dart 总超时成为真实绝对上限、renderer gone 销毁重建 WebView、请求专属图片目录 `webview-imports/<requestId>/images`；新增 cancelled/superseded/rendererGone 错误分类。**内容就绪+平台提取+可观测性（《解决方案.md》第二/三阶段，ADR-0033）已合入**：小红书/抖音/通用三套 readiness 探测（目标 ID 校验、非登录/验证/删除/受限）、抖音特化提取（`__RENDER_DATA__`）、通用 JSON-LD Recipe/Article 优先 + ResultValidator、图片阶段 SSL/renderer gone 不整单失败、请求级 OBS 汇总日志（阶段耗时/重定向/HTTP/readiness/指纹/图片统计/最终分类）。等待项目负责人复测 `tests/acceptance/IMPORT-008-webview-lifecycle-race-2026-08-06.md` 与 `tests/acceptance/IMPORT-008-webview-readiness-observability-2026-08-06.md` | `tracking/DECISIONS.md`（ADR-0018/0019）、`tracking/IMPORT-008-配图403与加载超时-交接-2026-08-03.md`、`research/spikes/SPK-007-top-level-image-nav.md`、`docs/product/AI食谱应用产品需求文档.md` 5.3、`tests/acceptance/IMPORT-008-webview-import-2026-08-03.md` |
| IMPORT-009 | P0 | DOING | 导入体验补强：快速导入分流 + 批量导入 + 未完成导入列表 + 进度条/正文去重修复 | ①进度条填充高度为 0（FractionallySizedBox 缺 heightFactor）已修；②正文与简介重复已修（description==bodyText 去重）；③快速导入 4 按钮分流：粘贴链接→添加页、剪贴板→文本输入导入（像素弹窗，自有 LLM 整理）、拍照选图→本地 OCR 图片导入（新任务）、手动创建→直接打开编辑器；④链接批量导入（多链接一次创建多个任务，成功后进入任务列表）；⑤新增未完成导入列表页（排队/解析中/待确认/失败/已取消，单个取消/删除、一键清空已结束），首页"有 N 个未完成导入"入口改打开列表；⑥Facade 新增 deleteImportTask(s)/createLocalImageImportTask/createLocalTextImportTask。**2026-08-06 按用户反馈新增未完成导入长按多选删除与全选**：长按任意任务进入选择模式并选中该项、点按切换选中（空选自动退出）、顶部"已选择 N 项"+全选/取消全选+"取消"、底部"删除所选 (N)"批量删除（二次确认）；**用户追加需求：进行中/待确认任务也可删除，弹窗提示**——deleteImportTask 对进行中/待确认任务先取消（中断解析）再清理全部关联草稿（主草稿+附加草稿 allResultRecipeIds，防孤儿）后删除，确认弹窗提示"其中 X 条正在进行或待确认：删除将中断解析并移除已生成的 AI 草稿"；新增 7 项 Widget 测试定义。**2026-08-06 弹窗风格统一（用户反馈"弹窗的风格没统一"）**：新建共享像素弹窗组件 `pixel_dialogs.dart`（PixelConfirmDialog/PixelInfoDialog + showPixelConfirm/showPixelInfo），清除全部原生 AlertDialog（12 处）、删除三个本地重复确认类（_PixelConfirmDialog/_LibraryConfirmDialog/_DevConfirmDialog）、菜谱编辑页"未保存修改"弹窗对齐基准样式；多草稿选择/生成进度/分类输入/剪贴板输入等特殊弹窗保留。代码与测试定义已完成，等待项目负责人构建 Android 复测 | `docs/product/AI食谱应用产品需求文档.md` 5.3、`tests/acceptance/IMPORT-009-import-experience-2026-08-03.md` |
| FRIDGE-002 | P0 | DOING | 实现冰箱库存批次管理 | 游客/登录本地离线可维护同名多批次，默认按冷藏区/冷冻区/常温区/其他区分区展示，支持位置、数量、日期、临期/过期状态、筛选和用完/丢弃；本轮实现：领域模型 + SQLite v5（inventory_batches/inventory_changes）+ CRUD/摘要/筛选 + 轻拟物分区库存 UI（聚合展开批次、五种状态徽标、空态）+ 批次新增/编辑页（存放位置跟随分区、数量为空=未知、同名提示）+ 四栏导航「首页/菜谱库/冰箱/我的」。**2026-08-07 补充（项目负责人反馈"库存食物不能删除，应点进去编辑时提供删除按钮"）**：`fridge_batch_edit_page.dart` 编辑态在「保存修改」下方新增红色「删除批次」按钮（`deleteInventoryBatchButton`）——二次确认（`showPixelConfirm`，confirmColor 红）后调 `AiRecipeBackendFacade.deleteInventoryBatch(batch.id)`，成功后返回库存页并刷新；新增态不显示。测试：`fridge_page_test` 新增「新增态无删除按钮 / 编辑态有 / 取消保留 / 确认删除成功」。**再补充（2026-08-07 项目负责人反馈①冰箱/我的页不显示全局添加菜谱 FAB；②推荐页「仅使用已选食材」位置不合理）**：`app_shell.dart` 全局 FAB 改仅首页/菜谱库显示（`_selectedIndex <= 1`）；`fridge_recommendation_view.dart` 把「仅使用已选食材」开关从底部移到顶部选择区（紧跟快捷操作，独占一行、文字左对齐），底部仅留推荐按钮（改 `Stack` 悬浮、带纸张背景，列表视窗不再被挤压）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015） | `US-011`、`FRIDGE-001`、`DESIGN-005`、`design/UI_HANDOFF.md`（UI-014/015）、`tests/acceptance/FRIDGE-002-inventory-batches-2026-08-04.md` |
| RECO-001 | P0 | DOING | 实现按库存推荐本地菜谱 | 用户先选择本次想优先使用的库存食材，仅匹配本地正式菜谱，离线分组展示现在就能做/可能能做/缺 1 样/缺 2 样/优先清库存，标注已选命中、冰箱已有但未选择、缺失、规格待确认与规格不符；本轮实现：确定性离线匹配用例 + 推荐页（按分区点选食材、快捷选择、底部 CTA、分组结果、临期标记、更多缺失折叠、查看详情/开始烹饪）；已按 ADR-0022 升级为"基础食材+属性规格+三值匹配"（精瘦肉→猪肉=能做、猪肉→精瘦肉=可能能做+视为可用、五花肉→精瘦肉=规格不符），库存录入页支持渐进式规格候选，草稿确认页显示"种类待确认"轻量标识；已按 ADR-0023 升级为"食材家族+模糊匹配"（辣椒→青椒、蘑菇→香菇、鱼→鲈鱼、青菜→小白菜=可能能做，干辣椒→青椒=规格不符），`IngredientImportance` 要求强度（菜名核心/可选不计缺失），修复 AI 导入调料误计缺失与库存规格未落库回退解析；缺失项加入购物清单因购物清单模块未实现，本版仅展示缺失。**2026-08-07 按项目负责人反馈：推荐结果「缺 1 样」「缺 2 样」分组整组折叠（默认折叠只显示标题，点标题展开/收起，箭头指示；展开后保留「查看更多」）**——`_ResultsSectionState._collapsed` + `_buildGroup(collapsible)` + `_GroupTitle(onToggle/collapsed)`。**再按项目负责人反馈参考原型 HTML 把推荐分组改为「方案A · 像素旗标带」**——对照 `prototype.css#.rg-ribbon` 用 `_GroupRibbon`（实色带+`PixelCut.sm` 切角+3px 投影 + 计数徽标 `soft`/`ink`/`PixelCut.xs` + 虚线延伸 `_RibbonLinePainter` 6px/12px）替换 `_GroupTitle`，配色 现在就能做=绿/可能可以做=琥珀/库存不足=红/缺 1·缺 2=琥珀/优先清库存=蓝，折叠保留。**2026-08-08 按项目负责人反馈优化推荐匹配关系（ADR-0038）**：推荐主循环重写为三阶段全局批次分配——同一批次在单道菜谱内最多满足一个需求（`usedBatchIds`），身份匹配（YES）按需求属性分面数从多到少优先分配（精确库存优先：五花肉批次优先五花肉、普通猪肉满足猪肉），家族/替代（MAYBE）只召回候选不代表已拥有（占用单一批次、不计命中/缺失/临期、数量不统计），需求去重由按基础 ID 改为按「基础+分面」（猪肉/五花肉为独立需求），数量只统计最终分配批次；未收录基础食材（如鸡蛋）退化为同名精确匹配。新增 `_RecipeRequirement`/`_isYesFor`/`_requirementKey`/`_facetCount`/`_unitOf`，删除 `_bestMatch`/`_BestMatch`；测试新增 3 项原则用例并修正 3 项旧断言（未收录食材无批次→缺失）。**2026-08-08 推荐页折叠与「更多缺失」对齐原型**：「现在就能做」「优先清库存」分组改可折叠（`collapsible: true`）；每张推荐卡片内新增「食材」区折叠开关（`_RecommendationCard` 改 StatefulWidget）；「更多缺失」按原型 `details.fold` 重做 `_FoldableMore`（切角+描边+summary 折叠+fold-body 列表，默认折叠，去掉查看更多/分页）。等待项目负责人复测 | `US-012`、`FRIDGE-001`、`SPK-008`、`ADR-0022`、`ADR-0023`、`ADR-0038`、`design/UI_HANDOFF.md`（UI-016）、`tests/acceptance/RECO-001-recommendation-2026-08-04.md` |
| FRIDGE-003 | P0 | DOING | 实现下厨后库存确认扣减 | 完成烹饪后自动生成预计消耗，用户逐项确认/调整/换批次/取消后才更新批次和变更记录，不产生负库存；本轮实现：库存变更领域模型 + Facade 扣减方法 + 扣减确认页（预计消耗、默认到期更早批次、逐项勾选/改量/换批次、确认才更新） | `US-013`、`FRIDGE-002`、`RECO-001`、`design/UI_HANDOFF.md`（UI-016 扣减面板）、`tests/acceptance/FRIDGE-003-deduction-2026-08-04.md` |
| UI-002 | P1 | DOING | HTML 原型 1:1 视觉复刻（页面逐层对齐） | 项目负责人反馈当前界面"与原型类似但非 1:1"；第一轮主题级像素基建（ADR-0024）：阶梯缺角三档精确化、按钮/输入/FAB/Chip 像素缺角化、全局米白渐变+圆点背景纹理、自绘等分像素底部导航、空状态 92px 浮动图标块、分区标题/虚线分隔；第二轮修「我的」页：inset 描边带消除"w"波浪、身份卡米白+52px 头像、能力配置改"能力配置"标题+平直 row-item、`PixelRowTile` 平直化+图标块 40px；第三轮对照 prototype.css 统一描边规范与切角：inset 描边带精确化、"--px-line"(line2 1.5px)/"--px-line-ink"(ink 2px) 对齐、`.ri-tag` 1px 描边、绿色系背景 greenSoft、`.notice` 去全描边、sec-title 补投影色块、背景圆点 1px、身份卡右上角绿色「登录/注册」按钮、HTML 缺角组件统一切角核查；第四轮按反馈修正：背景渐变→纯色 #F3F1E9、row-item 描边改 inset 1.5px 描边带（`_InsetRectBorderPainter`）、徽标描边改 inset 1px 带、按钮/FAB 墨色描边 2px→1.5px、`app_theme_test` 背景断言改 transparent；第五轮对齐设置页顶部 navbar：`PixelPageAppBar` 返回按钮改 32×32 pxc-xs 切角卡样式（inset 1.5px 描边）、背景 card 94%、底部实线改 2px 虚线、标题 15px/w800、高度 52，LLM/OCR/隐私设置页移除 eyebrow；第六轮按项目负责人指定改整行条目立体描边：`PixelRowTile` 外框改像素风立体边框（左/上亮 #545454、右/下暗 #000，1.5px，`_BevelBorderPainter`），chip 选中态描边补 green-deep 1.5px；第七轮复刻冰箱页（UI-014）+ 分区可折叠：`.seg` 二级切换（PixelSeg）、「我的冰箱」+ri-tag.ok 去推荐、stat-grid cols4 摘要、筛选 chip 平直化、冰箱箱体（#EBEFEA+pxc-lg+2px 描边+门缝虚线）、分区卡可折叠（zone-ic/zone-add/agg-arrow/zone-body 分隔/冷冻抽屉把手/空分区虚线框）、food-chip 状态变体+conf 标签、筛选联动隐藏无匹配分区、空状态 92px 图标块、背景透明露出 #F3F1E9；第八轮补冰箱状态标签 + 长按拖动排序/跨区移动：批次展开行补 conf 标签、`InventoryBatch` 加 sortOrder + DB v7 迁移 + 仓库排序 + 用例/Facade `moveBatchToZone`/`reorderBatch` + UI LongPressDraggable/DragTarget 区内排序与跨区移动；第九轮修复复测问题：嵌套 DragTarget 双回调导致跨区无效（chip 级按名称插入 + 分区级兜底 + 250ms 去重）、`_aggregateCondition` 未记录 normal 导致有日期显示未设置（补 hasNormal）、拖动触发全量刷新（移除 onDataChanged，本地即时更新）、`loadAggregated` 改按 sortOrder 排序；第十轮修复日期保存与"有些不能设置"（单位/分类下拉补入不在预设列表的当前值防断言崩溃、showDatePicker 用默认 Material 主题渲染 + 异常兜底）、冷冻区冰冻视觉+动画（_FoodChip frozen 浅冰蓝 + AnimatedSwitcher 冰冻/解冻过渡）、PixelConfTag 加 1px inset 内描边；第十一轮修复：①批次编辑保存后日期不立即同步（`_FridgePageState` 加 `_localRefresh` 本地计数，编辑保存/批次操作成功后递增传给 `_InventoryView`，立即重载）；②冰冻/解冻动画未生效（根因 AnimatedSwitcher 淡入淡出遇跨区重建新 State 无动画起点；改 `_FoodChip` 自维护 450ms AnimationController + `_FrostFillPainter` 8px 逐格从左往右变色，同位置 frozen 变化由 didUpdateWidget 捕获、跨区新 chip 由 `_pendingFrostAnim` 标记在 initState 播放）；第十二轮修复：①非冷冻区误显冰冻样式（根因 `_FrostFillPainter` 在 `freezing=false`+`progress=0` 时整块画冰蓝，静止态非冷冻 chip 的 value 落成 0；静止态进度恒为 1，仅动画触发时 `forward(from: 0)`）；②逐格动画阶梯感（格子 8px→16px、时长 450ms→900ms）；③日期同步补漏（`didUpdateWidget` 在 refreshToken 变化时先置 `_allItems = null` 再加载，避免 `_allItems ??=` 沿用旧缓存）；第十三轮按《解决方案.md》+`FRIDGE_DRAG_AND_FROST_ANIMATION_HANDOFF.md` 重构拖拽与冷冻动画：新增 `_FrostKind`/`_ArrivalEvent`（dragSessionId/moveEventId/stableItemId/animationKind，到达事件只在保存成功+目标挂载后生成一次、消费即删，删除名称+250ms 去重与 `_pendingFrostAnim`）；每分区单一最终 DragTarget（onMove 算插入序号/onLeave 清高亮/onAccept 提交）+ 会话级一次性提交守卫；`AggregatedInventoryItem` 加 `stableId`（批次 ID 集合）稳定身份；组件拆分（静态 `_FoodChipView` 无 controller 用于拖拽影子/占位，正式 `_FoodChip` 只消费到达事件后播放）；二维逐格 `_FrostGridPainter`（12dp 小格≥2 行、图标侧垂直居中冰核、曼哈顿距离由近到远、每 tick 一格、冷冻逐个出现/解冻严格逆序消失、550ms、描边/投影/图标离散切换不再 Color.lerp）；同区排序/非冷冻互移/长按/无效释放不播动画，保存失败恢复原位+中文提示；减少动态直接显示最终样式；第十四轮修推荐页食材样式对齐 HTML + 待确认改黄色替代标签：选择区食材 chip 改 HTML .food-chip（平直+底部 3px 硬投影+inset 1.5px 描边+图标+名称/数量+状态变体，选中态 green-soft 底+green-deep 描边+名称后 ✓，已过期 0.7 透明度，关闭水波纹）、快捷按钮改 .chip 平直样式、推荐卡食材标签重构为 HTML .mini-tag（已选命中=绿/冰箱已有可补选=蓝/缺失=琥珀带数量/规格不符=红）、待确认（MAYBE）改黄色“替代 牛肉→猪肉”标签（`IngredientMatchDetail` 新增 `matchedStockName`，移除“待确认”文本行，仅保留“视为可用”按钮）；第十五轮修推荐卡：缺失标签由琥珀改灰色（`_tagMiss*` 灰系，替代标签独立黄色 `_tagSub*`）、移除“视为可用”按钮（删 onConfirmMaybe 参数链，`confirmedBases` 保留恒空）、移除“有该食材，数量是否足够需确认”文本、推荐卡头部加 56×56 封面（`coverImage` 显示本地图/无图回退绿块+菜名图标，新增 `_cardCover`/`_coverIcon`）；第十七轮修首页快速导入：去 2×2 网格与外层绿底卡、改 HTML .quick-grid 一行 4 个 quick-btn（竖排 36×36 green-softer 图标块 pxc-xs 切角 + 文字，card 底 + pxc-sm 切角 + 墨色 1.5px inset 描边同 FAB 添加按钮）；剪贴板改文本输入导入（点“剪贴板”弹文本输入框 → `createLocalTextImportTask` + `runImportWithText` 允许 queued、自有 LLM 整理成菜谱，`ImportProgressPage` 加 `initialText`/`_runTextFallback`，不再读系统剪贴板预填链接）；等待项目负责人复测并继续逐页反馈 | `ADR-0013`、`ADR-0024`、`design/prototypes/`、`tests/acceptance/UI-002-visual-1v1-2026-08-04.md`、`design/flows/FRIDGE_DRAG_AND_FROST_ANIMATION_HANDOFF.md`、`tests/acceptance/UI-002-fridge-drag-frost-animation-2026-08-04.md` |
| UI-WELCOME-001 | P1 | VERIFY | 欢迎页按参考图视觉重设计 | 二次调整实现完成：五个漂浮元素按容器宽度比例定位、缩放并限制合理范围；「巴食」由 `CustomPainter` 使用两套 13×13 手工点阵逐格绘制；主插画采用右下投影、深绿外轮廓、浅色框带、上左高光、下右压暗和内侧压边的像素立体相框；红框外特性列表、登录/游客、隐私与错误行为保持不变。已补充 320/430/600px、减少动态效果、加载与错误状态的测试定义和人工验收方法。Codex 本轮未运行 Flutter/Dart 测试、静态分析、构建或设备验证，等待项目负责人按验收文档回传结果 | `design/prototypes/design-docs/UI-001-欢迎页.md`、`tests/acceptance/UI-WELCOME-001-welcome-page-redesign-2026-08-11.md` |
| RECO-002 | P2 | TODO | 用现有食材生成新菜谱 | 仅在可用 LLM Provider 下提供独立入口，生成结果进入草稿确认，不与本地确定性推荐混排 | `FRIDGE-001`、`AI-002` |
| PERF-001 | P0 | VERIFY | 菜谱列表与推荐性能优化（《解决方案.md》第一批） | ①`RecipeSummary` 摘要分页（keyset）+ `countRecipes` 总数；②消除 N+1（摘要单条 SQL、推荐轻量批量 2 次 SQL、首页摘要+分类计数）；③菜谱库页改 `SliverGrid` 虚拟化 + 滚动加载；④推荐匹配移入后台 `Isolate`（`RecommendationExecutor`，测试注入直算）；⑤推荐每组 Top 10 + 查看更多；⑥250ms 防抖 + 最新请求优先；⑦标准化器缓存 + 词典 Map 化 + 家族/上下位哈希索引；⑧schema v10 复合索引。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/PERF-001-recipe-list-recommendation-performance-2026-08-06.md` 复测并回传性能数据 | `解决方案.md`、`ADR-0030`、`tests/acceptance/PERF-001-recipe-list-recommendation-performance-2026-08-06.md` |
| PERF-003 | P0 | VERIFY | 回收站加载与删除性能优化（修复「回收站加载/删除太慢」） | 加载根因：回收站原 `listRecipes` 全量加载每条菜谱（含食材/步骤/图片，N+1）→ 新增轻量只读模型 `TrashRecipeSummary`（id/title/deletedAt）+ `RecipeRepository.listTrashSummaries()` 单条 SQL（`deleted_at IS NOT NULL ORDER BY deleted_at DESC, id DESC`）替代；`RecipeTrashPage` 切换轻量摘要并显示删除时间。删除根因：清空/批量删除原逐条「全量加载 + 独立事务」→ 新增 `permanentlyDeleteRecipesByIds`（单事务 500/批 IN 删除 + ON DELETE CASCADE 清子表）与 `softDeleteRecipesByIds`（单事务分批 UPDATE `deleted_at`），`emptyRecipeTrash` 改轻量取 id 批量删、`ProfilePage._clearTestRecipes` 改轻量摘要 keyset 分页收集 id + 批量软删除；配套 fake 仓库补实现；`PixelFloat` 支持系统减少动态（测试基建 + `accessibilityFeaturesTestValue` 注入）。验证：trash 页 3 项 + 菜谱库用例/集成 + sqlite 仓库（含 520 条跨批永久/软删除用例）**30 项全部通过**；`flutter analyze --no-pub` 本轮文件无新增问题。等待项目负责人实机确认回收站加载不再卡顿、清空/删除测试数据秒级完成 | `CURRENT.md`、`tests/acceptance/PERF-001-recipe-list-recommendation-performance-2026-08-06.md` |
| PERF-002 | P0 | VERIFY | 图片导入链路性能优化（《解决方案.md》第二批：P0 四项 + 深度思考开关） | ①任务级图片缓存 `TaskScopedImageCache`（`OcrRemoteImageStager` 实现，按 https URL 去重，识别与封面共用一次下载，处理器链结束后 `disposeAll()`）；②多模态识别有限并发流水线（并发 2 的 `_runConcurrent` 工作池，结果保序，单张失败折叠为 null 不拖垮整批，取消立即终止，全部失败可重试）；③识别前压缩重编码 `ImageRequestCompressor`（image 包 decode→bakeOrientation→超长边等比缩放→encodeJpg q85；普通照片 2048px、长宽比≥2.5 截图 4096px；无收益保留原图，不改磁盘原图）；④深度思考开关 `LlmReasoningMode{fast,deep}` + `LlmReasoningCapability` + `LlmConnectionConfig.reasoningMode`（默认 fast，兼容旧配置），OpenAI-compatible `reasoning_effort`/Gemini `thinkingConfig` 映射，图片转录 fast、分组 fast、最终结构化跟随 config.reasoningMode。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/PERF-002-import-pipeline-performance-2026-08-06.md` 复测 | `解决方案.md`、`ADR-0031`、`tests/acceptance/PERF-002-import-pipeline-performance-2026-08-06.md` |
| BUG-007 | P0 | VERIFY | 修复首页「拍照选图/剪贴板/通用网页」导入创建任务报「导入任务暂时无法保存，请稍后重试」+ 拍照选图直接多模态识别 | ①根因：`import_tasks.source_platform` 的 SQLite CHECK 约束只允许 `('xiaohongshu','douyin')`，而本地图片/文本导入占位 URL 与通用网页导入解析后的平台值为 `web`，insert 违反约束抛 DatabaseException，被 Facade catch 吞掉并替换为「导入任务暂时无法保存」。修复：schema v12 表重建迁移放宽约束为 `IN ('xiaohongshu','douyin','web')`（SQLite 无法 ALTER COLUMN 改 CHECK，采用建临时表→复制实际列→删旧表→重命名→重建索引的幂等迁移，兼容 v9 前缺列旧库）；迁移测试新增 web 平台任务真实路径写入/读取与旧数据保留。②**后续修复（2026-08-07）**：拍照选图导入解析后被展示为「网页链接」且暴露本地占位 URL，期望直接多模态识别。三处修复——`startWithFallback`/`runWithContent` 允许 queued 占位任务直接用本地内容运行（跳过 fetching）；`_SourceCard` 对占位任务显示「本地图片导入/文本整理导入」真实来源语义；`_resolveLocalImagePlan` 自动模式改为多模态优先（多模态未配置回退本地 OCR，ADR-0029 修订）。测试：domain/runner/facade 三文件更新（queued 允许、running 拒绝、多模态优先正面用例、多模态不可用回退 OCR、路由全不可用→providerRouteUnavailable 不暴露路径）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/BUG-007-local-image-import-task-save-2026-08-07.md` Android 复测 | `tests/acceptance/BUG-007-local-image-import-task-save-2026-08-07.md`、`docs/architecture/IMPORT_PIPELINE.md`、`tracking/DECISIONS.md`（ADR-0029 修订） |
| COOK-001 | P0 | VERIFY | 烹饪模式无时长步骤自定义计时并同步到菜谱 | 无时长（durationSeconds 为空/0）步骤显示「自定义本步计时」按钮；像素弹窗输入分钟/秒，确认后创建计时器并把时长写入菜谱步骤（只重建目标步骤，其他字段保留，localVersion 递增）；取消无副作用；非法时长/步骤不存在稳定报错。实现已完成：领域 `updateRecipeStepDuration` + Facade 透传 + 烹饪页按钮/弹窗/同步逻辑；domain/facade/widget 三处测试已更新。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/COOK-001-custom-timer-sync-2026-08-07.md` 复测 | `tracking/DECISIONS.md`（ADR-0037）、`docs/product/AI食谱应用产品需求文档.md` 5.4.4、`tests/acceptance/COOK-001-custom-timer-sync-2026-08-07.md` |**2026-08-09 追加（按钮亮色与暗色同长·补根因）**：项目负责人指出「阴影宽度比主体宽很多，主体由内容撑起而阴影不是」——真正根因在 `_CookingPixelSurface` 的 Stack：外部约束 tight（Expanded 整行宽）时 Stack 尺寸 = 整行宽、`Positioned.fill` 阴影被撑满整行，而亮色主体按内容收缩贴左上；已给 Stack 加 `fit: StackFit.expand` 让主体填满面板，主体 = Stack = 阴影同宽，阴影只露右下 2px（此前追加的半透明底色修复只是放大项）。IDE 诊断无错误，等待复测 |**2026-08-09 追加（按钮亮色与暗色同长）**：修复「上一步/下一步与计时器部分按钮亮色比暗色（阴影）短」——根因是按钮/面板主体底色半透明（`0x1AFFFFFF`/`0x14FFFFFF`/`_panel`/`_panelStrong`），半透明底叠在深绿背景上几乎不可见、只有右下像素阴影可见，视觉上暗色比亮色长；新增不透明实色 `_panelSolid`（`0xFF41584C`，比背景亮一档深绿）替换全部带阴影 `_CookingPixelSurface` 的半透明底色（`_CookingNavButton` 上一步/下一步、`_CookingIconAction` 暂停/继续/完成计时、`_TimerCard` 计时器卡片、当前步骤面板、`_CookingStateIcon` 完成大图标、`_CookingMiniButton`），删除不再使用的 `_panel`/`_panelStrong`。IDE 诊断无错误，等待项目负责人复测 |
| BUG-008 | P0 | VERIFY | 修复慢速 LLM 服务下「最终结构化生成」固定 120 秒超时失败（链接单图导入识别成功但生成失败） | 根因：`requestTimeout` 默认 120 秒，两处设置页（LLM/识图引擎）超时档位仅 30/60/120，慢速本地模型（Ollama/LM Studio 等）生成完整菜谱 JSON 或识别单图超过 120 秒即被客户端主动中断（`kind=timeout`）。修复：①两处设置页超时档位扩展为 30/60/120/180/300/600 秒；②结构化生成与多模态识别的超时错误文案补充「在 LLM/识图引擎设置中调大请求超时」指引；③LLM 设置页新增「测试结构化生成」诊断区块（输入任意文本走真实结构化生成链路，展示耗时与生成字符数，用于判断超时瓶颈在 LLM 本身还是图片识别等其他环节；`LlmSettingsUseCases.testStructuredGeneration` + Facade 透传，与 `testConnection` 共用 `_resolveApiKey`）。**追加修复（2026-08-07，排查「测试 30 秒、实际 120 秒超时」）**：④`_buildConfiguration` 未继承已保存 `reasoningMode`（恒 fast）、测试 prompt 未跟随存储配置——若存储为 deep（PERF-001，无 UI 入口不可见），实际导入发送 `reasoning_effort: high` 明显变慢而测试恒 fast，造成「测试快、导入慢」假象；已修复为保存/测试均继承 `existing.reasoningMode`、测试 prompt 显式传 `reasoningMode: existing?.reasoningMode`、`LlmStructuredGenerationResult` 新增 `reasoningMode` 字段并在设置页展示（如「· 模式 fast」）；另确认测试为短文本、实际导入 prompt 为「原文+整图 OCR 转录全文」（最大 40000 字符），长文本生成耗时更高属正常。测试：`llm_settings_use_cases_test`（`testStructuredGeneration` 组 5 项：成功耗时+系统/用户消息、空文本 invalidInput、Provider 超时脱敏、deep 继承、保存保留 deep）。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人按 `tests/acceptance/BUG-008-request-timeout-options-2026-08-07.md` 复测（含用例 7/8） | `tests/acceptance/BUG-008-request-timeout-options-2026-08-07.md`、`tracking/CHANGELOG.md`（2026-08-07） |
|| BUG-009 | P0 | VERIFY | 修复「识别图片导入后确认草稿」触发 framework 断言崩溃（_elements.contains / deactivated widget's ancestor） | 项目负责人反馈：图片识别导入后确认草稿时崩溃，日志含 `'framework.dart': _elements.contains(element) is not true` 与 `Looking up a deactivated widget's ancestor is unsafe`，并有系统返回键事件。根因（只读审查 `import_draft_review_page.dart` 与 `import_progress_page.dart`）：各 async 方法在 await 后使用 context 做导航/弹窗前，仅用 `if (!mounted) return;`（`State.mounted`）防护——但在路由退场过渡期 Element 已 deactivate 而 `State.mounted` 仍为 true，此时 `Navigator.of(context)`/`showDialog(context)` 会触发上述断言。修复：将「await 后使用 context 做 push/pop/showDialog」前的判断改为 `if (!context.mounted) return;`（`context.mounted` 在 deactivated 期为 false，可覆盖该窗口）。涉及位置：确认页 `_save`/`_discard` 的 pop；进度页 `_openReview` 的 confirmAll pop、单草稿保存后 pop、catch 回退 push/pop、`_pushReviewPage` 开头、`_showMultiDraftPicker` 的 showDialog。纯 setState 处仍保留 `State.mounted`。全项目 IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）；等待项目负责人复测「识别图片导入→确认草稿」在保存/放弃/按返回键时不再崩溃 | `tracking/CHANGELOG.md`（2026-08-07） |
|| VID-001 | P2 | VERIFY | 制作开源项目「开发历程分享」视频（16:9，约 7 分 20 秒，B站技术分享向） | 分镜 v2 已由项目负责人放行（`01_脚本与分镜_v2.md`，28 镜）。Remotion 工程完成全部 28 镜实现，修复 OffthreadVideo 竖屏横纹 bug（切换 `<Video>`）。成片已渲染：`视频剪辑/开发历程分享视频/video/out/promo_final.mp4`（1920×1080/30fps/440s，带 BGM）+ `promo_final-nobgm.mp4`（无 BGM 版，渲染中）。逐镜头终检 12 处关键点全部通过（四宫格/三卡/流程图/协作光标等，视觉核对），终检记录：`视频剪辑/开发历程分享视频/tests/终检记录_v1.md`。TTS 配音草稿 7 段已生成（`video/public/voice/`，S1/S2 因当时 API 请求格式错误未生成；成片不依赖配音，为字幕+BGM+SFX 方案）。等待项目负责人完整观看验收 | `视频剪辑/开发历程分享视频/01_脚本与分镜_v2.md` |
| SPK-008 | P1 | TODO | 验证中文食材标准化、同义词和单位换算 | 使用真实中文菜谱与库存样本量化名称命中、误判、数量可判定率和保守降级边界，形成采用/拒绝/继续研究结论 | `research/spikes/SPK-008-ingredient-normalization.md` |
| AI-001 | P0 | DONE | 定义 LLM Provider 接口 | OpenAI-compatible 与 Gemini native 已通过统一接口、配置校验、错误映射和 Fixture 测试 | `docs/architecture/LOCAL_LLM_NETWORK_SECURITY.md` |
| AI-002 | P0 | DONE | 实现结构化菜谱生成 Processor | 受限 Prompt、严格 Schema、草稿持久化、取消提交点和真实 SQLite 重开验证已通过 113 项全量测试 | `docs/architecture/RECIPE_GENERATION_PROCESSOR.md` |
| AI-003 | P0 | VERIFY | OpenAI-compatible 纯文本模型结构化输出兼容加固 | 受控纯 JSON/fence/短前言/闭合推理包装已通过真实服务与严格 Schema；草稿和 SQLite 恢复通过；待 BUG-002 Android 真实取消收口 | `docs/architecture/RECIPE_GENERATION_PROCESSOR.md`、`research/spikes/SPK-003-local-llm-api.md` |
| OCR-001 | P0 | DONE | 定义 OCR Provider 与插件 Manifest | 统一 Provider、严格 Manifest、OCR 证据字段和导入预处理流水线已通过 141 项全量测试 | `docs/architecture/OCR_PLUGIN.md` |

| OCR-002 | P0 | DONE | 实现远程图片安全暂存层 | 已实现 HTTPS-only、全量 DNS 公网校验、固定已验证 IP 连接、逐跳重定向复检、TLS 主机名校验、受限响应解析、MIME + magic bytes、体积/边长/像素限制、超时/取消和临时文件回收；错误不泄露 URL/主机/IP/路径 | `tests/acceptance/OCR-002-secure-remote-image-staging-2026-07-29.md` |
| OCR-003 | P0 | VERIFY | OCR 设置页"测试 OCR"：选图识别并输出文本与耗时 | 新增 `OcrTestResult`、Facade `testLocalOcrImage`（本地 Provider 直接识别、错误统一映射）+ composition root 注入；设置页"测试 OCR"按钮常驻显示（已安装→选图识别→结果卡片展示文本/耗时/块数/置信度/模型版本/语言，未安装→中文引导）；已接入真实模型包清单（RapidAI/RapidOCR 官方 ModelScope ONNX，真实 SHA-256/字节大小，ADR-0026）使"下载本地模型"可用 | `tests/acceptance/OCR-003-ocr-settings-test-2026-08-04.md` |
| IMAGE-001 | P0 | VERIFY | 识图引擎：OCR 引擎改名 + 图片识别方式可选（OCR / 多模态 LLM）+ 独立多模态配置 | 已实现：①"OCR 设置"改名"识图引擎"，顶部新增"图片识别方式"全局单选（自动/仅 OCR/多模态 LLM，SQLite v8 迁移 `image_recognition_mode`）；②独立多模态 LLM 配置区（Provider/API 地址/模型/Key/超时，复用 `LlmSettingsUseCases`，独立存储 key），与菜谱生成 LLM 分离；③`MultimodalLlmProvider`（OpenAI-compatible vision image_url + Gemini inline_data，图片转 base64，8MB/类型校验）+ `MultimodalImageEnrichingImportContentProcessor`（安全暂存→读字节→多模态识别→并入证据）；④`ImportImageRecognitionRoute {disabled,ocr,multimodal}` 替换旧 `ImportOcrRoute`，`_resolveDefaultPlan` 按设置+能力自动解析（auto 优先级：多模态→OCR→纯文本）；⑤`AppCapability.multimodalLlm` 能力（配置+Key 就绪）；进度阶段文案改"正在识别图片内容"；非目标：不改纯文本 LlmMessage、不做视频识别。**2026-08-05 复盘**：旧配置复用修复与 1×1 PNG 视觉请求只排除了“测到旧模型”和“纯文本探测”两类因素，不能证明最终根因；项目负责人确认实际故障并非普通网络超时，剩余诊断与融合改造转入 `BUG-006`，`IMAGE-001` 继续等待识图方式与独立配置的整体验收 | `ADR-0027`、`tests/acceptance/IMAGE-001-vision-engine-2026-08-04.md` |
| ASR-001 | P0 | DONE | 定义 ASR Provider 与导入预处理流水线 | 统一 Provider、时间证据、媒体限制、部分结果、错误映射和 Runner 集成已通过 161 项全量测试 | `docs/architecture/ASR_PROVIDER.md` |

## 待细化产品任务

| ID | 优先级 | 状态 | 任务 |
|---|---|---|---|
| PROD-001 | P0 | TODO | 补齐首页、分类和菜谱详情的逐页面验收标准 |
| PROD-002 | P0 | DONE | 补齐链接导入失败及降级流程的文案和状态 |
| DESIGN-000 | P0 | DONE | 输出移动端 UI 设计交付文档，明确页面树、状态、游客/登录差异和设计交付标准 |
| DESIGN-001 | P0 | TODO | 绘制链接导入低保真全流程 |
| DESIGN-002 | P0 | TODO | 绘制首页、菜谱详情、编辑和烹饪模式线框图 |
| DESIGN-005 | P1 | TODO | 绘制轻拟物冰箱分区库存、选择食材推荐、购物清单联动和库存扣减确认的低保真流程 |
| DESIGN-008 | P1 | VERIFY | 完成「巴食」Image 2 严格二维像素美术提示词 v1.3：48 条基础 Prompt 中仅品牌 4 条允许 IP，其他 44 条禁止 IP；底部导航 4 组 / 8 枚和分类 12 张 active 同样禁止 IP | 非品牌资产只能使用物体、食材和符号；出现角色、拟人化或任何 IP 特征直接淘汰；首轮验收导航 2×4 双状态稿、早餐 default / active 与冰箱空状态，项目负责人回传前保持 VERIFY | `design/assets/IMAGE2_ICON_PROMPTS.md`、`design/assets/prompts/`、`tests/acceptance/DESIGN-008-image2-icon-prompts-2026-08-10.md`、ADR-0039、ADR-0040、ADR-0041 |
| BRAND-001 | P1 | VERIFY | 统一 Flutter、HTML 原型与设计文档中的遗留产品名称「拾味」为「巴食」 | 全仓产品可见名称统一；不改数据库主键、包名或历史记录；实施前先盘点受影响文案和截图。**已实施（2026-08-10）**：AndroidManifest `android:label` → 巴食；iOS Info.plist `CFBundleDisplayName` → 巴食；`app.dart` MaterialApp title → 巴食；欢迎页品牌标题「拾 味」→「巴 食」（眉题 TASTE PIXEL · AI RECIPE 保留）；HTML 原型 index.html/app.js/prototype.css/README.md 与 design-docs 全部「拾味」→「巴食」。未改：pubspec `name: ai_recipe`（包名）、iOS `CFBundleName`/bundle id、历史验收记录与任务描述。等待项目负责人构建确认桌面应用名与欢迎页显示 | `docs/product/AI食谱应用产品需求文档.md`、`tracking/DECISIONS.md`（ADR-0039） |
| BRAND-002 | P1 | VERIFY | 将应用启动图标替换为 `design/assets/图标.png` | **已实施（2026-08-10）**：源图更新为 2048×2048 后已重新生成全部图标——Android 5 个 mipmap（48/72/96/144/192 的 `ic_launcher.png`，24bppRGB 无透明）；iOS `AppIcon.appiconset` 15 个尺寸（20×20@1x ~ 1024×1024@1x）合成纯白底去除 alpha。生成脚本保留于 `code/apps/mobile/tool/gen_launcher_icons.dart`（`dart run tool/gen_launcher_icons.dart`）；沙箱内 dart run 超时，实际改用 PowerShell/System.Drawing 等价脚本生成。等待项目负责人重新构建后在桌面/应用管理器确认新图标，确认后进入 `DONE` | `design/assets/图标.png` |
| PROF-001 | P2 | VERIFY | 「我的」页新增「支持我们」赞赏页 | **已实施（2026-08-10）**：收款码源图 `design/assets/收款码/微信.jpg`（1213×1213）、`支付宝.jpg`（1260×1890）打包为资产 `assets/payment/wechat_qr.jpg`、`assets/payment/alipay_qr.jpg` 并在 pubspec.yaml 注册；新增 `features/profile/support_page.dart` 赞赏页（感谢语卡片 + 「扫码赞赏」两张收款码卡片 + 自愿提示，点击收款码进入全屏黑底预览，左右滑动切换、双指缩放，参考菜谱详情 `_FullscreenImageGallery` 交互）；「我的」页「隐私与数据」区块末尾新增「支持我们」入口（`openSupportTile`）。IDE 诊断无错误；未运行测试/构建/真机（ADR-0015）。等待项目负责人构建后人工验收 | `docs/product/AI食谱应用产品需求文档.md`（4.4 我的） |
| TEST-001 | P0 | TODO | 建立第一批小红书/抖音公开测试样本 |
| TEST-002 | P0 | TODO | 建立 AI 菜谱解析人工评分基线 |

## AI-003 验收定义

- **用户价值**：使用 OpenAI-compatible 纯文本模型时，即使服务返回常见且可唯一识别的结构化包装，用户仍能安全生成可确认的菜谱草稿，而不是因非业务字段的轻微包装差异直接失败。
- **范围**：菜谱生成 Prompt 类型约束；纯 JSON；普通说明包围的唯一顶层 JSON；单一 Markdown JSON fence；闭合的 `<think>` 推理前缀；响应体积上限；严格字段 Schema；Provider 截断和空内容识别；稳定错误与测试定义；Android 真实服务复测、草稿保存和 SQLite 重启恢复。
- **非目标**：不接受多个 JSON 候选或多个 fenced 块；不修复截断或语法错误 JSON；不放宽未知字段、类型、范围、必填字段或本地受控字段；不记录完整 Prompt、模型响应、Authorization 或 API Key；不验证图片理解、OCR、视频 ASR、Gemini 真机或 iOS。
- **依赖**：`AI-002`、`SPK-003`、`docs/api/recipe-generation.schema.json`、现有 OpenAI-compatible Provider、Android 模拟器和项目负责人授权的运行时临时配置。
- **风险**：包装兼容过宽会错误选取说明中的示例对象；兼容过窄会继续拒绝常见纯语言模型输出。实现必须识别字符串和转义字符、只接受唯一完整顶层对象，并保留响应大小、严格 Schema 与多候选拒绝边界。
- **验收标准**：
  1. 纯 JSON 和现有单一 fenced JSON 保持可解析。
  2. 普通短说明或闭合 `<think>` 前缀之后，只要响应中存在且仅存在一个完整顶层 JSON 对象即可进入严格 Schema 校验；JSON 字符串内部的花括号和转义引号不能破坏边界识别。
  3. 多个 JSON 对象、多个 fenced 块、未闭合/重复推理标签、截断或花括号不平衡 JSON、未知字段、缺字段和错误类型继续稳定失败。
  4. 对模型响应设置明确字符数上限；Provider 将 `finish_reason=length` 和空 content 映射为稳定无效响应；失败不保存完整 Prompt、响应和凭证。
  5. Parser、Processor 和 OpenAI-compatible 测试定义覆盖正常包装、前后说明、推理包装、字符串转义、空内容、超大响应、缺字段、类型错误、未知字段、截断和歧义输出。
  6. Android 真实纯文本生成进入草稿确认页；记录人工修改字段数；保存后重启 App 可从 SQLite 恢复菜谱。
  7. 至少验证一个安全错误路径，并在收尾时通过 App 清除临时 Key；iOS 明确记录为未验证。

## BUG-003 验收定义

- **用户价值**：公开平台内容已经成功获取时，纯语言模型即使在唯一 JSON 外附带普通说明，也能生成可确认菜谱，而不是在 65% 因包装或常见字段类型歧义直接失败。
- **范围**：菜谱生成 Prompt 的完整合法示例与类型说明；唯一 JSON 安全提取；严格 Recipe Schema；OpenAI-compatible 截断/空响应识别；稳定脱敏错误；Android 同一小红书样本复测与 AI 质量归档。
- **非目标**：不重新抓取或保存完整小红书页面；不放宽菜谱字段白名单和类型；不自动产生额外付费重试；不保存完整模型响应、Prompt、Key、Cookie、Authorization 或原始查询参数；不验证 Gemini、OCR、ASR 或 iOS。
- **依赖**：`AI-002`、`AI-003`、`IMPORT-003`、`SPK-003`、现有 Android LLM 运行时配置和规范化脱敏样本。
- **风险**：第三方兼容服务可能返回截断、多个对象或模型自定义字段；此类结果必须继续失败，不能为了提高成功率绕过 Schema 或错误选取对象。
- **验收标准**：
  1. 同一任务进入“正在获取公开内容”和“正在生成结构化菜谱”，并能离开 65%。
  2. 唯一 JSON 外的普通前后说明、单一 JSON fence 和闭合推理前缀可兼容；多个对象、多个 fence、截断和不平衡结果继续拒绝。
  3. Prompt 明确 `quantity` 为字符串或 null、`optional` 为布尔值、`substitutes` 为字符串数组、`durationSeconds` 为整数或 null、`confidence` 为 0～1 数字或 null、`difficulty` 为受控枚举，并提供完整合法示例。
  4. Provider 对长度截断和空文本返回稳定错误；页面不显示完整模型响应或敏感信息。
  5. 成功进入待确认草稿后，菜名、食材、用量、步骤、低置信度和保存前修改数可由项目负责人评分；保存后未完成数量减少且重启可恢复正式菜谱。
  6. 失败不得创建重复任务、多余草稿或正式菜谱；强停重启保持真实任务状态。
  7. Codex 不执行测试；测试方法更新到 `tests/acceptance/BUG-003-xiaohongshu-public-link-2026-08-02.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## BUG-005 验收定义

- **用户价值**：不可重试导入失败后，用户可以明确结束该任务，使首页未完成数量恢复准确，而不是被一个无法继续的失败任务永久占用。
- **范围**：失败页操作按钮；复用现有 `failed → cancelled` 状态转换；操作忙碌态；首页未完成计数与 SQLite 重启恢复；现有人工粘贴、图片/OCR、视频和手动创建降级入口。
- **非目标**：不把 failed 从未完成查询中静默过滤；不删除失败记录；不自动重试或产生额外 AI 调用；不新增完整导入记录管理页。
- **依赖**：`ImportTask.cancel`、`AiRecipeBackendFacade.cancelImportTask`、`ImportProgressPage`、`HomeSnapshot.unfinishedImportTasks`、`IMPORT-001`。
- **风险**：失败任务仍可能含有诊断价值，因此必须由用户主动结束；结束动作必须保持幂等和持久化，不能只修改页面内存状态。
- **验收标准**：
  1. failed 页面继续显示真实错误详情与人工降级入口，并显示“结束此导入”。
  2. 点击后按钮禁用并显示“正在结束…”，最终任务转换为 `cancelled`，页面显示“解析已取消”。
  3. 返回首页后未完成数量减少 1；强停重启后该任务仍不计入未完成。
  4. 不创建重复任务、草稿或正式菜谱，不删除原失败记录。
  5. queued/running 原“取消解析”行为不退化；可重试失败仍可使用既有重试入口。
  6. Codex 不执行测试；测试方法写入 `tests/acceptance/BUG-005-failed-import-dismiss-2026-08-02.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## IMPORT-004 验收定义

- **用户价值**：AI 生成的菜谱草稿不理想时，用户可以在确认页重新生成一次，不需要放弃草稿后重新导入。
- **范围**：草稿确认页“重新生成”按钮；复用本次会话内保存的原文证据（`ImportContent`）重新调用 LLM 生成；新草稿安全替换旧草稿；重新生成失败保留旧草稿；任务保持 `needsReview`；无会话证据时禁用并提示。
- **非目标**：不持久化原文（重启后无会话证据时不可重新生成，保持既有已知限制）；重新生成期间不支持用户取消；不实现多草稿历史或“生成对比”；不重新执行 OCR/ASR（需要重新识别时走放弃草稿后重新导入）；不限制生成次数（由用户自行控制）。
- **依赖**：`ImportTask.needsReview`、`LlmRecipeGenerationProcessor`、`ImportContent` 会话证据、`ImportTaskRunnerFactory`、`ImportRecipeDraftDiscarder`、草稿确认页 `evidence` 参数。
- **风险**：会话证据在 App 重启后丢失，重新生成按钮必须禁用并明确提示，不能假装可用；新草稿替换旧草稿必须走安全丢弃（只删除 ID、来源匹配且仍为草稿的数据）；重新生成消耗额外 LLM 调用，页面必须给出忙碌态防止重复提交。
- **验收标准**：
  1. `needsReview` 草稿确认页显示“重新生成”按钮；页面持有会话原文证据时可点击。
  2. 点击后先二次确认（提示会替换当前草稿），确认后按钮禁用并显示“正在重新生成…”，完成后表单刷新为新草稿。
  3. 重新生成失败时旧草稿保留、任务仍为 `needsReview`，显示稳定脱敏错误，不创建多余草稿。
  4. 成功后旧草稿被安全删除，任务 `resultRecipeId` 指向新草稿，状态保持 `needsReview`，`localVersion` 递增。
  5. 无会话证据（例如重启后进入）时按钮禁用并提示“原始内容已过期，请重新导入”。
  6. 重新生成后保存菜谱：任务 `completed`，正式菜谱可打开，首页未完成数量减少，强停重启后可恢复。
  7. 全程不创建重复任务；页面只通过 `AiRecipeBackendFacade.regenerateImportDraft` 接入。
  8. Codex 不执行测试；测试方法写入 `tests/acceptance/IMPORT-004-regenerate-import-draft-2026-08-02.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## IMPORT-005 验收定义

- **用户价值**：用户可以给菜谱添加多张封面图，在详情页顶部轮播展示，提升菜谱的可视化表现。
- **范围**：菜谱新建/编辑页从系统相册多选图片；图片复制到应用私有目录持久化（重启、相册删图、权限变化后仍可用）；首图作为 `coverImage`；详情页顶部多图轮播（PageView + 指示点），无图回退现有像素插画；SQLite v4 `recipe_images` 表与 Repository 读写。
- **非目标**：不实现图片裁剪/滤镜/排序拖拽（首图即封面，删除可调整）；不复制菜谱副本的封面图片文件（避免共享文件误删，副本封面为空）；导入图文自动带多图另立 `IMPORT-006`；iOS 相册权限细节本轮不单独验收。
- **依赖**：`image_picker` 多选、`path_provider`、SQLite v4 迁移、`Recipe.images`、`RecipeDraftInput.images`、`AiRecipeBackendFacade.stageCoverImages/deleteCoverImage`、`DeviceRecipeCoverImageStager`。
- **风险**：相册多选在部分设备可能只支持单选或返回受限；复制失败必须回滚已复制文件并提示；新建菜谱在保存前复制使用临时容器 ID，保存失败会遗留孤儿文件（best-effort 容忍）。
- **验收标准**：
  1. 新建/编辑菜谱时出现“添加封面图（可多选）”，可从系统相册一次选择多张图片。
  2. 选图后缩略图立即显示（首张标“封面”），可逐张删除；删除同时清理对应私有文件。
  3. 保存后菜谱详情页顶部以轮播展示全部封面图（可左右滑动，多图显示指示点）；无图时保持原像素插画。
  4. 重启 App 后封面图仍可显示（图片在应用私有目录、路径写入 SQLite）。
  5. 编辑移除某张图并保存后，该图不再显示且私有文件被清理；其余图顺序与显示一致。
  6. 复制失败（空文件、超限、权限）显示稳定错误，不中断保存主流程。
  7. 菜谱副本不引用源菜谱封面文件，删除副本不删除源菜谱图片。
  8. Codex 不执行测试；测试方法写入 `tests/acceptance/IMPORT-005-recipe-cover-images-2026-08-02.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## BUG-004 验收定义

- **用户价值**：首页已经提示存在未完成导入时，用户可以回到原任务继续处理，而不是被带到新建入口并误创建重复任务。
- **范围**：首页未完成导入提示的点击路由；现有持久化任务对象到导入进度页的传递；排队、运行中断、待确认和失败任务的既有恢复行为；返回首页后的数量刷新。
- **非目标**：本任务不新增完整“导入记录”管理页，不改变导入状态机、抓取、OCR、ASR、LLM 规则，不处理小红书样本解析质量本身。
- **依赖**：`HomeSnapshot.unfinishedImportTasks`、`AppShell._openImportTask`、`ImportProgressPage`、`IMPORT-001`、`UI-001`。
- **风险**：未完成任务可能多于一个；当前 P0 按持久化列表的创建时间倒序打开最近一项，处理或退出后重新加载首页，再继续下一项。完整任务列表留在既有 P0“导入记录页”范围内。
- **验收标准**：
  1. 首页提示数量来自本地持久化的 `queued/running/needsReview/failed` 任务，不包含已完成、已取消或已删除任务。
  2. 点击提示直接把最近创建的未完成 `ImportTask` 交给现有任务打开入口，不调用 `createImportTask`，不进入添加菜谱页。
  3. 排队任务打开后继续执行；运行中断任务先恢复再继续；待确认任务进入草稿确认；失败任务展示真实错误和降级/重试入口。
  4. 点击前后数据库中导入任务总数不因“继续处理”操作增加；同一来源链接不会因为点击提示产生重复任务。
  5. 返回首页后数量重新读取；完成或取消一项后提示数量相应减少，其余任务仍可继续进入。
  6. Codex 不执行测试；测试方法写入 `tests/acceptance/BUG-004-unfinished-import-resume-2026-08-02.md`，由项目负责人在 Android 模拟器执行并反馈后归档。
## BUG-002 验收定义

- **用户价值**：用户在公开链接获取、OCR/ASR/LLM 处理或草稿提交期间点击取消后，任务不会被稍后到达的 Provider 成功、Schema 错误或其他失败结果重新改写，界面和持久化状态始终反映用户的取消决定。
- **范围**：`ImportTaskRepository` 的 `localVersion` 原子并发控制；导入 Runner 在获取、进度、生成、失败和草稿提交边界的取消优先级；待确认草稿的补偿清理；Facade 取消接线；运行态取消入口；SQLite、Application、Runner 与 Android 回归。
- **非目标**：不修改 UI 视觉布局或非取消流程交互；不实现服务器端任务队列；不扩展 Gemini、本地兼容服务、OCR、ASR 或 iOS 验证矩阵；不重构菜谱与导入任务的全部持久化架构。
- **依赖**：`IMPORT-001`、`IMPORT-002`、`APP-003`、`APP-004`、`AI-003`、`SPK-003`、现有 Android 模拟器和运行时临时 OpenAI-compatible 配置。
- **风险**：只在 Runner 错误分支检查内存取消 Token 无法阻止两个并发写入从同一旧快照提交；草稿已保存但任务尚未进入 `needsReview` 时需要补偿清理；并发控制变更会影响全部 ImportTask Fake Repository 和恢复用例。
- **验收标准**：
  1. Adapter 获取或 LLM 请求运行期间“取消解析”保持可点击；点击后最终任务稳定为 `cancelled`，后到的 Provider 成功、Schema 错误、网络错误或未知异常不得覆盖取消态。
  2. `localVersion` 用作 SQLite 原子 Compare-and-Set；基于旧版本的写入返回明确并发冲突，不使用 `INSERT OR REPLACE` 静默覆盖新状态。
  3. Runner 遇到并发冲突时重新读取任务；若持久化状态已取消，统一返回取消结果，不再尝试写入失败或待确认状态。
  4. 取消与草稿提交并发时，不产生仍可见或无任务引用的草稿；补偿清理必须幂等，且不得删除已完成导入的正式菜谱。
  5. SQLite 关闭并重新打开后任务仍为 `cancelled`，且不存在与该任务来源对应的孤立草稿。
  6. 自动化测试覆盖等待中取消后返回 Schema 错误、等待中取消后返回成功、旧版本写入冲突、取消后 SQLite 重开和草稿清理。
  7. Android 真实 OpenAI-compatible 请求中点击取消后稳定显示取消状态；Logcat、错误文本、数据库和验收文档不包含 API Key、Authorization、完整 Prompt、完整响应或真实 API 地址。

## BUG-001 验收定义

- **用户价值**：用户可以稳定创建、查看和选择菜谱分类，不会因运行时异常中断，也不会因文字与背景对比度不足而无法辨认分类。
- **范围**：Android 菜谱库分类创建弹窗；分类创建后的刷新、筛选与 SQLite 持久化；空名称、重复名称、超长名称等错误反馈；分类 Chip 的未选中、选中和禁用状态；相关 Widget 回归测试与 Android 人工验收。
- **非目标**：不重构分类领域模型、SQLite Schema 或 `AiRecipeBackendFacade`；不调整 HTML 原型整体视觉体系；不实现服务器同步；本轮不要求 iOS 验收。
- **依赖**：`APP-001`、`APP-004`、`UI-001`、`design/prototypes/`、现有分类 Application/Facade 契约和 Android 模拟器。
- **风险**：创建异常的根因尚未由 Android Flutter exception/Logcat 证据确认；共享 `ChipTheme` 的修改可能影响菜谱标签、筛选项或其他页面；只修复表面提示可能掩盖重复提交或持久化问题。
- **初步调查假设（待证实）**：分类创建弹窗关闭时，输入控制器的释放时机可能早于 Dialog 退场动画完成，从而在动画期间被继续访问；实施前必须先复现并用 Flutter exception 或 Logcat 确认，不能把该假设直接当作已确认根因。
- **验收标准**：
  1. Android 菜谱库输入合法分类名称并提交后，Dialog 正常关闭，不出现 Flutter 未处理异常、`E/flutter` 错误或 Android 崩溃。
  2. 单次提交只创建一条分类记录，并显示明确成功反馈；新分类无需重启即可出现在分类筛选列表中。
  3. 选择新分类后筛选结果正确；App 重启后分类仍存在，证明走真实 SQLite 持久化而非只更新页面内存。
  4. 空名称、重复名称、仅空白、超长名称和快速重复提交显示稳定业务错误或被安全阻止，不产生空分类、重复分类或脏数据。
  5. 分类 Chip 的未选中、选中和禁用状态均显式设置前景色，不依赖 Material 自动推导；普通正文颜色对比度按 WCAG AA 建议至少达到 `4.5:1`，并保持 HTML 原型的纸张米白与深绿视觉体系。
  6. 检查共享 Chip 样式对菜谱标签、筛选项和其他使用 Chip 的页面没有视觉或交互回退。
  7. 新增 Widget 回归：打开分类创建 Dialog、输入、提交并 `pumpAndSettle` 后，`tester.takeException()` 为空，新分类和成功反馈均可见。
  8. 完成 Android 模拟器人工验收并保存修复后截图、Flutter/Logcat 检查结果和验收记录；iOS 明确记录为未验证且不阻塞本次 Android 修复。
  9. `BUG-001` 通过后重新执行 `UI-001` 分类相关视觉验收；只有缺陷关闭且 UI 验收无回退时，`UI-001` 才可进入 `DONE`。

## UI-001 当前切片：Flutter 原生复刻 HTML 高保真原型

- **用户价值**：Android 用户看到的实际 Flutter 应用与已确认的「拾味 · AI 食谱」HTML 原型保持同一套视觉语言、页面结构和交互层级，避免设计稿与可运行产品脱节。
- **范围**：以 `design/prototypes/index.html`、`prototype.css`、`app.js` 为唯一视觉事实源；重构 Flutter 设计 Token、像素阶梯缺角、卡片/按钮/输入/状态反馈、欢迎页、三栏底部导航与悬浮添加入口、首页、菜谱库、导入、草稿确认、详情/编辑、烹饪模式、我的、LLM/OCR 设置及回收站的视觉呈现；保留现有业务接线。
- **非目标**：不使用 WebView；不修改 HTML 原型的产品规则；不重写 SQLite、Repository、Provider、OCR/LLM 流水线；本切片不完成真实 OCR/LLM 质量或 iOS 验收。
- **依赖**：`design/prototypes/README.md`、`design/prototypes/prototype.css`、`design/prototypes/app.js`、`docs/architecture/FLUTTER_BUSINESS_BACKEND_COMPLETION.md`、`AiRecipeBackendFacade`。
- **风险**：HTML 的 CSS `clip-path`、像素位图和 steps 动效需要用 Flutter CustomClipper/Animation 等价实现；系统字体在 Android 上与浏览器字形会有细微差异；页面状态较多，必须用截图矩阵持续对照而不是一次性主观判断。
- **验收标准**：
  1. 全部界面由 Flutter Widget 原生实现，不引入 WebView 或运行 HTML。
  2. Android 390px 竖屏基线下，关键页面的结构、色板、字体层级、间距、描边、阴影、像素缺角、状态标签和底部导航与 HTML 原型一致。
  3. 底部导航为「首页 / 菜谱库 / 我的」三项，添加菜谱使用右下悬浮按钮进入，符合原型 v0.4。
  4. 欢迎页包含像素厨房 Hero、拾味品牌、三项特性、登录/游客入口、PRESS START 与可展开隐私说明。
  5. 页面仍只通过 `AiRecipeBackendFacade` / Application 层访问业务能力，不直接访问 Repository、SQLite、SharedPreferences、安全存储或 Provider。
  6. 默认、空、加载、成功、错误、离线、极限、游客和登录状态继续可达；既有 Android 截图导入、导入失败降级和烹饪功能不得回退。
  7. 新增或更新 Widget 测试覆盖主题、欢迎页、三栏导航、FAB 和关键共享组件；全量 Flutter 测试不得低于当前 447 项基线。
  8. 在 Android 模拟器逐页截图，与 HTML 原型建立差异清单和验收记录；iOS 状态明确记录为未验证但不阻塞本切片。
- **设计差异记录**：`design/reviews/UI-001-html-flutter-gap-analysis-2026-08-01.md`。
- **验证结果（2026-08-01）**：Flutter 原生实现已覆盖欢迎、首页、菜谱库、添加/导入、进度、失败、草稿、详情、编辑、烹饪、我的、LLM、OCR、隐私和回收站；Android 16 / API 36 完成 16 张截图矩阵；`flutter analyze --no-pub` 无问题，`flutter test --no-pub --concurrency=4` 共 450 项通过；源码和 `pubspec.yaml` 未发现 WebView。任务进入 `VERIFY`，等待项目负责人最终视觉确认。
- **验证链接**：`tests/acceptance/UI-001-flutter-native-prototype-replication-2026-08-01.md`。
## UI-001 当前切片：Android 截图 OCR 导入验收定义

- **用户价值**：公开链接无法读取时，Android 用户可以从系统图片选择器选取一张菜谱截图，使用本地 OCR 与已配置的自有 LLM 继续生成可确认的菜谱草稿。
- **范围**：Android 系统图片选择；单张图片；失败/取消任务的本地图片降级；本地 OCR 路线；任务进度、取消、稳定错误和草稿确认；Activity 被系统回收后的图片选择结果恢复。
- **非目标**：相机拍摄、多图批量导入、视频选择/ASR、云 OCR、托管 LLM、真实模型质量验收、iOS 验收、长期保存原始截图或把截图加入正式菜谱媒体库。
- **依赖**：`US-004`、`US-007`、`OCR_PLUGIN.md`、`APPLICATION_BACKEND_FACADE.md`、已安装且运行时可用的本地 OCR 模型、已配置的自有 LLM。
- **风险**：真实 PP-OCRv5 模型包和真实图片质量仍属于 `SPK-002`；没有可用本地 OCR 或 LLM 时只能验证稳定失败与人工降级，不得伪造识别成功。
- **验收标准**：
  1. Android 使用系统图片选择器选择单张图片；用户取消选择时任务状态不变且不显示错误。
  2. 图片只通过新增 Facade 入口进入业务流水线，页面不直接访问 OCR Provider、Repository 或 SQLite。
  3. Facade 只接受失败或已取消的导入任务，校验本地资源标识和图片 MIME，并强制使用本地 OCR 路线；该入口不读取“允许上传图片”开关，也不会调用云 OCR。
  4. 选择成功后显示现有 OCR/LLM 进度，支持取消；成功时进入 AI 草稿确认并保留 OCR 证据。
  5. 本地 OCR 未安装/不可用、LLM 未配置、图片不可读或 OCR 失败时显示稳定安全错误，不泄露本地绝对路径、API Key 或图片内容，并保留粘贴正文和手动创建入口。
  6. Android Activity 在图片选择期间被系统回收时，可以通过插件丢失数据恢复机制继续处理返回的图片或显示稳定选择错误。
  7. 新增 Facade、图片选择封装和页面 Widget 测试，并在 Android 模拟器验证图片选择入口；真实 OCR 质量仅在实际模型和公开样本可用后记入 AI 质量日志。
- **验证结果（2026-08-01）**：Android API 36 系统 Photo Picker、取消返回和选择图片返回应用已人工通过；设备因自有 LLM 未配置先显示稳定 LLM 错误，OCR 未安装和 lost-data 恢复由自动测试覆盖；43 项定向、447 项全量测试和静态分析通过；真实 OCR/LLM 质量未验证。
- **验证链接**：`tests/acceptance/UI-001-android-image-ocr-import-2026-08-01.md`。
## PROD-002 验收定义

- **用户价值**：公开链接解析失败后，用户仍能安全、明确地继续生成或手动创建菜谱。
- **范围**：失败页文案；自动重试与人工降级入口；粘贴正文；截图/视频能力说明；手动创建；来源保留；Provider 不可用和中断行为。
- **非目标**：本任务不实现媒体选择器、真实视频 ASR、云端 OCR/ASR、服务器任务队列或跨设备恢复临时正文。
- **依赖**：`US-004`、`PUBLIC_CONTENT_IMPORT.md`、现有 `ImportTask` 状态机、`AiRecipeBackendFacade`、HTML 原型失败页。
- **验收标准**：
  1. 可重试和不可重试失败都提供人工降级入口，自动重试只在任务允许时显示。
  2. 粘贴正文跳过公开 Adapter，保持原任务来源，通过统一 Processor 进入 AI 草稿确认；空正文被拒绝。
  3. Provider 不可用时显示安全错误，正文保留在当前表单中，错误不泄露 API Key 或正文。
  4. 截图/视频依赖缺失时显示真实能力说明，不伪造 OCR/ASR 成功。
  5. 手动创建进入现有编辑页且不依赖 AI。
  6. 人工降级中断或失败不会被自动调度为公开链接抓取。
- **验证链接**：实现验收记录写入 `tests/acceptance/UI-001-import-fallback-slice-2026-07-31.md`。

## IMPORT-006 验收定义

- **用户价值**：链接导入生成菜谱草稿时，自动把公开内容（小红书/抖音）的配图下载到本地并加入菜谱封面轮播，用户不需要手动重新选图，图片在应用重启后仍可显示。
- **范围**：`LlmRecipeGenerationProcessor` 生成草稿时把内容图片经 OCR-002 安全暂存下载并校验，复制到 `recipe_covers/<recipeId>/<index>.<ext>`，写入草稿 `images`/`coverImage`（首图即封面）；最多 9 张；单张失败 best-effort 跳过；全部失败草稿仍生成；丢弃/重新生成草稿时同步清理旧封面目录。
- **非目标**：不重新实现远程图片下载安全层（复用 OCR-002 `SecureRemoteOcrImageStager`）；不改变封面排序规则；不做图片裁剪；手动图片导入、粘贴正文等既有入口不涉及。
- **依赖**：`LlmRecipeGenerationProcessor`、`RecipeCoverImageStorer`（新增领域接口，`DeviceRecipeCoverImageStager` 实现）、OCR-002 安全暂存、`SafeImportRecipeDraftDiscarder` 孤儿清理、IMPORT-005 封面数据模型。
- **风险**：平台 CDN 或网络限制导致部分图片下载失败，必须 best-effort 跳过而不是让整个导入失败；丢弃草稿时封面目录可能遗留，需同步清理。
- **验收标准**：
  1. 链接导入成功后，草稿自动携带公开内容图片，`images` 为应用私有本地路径（非远程 URL），`coverImage` 为第一张。
  2. 详情页/确认页顶部显示轮播，重启 App 后图片仍可显示。
  3. 部分图片下载失败时草稿仍生成，成功图片保留；全部失败时草稿生成但无封面，不报错阻断。
  4. 放弃草稿或重新生成后，旧草稿的封面文件目录被清理。
  5. 保存正式菜谱后封面图持久化，编辑/删除不影响其他菜谱。
  6. Codex 不执行测试；测试方法写入 `tests/acceptance/IMPORT-006-remote-covers-2026-08-03.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## IMPORT-007 验收定义

- **用户价值**：小红书/抖音图文笔记导入时，图片里的菜谱信息不再被丢弃：本地 OCR 把图片识别成文字后，与页面正文整合成同一批证据交给 AI，生成更完整的菜谱草稿。
- **范围**：链接导入默认执行计划的自动解析；本地 OCR 能力就绪时启用 `ocr: local`（图片经 OCR-002 远程安全暂存后识别）；OCR 文本片段与页面文本片段按顺序整合进 `ImportContent.textFragments` 后交给 LLM Processor；OCR 未安装时回退纯文本路径；OCR 链路错误文案中文化。
- **非目标**：不实现云 OCR、托管 ASR；不改变手动图片导入、粘贴正文等既有入口；不评价真实 PP-OCRv5 模型质量（属 SPK-002）；不做视频 ASR。
- **依赖**：`OcrEnrichingImportContentProcessor`、`RemoteStagingOcrProvider`、OCR-002 安全暂存、`AppCapability.localOcr` 能力快照、`LlmRecipeGenerationProcessor`。
- **风险**：本地 OCR 未安装时纯图片内容无法生成，必须提示安装而非静默丢弃图片；远程图片安全暂存失败映射为可操作中文错误；能力快照读取失败时回退纯文本路径。
- **验收标准**：
  1. 本地 OCR 能力就绪时，链接导入不传执行计划也会自动启用本地 OCR；图文内容生成草稿时 OCR 被实际调用。
  2. OCR 识别出的文本与页面正文文本一起进入 LLM 输入（同一批证据），草稿生成成功。
  3. 本地 OCR 未安装时链接导入回退纯文本路径：有正文的图文内容仍可生成；只有图片无正文的内容失败并提示“需要先完成图片文字识别”。
  4. OCR 模型未安装、识别不可用、图片无效等失败路径显示稳定中文文案，不出现底层英文错误。
  5. 无图（纯文字）内容即使 OCR 就绪也不会触发 OCR 调用。
  6. Codex 不执行测试；测试方法写入 `tests/acceptance/IMPORT-007-link-import-ocr-2026-08-03.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

## IMPORT-008 验收定义

- **用户价值**：链接导入改用内置浏览器内核（WebView）加载网页并保存网页真实文本与图片，规避直连抓取遇到的 CDN 403、登录墙与平台风控，且通用任意网页链接（小红书、抖音优先，其他平台零改造）。
- **范围**：
  - Android WebView 平台通道（Kotlin）：后台隐藏加载目标 URL；`onPageFinished` 后注入 JavaScript 从 DOM 提取标题/正文/作者/`og:` 元数据与图片地址；`shouldInterceptRequest` 以浏览器会话获取图片字节（与真实浏览器访问一致，不绕过平台访问控制）；加载超时/取消；按登录墙、验证码、网络失败、内容为空分类返回稳定结果。
  - Dart `WebViewImportContentAdapter`：WebView 抓取结果映射为 `ImportContent`（title/description/bodyText/media），替换链接导入主路径的直连 Adapter。
  - 图片字节经 OCR-002 安全暂存校验后进入现有 OCR/封面/LLM/草稿流程（IMPORT-006/007 联动）。
  - 隐私设置中“允许获取网页内容”授权联动；不采集、不存储、不外传 Cookie 与登录态。
- **非目标**：不做页面截图后 OCR（用户主动上传截图除外）；不保存网页 HTML 快照；不引入可见浏览器 UI（WebView 仅数据获取，不用于界面呈现）；不做 iOS WKWebView（暂缓）；不采集用户 Cookie/登录态。
- **依赖**：Android WebView 平台通道、`ImportContent` 领域模型、OCR-002 安全暂存、`AiRecipeBackendFacade` 链接导入流水线、隐私设置授权。
- **风险**：小红书/抖音正文或图片可能要求登录或触发验证码（需分类提示与降级）；SPA 页面渲染需要等待与超时控制；跨域图片 CORS 限制（以 `shouldInterceptRequest` 浏览器会话请求解决）；隐藏 WebView 需要挂载视图且后台加载受平台限制；`ADR-0013` 的 WebView 边界需在实现中明确（仅数据获取）。
- **验收标准**：
  1. 粘贴任意 URL 链接导入，App 后台隐藏 WebView 加载页面，草稿包含页面标题与正文文本（来自 DOM，非截图 OCR）。
  2. 页面图片经浏览器会话获取并保存为草稿封面（与 IMPORT-006 验收一致：确认页展示、详情页轮播、重启恢复）。
  3. 登录墙/验证码/网络失败/内容为空分别给出中文可操作提示与降级入口，不透传平台英文错误。
  4. 隐私设置关闭“允许获取网页内容”后链接导入按预期受限并提示。
  5. 本地 OCR 就绪时图片自动识别并入正文证据（与 IMPORT-007 联动）。
  6. Codex 不执行测试；测试方法写入 `tests/acceptance/IMPORT-008-webview-import-2026-08-03.md`，由项目负责人 Android 真机复测（小红书/抖音/普通网页）并反馈，iOS 未验证。

## FRIDGE-001 验收定义

- **用户价值**：先把“家里有什么 → 能做什么 → 还缺什么 → 下厨后如何更新库存”的闭环定义清楚，避免直接编码后反复改变导航、数据模型和推荐口径。
- **范围**：一级导航；冰箱库存与推荐二级结构；轻拟物冰箱分区 UI；库存批次字段和状态；用户选择食材后的本地菜谱推荐分组、排序与数量不确定提示；购物清单联动；下厨后自动生成预计消耗并确认扣减；后续 AI 生成入口；任务、风险、Spike 和设计交付规划。
- **非目标**：不修改业务代码；不实现条码、拍照、小票识别、后台到期通知、家庭实时共享；不执行 Flutter/Dart 测试、分析、构建、模拟器或真机验收。
- **依赖**：产品需求文档、`USER_STORIES.md`、`UI_HANDOFF.md`、Local-first 与游客完整本地能力决策。
- **风险**：中文同义词和单位不统一可能误判可做性，必须由 `SPK-008` 验证；购物清单、烹饪完成事件与库存持久化契约尚未实现。
- **验收标准**：
  1. 产品文档统一定义“首页 / 菜谱库 / 冰箱 / 我的”四栏导航，添加/导入保留全局 FAB，购物清单为二级页面。
  2. 库存按批次建模，字段、冷藏/冷冻/常温/其他分区、临期/过期规则、同名多批次与数量未知行为可验证。
  3. 本地推荐支持用户选择一个或多个库存食材作为本次意图，推荐范围、缺 0/1/2 分组、排序、缺失项、冰箱已有但未选择、基础调味品和数量无法判断时的提示清楚且不依赖 LLM。
  4. 下厨后自动生成预计消耗，但只有用户确认才扣减库存；同名多批次默认优先到期更早批次但可修改。
  5. AI 生成是后续独立入口，结果进入草稿确认且不与本地推荐混排。
  6. 相关任务、ADR、风险、Spike、流程和文档走查方法已同步；项目负责人走查前状态保持 `VERIFY`。

## FRIDGE-002 验收定义

- **用户价值**：用户可以离线记录家中真实库存、识别临期食材，并维护同名食材的不同批次。
- **范围**：库存批次持久化与变更记录；新增、编辑、删除、用完、丢弃；数量/单位可空；分类、位置、购买/到期日期、备注；冷藏区/冷冻区/常温区/其他区分区展示；状态计算、聚合展示和筛选。
- **非目标**：条码、拍照、小票识别、后台到期通知、家庭实时共享、自动采购入库。
- **依赖**：`FRIDGE-001` 文档走查、`DESIGN-005` 低保真、库存领域/API/SQLite 契约。
- **风险**：同名多批次聚合可能误操作；日期和数量缺失时不能伪造精确库存。
- **验收标准**：
  1. 游客与登录用户均可本地离线维护库存批次，应用重启后可恢复。
  2. 同名食材可有多个批次，编辑、删除、用完或丢弃只影响目标批次。
  3. 正常、临期、已过期、未设置日期、数量未知状态显示准确；临期默认到期前 3 天。
  4. 冷藏区、冷冻区、常温区、其他区默认分区展示；全部、临期、已过期、冷藏、冷冻、常温、其他筛选可用，空分区/错误/极限内容状态完整。
  5. 每次库存变化写入可追溯的本地变更记录。

## RECO-001 验收定义

- **用户价值**：用户无需联网或调用 AI，就能根据现有库存找到现在能做、只差少量食材或应优先消耗临期食材的本地菜谱。
- **范围**：用户选择本次想优先使用的库存食材；本地正式菜谱与可用库存匹配；推荐分组和排序；冰箱已有但未选择标记；基础调味品；数量不确定提示；缺失项加入购物清单；进入详情/烹饪。
- **非目标**：不推荐草稿或回收站；不自动生成新菜谱；不把同义词或不可换算单位当作精确命中。
- **依赖**：`FRIDGE-002`、正式菜谱食材数据、购物清单能力、`SPK-008`。
- **风险**：名称、同义词、分组和单位不统一导致误判；推荐必须保守显示证据与缺失项。
- **验收标准**：
  1. 离线、游客和无 LLM Provider 时推荐仍可用，只读取本地正式菜谱。
  2. 推荐前支持单选、多选、全选、选择临期和选择某分区；用户只选西红柿时也可推荐西红柿炒鸡蛋，并正确标注鸡蛋是冰箱已有或缺失。
  3. 页面分为“已具备 / 现在就能做”“缺 1 样”“缺 2 样”“优先清库存”，排序依次考虑缺失更少、临期命中更多、匹配比例更高。
  4. 卡片显示已选命中、冰箱已有但未选择、匹配/总数、缺失项、临期命中、推荐原因、时间与难度。
  5. 数量为空或单位无法换算时显示“有该食材，数量是否足够需确认”，不得宣称一定足够。
  6. 缺失项可预览后加入购物清单，无法换算的单位不被静默合并。

## FRIDGE-003 验收定义

- **用户价值**：用户完成一道菜后，可以按实际消耗更新冰箱，同时保留控制权并避免错误扣减。
- **范围**：预计消耗清单；批次选择；数量调整；逐项取消；确认提交；库存变更记录。
- **非目标**：未确认自动扣减、负库存、根据计时器或页面退出自动认定已消耗。
- **依赖**：`FRIDGE-002`、`RECO-001`、烹饪完成事件与单位换算结果。
- **风险**：菜谱用量与库存单位不一致；同名多批次可能扣错；数量未知时必须要求确认。
- **验收标准**：
  1. 完成烹饪后自动生成预计消耗建议，不立即修改库存。
  2. 用户可逐项修改数量、更换批次、取消或跳过；默认选择到期更早批次。
  3. 只有确认提交才原子更新库存并写入变更记录；关闭或取消后库存不变。
  4. 数量未知、单位不可换算或库存不足时不产生负库存，并显示需确认状态。

## RECO-002 验收定义

- **用户价值**：当本地菜谱没有合适结果时，用户可选择让已配置的 LLM 根据现有食材生成一份可编辑的新菜谱。
- **范围**：独立入口；库存摘要输入；Provider 能力检查；生成草稿；草稿确认、修改和保存。
- **非目标**：不替代本地推荐；不自动保存正式菜谱；不在 Provider 不可用时展示可执行入口；不自动扣减库存。
- **依赖**：`FRIDGE-002`、`AI-002`、现有草稿确认流程、上传/隐私和 Provider 能力策略。
- **风险**：LLM 可能生成库存不存在或用量不合理的食材，必须显示草稿、证据和人工确认。
- **验收标准**：
  1. 入口与本地推荐视觉和数据上分离，仅在可用 LLM Provider 时开放。
  2. 用户可确认将哪些库存食材提供给模型，敏感数据遵守现有上传授权。
  3. 生成结果进入现有草稿确认页，不自动混入本地推荐或正式菜谱。
  4. Provider 失败、取消或 Schema 错误时库存和本地推荐结果不受影响。

## SPK-008 验收定义

- **用户价值**：明确中文食材名称、同义词和单位换算的可信边界，避免推荐把“有类似名字”错误宣称为“肯定能做”。
- **范围**：真实中文库存/菜谱样本；名称标准化、别名、基础调味品和可换算单位候选方案；命中率、误判率、数量可判定率与保守降级。
- **非目标**：本任务不直接实现正式推荐引擎，不用 LLM 在线参与每次推荐，不伪造实验数据。
- **依赖**：真实样本、菜谱食材字段、库存字段和单位集合。
- **风险**：样本过少或只覆盖单一菜系会高估效果；单位和文本噪声可能无法完全规则化。
- **验收标准**：按 `research/spikes/SPK-008-ingredient-normalization.md` 执行并记录环境、样本、方案、数据、失败与限制，最终给出“采用 / 拒绝 / 继续研究”之一，并同步推荐契约。

## DESIGN-008 验收定义

- **用户价值**：为正式产品「巴食」建立一套真正服从现有 UI、可直接复制到 OpenAI Image 2 的严格二维像素美术提示词，并把官方 IP 限定在品牌用途，避免不同批次再次生成偏 3D、柔滑、体积化、角色泛滥或状态不一致的结果。
- **范围**：底部导航首页、菜谱库、冰箱、我的 4 组 / 8 枚 24×24 单色像素 UI glyph default / active；默认分类家常菜、快手菜、早餐、主食、汤羹、烘焙、甜品、饮品、素菜、肉类、水产、轻食 12 组 default / active；品牌 4 项、状态 12 项、功能入口 10 项、冰箱/库存 10 项、分类 default 12 项，共 48 条基础美术资产完整 Prompt；IP 使用边界、状态职责与生成、命名、验收流程。
- **非目标**：本任务不调用 Image 2、不生成最终 PNG/WebP、不修改 Flutter 页面或代码、不执行 Flutter/Dart 测试、分析或构建、不把官方 IP 原图的柔滑插画画法当成渲染标准、不为所有图片机械制作 active、不替换返回/搜索/收藏/删除/勾选等 16–24px 高频代码原生图标。
- **依赖**：`design/assets/IP.png` 与 `design/assets/封面图.png` 仅供 4 项品牌资产参考；所有非品牌资产只使用 `design/UI_HANDOFF.md`、`design/prototypes/prototype.css`、Flutter `app_theme.dart` 与 `pixel_ui.dart`、当前「巴食」页面截图或纯色板卡。
- **风险**：生成模型会把“像素风”解释成带 3/4 透视、物体厚度、明暗塑形和落地阴影的游戏道具画，也可能因看到 IP 参考图而在普通功能图标中加入水豚、厨师或拟人表情；active 可能被从零重画而产生轮廓、位置、比例和投影漂移。必须用导航双状态稿、早餐分类 default / active 与无角色冰箱空状态先验收，不以“边缘有像素”或“整体可爱”判为通过。
- **关联文档**：`design/assets/IMAGE2_ICON_PROMPTS.md`、`design/assets/README.md`、`design/assets/prompts/README.md`、`design/assets/prompts/00-bottom-navigation-icons.md`、`design/assets/prompts/01-brand-assets.md`、`design/assets/prompts/02-state-illustrations.md`、`design/assets/prompts/03-entry-icons.md`、`design/assets/prompts/04-fridge-inventory-icons.md`、`design/assets/prompts/05-category-icons.md`、`design/assets/prompts/06-active-state-supplements.md`、`tests/acceptance/DESIGN-008-image2-icon-prompts-2026-08-10.md`、ADR-0039、ADR-0040、ADR-0041。
- **验收标准**：
  1. 所有当前文档使用正式名称「巴食」；现有 Flutter/HTML UI 是渲染事实源，所有资产继续执行严格二维像素、正视 / 正交、有限色板、实色块、硬边和清晰方形像素台阶规则。
  2. `IP.png` 只允许用于 App 启动图标、品牌核心符号、欢迎页 Hero、通用菜谱无封面 4 项品牌资产，只决定官方水豚主厨身份，不继承平滑抗锯齿、渐变、柔光、体积或类 3D 画法。
  3. 状态插图 12 条、功能入口 10 条、冰箱/库存 10 条、分类 default 12 条，共其他 44 条基础 Prompt，以及导航 8 枚 glyph 和分类 12 张 active，全部禁止上传、参考或生成 `IP.png` / `封面图.png`；只使用物体、食材和符号。
  4. 任一非品牌资产出现水豚、人物、动物角色、厨师、厨师帽、墨镜、脸、五官、手脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征，整张直接淘汰。
  5. 导航首轮生成 2 行 × 4 列、共 8 枚 glyph：第一行 `#8F978F` outline default，第二行 `#476B52` filled / strong active；每列上下两态同外轮廓、同尺寸、同位置、同重心、同基线和同负空间，书本和冰箱完全正视，约 21px 下四个语义仍清楚。
  6. 导航图片不包含 `#EDF2EA` 激活底板、边框、文字或点击反馈；这些状态由 Flutter 绘制。确认稿通过后才按 `nav-*-default-v1.png` / `nav-*-active-v1.png` 逐枚导出。
  7. 分类 12 组均具有 default / active 命名；active 必须上传已通过的同一张无 IP default 原图作为唯一 Image 1，只调整 `#476B52` / `#33513C` 深绿色视觉权重，保持外轮廓、像素矩阵、构图、位置、基线、2px 描边、2–3px 右下硬投影和透明区域完全不变。
  8. 分类 active 不包含 `#DDE7DC` 选中底板、边框、对勾、光圈、发光、角标或额外投影；选中容器由 Flutter 绘制。default / active 以 50% 透明叠放不得出现双边或位移，40px 下状态差异仍可辨。
  9. 品牌资产、状态插图、功能入口、冰箱分区、库存与推荐图标不制作独立 active；pressed / busy / disabled / focus、选中、缺失、数量和推荐等级由 Flutter 容器、透明度、描边、文字、标签和进度状态表达；返回、关闭、收藏、勾选、删除、箭头、开关等继续使用 Flutter 原生组件。
  10. 48 条基础美术提示词均为一图一资产、独立完整可复制的 Prompt：品牌 4 条允许 IP，其他 44 条禁止 IP；每条包含严格二维像素正向约束、3D / 柔滑反向约束、色板、构图、背景和输出检查；App 图标不生成「巴食」文字且不预制系统圆角。
  11. 任一样张出现 3D、等距或 3/4 透视、侧面 / 顶面 / 厚度、渐变、柔滑体积、黏土 / 塑料、倒角 / 挤出、环境光 / 体积光 / AO、模糊阴影、平滑抗锯齿或柔和圆角矢量感，整张直接淘汰。
  12. 首轮只验收 `bottom-navigation-glyph-state-proof-v1.3.png`、`category-breakfast-v1.png`、`category-breakfast-active-v1.png`、`state-fridge-empty-v1.png`；收到项目负责人通过证据前任务保持 `VERIFY`，通过后再继续其他 46 条基础 Prompt、其余 11 张分类 active 与后续代表样张。

## DESIGN-005 验收定义

- **用户价值**：在开发前验证冰箱、推荐和扣减的主要操作是否清楚，避免把高风险库存操作隐藏在聚合列表或自动行为中。
- **范围**：轻拟物冰箱分区库存默认/空/加载/错误/离线/极限/游客/登录状态；选择食材推荐流程；缺 0/1/2 分组与卡片；缺失项加入购物清单；批次编辑；扣减确认。
- **非目标**：不输出可运行 Flutter 页面，不覆盖现有 HTML 原型，不设计首版非目标能力。
- **依赖**：`FRIDGE-001` 走查通过、`UI_HANDOFF.md` 和 `FRIDGE_AND_RECOMMENDATION_FLOW.md`。
- **风险**：若批次、数量不确定和扣减确认状态未在低保真中显式展示，实现时容易误导用户。
- **验收标准**：
  1. 低保真覆盖冷藏区/冷冻区/常温区/其他区的冰箱分区库存、选择食材推荐、批次新增/编辑、购物清单确认和库存扣减确认。
  2. 覆盖默认、空、加载、成功、错误、离线、极限、游客和登录状态；首版无权限依赖时注明不适用。
  3. 所有危险操作和未确认扣减均有清晰反馈与取消路径。
  4. 项目负责人走查后才能进入 Flutter 实施。

## BACKUP-001 详细验收定义

- **用户价值 / 问题**：本地优先菜谱库缺少可迁移、可验证、可长期演进的全量备份文件；直接复制 SQLite 或使用单个巨型 JSON 会绑定当前实现，难以安全跨版本、跨平台恢复。
- **范围**：只定义全量菜谱备份与恢复产品边界、归档格式、版本/迁移策略、导出流水线、导入预检、合并/冲突、替换/回滚、安全限制和交互状态。
- **非目标**：本任务不编写代码，不实现文件选择器、媒体资产层、导出器、导入器、加密、云同步、库存/购物清单/制作记录备份，也不执行自动测试、构建、模拟器或真机测试。
- **依赖**：现有 Flutter + SQLite Local-first 架构；菜谱/分类/食材/步骤/图片数据模型；实施前需补稳定媒体资产契约；来源 URL 与不可变来源证据契约仍受 `R-016` 约束。
- **风险**：SQLite 与文件系统不能共享事务；当前图片以设备路径保存；旧/未来版本兼容、恶意 ZIP、空间不足和替换失败都可能造成数据或媒体不一致，详见 `R-020`。
- **关联文档**：产品需求 5.12.3；US-014；`docs/architecture/RECIPE_BACKUP_RESTORE.md`；`design/flows/RECIPE_BACKUP_RESTORE_FLOW.md`；ADR-0034；R-006/R-020。

### 验收标准

- [x] 明确备份始终覆盖全部正式、草稿、归档和回收站菜谱，不提供部分备份。
- [x] 明确首版包含分类、关系、食材、步骤、标签、收藏、版本/软删除和全部菜谱图片，并列出排除项。
- [x] 选择 `.airecipe-backup`（标准 ZIP）+ Manifest + 版本化 NDJSON Dataset + SHA-256 内容寻址媒体，不直接复制 SQLite。
- [x] 归档格式版本、Dataset Schema 版本和 SQLite schemaVersion 相互独立，定义 Dataset Adapter、Migration Registry 与 migrator 链。
- [x] 导出定义一致性快照、空间预检、流式打包、哈希、复核、原子发布和失败清理；必需媒体缺失时失败。
- [x] 导入定义 staging、安全/版本/哈希/空间预检、ImportPlan、默认合并、显式冲突处理、两阶段提交和失败清理。
- [x] 高级替换模式执行前强制创建并验证回滚备份。
- [x] 设计覆盖默认、空、加载、完成、错误、离线、权限、未来版本、冲突、空间不足、游客、登录和极限规模状态。
- [x] 产品需求、用户故事、架构、流程、决策、风险和验收走查文档已同步。
- [x] 项目负责人按 `tests/acceptance/BACKUP-001-recipe-backup-restore-plan-2026-08-06.md` 完成方案走查并回传结果（2026-08-06：7 项维度全部通过，附 3 项实施前细化建议）。

## COOK-001 详细验收定义

- **用户价值**：下厨时遇到没有设置时长的步骤，用户可以直接自定义一个时长并启动计时器；自定义的时长会保存到该菜谱步骤，下次烹饪同一菜谱时无需重新输入。
- **范围**：烹饪模式无时长步骤（`durationSeconds` 为 null 或 0）的「自定义本步计时」入口；像素风分钟/秒输入弹窗；创建计时器；把时长写入菜谱步骤（只更新目标步骤、保留其他字段、递增 `localVersion`）；取消与非法输入处理。
- **非目标**：不修改既有有时长步骤的一键启动行为；不实现计时器与步骤的索引级关联（沿用「步骤 N」标签）；不调整计时器运行、暂停、提前完成等既有能力。
- **依赖**：`CookingSession`/`CookingTimer`、`Recipe.steps`、`RecipeLibraryUseCases.updateRecipeStepDuration`、`AiRecipeBackendFacade.updateRecipeStepDuration`。
- **风险**：同步是写操作，失败必须提示且不得创建与菜谱时长不一致的计时器；弹窗输入非法时长必须拦截而不是生成无效计时器。
- **验收标准**：
  1. 无时长步骤显示「自定义本步计时」按钮，不再只显示"无法直接启动计时器"的静态提示；有时长步骤保持原「启动计时器」一键行为。
  2. 点击按钮弹出像素风弹窗，可分别输入分钟与秒；两者都为 0 或非法输入时提示"请输入大于 0 的时长"且弹窗不关闭。
  3. 输入合法时长确认后：创建标签为「步骤 N」的计时器（总秒数正确），同时菜谱该步骤时长被持久化，页面立即刷新为更新后的菜谱。
  4. 再次进入该菜谱烹饪模式时，该步骤显示一键启动（时长即上次自定义值），无需重新输入。
  5. 取消弹窗不创建计时器、不修改菜谱；App 重启后自定义时长仍保留。
  6. 非法时长（≤0）与步骤不属于当前菜谱时返回稳定业务错误，不崩溃、不写脏数据。
  7. 页面仍只通过 `AiRecipeBackendFacade` 访问业务能力（ADR-0012/0013 边界不变）。
  8. Codex 不执行测试；测试方法见 `tests/acceptance/COOK-001-custom-timer-sync-2026-08-07.md`，由项目负责人 Android 复测并反馈，iOS 未验证。

> **2026-08-08 追加（排版改版，VERIFY 待复测）**：按项目负责人要求重排烹饪模式页——头部改为「关闭按钮 | 进度（最多 5 个小方块 + 上方 `STEP 当前/总数`）| 菜谱名称」；详细步骤/所需时间/火候/温度/炊具/分割线/所需食材合并为一个分组面板（`_CookingStepGroup`，替换 `_StepPanel`），分组后接计时器区。未改计时器业务逻辑；`currentCookingStepText`/`cookingStepProgress`/`cookingTimer-*` key 保留。

---

## 完成定义

任务进入 `DONE` 前必须满足验收、测试记录、文档同步、已知缺陷说明和当前状态更新。
