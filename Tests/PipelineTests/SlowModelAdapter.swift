import DaybriefCore
import Foundation
import LLMKit
import Testing

/// A ``ModelAdapter`` that deliberately stalls its structured call past any
/// reasonable budget — used to verify the synthesizer's timeout race.
///
/// `completeStructured` sleeps for `delay` (honoring cooperative cancellation, so
/// the timeout sleeper winning the race tears this down) and only then would
/// return; in practice the synthesizer's much smaller injected budget always wins.
/// The other call shapes are unused by the synthesizer and assert if hit.
struct SlowModelAdapter: ModelAdapter {
    /// How long the structured call sleeps before it would return.
    let delay: Duration

    init(delay: Duration = .seconds(60)) {
        self.delay = delay
    }

    func complete(_: CompletionInput) async throws -> String {
        Issue.record("SlowModelAdapter.complete should not be called by the synthesizer")
        return ""
    }

    func streamComplete(_: CompletionInput) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func completeStructured<T: Decodable & Sendable>(
        _: CompletionInput,
        schema _: JSONSchema,
        as _: T.Type
    ) async throws -> T {
        try await ContinuousClock().sleep(for: delay)
        throw LLMError.malformedResponse("SlowModelAdapter never produces output")
    }

    func availableModels() async throws -> [ModelInfo] {
        []
    }
}
