import Foundation
@testable import LLMKit
import Testing

private struct Brief: Decodable, Equatable {
    let title: String
    let priorities: [String]
}

@Suite("OpenRouter adapter over a mock transport")
struct OpenRouterAdapterTests {
    private let schema = JSONSchema(
        name: "daily_brief",
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

    /// Wraps the assistant `content` string in an OpenAI/OpenRouter chat-completion envelope.
    private func chatCompletion(content: String) -> Data {
        let escaped = String(decoding: try! JSONEncoder().encode(content), as: UTF8.self)
        let body = #"{"id":"gen-1","choices":[{"index":0,"message":{"role":"assistant","content":\#(escaped)}}]}"#
        return Data(body.utf8)
    }

    @Test("completeStructured happy path decodes the schema-shaped content")
    func completeStructuredHappyPath() async throws {
        let transport = MockHTTPTransport()
        let payload = #"{"title":"Wednesday","priorities":["finish LLMKit","prep standup"]}"#
        await transport.enqueue(data: chatCompletion(content: payload))

        let adapter = OpenRouterAdapter(
            apiKey: "sk-or-test",
            defaultModel: "openrouter/auto",
            transport: transport
        )
        let input = CompletionInput(
            system: "You generate briefs.",
            messages: [.user("Brief me.")],
            model: "anthropic/claude-opus-4-8"
        )

        let brief = try await adapter.completeStructured(input, schema: schema, as: Brief.self)
        #expect(brief == Brief(title: "Wednesday", priorities: ["finish LLMKit", "prep standup"]))

        // Verify the request was correctly shaped: URL, auth, and response_format.
        let requests = await transport.recordedRequests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")

        let sentBody = try #require(request.httpBody)
        let json = try JSONDecoder().decode(JSONValue.self, from: sentBody)
        #expect(json["model"]?.string == "anthropic/claude-opus-4-8")
        #expect(json["response_format"]?["type"]?.string == "json_schema")
        #expect(json["response_format"]?["json_schema"]?["name"]?.string == "daily_brief")
        #expect(json["response_format"]?["json_schema"]?["strict"]?.bool == true)
        #expect(json["provider"]?["require_parameters"]?.bool == true)
        // System prompt is mapped to a leading system message.
        #expect(json["messages"]?[0]?["role"]?.string == "system")
        #expect(json["messages"]?[1]?["role"]?.string == "user")
    }

    @Test("completeStructured repairs fenced content from the model, still one HTTP call")
    func completeStructuredRepairsFenced() async throws {
        let transport = MockHTTPTransport()
        let fenced = "```json\n{\"title\":\"T\",\"priorities\":[]}\n```"
        await transport.enqueue(data: chatCompletion(content: fenced))

        let adapter = OpenRouterAdapter(apiKey: "k", defaultModel: "m", transport: transport)
        let input = CompletionInput(messages: [.user("go")], model: "m")

        let brief = try await adapter.completeStructured(input, schema: schema, as: Brief.self)
        #expect(brief == Brief(title: "T", priorities: []))
        let count = await transport.recordedRequests.count
        #expect(count == 1) // extraction succeeded; no corrective re-ask round-trip.
    }

    @Test("complete returns the assistant content")
    func completeReturnsContent() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: chatCompletion(content: "hello there"))

        let adapter = OpenRouterAdapter(apiKey: "k", defaultModel: "m", transport: transport)
        let result = try await adapter.complete(CompletionInput(messages: [.user("hi")], model: "m"))
        #expect(result == "hello there")
    }

    @Test("availableModels parses the /models data array")
    func availableModelsParses() async throws {
        let transport = MockHTTPTransport()
        let body = #"""
        {"data":[
          {"id":"anthropic/claude-opus-4-8","name":"Claude Opus 4.8","context_length":200000},
          {"id":"openai/gpt-5","name":"GPT-5"}
        ]}
        """#
        await transport.enqueue(data: Data(body.utf8))

        let adapter = OpenRouterAdapter(apiKey: "k", defaultModel: "m", transport: transport)
        let models = try await adapter.availableModels()

        #expect(models.count == 2)
        #expect(models[0] == ModelInfo(id: "anthropic/claude-opus-4-8", displayName: "Claude Opus 4.8", contextLength: 200_000))
        #expect(models[1] == ModelInfo(id: "openai/gpt-5", displayName: "GPT-5", contextLength: nil))

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/models")
        #expect(request.httpMethod == "GET")
    }

    @Test("attribution headers are attached when provided")
    func attributionHeaders() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: chatCompletion(content: "ok"))

        let adapter = OpenRouterAdapter(
            apiKey: "k",
            defaultModel: "m",
            attribution: OpenRouterAttribution(referer: "https://github.com/example/daybrief", title: "Daybrief"),
            transport: transport
        )
        _ = try await adapter.complete(CompletionInput(messages: [.user("hi")], model: "m"))

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://github.com/example/daybrief")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Daybrief")
    }

    @Test("a non-2xx transport error maps to LLMError.httpStatus")
    func mapsTransportError() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueueFailure(TransportError.unacceptableStatus(code: 401, body: Data("unauthorized".utf8)))

        let adapter = OpenRouterAdapter(apiKey: "bad", defaultModel: "m", transport: transport)
        await #expect(throws: LLMError.httpStatus(code: 401, body: "unauthorized")) {
            _ = try await adapter.complete(CompletionInput(messages: [.user("hi")], model: "m"))
        }
    }
}
