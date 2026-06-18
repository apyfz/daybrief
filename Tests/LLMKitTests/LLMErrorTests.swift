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
        #expect(LLMError.httpStatus(code: 503, body: "down").displayReason == "the model service returned HTTP 503")
    }

    @Test("A data-policy failure points at the OpenRouter privacy settings")
    func dataPolicyGuidance() {
        let reason = LLMError.httpStatus(code: 404, body: "No endpoints found matching your data policy").displayReason
        #expect(reason.contains("openrouter.ai/settings/privacy"))
        // Curated guidance, never the raw body.
        #expect(!reason.contains("No endpoints found"))
    }

    @Test("A credits failure points at adding credits")
    func creditsGuidance() {
        #expect(LLMError.httpStatus(code: 402, body: "Insufficient credits").displayReason.contains("openrouter.ai/credits"))
        #expect(LLMError.httpStatus(code: 403, body: "This request requires more credits").displayReason.contains("openrouter.ai/credits"))
    }

    @Test("A schema-incapable model is called out as such")
    func schemaGuidance() {
        let reason = LLMError.httpStatus(code: 404, body: "No endpoints found that support response_format").displayReason
        #expect(reason.contains("structured output"))
    }

    @Test("Rate-limited free pools get a try-again / go-paid hint")
    func rateLimitGuidance() {
        let reason = LLMError.httpStatus(code: 429, body: "rate limited").displayReason
        #expect(reason.contains("rate-limited"))
    }

    @Test("Non-HTTP cases keep their existing reasons")
    func nonHTTPCasesUnchanged() {
        #expect(LLMError.missingAPIKey(provider: "openrouter").displayReason == "no API key for openrouter")
        #expect(LLMError.cancelled.displayReason == "the request was cancelled")
        #expect(LLMError.refused("policy").displayReason == "the model refused to answer (policy)")
    }
}
