import DaybriefCore
import Foundation

/// The default backend: OpenRouter's OpenAI-compatible Chat Completions API.
///
/// - Chat: `POST {baseURL}/chat/completions`, `Authorization: Bearer <key>`,
///   optional `HTTP-Referer` / `X-Title` attribution.
/// - Structured: `response_format = {type:"json_schema", json_schema:{name, strict, schema}}`
///   plus `provider.require_parameters = true` so routing only picks models that
///   honor the schema. Output still passes through the universal repair layer
///   because enforcement fidelity varies by underlying model.
/// - Streaming: OpenAI-style SSE (`choices[0].delta.content`, `[DONE]` sentinel).
/// - Models: `GET {baseURL}/models`.
public struct OpenRouterAdapter: ModelAdapter {
    /// `https://openrouter.ai/api/v1`.
    /// Force-unwrap is safe: a compile-time-constant, well-formed URL literal.
    public static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let attribution: OpenRouterAttribution?
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport

    /// Creates an OpenRouter adapter.
    public init(
        apiKey: String,
        baseURL: URL = OpenRouterAdapter.defaultBaseURL,
        defaultModel: String,
        attribution: OpenRouterAttribution? = nil,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        streamingTransport: any StreamingHTTPTransport = URLSessionStreamingTransport()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.attribution = attribution
        self.transport = transport
        self.streamingTransport = streamingTransport
    }

    private var headers: [String: String] {
        var h = ["Authorization": "Bearer \(apiKey)"]
        if let attribution {
            h["HTTP-Referer"] = attribution.referer
            h["X-Title"] = attribution.title
        }
        return h
    }

    private func modelOrDefault(_ input: CompletionInput) -> String {
        input.model.isEmpty ? defaultModel : input.model
    }

    // MARK: complete

    public func complete(_ input: CompletionInput) async throws -> String {
        let body = chatBody(input, stream: false, responseFormat: nil)
        let request = try RequestBuilder.jsonPOST(
            url: baseURL.appending(path: "chat/completions"),
            headers: headers,
            body: body
        )
        let json = try await sendForJSON(request)
        return try Self.extractContent(from: json)
    }

    // MARK: streamComplete

    public func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error> {
        let body = chatBody(input, stream: true, responseFormat: nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try RequestBuilder.jsonPOST(
                        url: baseURL.appending(path: "chat/completions"),
                        headers: headers,
                        body: body
                    )
                    let bytes = try await streamingTransport.stream(request)
                    for try await payload in SSEReader.frames(from: bytes) {
                        if let delta = Self.streamDelta(from: payload) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: completeStructured

    public func completeStructured<T: Decodable & Sendable>(
        _ input: CompletionInput,
        schema: JSONSchema,
        as type: T.Type
    ) async throws -> T {
        let responseFormat = Self.responseFormat(for: schema)
        let body = chatBody(input, stream: false, responseFormat: responseFormat)
        let request = try RequestBuilder.jsonPOST(
            url: baseURL.appending(path: "chat/completions"),
            headers: headers,
            body: body
        )
        let json = try await sendForJSON(request)
        let raw = try Self.extractContent(from: json)

        return try await StructuredOutputRepair.decode(
            raw,
            as: type,
            input: input,
            schema: schema,
            reAsk: { [self] correctivePrompt in
                let repairInput = CompletionInput(
                    system: input.system,
                    messages: input.messages + [.user(correctivePrompt)],
                    model: input.model,
                    temperature: input.temperature,
                    maxTokens: input.maxTokens
                )
                let repairBody = chatBody(repairInput, stream: false, responseFormat: responseFormat)
                let repairRequest = try RequestBuilder.jsonPOST(
                    url: baseURL.appending(path: "chat/completions"),
                    headers: headers,
                    body: repairBody
                )
                let repairJSON = try await sendForJSON(repairRequest)
                return try Self.extractContent(from: repairJSON)
            }
        )
    }

    // MARK: availableModels

    public func availableModels() async throws -> [ModelInfo] {
        let request = RequestBuilder.get(url: baseURL.appending(path: "models"), headers: headers)
        let json = try await sendForJSON(request)
        guard let data = json["data"]?.array else {
            throw LLMError.malformedResponse("OpenRouter /models had no `data` array")
        }
        return data.compactMap { entry in
            guard let id = entry["id"]?.string else { return nil }
            return ModelInfo(
                id: id,
                displayName: entry["name"]?.string,
                contextLength: entry["context_length"]?.int
            )
        }
    }

    // MARK: - Body construction

    private func chatBody(
        _ input: CompletionInput,
        stream: Bool,
        responseFormat: JSONValue?
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(modelOrDefault(input)),
            "messages": RequestBuilder.openAIMessages(system: input.system, messages: input.messages),
            "stream": .bool(stream),
        ]
        if let temperature = input.temperature { object["temperature"] = .number(temperature) }
        if let maxTokens = input.maxTokens { object["max_tokens"] = .number(Double(maxTokens)) }
        if let responseFormat {
            object["response_format"] = responseFormat
            // Route only to models that honor the schema (research §8).
            object["provider"] = .object(["require_parameters": .bool(true)])
        }
        return .object(object)
    }

    static func responseFormat(for schema: JSONSchema) -> JSONValue {
        .object([
            "type": "json_schema",
            "json_schema": .object([
                "name": .string(schema.name),
                "strict": .bool(schema.strict),
                "schema": schema.schema,
            ]),
        ])
    }

    // MARK: - Response parsing

    private func sendForJSON(_ request: URLRequest) async throws -> JSONValue {
        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let transportError as TransportError {
            throw LLMError.from(transportError)
        }
        return try JSONValue.parse(data, context: "OpenRouter response")
    }

    /// Extracts `choices[0].message.content` from a chat-completion response.
    static func extractContent(from json: JSONValue) throws -> String {
        guard let content = json["choices"]?[0]?["message"]?["content"]?.string else {
            throw LLMError.malformedResponse("OpenRouter response had no choices[0].message.content")
        }
        return content
    }

    /// Extracts `choices[0].delta.content` from a streaming chunk payload.
    static func streamDelta(from payload: String) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) else {
            return nil
        }
        return json["choices"]?[0]?["delta"]?["content"]?.string
    }
}
