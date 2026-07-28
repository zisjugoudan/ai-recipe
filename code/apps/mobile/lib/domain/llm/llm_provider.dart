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
