enum LlmMessageRole { system, user, assistant }

class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final LlmMessageRole role;
  final String content;
}

class LlmGenerationRequest {
  const LlmGenerationRequest({required this.messages, this.temperature});

  final List<LlmMessage> messages;
  final double? temperature;
}

class LlmGenerationResult {
  const LlmGenerationResult({required this.text});

  final String text;
}
