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
    /// Whether this is a free / `$0`-priced model. Kept available but flagged: free
    /// models often 404 / rate-limit until the account enables a data-policy setting.
    public let isFree: Bool
    /// Whether this model is in the curated "reliable" set — drives the picker's
    /// Recommended group and the default selection. Other adapters leave it `false`.
    public let isRecommended: Bool

    /// Creates model metadata.
    public init(
        id: String,
        displayName: String? = nil,
        contextLength: Int? = nil,
        isFree: Bool = false,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.contextLength = contextLength
        self.isFree = isFree
        self.isRecommended = isRecommended
    }
}
