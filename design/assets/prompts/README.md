# 巴食 · Image 2 提示词分组索引

> 任务：DESIGN-008  
> 版本：v1.3 / 2026-08-10  
> 交付：底部导航双状态 glyph、48 条基础美术资产完整 Prompt、分类 active 编辑补充

## 本轮调整 v1.3

项目负责人明确要求“其他图标不需要使用 IP”。本版将 IP 使用范围收紧为：

1. 只有 [01-brand-assets.md](./01-brand-assets.md) 的 4 项品牌资产允许上传和参考 `../IP.png`。
2. 状态插图 12 项、功能入口 10 项、冰箱/库存/推荐 10 项、分类 default 12 项，共 44 条非品牌基础 Prompt 全部禁止 IP。
3. 底部导航 4 组 / 8 枚 glyph 和分类 12 张 active 也全部禁止 IP。
4. 非品牌资产只使用功能物体、食材和符号表达语义；出现人物、动物角色、厨师、五官、手脚、拟人表情、吉祥物或 IP 特征即淘汰。
5. 导航与分类保留 `default` / `active`；其他资产的交互状态仍由 Flutter 负责，不额外生成重复图片。

品牌资产优先级：**巴食 UI 风格与严格像素约束 > 官方 IP 身份 > 品牌构图细节**。  
非品牌资产优先级：**巴食 UI 风格与严格像素约束 > 单项功能语义**。

## Prompt 分组

| 优先级 | 文件 | 数量 | IP 边界 | 用途 |
|---|---|---:|---|---|
| P0 | [00-bottom-navigation-icons.md](./00-bottom-navigation-icons.md) | 1 张确认稿 / 8 枚最终 glyph | 禁止 | 底部导航 default / active 双状态 |
| P0 | [01-brand-assets.md](./01-brand-assets.md) | 4 | 允许 | App 图标、品牌符号、欢迎 Hero、通用封面 |
| P0 | [02-state-illustrations.md](./02-state-illustrations.md) | 12 | 禁止 | 空、加载、成功、失败等状态插图 |
| P1 | [03-entry-icons.md](./03-entry-icons.md) | 10 | 禁止 | 快速导入、AI 与主要功能入口 |
| P1 | [04-fridge-inventory-icons.md](./04-fridge-inventory-icons.md) | 10 | 禁止 | 冰箱分区、库存和推荐语义 |
| P1 | [05-category-icons.md](./05-category-icons.md) | 12 个 default | 禁止 | 默认分类图标 |
| P0 | [06-active-state-supplements.md](./06-active-state-supplements.md) | 分类 12 组 active | 禁止 | 双状态范围、分类 active 编辑 Prompt |

基础美术资产仍为 **48 条独立完整 Prompt**：品牌 4 条允许 IP，其他 44 条禁止 IP；v1.3 另包含无 IP 导航 8 枚 glyph 产物和无 IP 分类 12 枚 active 产物。导航确认稿只是校准图，不作为最终 sprite sheet 使用。

## 直接投喂 Image 2 的 txt

| 优先级 | 文件 | 内容 | IP 边界 |
|---|---|---|---|
| P0 | [for-ai/01-brand-assets.txt](./for-ai/01-brand-assets.txt) | 品牌 4 条 | 允许 |
| P0 | [for-ai/02-state-illustrations.txt](./for-ai/02-state-illustrations.txt) | 状态 12 条 | 禁止 |
| P1 | [for-ai/03-entry-icons.txt](./for-ai/03-entry-icons.txt) | 功能入口 10 条 | 禁止 |
| P1 | [for-ai/04-fridge-inventory-icons.txt](./for-ai/04-fridge-inventory-icons.txt) | 冰箱 / 库存 10 条 | 禁止 |
| P1 | [for-ai/05-category-icons.txt](./for-ai/05-category-icons.txt) | 分类 default 12 条 | 禁止 |
| P0 | [for-ai/06-active-state-supplements.txt](./for-ai/06-active-state-supplements.txt) | 分类 active 编辑 Prompt | 禁止 |

## 推荐生成顺序

### 1. 导航双状态确认

先用 [00-bottom-navigation-icons.md](./00-bottom-navigation-icons.md) 生成 2×4、共 8 枚 glyph 的确认稿：

- 第一行：`#8F978F` outline 未激活态。
- 第二行：`#476B52` filled / strong 激活态。
- 上下两态同轮廓、同尺寸、同基线、同重心。
- 不包含 `#EDF2EA` 激活底板；底板由 Flutter 绘制。
- 不上传或参考 `IP.png`、`封面图.png`，不出现角色或拟人化元素。

确认稿命名：`bottom-navigation-glyph-state-proof-v1.3.png`。

### 2. 早餐分类 default / active

1. 使用 [05-category-icons.md](./05-category-icons.md) 生成无 IP 的 `category-breakfast-v1.png`。
2. 通过 default 验收后，把同一张原图作为唯一编辑目标，使用 [06-active-state-supplements.md](./06-active-state-supplements.md) 生成无 IP 的 `category-breakfast-active-v1.png`。
3. 两张图以 50% 透明度叠放，确认外轮廓、像素矩阵、位置、基线、描边和投影完全重合。

### 3. 无角色冰箱空状态

使用 [02-state-illustrations.md](./02-state-illustrations.md) 生成 `state-fridge-empty-v1.png`：正视双门冰箱正交剖面、空搁板和添加食材符号；不得出现水豚、人物、厨师、脸、手脚、拟人表情、吉祥物或任何 IP 特征。

以上四张首轮产物通过后，再继续其他 46 条基础 Prompt，并制作其余 11 枚分类 active。

## 参考图规则

1. **品牌 4 项**：上传 `../IP.png` + 当前「巴食」UI 截图或色板卡；需要大场景关系时才可附 `../封面图.png`。
2. **所有非品牌资产**：不得上传或参考 `../IP.png`、`../封面图.png`，只上传当前 UI 截图或色板卡。
3. **导航 glyph**：只用导航专用 Prompt，必要时附纯色板卡。
4. **分类 active**：只上传已经通过的无 IP default 原图作为唯一编辑目标。
5. 品牌优先级：**巴食 UI 风格与严格像素约束 > 官方 IP 身份 > 品牌构图细节**。
6. 非品牌优先级：**巴食 UI 风格与严格像素约束 > 单项功能语义**。

## 非品牌母规则

```text
这是「巴食」App 的非品牌功能美术资产，不使用任何角色或 IP。
不要上传或参考 IP.png、封面图.png。
不要水豚、人物、厨师、厨师帽、墨镜、脸、手脚、拟人姿态、拟人表情或吉祥物。
只使用最简洁的功能物体、食材和符号表达语义。

严格二维像素风，完全正视或正交平面构图。
使用清晰方形像素台阶、有限色板和实色块。
无 3D、无等距视角、无 3/4 透视、无侧面厚度、无顶面、无高光、无渐变、无材质、无环境光、无体积光、无 AO、无软阴影、无模糊、无平滑抗锯齿、无柔和圆角矢量感、无贴纸感、无 emoji。
```

各分组文件中的每条 Prompt 已包含完整限制；母规则用于人工检查，不要求使用者手工拼接。

## 不制作独立 active 图片的资产

- 品牌资产：非交互标识。
- 状态插图：图片本身已经表达页面状态。
- 功能入口：pressed / busy / disabled / focus 由 Flutter 容器、透明度、描边和进度状态表达。
- 冰箱分区、库存与推荐：选中、缺失、数量和等级由卡片、文字、标签与原生箭头表达。
- 返回、关闭、收藏、勾选、删除、箭头、开关等 16–24px 高频操作符号继续使用 Flutter 原生图标。

## 一票否决

出现任一项即整张淘汰：

- 3D、等距、3/4 透视、可见侧面、顶面或厚度。
- 渐变、柔光、环境光、AO、体积光、软阴影、倒角、挤出。
- 平滑抗锯齿、亚像素曲线、圆润矢量感。
- 黏土、塑料、贴纸、emoji、游戏道具质感。
- 文字、水印、第三方 Logo、设备框、UI mockup。
- active 与 default 外轮廓、比例、位置、基线或投影不一致。
- 非品牌资产出现水豚、人物、厨师、厨师帽、墨镜、脸、手脚、拟人姿态、拟人表情、吉祥物或任何 IP 特征。

## 当前状态

本轮只交付可复制提示词与状态规范，**未调用 Image 2、未生成图片**。等待项目负责人回传导航双状态确认稿、早餐分类 default / active 和冰箱空状态样张；收到验证反馈前，DESIGN-008 保持 `VERIFY`。
