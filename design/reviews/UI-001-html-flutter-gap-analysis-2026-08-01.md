# UI-001 HTML 原型 → Flutter 差异与验收清单

> 日期：2026-08-01  
> 状态：`VERIFY`  
> 视觉事实源：`design/prototypes/index.html`、`prototype.css`、`app.js`  
> 实现约束：仅使用 Flutter Widget / Painter / Clipper，不使用 WebView。  
> 正式验收：`tests/acceptance/UI-001-flutter-native-prototype-replication-2026-08-01.md`

## 总体对齐结果

| 维度 | HTML 原型要求 | Flutter 最终实现 | 结果 |
|---|---|---|---|
| 导航 | 首页 / 菜谱库 / 我的三栏 + 右下 FAB | 已改为三栏导航，添加页作为 FAB 独立路由 | 已对齐 |
| 形状 | 面板、按钮、徽标使用像素阶梯缺角 | `PixelCutBorder`、`PixelClipper` 与共享像素表面组件 | 已对齐 |
| 色板 | 纸张米白、低饱和绿、琥珀/红/蓝状态色 | 已补齐 paper/card/ink/line 与状态色 Token | 已对齐 |
| 阴影 | 交互控件硬边像素阴影，卡片细描边柔和阴影 | 按交互与内容表面分别使用硬影和细描边阴影 | 已对齐 |
| 字体层级 | 中文无衬线 + 等宽像素标签 | 中文粗体标题、紧凑正文和 `PxLabel` 等宽眉题 | 已对齐，系统字形允许细微差异 |
| 动效与加载 | steps 阶梯入场、浮动、加载方块 | 使用 Flutter 阶梯曲线与方块加载表达 | 已对齐 |
| 欢迎页 | 像素厨房 Hero、品牌、三特性、PRESS START、隐私折叠 | 已按 v0.4 重做 | 已对齐 |
| 状态反馈 | 左侧色条通知、图标 + 文案标签 | 共享 `PixelNotice` 与状态标签 | 已对齐 |
| 业务接线 | 视觉实现不得绕开本地业务后端 | 页面仅调用 `AiRecipeBackendFacade` / Application | 已保持 |
| 运行技术 | Flutter 原生页面 | 未发现 WebView 依赖或源码引用 | 已满足 |

## 逐页 Android 证据

证据目录：`tests/acceptance/artifacts/UI-001-2026-08-01/`

| 页面 | HTML 原型重点 | Flutter 验收结果 | Android 证据 |
|---|---|---|---|
| UI-001 欢迎 | 像素厨房 Hero、拾味字标、三特性、双入口、隐私折叠 | 结构、层级和入口已对齐 | `android-welcome.png` |
| UI-002 首页 | 日期问候、游客徽标、未完成任务、快捷入口、分类和菜谱卡 | 纸张色板、像素卡片、三栏导航和 FAB 已对齐 | `android-home-top.png` |
| UI-003 添加 | 多种创建/导入入口、剪贴板确认 | 独立路由和像素入口卡已对齐 | `android-add-recipe.png` |
| UI-004 链接导入 | 来源识别、路线说明、主按钮 | 与添加页形成原型一致的导入区域 | `android-add-recipe.png` |
| UI-005 进度/失败 | 分阶段方块加载、降级列表 | 处理中和失败人工降级均已对齐 | `android-import-progress.png`、`android-import-failure.png` |
| UI-006 草稿确认 | 低置信标签、证据、底部保存栏 | 普通草稿与低置信状态已覆盖 | `android-draft-review.png`、`android-draft-low-confidence.png` |
| UI-007 详情 | 像素封面、食材/步骤分区、固定操作栏 | Hero、内容分区、来源和底部操作已对齐 | `android-recipe-detail.png` |
| UI-008 编辑 | 行内输入、增删、离开确认 | 基础信息、食材、步骤和保存底栏已对齐 | `android-recipe-edit.png` |
| UI-009 菜谱库 | 搜索、筛选、排序、回收站 | 搜索/排序/筛选、像素卡和导航已对齐 | `android-library.png` |
| UI-010 烹饪 | 深绿沉浸态、步骤面板、大字号、多计时器 | 深绿背景、步骤、食材、计时器和上下步已对齐 | `android-cooking-mode.png` |
| UI-011 我的 | 游客卡、云同步差异、设置列表 | 游客能力说明和设置入口已对齐 | `android-profile.png` |
| UI-012 LLM | Provider、Key 不回显、稳定错误条 | OpenAI-compatible / Gemini 设置和安全提示已对齐 | `android-llm-settings.png` |
| UI-013 OCR | 路线状态、运行时检查、模型管理、云 OCR | 本地模型和云路线状态已对齐 | `android-ocr-settings.png` |
| UI-014 隐私 | 历史、上传权限和清理动作 | 开关、说明、错误和破坏性动作已对齐 | `android-privacy-settings.png` |
| UI-015 回收站 | 空状态、恢复、永久删除和清空 | 当前截图覆盖空状态和像素页面结构 | `android-trash.png` |

## 验收结果

- Android 16 / API 36 模拟器逐页截图：16 张。
- `flutter analyze --no-pub`：无问题。
- `flutter test --no-pub --concurrency=4`：450 项通过。
- WebView 扫描：`code/apps/mobile/lib` 与 `pubspec.yaml` 无相关引用。
- iOS：未验证，不阻塞本次 Android 视觉切片。
- AI：草稿与低置信数据为 Mock，仅用于 UI 状态，不形成真实 OCR/LLM 质量结论。

## 剩余视觉验收动作

当前差异清单已从“等待 Android 截图”转为“实现与证据齐备”。进入 `DONE` 前仅等待项目负责人对 16 张截图和实际模拟器页面进行最终视觉确认；若发现视觉偏差，继续记录具体页面、状态和差异后在 `UI-001` 内修正。
