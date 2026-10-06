abstract interface class TokenCounter {
  Future<int> countTokens(String text);
}

abstract interface class ModelContextProbe {
  Future<int> contextWindowSize();

  /// May be zero when countPromptTokens includes the full instruction framing.
  Future<int> countInstructionTokens(String instructions);

  Future<int> countPromptTokens(String prompt);
}
