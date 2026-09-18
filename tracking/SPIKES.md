# 技术探索清单

| ID | 优先级 | 状态 | 探索主题 | 成功标准 | 输出文件 |
|---|---|---|---|---|---|
| SPK-001 | P0 | BLOCKED | Flutter 关键能力基线验证 | LLM Provider/Android 工程切片通过；分享、后台任务、通知、安全存储真机、OCR 桥接和 iOS 条件未齐，解除条件后继续 | `research/spikes/SPK-001-cross-platform-framework.md` |
| SPK-002 | P0 | TODO | PaddleOCR 本地插件和模型包 | Android Runtime 与安装基础切片已通过；待真实 PP-OCRv5 模型、公开样本和 Android 验收条件齐备后继续真实识别、性能、内存、准确性和 iOS 验证 | `research/spikes/SPK-002-local-ocr.md` |
| SPK-003 | P0 | VERIFY | 自定义 LLM API 多协议兼容性 | OpenAI-compatible Android 首阶段真实连接、结构化生成、SQLite 恢复和脱敏通过；真实取消、Gemini、局域网兼容服务和 iOS 待验证 | `research/spikes/SPK-003-local-llm-api.md` |
| SPK-004 | P0 | TODO | 小红书单链接解析 | 公开样本能够稳定提取正文、图片和来源信息，并确认降级边界 | `research/spikes/SPK-004-xiaohongshu-import.md` |
| SPK-005 | P0 | TODO | 抖音单链接解析 | 公开样本能够稳定提取标题、描述、视频/字幕信息，并确认降级边界 | `research/spikes/SPK-005-douyin-import.md` |
| SPK-006 | P1 | TODO | LLM 结构化输出兼容性 | 比较原生 Schema、JSON mode 和文本 JSON 修复的成功率 | `research/spikes/SPK-006-structured-output.md` |
| SPK-007 | P0 | TODO | WebView 图片顶层导航 + 同源读取可行性 | 图片作为 WebView 顶层文档后，同源 fetch / Canvas 导出能否稳定读取图片字节（Android WebView 具体实现待真机验证）；正文成功时图片失败只产生"配图部分失败" | `research/spikes/SPK-007-top-level-image-nav.md` |
| SPK-008 | P1 | TODO | 中文食材标准化、同义词和单位换算 | 用真实中文库存/菜谱样本量化名称命中、误判、数量可判定率和保守降级边界，形成采用/拒绝/继续研究结论 | `research/spikes/SPK-008-ingredient-normalization.md` |

## 执行规则

1. Spike 开始前复制 `tracking/templates/SPIKE_TEMPLATE.md`。
2. 状态改为 `DOING` 并同步 `tracking/CURRENT.md`。
3. 记录真实环境、样本、命令、结果和失败，不只写结论。
4. 结论必须为“采用”“拒绝”或“继续研究”。
5. 影响长期方案时新增 ADR。
