import Foundation
@testable import LLMKit
import Testing

@Suite("Provider registry + per-provider request shapes")
struct ProviderRegistryTests {
    @Test("missing key throws for key-requiring providers")
    func missingKeyThrows() throws {
        let registry = ProviderRegistry(transport: MockHTTPTransport())
        #expect(throws: LLMError.missingAPIKey(provider: "openRouter")) {
            _ = try registry.makeAdapter(.openRouter, config: ProviderConfig(apiKey: nil, defaultModel: "m"))
        }
    }

    @Test("Ollama is keyless and resolves to its default base URL")
    func ollamaIsKeyless() throws {
        let registry = ProviderRegistry(transport: MockHTTPTransport())
        let adapter = try registry.makeAdapter(.ollama, config: ProviderConfig(defaultModel: "llama3"))
        #expect(adapter is OllamaAdapter)
    }

    @Test("each provider maps to its concrete adapter type")
    func providerMapping() throws {
        let registry = ProviderRegistry(transport: MockHTTPTransport())
        let cfg = ProviderConfig(apiKey: "k", defaultModel: "m")
        #expect(try registry.makeAdapter(.openRouter, config: cfg) is OpenRouterAdapter)
        #expect(try registry.makeAdapter(.openAI, config: cfg) is OpenAIAdapter)
        #expect(try registry.makeAdapter(.anthropic, config: cfg) is AnthropicAdapter)
        #expect(try registry.makeAdapter(.gemini, config: cfg) is GeminiAdapter)
    }

    @Test("Anthropic uses x-api-key + anthropic-version and a top-level system field")
    func anthropicRequestShape() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data(#"{"content":[{"type":"text","text":"hi"}]}"#.utf8))

        let adapter = AnthropicAdapter(apiKey: "ak", defaultModel: "claude", transport: transport)
        _ = try await adapter.complete(CompletionInput(system: "be brief", messages: [.user("hi")], model: "claude"))

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "ak")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(json["system"]?.string == "be brief")
        #expect(json["max_tokens"]?.int == AnthropicAdapter.defaultMaxTokens)
        #expect(json["messages"]?[0]?["role"]?.string == "user")
    }

    @Test("Gemini puts the key in the query and uses contents/parts + systemInstruction")
    func geminiRequestShape() async throws {
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data(#"{"candidates":[{"content":{"parts":[{"text":"hi"}]}}]}"#.utf8))

        let adapter = GeminiAdapter(apiKey: "gk", defaultModel: "gemini-x", transport: transport)
        _ = try await adapter.complete(CompletionInput(system: "sys", messages: [.user("hi")], model: "gemini-x"))

        let request = try #require(await transport.recordedRequests.first)
        let url = try #require(request.url)
        #expect(url.path().contains("/v1beta/models/gemini-x:generateContent"))
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        #expect(comps?.queryItems?.contains(URLQueryItem(name: "key", value: "gk")) == true)

        let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(json["systemInstruction"]?["parts"]?[0]?["text"]?.string == "sys")
        #expect(json["contents"]?[0]?["role"]?.string == "user")
        #expect(json["contents"]?[0]?["parts"]?[0]?["text"]?.string == "hi")
    }

    @Test("Ollama posts to /api/chat with a bare format schema for structured output")
    func ollamaStructuredShape() async throws {
        struct Out: Decodable, Equatable { let ok: Bool }
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data(#"{"message":{"content":"{\"ok\":true}"}}"#.utf8))

        let adapter = OllamaAdapter(defaultModel: "llama3", transport: transport)
        let schema = JSONSchema(name: "out", schema: .object(["type": "object"]))
        let out = try await adapter.completeStructured(
            CompletionInput(messages: [.user("go")], model: "llama3"),
            schema: schema,
            as: Out.self
        )
        #expect(out == Out(ok: true))

        let request = try #require(await transport.recordedRequests.first)
        #expect(request.url?.absoluteString == "http://localhost:11434/api/chat")
        let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        // `format` must be the bare schema, NOT wrapped in response_format/json_schema.
        #expect(json["format"]?["type"]?.string == "object")
        #expect(json["response_format"] == nil)
    }
}
