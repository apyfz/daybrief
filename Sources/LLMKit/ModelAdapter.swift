import Foundation

// Re-exported so callers (and tests that depend only on LLMKit) can use the
// transport seam and JSON value types without importing DaybriefCore directly.
@_exported import DaybriefCore

/// A bring-your-own-model backend.
///
/// One protocol covers the three call shapes Daybrief needs: one-shot synthesis
/// (``complete(_:)``), streaming chat (``streamComplete(_:)``), and structured
/// brief JSON (``completeStructured(_:schema:as:)``). Conformers are independent
/// `Sendable` value types (or actors) — the protocol is intentionally
/// isolation-agnostic so a caller can invoke it from any context under Swift 6.2
/// strict concurrency (design §8 / research "LLM adapter").
public protocol ModelAdapter: Sendable {
    /// Runs a single non-streaming completion and returns the full text.
    func complete(_ input: CompletionInput) async throws -> String

    /// Streams token deltas as they arrive.
    ///
    /// Uses `AsyncThrowingStream` (not `AsyncStream`) so a mid-flight failure —
    /// network drop, provider 5xx, malformed frame — surfaces as a thrown error
    /// rather than a silently truncated stream.
    func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error>

    /// Runs a completion constrained to `schema` and decodes the result as `T`.
    ///
    /// Each adapter uses its provider's native schema enforcement where available,
    /// but the output is **always** run through a provider-agnostic
    /// validate-and-repair step (with one bounded corrective re-ask) before
    /// decoding — passthrough fidelity varies by underlying model.
    func completeStructured<T: Decodable & Sendable>(
        _ input: CompletionInput,
        schema: JSONSchema,
        as type: T.Type
    ) async throws -> T

    /// Lists the models this provider currently exposes.
    ///
    /// Model ids drift, so callers resolve them here at runtime rather than
    /// hard-coding (design §8).
    func availableModels() async throws -> [ModelInfo]
}
