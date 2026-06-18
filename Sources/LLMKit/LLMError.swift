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

public extension LLMError {
    /// A short, secret-free reason string suitable for display.
    ///
    /// Deliberately avoids echoing ``httpStatus``'s `body` (provider error payloads
    /// may carry sensitive detail) and never includes the request body. The HTTP
    /// statuses callers can act on are spelled out:
    ///
    /// - **404** maps to "choose a different model" — OpenRouter returns 404 for model
    ///   ids that appear in `/models` but aren't actually usable on the account, so the
    ///   actionable fix is picking another model rather than re-entering the key.
    /// - **401** maps to "re-enter the AI key" — the credential was rejected.
    var displayReason: String {
        switch self {
        case let .missingAPIKey(provider):
            return "no API key for \(provider)"
        case let .invalidBaseURL(provider):
            return "invalid base URL for \(provider)"
        case .requestEncodingFailed:
            return "the request could not be encoded"
        case let .httpStatus(code, body):
            return Self.httpReason(code: code, body: body)
        case let .malformedResponse(detail):
            return detail
        case let .streamDecodingFailed(detail):
            return "the model stream could not be read (\(detail))"
        case let .structuredOutputUnrepairable(detail):
            return "the model's output could not be parsed (\(detail))"
        case let .refused(detail):
            return "the model refused to answer (\(detail))"
        case .cancelled:
            return "the request was cancelled"
        }
    }
}

extension LLMError {
    /// Turns an HTTP failure into an actionable, secret-free reason.
    ///
    /// OpenRouter's error *body* states the actual fix (enable a data policy, add credits,
    /// pick a schema-capable model), but the body can carry detail we don't want to echo
    /// verbatim. So we pattern-match known phrases and return our own fixed guidance —
    /// the body itself is never surfaced.
    static func httpReason(code: Int, body: String) -> String {
        let lower = body.lowercased()

        if lower.contains("data policy") || lower.contains("data_policy") || lower.contains("no endpoints found matching your data policy") {
            return "This model needs a data-policy setting enabled on your OpenRouter account. Open openrouter.ai/settings/privacy, allow prompt logging, then try again — or pick a different model in Settings."
        }
        if code == 402 || lower.contains("insufficient") || lower.contains("requires more credits") || lower.contains("can only afford") || lower.contains("add more credits") {
            return "Your OpenRouter account doesn't have enough credit for this model. Add credits at openrouter.ai/credits, or choose a cheaper model in Settings."
        }
        if lower.contains("no endpoints found that support") || lower.contains("response_format") || lower.contains("structured output") {
            return "The selected model can't produce the structured output Daybrief needs — choose a different model in Settings."
        }

        switch code {
        case 401:
            return "the AI key was rejected — re-enter it in Settings → AI model"
        case 404:
            return "the selected model isn't available on this provider — choose a different model in Settings"
        case 429:
            return "the model is rate-limited right now (free models share a busy pool) — try again in a moment, or pick a paid model in Settings"
        default:
            return "the model service returned HTTP \(code)"
        }
    }

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
