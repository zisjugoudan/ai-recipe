# 底部导航栏 24×24 像素 UI Glyph 双状态提示词

> 任务：DESIGN-008  
> 版本：v1.3 / 2026-08-10  
> 用途：先确认首页、菜谱库、冰箱、我的四个底部导航图标的未激活态 / 激活态造型

## 使用规则

- **不要上传或参考 `IP.png`、`封面图.png`**。导航 glyph 是纯功能符号，与官方 IP 无关；上传角色参考会把结果带回角色插画或 3D 风格。
- 如需参考，只上传当前「巴食」UI 截图或只包含正式色板、像素切角的风格卡；不要复制界面文字和布局。
- 首轮生成 2 行 × 4 列双状态确认稿，用于比较同一图标的 default / active；确认后再逐枚生成最终单图。
- Flutter 实际显示约 21px，因此所有笔画、孔洞和负空间至少 2 个逻辑像素。
- `#EDF2EA` 激活背景、外框、文字颜色、点击反馈均由 Flutter 绘制，不能烘焙进图片。

## 可直接复制给 Image 2 的提示词

```text
用途：为中国食谱 App「巴食」制作底部导航栏的严格二维像素 UI glyph 双状态确认稿。

这不是插画、游戏道具、物体渲染、贴纸或 3D 像素画，而是一套真正用于移动端底部导航栏的 monochrome pixel UI glyphs。所有图标必须遵守同一套 24×24 logical pixel grid、同一笔画宽度、同一视觉重量、同一基线和同一像素密度。

画布排版：2 行 × 4 列，共 8 枚 glyph，列间距和行间距完全一致；不生成文字、标签、按钮、卡片或设备界面。
- 第一行：四枚未激活态，依次为首页、菜谱库、冰箱、我的。
- 第二行：对应的四枚激活态，顺序完全相同。
- 每一列的上下两枚必须共享相同外轮廓、尺寸、位置、重心、基线和负空间，只改变状态表达，不得重画成不同图标。

四个语义：
1. 首页：完全正视的简化房屋轮廓，屋顶与方形门洞清楚，无烟囱、窗景或装饰。
2. 菜谱库：完全正视、左右对称的打开书本，只有书页轮廓和中央书脊分隔线；不可出现封面厚度、纸张侧面、翻页透视或 3/4 视角。
3. 冰箱：完全正视的双门冰箱，矩形外轮廓、水平门缝和短把手清楚；不可看见顶面、侧面或门体厚度。
4. 我的：正视圆形头像与简化肩部，只表达普通用户轮廓；不要水豚、人物、厨师、厨师帽、墨镜、脸、手脚、拟人表情、吉祥物或任何 IP 特征。

第一行未激活态：
- 使用 outline glyph；统一 2 logical pixel 主笔画。
- 唯一颜色为 #8F978F；不要任何第二种图标颜色。
- 内部留白清楚，最小孔洞和间距不小于 2 logical pixels。

第二行激活态：
- 使用 filled / strong glyph，但必须保持与上方未激活态相同的外轮廓、尺寸、占比和基线。
- 通过加粗关键结构、填充局部主体面或减少内部空白表达选中，不得变成立体实物、复杂剪影或另一套图标。
- 唯一颜色为 #476B52；不要沿用 #8F978F，不要渐变，不要叠加第三种颜色。
- 仍保留必要的 2 logical pixel 负空间，使房屋门洞、书本中缝、冰箱门缝、头像与肩部关系清楚。

像素与构图：
- 每枚严格按照 24×24 logical pixel grid 设计，主体占约 18×18 到 20×20 logical pixels。
- 只允许 90 度水平/垂直线和由方形像素台阶构成的 45 度斜线；圆弧必须显示明确的整数像素台阶。
- 8 枚图标视觉重量一致，不能某一枚更写实、更粗、更高、更大或更复杂。
- 画布使用完全均匀的纯 #FCFBF6 背景，仅用于查看；不要加入激活胶囊、选中底板、边框、文字、阴影或页面 UI。
- 图标边缘必须是 hard-edged square pixels，nearest-neighbor pixel rendering，无抗锯齿、无半透明像素、无模糊。

严格禁止：
no 3D, no perspective, no isometric, no three-quarter view, no side face, no top face, no thickness, no depth, no bevel, no extrusion, no shading, no highlight, no gradient, no cast shadow, no ambient shadow, no ambient occlusion, no lighting, no material, no texture, no glossy surface, no realistic object, no game item icon, no inventory icon, no illustration, no scene, no sticker, no emoji, no soft rounded vector icon, no antialiasing, no subpixel curve, no blur, no extra colors, no capybara, no chef, no bowl, no utensils, no food, no text, no letters, no numbers, no logo, no watermark.

输出要求：只输出这一张 2×4 双状态造型确认稿。若书本或冰箱出现侧面、顶面、厚度、纸张层叠、明暗、高光或投影，整张直接淘汰并重新生成；不要在 3D 结果上添加像素滤镜。
```

## 最终单枚文件名

双状态确认稿通过后，按同一像素矩阵逐枚导出，不要让模型重新设计轮廓：

| Tab | 未激活态 | 激活态 |
|---|---|---|
| 首页 | `nav-home-default-v1.png` | `nav-home-active-v1.png` |
| 菜谱库 | `nav-library-default-v1.png` | `nav-library-active-v1.png` |
| 冰箱 | `nav-fridge-default-v1.png` | `nav-fridge-active-v1.png` |
| 我的 | `nav-profile-default-v1.png` | `nav-profile-active-v1.png` |

最终单枚必须只包含 glyph；未激活态像素只用 `#8F978F`，激活态像素只用 `#476B52`，透明区域由本地切图处理。

## 首轮验收

1. 上下两态是否同轮廓、同尺寸、同基线、同重心，而不是两套不同造型。
2. 未激活态是否仅 `#8F978F`，激活态是否仅 `#476B52`，无任何塑形色阶。
3. 缩到 21px 后，房屋、书本、冰箱、头像是否仍能一眼区分。
4. 书本与冰箱是否完全正视，不可见顶面、侧面、厚度和透视。
5. 是否完全没有 3D、渐变、高光、投影、材质、抗锯齿和激活容器。
6. `#EDF2EA` 激活底板、边框和文字状态是否仍留给 Flutter 绘制。
