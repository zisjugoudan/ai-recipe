import 'llm_cancellation_token.dart';
import 'llm_connection_config.dart';
import 'llm_models.dart';
import 'llm_provider_exception.dart';

abstract class LlmProvider {
  const LlmProvider();
  Future<LlmGenerationResult> generate({
    required LlmConnectionConfig config,
    required String apiKey,
    required LlmGenerationRequest request,
    LlmCancellationToken? cancellationToken,
  });

  /// 推理深度控制能力（《解决方案.md》第四节）。
  ///
  /// 默认实现声明“不支持从客户端控制推理”，具体 Provider 按需覆盖：
  /// - OpenAI-compatible 可通过 `reasoning_effort` 等字段控制；
  /// - Gemini 通过 `generationConfig.thinkingConfig` 控制。
  /// 不支持时上层不发送任何未知字段，也不把开关描述为“真正关闭了思考”。
  LlmReasoningCapability get reasoningCapability => const LlmReasoningCapability(
    supportsReasoningControl: false,
    supportedModes: <LlmReasoningMode>{LlmReasoningMode.fast},
    defaultMode: LlmReasoningMode.fast,
  );

  Future<void> testConnection({
    required LlmConnectionConfig config,
    required String apiKey,
    LlmCancellationToken? cancellationToken,
  }) async {
    final result = await generate(
      config: config,
      apiKey: apiKey,
      request: const LlmGenerationRequest(
        messages: <LlmMessage>[
          LlmMessage(role: LlmMessageRole.user, content: 'Reply with OK only.'),
        ],
        temperature: 0,
      ),
      cancellationToken: cancellationToken,
    );
    if (result.text.trim().isEmpty) {
      throw const LlmProviderException(
        LlmProviderErrorKind.invalidResponse,
        '接口返回了空文本',
      );
    }
  }
}
