# P1 默认分类图标 · Image 2 完整提示词

> 正式产品名称：巴食
> 版本：v1.3 / 2026-08-10
> 位置/场景：家常菜、快手菜、早餐、主食、汤羹、烘焙、甜品、饮品、素菜、肉类、水产、轻食
> 规则：本文件 12 条均为 default 图完整 Prompt；对应 active 图必须使用 `06-active-state-supplements.md` 的编辑 Prompt 基于已通过的 default 原图制作。
> 分类图标额外检查 40px；食物使用低饱和实色块，不追求写实、油亮或立体。

## 使用前准备

- **本文件全部资产禁止上传、参考或生成 `IP.png` / 官方水豚主厨**，也不要上传 `封面图.png`。
- 只上传一张当前「巴食」UI 截图或只包含正式色板、像素切角、描边与硬投影的风格卡。
- 只用最简洁的功能物体、食材和符号表达语义；不要人物、厨师、脸、手脚或拟人姿态。
- 生成一图一资产；不要一次生成 icon grid、sprite sheet 或多版本拼图。
- 上一版已因结果偏 3D 退役；正式候选只使用本文件的 v1.3 Prompt。

## Default / Active 双状态规则

- 12 个分类都需要 `default` / `active` 两张图，以支持当前分类筛选的长期选中状态。
- 本文件只负责 default 原图；default 通过后，把**同一张原图作为编辑目标**交给 Image 2 制作 active。
- active 必须保持外轮廓、像素矩阵、构图、位置、基线、描边、硬投影和透明区域完全不变，只调整正式深绿色的视觉权重。
- 选中卡片背景 `#DDE7DC`、选中边框 `#476B52`、标签颜色与点击反馈全部由 Flutter 绘制，不能烘焙进图片。
- 通用 active 编辑 Prompt 和 12 组文件名见 [06-active-state-supplements.md](./06-active-state-supplements.md)。
- 先验证 `category-breakfast-v1.png` / `category-breakfast-active-v1.png`，叠放无位移且 40px 可辨后再继续其余 11 组。

## 1. 家常菜 `category-home-cooking-v1.png`

```text
用途：「巴食」默认菜谱分类“家常菜”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-home-cooking-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只小炒锅与一把短锅铲，锅内只有三块青绿和暖褐色食材，升起一缕方块蒸汽，表达日常热菜。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 2. 快手菜 `category-quick-v1.png`

```text
用途：「巴食」默认菜谱分类“快手菜”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-quick-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只小煎锅与一个极简四分之一钟面并列成紧凑整体，锅边有两条短像素速度线，不能像赛车或闪电 Logo。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 3. 早餐 `category-breakfast-v1.png`

```text
用途：「巴食」默认菜谱分类“早餐”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-breakfast-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一片方吐司与一枚煎蛋轻微重叠，蛋黄使用低饱和琥珀色，轮廓简洁，无咖啡馆背景。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 4. 主食 `category-staple-v1.png`

```text
用途：「巴食」默认菜谱分类“主食”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-staple-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只浅色饭碗，碗中同时以少量米粒方块和两根短面条概括主食，不堆满配菜。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 5. 汤羹 `category-soup-v1.png`

```text
用途：「巴食」默认菜谱分类“汤羹”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-soup-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只带小把手的汤碗与短勺，表面只有两块配料和一缕蒸汽，汤色低饱和。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 6. 烘焙 `category-baking-v1.png`

```text
用途：「巴食」默认菜谱分类“烘焙”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-baking-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个小面包与一只烤箱手套轻微重叠，面包暖褐色面积受控，不画完整烤箱。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 7. 甜品 `category-dessert-v1.png`

```text
用途：「巴食」默认菜谱分类“甜品”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-dessert-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一小块方形布丁或蛋糕，顶部只有一枚绿色小叶点缀，造型克制，不使用粉红糖果色。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 8. 饮品 `category-drink-v1.png`

```text
用途：「巴食」默认菜谱分类“饮品”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-drink-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只透明感被简化为浅色块面的杯子与一根短吸管，杯中有一片叶形点缀；不要玻璃高光和品牌标签。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 9. 素菜 `category-vegetarian-v1.png`

```text
用途：「巴食」默认菜谱分类“素菜”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-vegetarian-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一小朵西兰花与一片叶菜组成紧凑主体，以青灰绿为主，不画篮子或农场。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 10. 肉类 `category-meat-v1.png`

```text
用途：「巴食」默认菜谱分类“肉类”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-meat-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只熟制鸡腿或两片熟肉的概括轮廓，使用低饱和暖褐与红棕，表现已烹饪、干净、不血腥。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 11. 水产 `category-seafood-v1.png`

```text
用途：「巴食」默认菜谱分类“水产”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-seafood-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一条侧面的简化小鱼，鱼身蓝灰与浅绿，只有一个像素眼点和两条鳍，不画水族馆背景。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 12. 轻食 `category-light-v1.png`

```text
用途：「巴食」默认菜谱分类“轻食”的美术型图标；分类名由 Flutter 单独渲染。
资产文件名：`category-light-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只浅色沙拉碗，碗内只有三片绿叶、一块番茄色方块和一枚浅色谷物块，整体清爽但不高饱和。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或盘面透视；单主体或最多两个紧密相关食物元素，占画布约 70%，不堆满餐盘；轮廓在 48px 和 40px 都应清楚。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px；分类图标额外检查 40px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```
