import DaybriefCore
import Foundation

/// A scripted ``ModelAdapter`` for tests — no network.
///
/// Returns canned text for ``complete(_:)`` / ``streamComplete(_:)`` and drives the
/// real ``StructuredOutputRepair`` layer for ``completeStructured(_:schema:as:)``:
/// the first scripted structured response is the model's "raw" output, and the
/// second (if present) is the corrective re-ask result. This lets tests exercise
/// the validate-and-repair ladder (malformed → extracted → re-asked) deterministically.
public actor StubModelAdapter: ModelAdapter {
    private var completions: [String]
    private var structuredResponses: [String]
    /// `nonisolated` so the `nonisolated` streaming method can read it without
    /// crossing the actor boundary; it never changes after init.
    private nonisolated let streamDeltas: [String]
    private let models: [ModelInfo]
    /// A simple Sendable flag describing whether calls should fail.
    private nonisolated let failure: StubFailure?

    /// Records of inputs the stub was asked to complete, in order.
    public private(set) var receivedInputs: [CompletionInput] = []

    /// A scriptable error for the stub to throw (kept Sendable for actor safety).
    public enum StubFailure: Error, Sendable, Equatable {
        case llm(LLMError)
    }

    /// Creates a stub adapter.
    ///
    /// - Parameters:
    ///   - completions: Texts returned FIFO from ``complete(_:)``.
    ///   - structuredResponses: Raw texts fed FIFO into the repair layer from
    ///     ``completeStructured(_:schema:as:)`` — element 0 is the initial output,
    ///     element 1 (if any) is the corrective re-ask result.
    ///   - streamDeltas: Chunks yielded from ``streamComplete(_:)``.
    ///   - models: Returned from ``availableModels()``.
    ///   - failure: If set, every call throws this instead.
    public init(
        completions: [String] = [],
        structuredResponses: [String] = [],
        streamDeltas: [String] = [],
        models: [ModelInfo] = [],
        failure: StubFailure? = nil
    ) {
        self.completions = completions
        self.structuredResponses = structuredResponses
        self.streamDeltas = streamDeltas
        self.models = models
        self.failure = failure
    }

    public func complete(_ input: CompletionInput) async throws -> String {
        receivedInputs.append(input)
        if let failure { throw failure }
        guard !completions.isEmpty else {
            throw LLMError.malformedResponse("StubModelAdapter has no scripted completions")
        }
        return completions.removeFirst()
    }

    public nonisolated func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error> {
        let deltas = streamDeltas
        let failure = self.failure
        return AsyncThrowingStream { continuation in
            let task = Task {
                await self.record(input)
                if let failure {
                    continuation.finish(throwing: failure)
                    return
                }
                for delta in deltas {
                    continuation.yield(delta)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func completeStructured<T: Decodable & Sendable>(
        _ input: CompletionInput,
        schema: JSONSchema,
        as type: T.Type
    ) async throws -> T {
        receivedInputs.append(input)
        if let failure { throw failure }
        guard !structuredResponses.isEmpty else {
            throw LLMError.malformedResponse("StubModelAdapter has no scripted structured responses")
        }
        let raw = structuredResponses.removeFirst()
        return try await StructuredOutputRepair.decode(
            raw,
            as: type,
            input: input,
            schema: schema,
            reAsk: { _ in try await self.nextStructuredResponse() }
        )
    }

    public func availableModels() async throws -> [ModelInfo] {
        if let failure { throw failure }
        return models
    }

    /// Pops the next scripted structured response (used for the corrective re-ask).
    private func nextStructuredResponse() throws -> String {
        guard !structuredResponses.isEmpty else {
            throw LLMError.structuredOutputUnrepairable(detail: "no scripted re-ask response")
        }
        return structuredResponses.removeFirst()
    }

    private func record(_ input: CompletionInput) {
        receivedInputs.append(input)
    }
}
