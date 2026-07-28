enum LlmProviderType {
  openAiCompatible(
    'openai_compatible',
    'OpenAI 兼容',
    'https://api.openai.com/v1',
  ),
  gemini(
    'gemini',
    'Gemini 原生',
    'https://generativelanguage.googleapis.com/v1beta',
  );

  const LlmProviderType(this.wireName, this.displayName, this.defaultBaseUrl);

  final String wireName;
  final String displayName;
  final String defaultBaseUrl;

  static LlmProviderType fromWireName(String value) {
    return values.firstWhere(
      (type) => type.wireName == value,
      orElse: () => throw FormatException('不支持的 LLM 协议类型：$value'),
    );
  }
}
