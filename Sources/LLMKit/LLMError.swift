import DaybriefCore
import Foundation

/// The one typed error for everything in `LLMKit`.
public enum LLMError: Error, Sendable, Equatable {
    /// A provider that requires an API key was configured without one.
    case missingAPIKey(provider: String)
    /// The configured base URL was missing or malformed for this provider.
    case invalidBaseURL(provider: String)
    /// The request body could not be encoded to JSON.
    case requestEncodingFailed(String)
    /// The provider returned a non-2xx HTTP status.
    ///
    /// `body` is a (possibly truncated) diagnostic string; it may contain
    /// provider error detail and must never be logged `.public`.
    case httpStatus(code: Int, body: String)
    /// The response was structurally not what this provider's wire format requires
    /// (e.g. missing `choices`, no tool-use block, empty `candidates`).
    case malformedResponse(String)
    /// A streaming frame could not be parsed.
    case streamDecodingFailed(String)
    /// Structured output could not be decoded even after the repair + re-ask pass.
    case structuredOutputUnrepairable(detail: String)
    /// The provider refused to answer (e.g. Anthropic `stop_reason == "refusal"`).
    case refused(String)
    /// The operation was cancelled.
    case cancelled
}

extension LLMError {
    /// Maps a ``TransportError`` from the injected transport into the matching ``LLMError``.
    static func from(_ transportError: TransportError) -> LLMError {
        switch transportError {
        case .nonHTTPResponse:
            return .malformedResponse("Response was not an HTTP response")
        case let .unacceptableStatus(code, body):
            return .httpStatus(code: code, body: String(decoding: body.prefix(2048), as: UTF8.self))
        }
    }
}
