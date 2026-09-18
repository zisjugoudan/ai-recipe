# P1 冰箱与库存图标 · Image 2 完整提示词

> 正式产品名称：巴食
> 版本：v1.3 / 2026-08-10
> 位置/场景：冷藏/冷冻/常温/其他分区、临期/过期/数量未知、清库存、推荐匹配
> 规则：每条都是可独立复制的完整 Prompt，不需要再拼接母版。
> 分区、状态和推荐图标必须优先保证 48px 语义，文字与数字由 Flutter 渲染。

## 使用前准备

- **本文件全部资产禁止上传、参考或生成 `IP.png` / 官方水豚主厨**，也不要上传 `封面图.png`。
- 只上传一张当前「巴食」UI 截图或只包含正式色板、像素切角、描边与硬投影的风格卡。
- 只用最简洁的功能物体、食材和符号表达语义；不要人物、厨师、脸、手脚或拟人姿态。
- 生成一图一资产；不要一次生成 icon grid、sprite sheet 或多版本拼图。
- 上一版已因结果偏 3D 退役；正式候选只使用本文件的 v1.3 Prompt。

## 1. 冷藏区 `fridge-zone-chilled-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“冷藏区”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`fridge-zone-chilled-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一台简化双门冰箱的上层冷藏门被浅绿色高亮，门内可见一层搁板和一片叶菜；不要雪花，避免与冷冻区混淆。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 2. 冷冻区 `fridge-zone-frozen-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“冷冻区”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`fridge-zone-frozen-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：与冷藏图标同一台冰箱，下层抽屉被蓝灰色高亮，抽屉前有一个极简六角雪花像素符号；雪花是辅助，不超过主体 18%。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 3. 常温区 `fridge-zone-room-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“常温区”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`fridge-zone-room-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个整洁的矮储物篮，里面只有一只密封罐和一个根茎食材轮廓，使用暖米白与青灰绿，不出现冰箱或雪花。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 4. 其他区 `fridge-zone-other-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“其他区”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`fridge-zone-other-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个带四格分区的浅色收纳盒，里面只露出三种不同几何轮廓的小食材包，表达未归入固定温区的其他存放。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 5. 临期 `inventory-expiring-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“临期”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`inventory-expiring-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个完整食材袋或保鲜盒，右上附一个琥珀色小钟面符号；食材仍新鲜挺立，不要枯萎或红叉。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 6. 已过期 `inventory-expired-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“已过期”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`inventory-expired-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个保鲜盒与一片轻微下垂的叶子，右上附低饱和红色感叹方块；保持克制卫生，不画腐烂、虫子、液体或恶心细节。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 7. 数量未知 `inventory-quantity-unknown-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“数量未知”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`inventory-quantity-unknown-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个食材保鲜盒放在简化秤盘旁，秤盘刻度留空并以三个方块点表示尚未记录；不使用问号、数字或文字。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 8. 优先清库存 `inventory-use-first-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“优先清库存”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`inventory-use-first-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个食材篮通过短箭头指向一只小锅，篮中最前方食材带一个琥珀色小钟点，表达优先使用临期库存。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 9. 可能可以做 `recommend-maybe-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“可能可以做”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`recommend-maybe-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只小锅与两枚相似但不完全相同的食材方块，中间用琥珀色半闭合连接符连接，表达可替代但需要确认；不要使用绿色勾或红叉。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 10. 缺少食材 `recommend-missing-v1.png`

```text
用途：「巴食」冰箱/库存/推荐场景中的“缺少食材”美术型图标；具体状态名称与数字由 Flutter 文案显示。
资产文件名：`recommend-missing-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一只小锅旁有两个已填充食材方块和一个空心占位方块，表达还缺少内容；不画数字，具体「缺 1/2 样」由 UI 文案显示。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 或等距透视，主体占画布约 68%；相关分区图标共享冰箱/容器的相同比例，状态辅助符号不超过主体 18%；48px 仍能区分语义。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```
