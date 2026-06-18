import Foundation

/// The provider-neutral request passed to every ``ModelAdapter`` call.
///
/// `system` is kept separate from `messages` because providers disagree on where
/// the system prompt lives (Anthropic and Gemini have a dedicated field; OpenAI-style
/// APIs use a leading `system` message). Adapters place it correctly per provider.
public struct CompletionInput: Sendable, Codable, Equatable {
    /// The system prompt (may be empty).
    public let system: String
    /// The conversation turns, in order. Should generally not contain a leading
    /// `.system` message — use ``system`` for that.
    public let messages: [ChatMessage]
    /// The provider-specific model id (resolve at runtime via ``ModelAdapter/availableModels()``).
    public let model: String
    /// Sampling temperature, or `nil` to use the provider default.
    public let temperature: Double?
    /// Maximum tokens to generate, or `nil` to use the provider default.
    ///
    /// Required by some providers (e.g. Anthropic's `max_tokens`); adapters that
    /// require it substitute a sensible default when this is `nil`.
    public let maxTokens: Int?

    /// Creates a completion input.
    public init(
        system: String = "",
        messages: [ChatMessage],
        model: String,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.system = system
        self.messages = messages
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}
