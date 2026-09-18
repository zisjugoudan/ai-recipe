# P0 品牌资产 · Image 2 完整提示词

> 正式产品名称：巴食
> 版本：v1.3 / 2026-08-10
> 位置/场景：App 图标、品牌核心符号、欢迎页 Hero、通用菜谱无封面
> 规则：每条都是可独立复制的完整 Prompt，不需要再拼接母版。
> 四项均使用官方水豚主厨；`IP.png` 只控制身份，现有 UI 控制严格二维像素渲染。

## 使用前准备

- **仅本文件这 4 项品牌资产允许上传 `../IP.png`**；状态插图、功能入口、冰箱/库存、分类和导航全部禁止使用 IP。
- 同时上传一张当前「巴食」UI 截图或色板卡，由 UI 控制颜色、像素密度、阶梯缺角、描边与硬投影；`IP.png` 只控制官方水豚主厨身份。
- `封面图.png` 仅在欢迎页 Hero 需要理解厨房关系时作为次级构图参考，不能控制渲染画法。
- 生成一图一资产；不要一次生成 icon grid、sprite sheet 或多版本拼图。
- 上一版已因结果偏 3D 退役；正式候选只使用本文件的 v1.3 Prompt。

## 1. App 启动图标 `brand-app-icon-capybara-chef-v1.png`

```text
用途：移动端 App 启动图标；产品正式名称为「巴食」，但图片内不生成任何文字。
资产文件名：`brand-app-icon-capybara-chef-v1.png`。
参考图与优先级：必须使用 `IP.png` 识别官方水豚主厨，只保留金棕色水豚、白色厨师帽、白色双排扣厨师服、黑色墨镜、粉红腮红、木勺/打蛋器、圆胖短肢比例与轮廓身份；绝对不要继承参考图的平滑抗锯齿、渐变、柔光、体积光、厚涂或类 3D 画法。如同时附带「巴食」UI 截图或 UI 色板卡，由 UI 控制渲染、配色、像素密度、切角和硬阴影，不复制 UI 的文字与布局。`封面图.png` 只帮助理解角色与厨房场景关系，不是小图标渲染标准。Rendering priority: 巴食 UI style and strict pixel constraints > IP identity reference > subject details。
主要请求：官方水豚主厨的正面头部到胸像：金棕色脸部、圆短耳、白色高厨师帽、黑色墨镜、粉红腮红，胸前露出白色双排扣厨师服；一把短木勺从右肩后方斜出但不遮挡脸。轮廓压缩成一个紧凑、可记忆的整体，48×48 时仍能一眼认出水豚主厨、厨师帽和墨镜。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；官方 IP 正面、平视、无透视，头像/胸像占画布约 72%，四周安全留白一致。厨师帽顶部、耳朵、墨镜和脸部外轮廓必须在 48px 缩略图中仍分离可辨。
背景：完整不透明的纯 #F3F1E9 暖米白正方形背景，可有极少量按 8 逻辑像素节奏排列的 #EAE7DC 单像素纸张点纹，但不得形成渐变或噪点。不要预制 iOS/Android 圆角，四角保持完整正方形，由系统遮罩。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或主体身份/语义不可辨时，减少细节后重新生成。
```

## 2. 品牌核心符号 `brand-mark-capybara-chef-v1.png`

```text
用途：「巴食」品牌核心符号，可用于欢迎页、关于页和较大品牌装饰，不用于 16–24px 操作按钮。
资产文件名：`brand-mark-capybara-chef-v1.png`。
参考图与优先级：必须使用 `IP.png` 识别官方水豚主厨，只保留金棕色水豚、白色厨师帽、白色双排扣厨师服、黑色墨镜、粉红腮红、木勺/打蛋器、圆胖短肢比例与轮廓身份；绝对不要继承参考图的平滑抗锯齿、渐变、柔光、体积光、厚涂或类 3D 画法。如同时附带「巴食」UI 截图或 UI 色板卡，由 UI 控制渲染、配色、像素密度、切角和硬阴影，不复制 UI 的文字与布局。`封面图.png` 只帮助理解角色与厨房场景关系，不是小图标渲染标准。Rendering priority: 巴食 UI style and strict pixel constraints > IP identity reference > subject details。
主要请求：沿用已批准 App 图标中完全相同的官方水豚主厨正面头像/胸像比例、厨师帽、黑墨镜、腮红和短木勺，去掉不透明 App 图标底，只保留紧凑角色主体；不得重新设计物种、服装、配件或表情。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个正面品牌主体；角色占画布约 72%，无外框、无底板、无预制圆角，四周留足去背安全区。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或主体身份/语义不可辨时，减少细节后重新生成。
```

## 3. 欢迎页 Hero `welcome-hero-capybara-kitchen-v1.png`

```text
用途：「巴食」欢迎页顶部横向 Hero；产品名称和按钮由 Flutter 单独渲染，图片内不出现文字。
资产文件名：`welcome-hero-capybara-kitchen-v1.png`。
参考图与优先级：必须使用 `IP.png` 识别官方水豚主厨，只保留金棕色水豚、白色厨师帽、白色双排扣厨师服、黑色墨镜、粉红腮红、木勺/打蛋器、圆胖短肢比例与轮廓身份；绝对不要继承参考图的平滑抗锯齿、渐变、柔光、体积光、厚涂或类 3D 画法。如同时附带「巴食」UI 截图或 UI 色板卡，由 UI 控制渲染、配色、像素密度、切角和硬阴影，不复制 UI 的文字与布局。`封面图.png` 只帮助理解角色与厨房场景关系，不是小图标渲染标准。Rendering priority: 巴食 UI style and strict pixel constraints > IP identity reference > subject details。
主要请求：官方水豚主厨站在简化厨房台面后，左手握木勺搅拌浅色碗，右侧放打蛋器；后方只保留一个阶梯切角橱柜轮廓、一片香草叶和两颗小方块星点。画面表达“把零散内容整理成可以下厨的菜谱”，角色是主视觉，厨房只是低信息量辅助，不出现手机、机器人或文字。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1536×1024 横向画布，使用 96×64 逻辑像素网格；角色和台面主体集中在中部 70%，左右留白供响应式裁切；平视正交，无室内透视、景深或远近缩放。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或主体身份/语义不可辨时，减少细节后重新生成。
```

## 4. 通用菜谱无封面 `recipe-cover-placeholder-v1.png`

```text
用途：「巴食」菜谱没有用户封面时的通用占位图，不能暗示具体菜名或食材品牌。
资产文件名：`recipe-cover-placeholder-v1.png`。
参考图与优先级：必须使用 `IP.png` 识别官方水豚主厨，只保留金棕色水豚、白色厨师帽、白色双排扣厨师服、黑色墨镜、粉红腮红、木勺/打蛋器、圆胖短肢比例与轮廓身份；绝对不要继承参考图的平滑抗锯齿、渐变、柔光、体积光、厚涂或类 3D 画法。如同时附带「巴食」UI 截图或 UI 色板卡，由 UI 控制渲染、配色、像素密度、切角和硬阴影，不复制 UI 的文字与布局。`封面图.png` 只帮助理解角色与厨房场景关系，不是小图标渲染标准。Rendering priority: 巴食 UI style and strict pixel constraints > IP identity reference > subject details。
主要请求：官方水豚主厨从台面后露出头部和上半身，双手呈上一个装有概括化家常热菜的浅色盘：三块青绿色蔬菜、两块暖褐色食材和一小撮米饭或面条，上方两缕方块蒸汽。食物不对应具体菜名，角色身份清楚但不抢过菜品。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1536×1024 横向画布，使用 96×64 逻辑像素网格；角色与菜盘组成居中紧凑主体，占画布约 68%，允许安全裁成 4:3 或 16:9；平视正交，不做桌面透视。
背景：完整不透明的 #F3F1E9 暖米白纸张底，可用极少量规则的 #EAE7DC 单像素点形成 8 逻辑像素节奏；无渐变、无摄影纹理、无环境光。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或主体身份/语义不可辨时，减少细节后重新生成。
```
