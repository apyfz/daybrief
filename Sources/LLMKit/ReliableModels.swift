import Foundation

/// A small, hand-maintained notion of which OpenRouter models are reliable enough to
/// recommend by default.
///
/// OpenRouter's `/models` lists 300+ entries, most of which aren't actually callable on
/// a given account (free pools, data-policy gating, non-chat modalities, stale slugs).
/// The catalogue can't tell us live usability, so the picker leads with a curated set of
/// widely-available, schema-capable model families and tucks everything else behind a
/// "Show all" toggle.
///
/// Matching is by **family substring** (case-insensitive) so it survives OpenRouter's
/// constant slug versioning — e.g. `anthropic/claude-sonnet-4.5` and a future
/// `anthropic/claude-sonnet-4.5-20260601` both match `claude-sonnet`. Because the
/// recommended set is always intersected against the live catalogue at call time, a
/// family that no longer exists simply drops out (no stale dead entries).
public enum ReliableModels {
    /// Lowercased family substrings of models reliable enough to recommend by default.
    /// Edit this list as the model landscape moves; it needs no other code changes.
    public static let recommendedFamilies: [String] = [
        // Anthropic
        "claude-sonnet", "claude-opus", "claude-3.7-sonnet", "claude-3.5-sonnet",
        // OpenAI
        "gpt-5", "gpt-4.1", "gpt-4o",
        // Google
        "gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash",
        // Meta
        "llama-3.3-70b",
        // DeepSeek (paid, schema-capable)
        "deepseek-chat", "deepseek-v3",
    ]

    /// Whether `id` belongs to a recommended family (case-insensitive substring match).
    public static func isRecommendedFamily(_ id: String) -> Bool {
        let lower = id.lowercased()
        return recommendedFamilies.contains { lower.contains($0) }
    }
}
