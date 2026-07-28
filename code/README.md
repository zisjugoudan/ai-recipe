# Code 目录

本目录只存放可运行代码、构建配置和代码级说明。移动端框架已确定为 Flutter；在 `SPK-001` 完成关键能力基线验证后，由 `ARCH-001` 初始化正式可运行工程。

## 计划结构

```text
code/
├── apps/
│   └── mobile/               Flutter iOS/Android 客户端
├── services/
│   └── backend/              鉴权、同步、导入、托管 AI 网关
├── packages/
│   ├── shared/               Schema、领域模型、错误码和共享工具
│   └── providers/            LLM、OCR、ASR、链接解析适配器
└── tools/                    开发、迁移、样本和质量分析工具
```

## 代码实施规则

- 不因框架已确定而跳过 `SPK-001` 的真机能力验证。
- 所有任务必须关联 `tracking/BACKLOG.md` 中的 ID。
- 产品行为必须关联用户故事和验收标准。
- Provider 接口先写契约和测试，再写供应商实现。
- 密钥、Token、用户真实数据和受限内容不得提交。
- 构建产物、模型大文件和本地数据库不得进入版本控制。
- 每个可运行模块需要自己的 README，包含启动、测试和环境变量说明。
