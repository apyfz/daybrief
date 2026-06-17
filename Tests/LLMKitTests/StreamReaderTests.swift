import Foundation
@testable import LLMKit
import Testing

/// A scripted streaming transport that replays a fixed byte payload, split into
/// arbitrary chunks (to exercise frame re-assembly across reads).
private struct ScriptedStreamingTransport: StreamingHTTPTransport {
    let chunks: [Data]

    init(_ text: String, chunkSize: Int = 7) {
        let bytes = Array(text.utf8)
        var out: [Data] = []
        var index = 0
        while index < bytes.count {
            let end = min(index + chunkSize, bytes.count)
            out.append(Data(bytes[index ..< end]))
            index = end
        }
        chunks = out
    }

    func stream(_: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

@Suite("SSE / NDJSON stream readers and adapter streaming")
struct StreamReaderTests {
    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var out: [String] = []
        for try await item in stream {
            out.append(item)
        }
        return out
    }

    @Test("OpenRouter SSE streaming yields concatenated deltas and stops at [DONE]")
    func openRouterStreaming() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hel"}}]}

        data: {"choices":[{"delta":{"content":"lo"}}]}

        : keep-alive comment

        data: {"choices":[{"delta":{"content":"!"}}]}

        data: [DONE]

        data: {"choices":[{"delta":{"content":"IGNORED"}}]}

        """
        let adapter = OpenRouterAdapter(
            apiKey: "k",
            defaultModel: "m",
            transport: MockHTTPTransport(),
            streamingTransport: ScriptedStreamingTransport(sse)
        )
        let deltas = try await collect(adapter.streamComplete(CompletionInput(messages: [.user("hi")], model: "m")))
        #expect(deltas == ["Hel", "lo", "!"])
    }

    @Test("Anthropic SSE streaming reads only content_block_delta text")
    func anthropicStreaming() async throws {
        let sse = """
        event: message_start
        data: {"type":"message_start"}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi "}}

        event: ping
        data: {"type":"ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"there"}}

        event: message_stop
        data: {"type":"message_stop"}

        """
        let adapter = AnthropicAdapter(
            apiKey: "k",
            defaultModel: "m",
            transport: MockHTTPTransport(),
            streamingTransport: ScriptedStreamingTransport(sse)
        )
        let deltas = try await collect(adapter.streamComplete(CompletionInput(messages: [.user("hi")], model: "m")))
        #expect(deltas == ["Hi ", "there"])
    }

    @Test("Ollama NDJSON streaming yields message.content and stops on done")
    func ollamaStreaming() async throws {
        let ndjson = """
        {"message":{"content":"foo"},"done":false}
        {"message":{"content":"bar"},"done":false}
        {"message":{"content":""},"done":true}
        {"message":{"content":"IGNORED"},"done":false}
        """
        let adapter = OllamaAdapter(
            defaultModel: "llama3",
            transport: MockHTTPTransport(),
            streamingTransport: ScriptedStreamingTransport(ndjson)
        )
        let deltas = try await collect(adapter.streamComplete(CompletionInput(messages: [.user("hi")], model: "llama3")))
        // Empty final delta is dropped by the adapter's nil guard on the done frame.
        #expect(deltas == ["foo", "bar"])
    }
}
