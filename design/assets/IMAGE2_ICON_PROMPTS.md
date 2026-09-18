# 巴食 · OpenAI Image 2 图标与美术资产提示词规范

> 任务：DESIGN-008
> 版本：v1.3 / 2026-08-10
> 结论：上一轮样张因过度 3D 被淘汰；本版继续执行严格二维像素风，并将官方 IP 的使用范围收紧为仅限 4 项品牌资产。其余功能美术资产全部以物体、食材和符号表达语义。

## 1. 事实源与优先级

### 1.1 正式产品名

产品正式名称为 **「巴食」**。生成图片内默认不出现产品文字；需要展示名称时由 Flutter 文字组件渲染。

### 1.2 IP 使用边界

`IP.png` 是官方水豚主厨的唯一身份参考，但只允许用于以下 4 项品牌资产：

1. `brand-app-icon-capybara-chef-v1.png`
2. `brand-mark-capybara-chef-v1.png`
3. `welcome-hero-capybara-kitchen-v1.png`
4. `recipe-cover-generic-capybara-cooking-v1.png`

品牌资产需要保留：金棕色水豚、圆胖身体、短肢、圆短耳、白色厨师帽、白色双排扣厨师服、黑色墨镜、粉红腮红，以及与具体构图相符的主厨配件。

**只继承身份，不继承画法。** 禁止从 `IP.png` 继承平滑抗锯齿、渐变、柔光、体积光、厚涂、圆润塑料感或类 3D 质感。`封面图.png` 只能辅助理解品牌角色与厨房场景关系，不是渲染标准。

以下所有非品牌资产禁止上传、参考或生成官方 IP：

| 资产分组 | 数量 | IP 边界 |
|---|---:|---|
| 状态插图 | 12 | 禁止 |
| 功能入口 | 10 | 禁止 |
| 冰箱 / 库存 / 推荐 | 10 | 禁止 |
| 分类 default | 12 | 禁止 |
| 分类 active | 12 | 禁止 |
| 底部导航 default / active | 4 组 / 8 枚 | 禁止 |

非品牌资产不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征，只使用最简洁的功能物体、食材和符号表达语义。

### 1.3 渲染事实源

现有 Flutter/HTML UI 决定最终画法：

- 米白纸张底、低饱和青灰绿、深墨绿文字与描边。
- 8px / 4px / 3px 阶梯缺角。
- 2–3px 右下单色硬投影。
- 实色块、硬边、可见方形像素台阶、最近邻缩放。
- 现代克制、温暖厨房感；不是复古街机，不是贴纸，不是柔滑圆角矢量插画。

品牌资产固定优先级：

```text
巴食 UI 风格与严格像素约束 > 官方 IP 身份 > 品牌构图细节
```

非品牌资产固定优先级：

```text
巴食 UI 风格与严格像素约束 > 单项功能语义
```

## 2. 正式色板

| 角色 | 色值 | 用途 |
|---|---|---|
| paper | `#F3F1E9` | 页面与 App 图标暖米白底 |
| paper2 | `#EAE7DC` | 纸张点纹、次级底 |
| card | `#FCFBF6` | 厨师服、卡片高亮面 |
| card2 | `#F5F2E9` | 次级卡片面 |
| ink | `#36403A` | 主轮廓、墨镜、主文字 |
| ink2 | `#5F6A63` | 次级轮廓 |
| ink3 | `#8F978F` | 弱信息 |
| green | `#5F8F6E` | 主绿 |
| greenDeep | `#476B52` | 深绿 |
| greenInk | `#33513C` | 硬描边与投影 |
| greenSoft | `#DDE7DC` | 浅绿块 |
| greenSofter | `#EDF2EA` | 淡绿底 |
| amber | `#B08D4F` | IP 金棕、食物暖色、临期 |
| red | `#AF6859` | IP 腮红、克制错误色 |
| blue | `#6E8697` | 冷冻、离线 |
| line | `#DDD8C9` | 浅描边 |
| line2 | `#CFC9B6` | 次描边 |

单个小图标通常只使用 4–7 色。每个表面最多一个基础色、一个硬阴影色和一个可选硬高光色。

## 3. 严格二维像素语法

每条正式 Prompt 已重复以下要求，无需手工拼装：

```text
strict flat 2D pixel art
true hard-edged square pixels
nearest-neighbor pixel rendering
limited palette
solid color blocks
one hard shadow tone and one optional highlight tone
no smooth transitions between colors
front-facing orthographic icon
no perspective depth
no environmental lighting
```

执行边界：

1. 小图标按 64×64 逻辑像素网格设计，状态 / Hero 可用 96×64。
2. 只做整数倍最近邻放大；禁止双线性 / 双三次缩放。
3. 所有弧线由清楚可见的方形像素台阶组成。
4. 禁止半透明边缘、亚像素曲线、平滑抗锯齿。
5. 只允许右下 2–3 逻辑像素的单色硬投影，不做环境阴影。
6. 不能先生成柔滑插画再叠加像素滤镜。

## 4. 一票否决项

任何样张出现以下任一项，整张直接淘汰：

```text
no 3D
no isometric
no 3/4 perspective
no visible side thickness or top face
no clay render
no glossy plastic
no bevel
no extrusion
no realistic lighting
no volumetric lighting
no ambient occlusion
no soft shadow
no gradient
no airbrush
no painterly shading
no watercolor
no smooth antialiasing
no soft rounded vector illustration
no sticker outline
no emoji
no cinematic depth of field
no photorealism
```

同时禁止文字、汉字、字母、数字、水印、签名、第三方 Logo、设备框、页面截图、icon grid、sprite sheet 和多版本拼图。

对非品牌资产，出现任何水豚、人物、厨师、厨师帽、墨镜、脸、五官、手脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或 IP 特征，同样整张淘汰。

## 5. 资产范围与提示词入口

| 优先级 | 分组 | 数量 | IP 边界 | 完整 Prompt |
|---|---|---:|---|---|
| P0 | 底部导航双状态 | 4 组 / 8 枚 glyph | 禁止 | [prompts/00-bottom-navigation-icons.md](./prompts/00-bottom-navigation-icons.md) |
| P0 | 品牌资产 | 4 | 允许 | [prompts/01-brand-assets.md](./prompts/01-brand-assets.md) |
| P0 | 状态插图 | 12 | 禁止 | [prompts/02-state-illustrations.md](./prompts/02-state-illustrations.md) |
| P1 | 功能入口 | 10 | 禁止 | [prompts/03-entry-icons.md](./prompts/03-entry-icons.md) |
| P1 | 冰箱与库存 | 10 | 禁止 | [prompts/04-fridge-inventory-icons.md](./prompts/04-fridge-inventory-icons.md) |
| P1 | 默认分类 | 12 | 禁止 | [prompts/05-category-icons.md](./prompts/05-category-icons.md) |
| P1 | 分类 active 衍生态 | 12 | 禁止 | [prompts/06-active-state-supplements.md](./prompts/06-active-state-supplements.md) |

基础美术资产仍为 48 条一图一资产 Prompt，其中只有品牌 4 条允许 IP，其他 44 条基础 Prompt 禁止 IP；另有底部导航 8 枚双状态 glyph 和基于 12 张无 IP 分类 default 原图编辑得到的 12 张无 IP active 图。分组索引与生成顺序见 [prompts/README.md](./prompts/README.md)。

## 6. 参考图工作流

### 6.1 品牌 4 项

上传：

1. `IP.png`：只控制角色身份。
2. 一张当前「巴食」UI 截图或色板卡：控制颜色、像素密度、阶梯缺角、描边与硬投影。
3. 需要大场景关系时可附 `封面图.png`，但明确它不是渲染标准。

### 6.2 所有非品牌资产

- 不要上传或参考 `IP.png`、`封面图.png`。
- 只附当前「巴食」UI 截图或纯色板卡。
- 只用物体、食材和符号表达语义，不出现任何角色或拟人化元素。
- 不附 3D、黏土、光泽图标或柔滑插画作为参考。

### 6.3 底部导航 glyph

只使用 [prompts/00-bottom-navigation-icons.md](./prompts/00-bottom-navigation-icons.md) 的导航专用 Prompt；它是 24×24 单色 UI glyph，不沿用 48–96px 美术插图的多色、描边和硬投影规则。

### 6.4 分类 active 图

先生成并验收无 IP 的 default，再把**已通过的同一张 default 原图**作为唯一 Image 1 上传，根据 [prompts/06-active-state-supplements.md](./prompts/06-active-state-supplements.md) 编辑。不要附 `IP.png` 或 `封面图.png`，禁止只输入分类名称从零重画 active。

### 6.5 防止复制 UI

提示词已要求只学习视觉 token，不复制截图中的文字、状态栏、按钮或页面布局。若模型仍复制界面，移除截图，改用只包含色块、缺角框和硬投影的 UI 风格卡再生成。

## 7. 背景与导出

- App 图标：完整不透明 `#F3F1E9` 正方形底，不预制 iOS / Android 圆角。
- 通用菜谱无封面：不透明纸张底。
- 其他透明资产：先生成纯 `#FF00FF` chroma-key 背景，再本地去背。
- 去背后分别放在 `#F3F1E9`、`#FCFBF6`、`#243B2D` 上检查洋红边、孔洞和误删。
- 使用最近邻缩放导出 96px、64px、48px；分类额外检查 40px。
- 导航最终单枚按 24×24 逻辑像素矩阵导出，Flutter 中实际显示约 21px。
- 16–24px 的返回、关闭、搜索、收藏、删除、勾选、箭头、开关、更多等操作符号继续使用 Flutter 原生图标。

## 8. v1.3 首轮验证顺序

本轮不要直接批量生成全部资产，按以下顺序验证：

1. `bottom-navigation-glyph-state-proof-v1.3.png`：2 行 × 4 列，共 8 枚无 IP 的 default / active glyph。
2. `category-breakfast-v1.png`：无 IP 的早餐分类 default。
3. `category-breakfast-active-v1.png`：以上一步通过的无 IP default 原图作为 Image 1 编辑得到。
4. `state-fridge-empty-v1.png`：无角色的正视双门冰箱正交剖面、空搁板与添加食材符号。

导航通过后再切分 8 枚单图；早餐 default / active 叠放无轮廓位移且 40px 可辨后，再制作其余 11 组分类 active。冰箱空状态需要在 3 秒内表达“暂无库存，可以添加食材”，并确认没有角色或 IP 特征。上述验证通过前，不批量生成其他同组资产，也不把任何图片接入 Flutter。

## 9. 当前状态

v1.3 已将 IP 使用范围收紧为仅限品牌 4 项；其他 44 条基础 Prompt、导航 8 枚 glyph 和分类 12 张 active 全部禁止 IP。**Codex 未调用 Image 2、未生成正式图片资产**。当前等待项目负责人按 `tests/acceptance/DESIGN-008-image2-icon-prompts-2026-08-10.md` 回传导航、早餐双状态和冰箱空状态样张；收到通过反馈前，任务保持 `VERIFY`。

## 10. 底部导航栏双状态专用规则

底部导航不沿用本规范中“64×64、4–7 色、允许右下硬投影”的美术型图标语法：

- 每枚是 24×24 logical pixel monochrome UI glyph，实际显示约 21px。
- 未激活态只使用 `#8F978F`，采用 outline。
- 激活态只使用 `#476B52`，采用 filled / strong。
- 同一 Tab 上下两态必须同外轮廓、同尺寸、同位置、同重心、同基线。
- 完全正视，无侧面、顶面、厚度、透视、阴影、高光、渐变、材质、抗锯齿或第二种图标颜色。
- 不上传或参考 `IP.png`、`封面图.png`；不出现水豚、人物、厨师、厨师帽、墨镜、脸、手脚、拟人姿态、拟人表情、吉祥物或任何 IP 特征。
- 激活容器 `#EDF2EA`、边框、文字和点击反馈由 Flutter 的 `PixelTabBar` 绘制，不能烘焙进 glyph。

完整可复制 Prompt 见 [prompts/00-bottom-navigation-icons.md](./prompts/00-bottom-navigation-icons.md)，其导航专用规则优先于本规范中面向 48–96px 美术资产的通用规则。

## 11. 分类图标双状态专用规则

十二个默认分类都需要 `default` / `active` 两张图：

- default 使用 [prompts/05-category-icons.md](./prompts/05-category-icons.md) 中对应分类的无 IP 完整 Prompt。
- active 必须上传已经通过的无 IP default 原图作为唯一编辑目标，保持外轮廓、像素矩阵、构图、位置、基线、描边、硬投影和透明区域不变。
- active 仅提高 `#476B52` / `#33513C` 的视觉权重，同时保留必要食物语义色；不得重画、位移、增删物体或变成整块深绿剪影。
- default 与 active 均不得上传、参考或生成 `IP.png`、`封面图.png` 中的角色；不得出现任何人物、动物角色、厨师或拟人化特征。
- 选中卡片背景 `#DDE7DC`、选中边框 `#476B52`、标签颜色和点击反馈由 Flutter 绘制，不进入图片。

完整编辑 Prompt 与十二组文件名见 [prompts/06-active-state-supplements.md](./prompts/06-active-state-supplements.md)。

## 12. 不制作独立 active 的资产

品牌资产和状态插图不是长期可选控件；功能入口的 pressed / busy / disabled / focus，冰箱库存的选中 / 数量 / 缺失 / 推荐等级，以及返回、关闭、收藏、勾选、删除、箭头和开关等操作状态，均由 Flutter 卡片、标签、文字或原生组件统一表达，不额外生成图片 active 版本。
