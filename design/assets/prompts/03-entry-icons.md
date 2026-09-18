# P1 功能入口图标 · Image 2 完整提示词

> 正式产品名称：巴食
> 版本：v1.3 / 2026-08-10
> 位置/场景：链接/文本/图片/视频导入、手动创建、AI 整理、备份、分享、识图引擎
> 规则：每条都是可独立复制的完整 Prompt，不需要再拼接母版。
> 本文件全部是非品牌功能图标，只使用功能物体、食材与符号表达语义；禁止任何角色或 IP。

## 使用前准备

- **本文件全部资产禁止上传、参考或生成 `IP.png` / 官方水豚主厨**，也不要上传 `封面图.png`。
- 只上传一张当前「巴食」UI 截图或只包含正式色板、像素切角、描边与硬投影的风格卡。
- 只用最简洁的功能物体、食材和符号表达语义；不要人物、厨师、脸、手脚或拟人姿态。
- 生成一图一资产；不要一次生成 icon grid、sprite sheet 或多版本拼图。
- 上一版已因结果偏 3D 退役；正式候选只使用本文件的 v1.3 Prompt。

## 1. 链接导入 `entry-import-link-v1.png`

```text
用途：「巴食」移动端“链接导入”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-import-link-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一张竖向菜谱卡与一个简化链环紧密组合，链环从卡片左下穿入但不遮挡主体；只画两节链环，轮廓清楚，表达从公开链接导入菜谱。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 2. 粘贴文本 `entry-paste-text-v1.png`

```text
用途：「巴食」移动端“粘贴文本”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-paste-text-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个简化剪贴板，纸面上只有三条粗短像素线，不出现真实文字；右下角有一个小型向内箭头方块，表达粘贴已有正文。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 3. 图片识别 `entry-image-ocr-v1.png`

```text
用途：「巴食」移动端“图片识别”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-image-ocr-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一台简化相机与四个取景框角标组合，相机中央不是眼睛而是浅绿食谱卡轮廓；不要出现 OCR 字母，表达从图片识别菜谱。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 4. 视频识别 `entry-video-asr-v1.png`

```text
用途：「巴食」移动端“视频识别”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-video-asr-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一小段双孔胶片与三段方块音频波形组合，胶片和波形形成一个紧凑整体；不出现播放按钮文字，表达从视频提取语音与画面信息。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 5. 手动创建 `entry-manual-create-v1.png`

```text
用途：「巴食」移动端“手动创建”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-manual-create-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一支短铅笔斜放在空白菜谱卡右下，卡片上只有标题块、食材块和步骤块三个几何占位，不出现文字。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 6. AI 结构化整理 `entry-ai-structure-v1.png`

```text
用途：「巴食」移动端“AI 结构化整理”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-ai-structure-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一张散乱的三枚内容卡片经过两颗绿色像素星点后，排列成一张整齐菜谱纸；用从左到右的清晰关系表达「整理」，不要机器人头像或大脑。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 7. 创建备份 `entry-backup-create-v1.png`

```text
用途：「巴食」移动端“创建备份”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-backup-create-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一张菜谱卡向下进入一个归档盒，箭头只有一段粗像素杆和清晰箭头头部；盒子稳定完整，不画云端。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 8. 恢复备份 `entry-backup-restore-v1.png`

```text
用途：「巴食」移动端“恢复备份”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-backup-restore-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一张菜谱卡从归档盒向上返回，使用与创建备份完全相同的盒子和卡片比例，只改变箭头方向，形成一对图标。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 9. 分享菜谱入口 `entry-share-recipe-v1.png`

```text
用途：「巴食」移动端“分享菜谱入口”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-share-recipe-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一张完整菜谱卡与一个从卡片右上向外的分叉箭头组合，箭头保持粗短，卡片内容用几何块表示；不出现社交平台 Logo。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```

## 10. 识图引擎设置 `entry-vision-engine-v1.png`

```text
用途：「巴食」移动端“识图引擎设置”美术型入口图标；仅用于 48–96px 较大入口，16–24px 操作位继续使用 Flutter 原生图标。
资产文件名：`entry-vision-engine-v1.png`。
参考图与优先级：不要上传、不要参考 `IP.png` 或 `封面图.png`。如附带「巴食」当前 UI 截图或 UI 色板卡，只学习其颜色、像素密度、阶梯缺角、深墨绿描边与右下硬投影；不要复制截图里的文字、状态栏、按钮或页面布局。Rendering priority: 巴食 UI style and strict pixel constraints > subject details。
主要请求：一个简化相机镜头与两颗小型 AI 星点组合，镜头中心是一块浅绿图像方块而不是写实眼球；表达图片理解能力，不画机器人。
渲染风格：strict flat 2D pixel art；true hard-edged square pixels；nearest-neighbor pixel rendering；limited palette；solid color blocks；one hard shadow tone and one optional highlight tone；no smooth transitions between colors。基于 64×64 逻辑像素网格构图（状态/Hero 可用 96×64 逻辑网格），只按整数倍最近邻放大。所有弧线必须由肉眼可见的方形像素台阶组成，禁止亚像素曲线、半透明边缘与平滑抗锯齿。每个表面最多基础色、一个硬阴影色、可选一个硬高光色。使用正面正交图标或平视正交插图，front-facing orthographic，no perspective depth，no environmental lighting。
UI 一致性：匹配「巴食」现有 Flutter/HTML UI 的像素切角语法；适合的位置使用 8→4→3 逻辑像素的阶梯缺角，深墨绿色 2 逻辑像素硬描边，仅在主体右下偏移 2–3 逻辑像素放置单色硬投影。形状由实色块和阶梯几何构成，不做圆润矢量曲线。画面安静、低饱和、温暖、现代，不做复古街机、贴纸或 emoji。
正式色板：纸张 #F3F1E9、次纸张 #EAE7DC、卡片 #FCFBF6、次卡片 #F5F2E9、主墨色 #36403A、次墨色 #5F6A63、弱墨色 #8F978F、主绿 #5F8F6E、深绿 #476B52、墨绿 #33513C、浅绿 #DDE7DC、淡绿 #EDF2EA、琥珀 #B08D4F、低饱和红/腮红 #AF6859、蓝灰 #6E8697、描边线 #DDD8C9、次描边 #CFC9B6。只从这些颜色中选取，单个图标通常控制在 4–7 色。
构图：1024×1024 正方形，只生成一个图标；正面正交，无 3/4 视角，主体占画布约 68%，最多两个紧密相关元素；深墨绿硬轮廓和右下硬投影保持统一，48px 时不依赖微小细节。
背景：完全均匀的纯 #FF00FF chroma-key 背景，无渐变、无纹理、无地面、无反射、无环境阴影；主体内禁止使用洋红色或接近 #FF00FF 的颜色。生成后本地去背，保留主体的右下硬边投影。
反向约束：no 3D, no isometric, no clay render, no glossy plastic, no bevel, no extrusion, no realistic lighting, no volumetric lighting, no ambient occlusion, no soft shadow, no gradient, no airbrush, no painterly shading, no watercolor, no smooth antialiasing, no soft rounded vector illustration, no sticker outline, no emoji, no cinematic depth of field, no photorealism。不得出现水豚、人物、厨师、厨师帽、墨镜、脸、眼睛、嘴、手、脚、四肢、拟人姿态、拟人表情、吉祥物、角色轮廓或任何 IP 特征。不得出现文字、汉字、字母、数字、水印、签名、品牌字样、第三方 Logo、设备框、按钮、页面截图、icon grid、sprite sheet 或多版本拼图。若结果仍显圆润、有体积、像黏土/塑料，或边缘不是清晰方形像素台阶，直接淘汰并重新生成，不要在柔滑插画上叠加伪像素滤镜。
输出要求：只输出一张最终资产，不输出说明文字。生成后以最近邻方式检查 96px、64px、48px。任何缩略尺寸出现糊边、轮廓粘连或功能语义不可辨时，减少细节后重新生成。
```
