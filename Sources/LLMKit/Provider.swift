import Foundation

/// The bring-your-own-model providers Daybrief ships adapters for.
///
/// OpenRouter is the recommended default on-ramp (one key, any model). Ollama is
/// local (no key). See design §8.
public enum Provider: String, Sendable, Codable, Equatable, CaseIterable, Identifiable {
    /// OpenRouter — the default; OpenAI-compatible gateway over many models.
    case openRouter
    /// OpenAI directly (Chat Completions, not the Responses API).
    case openAI
    /// Anthropic (Messages API).
    case anthropic
    /// Google Gemini (`generateContent`).
    case gemini
    /// Local Ollama daemon.
    case ollama

    public var id: String {
        rawValue
    }

    /// `true` if this provider requires an API key (everything except local Ollama).
    public var requiresAPIKey: Bool {
        self != .ollama
    }
}

/// User configuration for one ``Provider``.
///
/// The key is loaded from the Keychain by the app and passed in here; LLMKit never
/// persists it. `baseURL` overrides the provider default (e.g. a self-hosted
/// OpenAI-compatible gateway, or a non-default Ollama host).
public struct ProviderConfig: Sendable, Equatable {
    /// The API key, or `nil` for keyless providers (Ollama).
    public let apiKey: String?
    /// An override for the provider's base URL, or `nil` to use the default.
    public let baseURL: URL?
    /// The model id to default to when a ``CompletionInput`` doesn't override it.
    ///
    /// Resolve real ids at runtime via ``ModelAdapter/availableModels()``.
    public let defaultModel: String

    /// Creates a provider configuration.
    public init(apiKey: String? = nil, baseURL: URL? = nil, defaultModel: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
    }
}
