# 设计目录与交付规则

> 本目录是 UI/UX 的本地事实源。设计可以是图片，也可以是可离线运行的 HTML，不依赖 Figma 或其他云平台。

## 子目录

- `flows/`：用户流程、状态机、Mermaid 或流程图图片。
- `wireframes/`：低保真线框图。
- `ui/`：高保真界面图片、SVG 和视觉规范。
- `prototypes/`：可交互 HTML/CSS/JS 原型。
- `assets/`：设计使用的本地图标、图片和字体说明。
- `reviews/`：设计走查记录和验收清单。

## 设计入口文档

- `UI_HANDOFF.md`：移动端 UI 设计交付文档，交付给 UI/UX 或前端前必须先读。

## 设计文件索引

| ID | 功能 | 形式 | 版本 | 状态 | 文件 | 关联故事 |
|---|---|---|---|---|---|---|
| DESIGN-001 | 链接导入全流程 | HTML 原型 | v0 | 待走查 | `prototypes/index.html`（添加入口、链接导入、解析进度、失败降级、草稿确认） | US-004、US-005 |
| DESIGN-002 | 首页与菜谱管理 | HTML 原型 | v0 | 待走查 | `prototypes/index.html`（首页默认/空态、菜谱库、详情、编辑） | US-009 |
| DESIGN-003 | LLM 与 OCR 设置 | HTML 原型 | v0 | 待走查 | `prototypes/index.html`（我的、LLM API 设置、OCR 设置） | US-006、US-007、US-008 |
| DESIGN-004 | 烹饪模式 | HTML 原型 | v0 | 待走查 | `prototypes/index.html`（步骤大卡、多计时器、退出确认） | US-010 |
| DESIGN-005 | 冰箱与按食材推荐 | 流程文档 + HTML 原型 | v0 | 待走查 | `flows/FRIDGE_AND_RECOMMENDATION_FLOW.md`、`prototypes/index.html`（四栏导航、库存批次、筛选、推荐分组、扣减确认） | US-011、US-012、US-013 |
| DESIGN-006 | 冰箱拖拽与逐格冷冻动效 | 交互交接文档 | v0 | 待实施 | `flows/FRIDGE_DRAG_AND_FROST_ANIMATION_HANDOFF.md`（拖拽状态机、提交边界、二维逐格动画、失败与减少动态） | US-011 |
| DESIGN-007 | 全量菜谱备份与恢复 | 流程文档 | v0 | 待走查 | `flows/RECIPE_BACKUP_RESTORE_FLOW.md` | US-014 |
| DESIGN-008 | Image 2 图标与美术资产提示词 | 提示词规范 | v0 | 待走查 | `assets/IMAGE2_ICON_PROMPTS.md` | 全局 UI 美术资产 |

## 固定交付要求

每个关键页面至少包含：

- 默认态。
- 空状态。
- 加载态。
- 成功态。
- 错误态。
- 离线/弱网态。
- 权限拒绝态。
- 极限内容态。
- 游客态。
- 登录态。

设计完成标准以 `reviews/DESIGN_REVIEW_CHECKLIST.md` 为准。

## 图片交付

支持 PNG、JPG、WebP、SVG。要求：

- 文件名包含功能、页面/流程、状态和版本。
- 原始尺寸和目标设备尺寸写入同目录说明文件。
- 如使用外部素材，记录来源和授权。
- 不只输出一张拼图；关键状态应能单独查看。

## HTML 原型交付

- 必须能从本地文件或本地开发服务运行。
- 样式、脚本和图片优先放在原型自己的目录中。
- 不依赖登录后的云端链接。
- 必须附 `README.md`，说明启动方式、入口文件、已实现交互和未实现部分。
- 原型只是设计产物，生产代码仍写入 `code/`。

## 版本规则

- 首次探索：`v0`。
- 走查通过但尚未开发：`v1`。
- 实施中修改：递增小版本，例如 `v1.1`。
- 产品流程变化后，旧设计不能静默覆盖，应保留或在评审记录中说明被替代。
