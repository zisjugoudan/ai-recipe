# 技术探索清单

| ID | 优先级 | 状态 | 探索主题 | 成功标准 | 输出文件 |
|---|---|---|---|---|---|
| SPK-001 | P0 | DOING | Flutter 关键能力基线验证 | LLM Provider/Android 工程切片通过；继续验证数据库、分享、后台任务、通知、安全存储、OCR 桥接和 iOS | `research/spikes/SPK-001-cross-platform-framework.md` |
| SPK-002 | P0 | TODO | PaddleOCR 本地插件和模型包 | Android/iOS 至少各验证一条可行路径；记录体积、速度、内存、中文准确性和授权 | `research/spikes/SPK-002-local-ocr.md` |
| SPK-003 | P0 | TODO | 自定义 LLM API 多协议兼容性 | 验证 OpenAI-compatible、Gemini、本地兼容服务的连接、结构化生成和错误处理 | `research/spikes/SPK-003-local-llm-api.md` |
| SPK-004 | P0 | TODO | 小红书单链接解析 | 公开样本能够稳定提取正文、图片和来源信息，并确认降级边界 | `research/spikes/SPK-004-xiaohongshu-import.md` |
| SPK-005 | P0 | TODO | 抖音单链接解析 | 公开样本能够稳定提取标题、描述、视频/字幕信息，并确认降级边界 | `research/spikes/SPK-005-douyin-import.md` |
| SPK-006 | P1 | TODO | LLM 结构化输出兼容性 | 比较原生 Schema、JSON mode 和文本 JSON 修复的成功率 | `research/spikes/SPK-006-structured-output.md` |

## 执行规则

1. Spike 开始前复制 `tracking/templates/SPIKE_TEMPLATE.md`。
2. 状态改为 `DOING` 并同步 `tracking/CURRENT.md`。
3. 记录真实环境、样本、命令、结果和失败，不只写结论。
4. 结论必须为“采用”“拒绝”或“继续研究”。
5. 影响长期方案时新增 ADR。

