# 设计素材

本目录只保存项目设计实际使用且授权或来源边界明确的本地素材。每批外部素材或 AI 生成素材都应记录来源、用途、日期、版本和使用范围。

## 品牌事实源与 IP 边界

- 正式产品名称：**巴食**。
- `IP.png`：官方水豚主厨的唯一身份参考，只允许用于 4 项品牌资产，并且只控制角色身份、比例、服装、配件和轮廓。
- `封面图.png`：只允许辅助品牌资产理解角色与厨房场景关系；不是 48–96px 图标的渲染标准。
- Flutter/HTML 已落地 UI：全部美术资产的渲染事实源，控制色板、像素密度、阶梯缺角、深墨绿描边和右下硬投影。

只有以下 4 项允许使用 IP：App 图标、品牌核心符号、欢迎页 Hero、通用菜谱占位封面。状态插图、功能入口、冰箱/库存/推荐、分类 default / active、底部导航 default / active 全部禁止上传、参考或生成 IP，只使用物体、食材和符号表达语义。

品牌资产也严禁从 `IP.png` 或 `封面图.png` 继承平滑抗锯齿、渐变、柔光、体积光、厚涂、黏土/塑料或类 3D 画法。

## 当前入口

- [IMAGE2_ICON_PROMPTS.md](./IMAGE2_ICON_PROMPTS.md)：DESIGN-008 v1.3 总规范、色板、IP 使用边界、双状态边界、淘汰规则与生成流程。
- [prompts/README.md](./prompts/README.md)：导航双状态、分类双状态与 48 条基础美术资产 Prompt 的分组索引。
- [prompts/00-bottom-navigation-icons.md](./prompts/00-bottom-navigation-icons.md)：底部导航 4 组 / 8 枚 default / active 的 24×24 单色像素 UI glyph Prompt；禁止 IP、阴影或多色塑形。
- [prompts/06-active-state-supplements.md](./prompts/06-active-state-supplements.md)：需要独立 active 图片的资产边界，以及无 IP 分类 12 组 active 的编辑 Prompt。
- [prompts/01-brand-assets.md](./prompts/01-brand-assets.md)：品牌 4 项，唯一允许使用 IP 的分组。
- [prompts/02-state-illustrations.md](./prompts/02-state-illustrations.md)：无角色状态插图 12 项。
- [prompts/03-entry-icons.md](./prompts/03-entry-icons.md)：无角色功能入口 10 项。
- [prompts/04-fridge-inventory-icons.md](./prompts/04-fridge-inventory-icons.md)：无角色冰箱/库存/推荐 10 项。
- [prompts/05-category-icons.md](./prompts/05-category-icons.md)：无角色分类 12 组 default；每组对应一枚基于原图编辑的无角色 active。

## 资产与状态分工

- **底部导航自定义 glyph**：首页、菜谱库、冰箱、我的共 4 组 / 8 枚图片，分别制作 default 与 active；禁止 IP。图片只负责 glyph 差异，选中底板、边框、文字颜色和点击反馈由 Flutter 绘制。
- **默认分类图标**：家常菜、快手菜、早餐、主食、汤羹、烘焙、甜品、饮品、素菜、肉类、水产、轻食共 12 组 default / active；禁止 IP，active 必须基于已通过的 default 原图编辑，禁止从零重画。
- **品牌 4 项**：App 图标、品牌符号、欢迎页 Hero、通用菜谱占位封面允许使用官方 IP。
- **其他生成型美术资产**：48px 以上功能入口、空/错/完成状态、冰箱分区、库存和推荐图标禁止 IP，只制作其语义主图，不制作独立 active 图片。
- **短暂交互状态**：功能入口的 pressed / busy / disabled / focus，以及库存卡片的选中、缺失、数量和推荐等级，由 Flutter 容器、透明度、描边、文字、标签和进度状态处理。
- **代码原生图标**：返回、关闭、搜索、收藏、删除、勾选、箭头、更多、开关等 16–24px 高频操作符号继续使用 Flutter 原生组件。
- **文字与数字状态**：分类名、状态名、「缺 1 样 / 缺 2 样」等始终由 Flutter 渲染，不烘焙进图片。

## 建议目录

```text
design/assets/generated/
├─ brand/
├─ states/
├─ entries/
├─ fridge/
├─ categories/
├─ navigation/
└─ source/
```

只有开始生成并选定资产后才创建对应目录，不提交空目录。

## 命名规则

```text
<组>-<语义>-<状态>-v<版本>-<尺寸>.<png|webp>
```

示例：

```text
brand-app-icon-capybara-chef-v1-1024.png
state-fridge-empty-v1-256.png
entry-import-link-v1-96.webp
category-breakfast-v1-64.webp
category-breakfast-active-v1-64.webp
nav-home-default-v1-24.png
nav-home-active-v1-24.png
```

## 每批素材登记要求

| 字段 | 要求 |
|---|---|
| 文件 | 本地相对路径 |
| 用途 | 对应页面、组件和状态 |
| 来源 | 自制 / OpenAI Image 2 / 外部素材站点 |
| 日期与版本 | 生成或下载日期、资产版本 |
| Prompt / 参考图 | 完整提示词文件与实际使用的 UI 截图或色板卡；只有品牌 4 项可登记 `IP.png` / `封面图.png` |
| 授权 / 使用边界 | 是否允许商用、修改、再分发；AI 生成时记录适用服务条款 |
| 验收 | 项目负责人选择结果；品牌项检查 IP 相似度；非品牌项检查无角色/IP；全部检查小尺寸、双状态重合、透明边缘与一票否决项 |

## 交付限制

- 一图一资产，不把 icon grid / sprite sheet 当最终切图来源；导航 2×4 只用于首轮造型确认。
- AI 原始母稿、去背母稿和最终导出尺寸分开保存。
- 正式进入 Flutter 前检查 96px、64px、48px；分类额外检查 40px；导航额外检查约 21px；App 图标检查到 48px。
- 导航 default / active 必须同外轮廓、同尺寸、同位置、同重心、同基线；分类 active 必须与 default 的像素矩阵、描边、硬投影和透明区域完全一致。
- 出现 3D、透视、厚度、渐变、软阴影、平滑抗锯齿、圆润矢量感等任一偏差，整张淘汰。
- 非品牌资产出现水豚、人物、厨师、厨师帽、墨镜、脸、手脚、拟人姿态、拟人表情、吉祥物或任何 IP 特征，整张淘汰。
- 图片内不得包含密钥、Token、账号、隐私数据、第三方平台 Logo 或未授权商标。
- 只有项目负责人按验收文档走查通过后，生成结果才可视为可实施资产。

## 当前资产登记

本轮只交付 v1.3 提示词与状态规范，**尚未调用 Image 2、尚未生成或选定正式图片资产**。当前等待 `bottom-navigation-glyph-state-proof-v1.3.png`、`category-breakfast-v1.png`、`category-breakfast-active-v1.png` 和 `state-fridge-empty-v1.png` 首轮样张。
