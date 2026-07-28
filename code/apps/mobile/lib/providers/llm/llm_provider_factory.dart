import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_type.dart';
import 'gemini_provider.dart';
import 'http_llm_transport.dart';
import 'llm_transport.dart';
import 'openai_compatible_provider.dart';

class LlmProviderFactory {
  const LlmProviderFactory({this.transport = const HttpLlmTransport()});

  final LlmTransport transport;

  LlmProvider create(LlmProviderType type) {
    return switch (type) {
      LlmProviderType.openAiCompatible => OpenAiCompatibleProvider(transport),
      LlmProviderType.gemini => GeminiProvider(transport),
    };
  }
}
