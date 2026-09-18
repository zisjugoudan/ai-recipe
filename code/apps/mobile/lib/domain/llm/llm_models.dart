enum LlmMessageRole { system, user, assistant }

class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final LlmMessageRole role;
  final String content;
}

/// 模型推理深度（《解决方案.md》深度思考开关）。
///
/// - [LlmReasoningMode.fast]：快速模式。优先速度，适合图片文字转录、分组判断等
///   忠实提取类任务，不发送任何推理控制参数。
/// - [LlmReasoningMode.deep]：深度思考。可能提高复杂、模糊内容的分析质量，但会
///   明显增加等待时间与资源消耗；仅在 Provider 支持且用户开启时发送对应参数。
enum LlmReasoningMode { fast, deep }

/// 模型推理深度开关能力（《解决方案.md》第四节）。
///
/// 不同 Provider 的推理控制字段完全不同，因此需要显式声明能力与参数映射，
/// 避免向不支持的服务发送未知字段冒充关闭/开启思考。
class LlmReasoningCapability {
  const LlmReasoningCapability({
    required this.supportsReasoningControl,
    required this.supportedModes,
    required this.defaultMode,
  });

  /// 该 Provider 是否支持从客户端控制推理深度。
  final bool supportsReasoningControl;

  /// 支持的推理模式集合（不含内部保留的 auto）。
  final Set<LlmReasoningMode> supportedModes;

  /// 未显式指定时的默认模式。
  final LlmReasoningMode defaultMode;

  bool supportsMode(LlmReasoningMode mode) => supportedModes.contains(mode);
}

class LlmGenerationRequest {
  const LlmGenerationRequest({
    required this.messages,
    this.temperature,
    this.reasoningMode,
  });

  final List<LlmMessage> messages;
  final double? temperature;

  /// 本次请求期望的推理深度；null 表示交给 Provider 默认策略。
  final LlmReasoningMode? reasoningMode;
}

class LlmGenerationResult {
  const LlmGenerationResult({required this.text});

  final String text;
}
