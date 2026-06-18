@testable import LLMKit
import Testing

@Suite("LLMError.displayReason — actionable, secret-free reasons")
struct LLMErrorTests {
    @Test("HTTP 404 points the user at choosing a different model")
    func http404SuggestsDifferentModel() {
        let reason = LLMError.httpStatus(code: 404, body: "model not usable").displayReason
        #expect(reason == "the selected model isn't available on this provider — choose a different model in Settings")
        // The (possibly sensitive) body must never leak into the display reason.
        #expect(!reason.contains("model not usable"))
    }

    @Test("HTTP 401 points the user at re-entering the AI key")
    func http401SuggestsReenterKey() {
        let reason = LLMError.httpStatus(code: 401, body: "invalid_api_key").displayReason
        #expect(reason == "the AI key was rejected — re-enter it in Settings → AI model")
        #expect(!reason.contains("invalid_api_key"))
    }

    @Test("Other HTTP statuses keep the generic code message")
    func otherStatusesUnchanged() {
        #expect(LLMError.httpStatus(code: 500, body: "boom").displayReason == "the model service returned HTTP 500")
        #expect(LLMError.httpStatus(code: 429, body: "slow down").displayReason == "the model service returned HTTP 429")
    }

    @Test("Non-HTTP cases keep their existing reasons")
    func nonHTTPCasesUnchanged() {
        #expect(LLMError.missingAPIKey(provider: "openrouter").displayReason == "no API key for openrouter")
        #expect(LLMError.cancelled.displayReason == "the request was cancelled")
        #expect(LLMError.refused("policy").displayReason == "the model refused to answer (policy)")
    }
}
