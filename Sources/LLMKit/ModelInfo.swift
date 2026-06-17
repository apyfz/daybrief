import Foundation

/// A model exposed by a provider, as returned from ``ModelAdapter/availableModels()``.
///
/// Model ids drift constantly, so callers resolve them at runtime from this list
/// rather than hard-coding (design §8). The `id` is the value to put in
/// ``CompletionInput/model``.
public struct ModelInfo: Sendable, Codable, Equatable, Identifiable {
    /// The id to pass as ``CompletionInput/model`` (e.g. `"anthropic/claude-opus-4-8"`).
    public let id: String
    /// A human-friendly name, when the provider supplies one.
    public let displayName: String?
    /// The model's maximum context length in tokens, when known.
    public let contextLength: Int?

    /// Creates model metadata.
    public init(id: String, displayName: String? = nil, contextLength: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.contextLength = contextLength
    }
}
