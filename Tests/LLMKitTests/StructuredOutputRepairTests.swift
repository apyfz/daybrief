import Foundation
@testable import LLMKit
import Testing

/// The brief-shaped payload the repair layer decodes in these tests.
private struct Brief: Decodable, Equatable {
    let title: String
    let priorities: [String]
}

@Suite("Structured-output validate-and-repair")
struct StructuredOutputRepairTests {
    private let schema = JSONSchema(
        name: "brief",
        schema: .object([
            "type": "object",
            "additionalProperties": false,
            "required": .array(["title", "priorities"]),
            "properties": .object([
                "title": .object(["type": "string"]),
                "priorities": .object(["type": "array", "items": .object(["type": "string"])]),
            ]),
        ])
    )

    private let input = CompletionInput(
        system: "You are a brief generator.",
        messages: [.user("Make my brief.")],
        model: "stub/model"
    )

    @Test("decodes clean JSON on the first attempt (no re-ask)")
    func decodesCleanJSON() async throws {
        let clean = #"{"title":"Today","priorities":["ship LLMKit"]}"#
        let stub = StubModelAdapter(structuredResponses: [clean])

        let brief = try await stub.completeStructured(input, schema: schema, as: Brief.self)

        #expect(brief == Brief(title: "Today", priorities: ["ship LLMKit"]))
        // Only one structured response should have been consumed (no re-ask).
        let count = await stub.receivedInputs.count
        #expect(count == 1)
    }

    @Test("repairs markdown-fenced JSON with leading prose without re-asking")
    func repairsFencedJSON() async throws {
        let fenced = """
        Sure! Here is your brief:

        ```json
        {"title":"Today","priorities":["ship LLMKit","review PRs"]}
        ```

        Let me know if you want changes.
        """
        let stub = StubModelAdapter(structuredResponses: [fenced])

        let brief = try await stub.completeStructured(input, schema: schema, as: Brief.self)

        #expect(brief == Brief(title: "Today", priorities: ["ship LLMKit", "review PRs"]))
    }

    @Test("falls back to a single corrective re-ask when the first output is unparseable")
    func reAsksOnUnparseableOutput() async throws {
        // First output is pure prose (no JSON span); the re-ask returns valid JSON.
        let prose = "I'm sorry, I cannot produce that."
        let corrected = #"{"title":"Recovered","priorities":["a"]}"#
        let stub = StubModelAdapter(structuredResponses: [prose, corrected])

        let brief = try await stub.completeStructured(input, schema: schema, as: Brief.self)

        #expect(brief == Brief(title: "Recovered", priorities: ["a"]))
    }

    @Test("throws .structuredOutputUnrepairable after the bounded re-ask still fails")
    func throwsWhenUnrepairable() async throws {
        let stub = StubModelAdapter(structuredResponses: ["not json", "still not json"])

        await #expect(throws: LLMError.self) {
            _ = try await stub.completeStructured(input, schema: schema, as: Brief.self)
        }
    }

    @Test("when the corrective re-ask itself throws, the original parse error is preserved")
    func reAskThrowsPreservesOriginalParseError() async throws {
        // Only one structured response is scripted: the first (unparseable) output is
        // consumed, then the corrective re-ask has nothing to return and throws — standing
        // in for a provider 5xx / hang on the retry. The give-up error must still carry the
        // ORIGINAL parse diagnostic, not just the re-ask transport failure.
        let stub = StubModelAdapter(structuredResponses: ["not json"])

        let error = try #require(
            await #expect(throws: LLMError.self) {
                _ = try await stub.completeStructured(input, schema: schema, as: Brief.self)
            }
        )
        let detail: String
        switch error {
        case let .structuredOutputUnrepairable(d): detail = d
        default:
            Issue.record("expected .structuredOutputUnrepairable, got \(String(describing: error))")
            return
        }
        // Original parse diagnostic is preserved.
        #expect(detail.contains("Initial output was not decodable JSON"))
        // ...and the re-ask failure is folded in (not the value the give-up path returns instead).
        #expect(detail.contains("corrective re-ask failed"))
    }

    @Test("extracts a balanced object even with trailing garbage")
    func extractsBalancedSpan() throws {
        let messy = #"prefix {"title":"X","priorities":[]} trailing {bad"#
        let extracted = try #require(JSONExtractor.extract(from: messy))
        let brief = try JSONDecoder().decode(Brief.self, from: Data(extracted.utf8))
        #expect(brief == Brief(title: "X", priorities: []))
    }

    @Test("returns nil when no JSON span is present")
    func extractorReturnsNilForProse() {
        #expect(JSONExtractor.extract(from: "completely free-form text") == nil)
    }
}
