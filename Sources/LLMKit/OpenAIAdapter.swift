import DaybriefCore
import Foundation

/// OpenAI backend using the Chat Completions API (NOT the Responses API).
///
/// Chat Completions is the cross-provider lingua franca and the lower-risk shared
/// shape for a multi-provider adapter (research §8 verification).
/// - Chat: `POST {baseURL}/chat/completions`, `Authorization: Bearer <key>`.
/// - Structured: `response_format = {type:"json_schema", json_schema:{name, strict, schema}}`;
///   strict mode requires `additionalProperties:false` + every property in `required`.
/// - Streaming: OpenAI SSE (`choices[0].delta.content`, `[DONE]`).
/// - Models: `GET {baseURL}/models`.
public struct OpenAIAdapter: ModelAdapter {
    /// `https://api.openai.com/v1`.
    /// Force-unwrap is safe: a compile-time-constant, well-formed URL literal.
    public static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport

    /// Creates an OpenAI adapter.
    public init(
        apiKey: String,
        baseURL: URL = OpenAIAdapter.defaultBaseURL,
        defaultModel: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        streamingTransport: any StreamingHTTPTransport = URLSessionStreamingTransport()
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.transport = transport
        self.streamingTransport = streamingTransport
    }

    private var headers: [String: String] {
        ["Authorization": "Bearer \(apiKey)"]
    }

    private func modelOrDefault(_ input: CompletionInput) -> String {
        input.model.isEmpty ? defaultModel : input.model
    }

    // MARK: complete

    public func complete(_ input: CompletionInput) async throws -> String {
        let request = try RequestBuilder.jsonPOST(
            url: baseURL.appending(path: "chat/completions"),
            headers: headers,
            body: chatBody(input, stream: false, responseFormat: nil)
        )
        let json = try await sendForJSON(request)
        return try OpenRouterAdapter.extractContent(from: json)
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
                        if let delta = OpenRouterAdapter.streamDelta(from: payload) {
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
        let responseFormat = OpenRouterAdapter.responseFormat(for: schema)
        let request = try RequestBuilder.jsonPOST(
            url: baseURL.appending(path: "chat/completions"),
            headers: headers,
            body: chatBody(input, stream: false, responseFormat: responseFormat)
        )
        let json = try await sendForJSON(request)
        let raw = try OpenRouterAdapter.extractContent(from: json)

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
                let repairRequest = try RequestBuilder.jsonPOST(
                    url: baseURL.appending(path: "chat/completions"),
                    headers: headers,
                    body: chatBody(repairInput, stream: false, responseFormat: responseFormat)
                )
                let repairJSON = try await sendForJSON(repairRequest)
                return try OpenRouterAdapter.extractContent(from: repairJSON)
            }
        )
    }

    // MARK: availableModels

    public func availableModels() async throws -> [ModelInfo] {
        let request = RequestBuilder.get(url: baseURL.appending(path: "models"), headers: headers)
        let json = try await sendForJSON(request)
        guard let data = json["data"]?.array else {
            throw LLMError.malformedResponse("OpenAI /models had no `data` array")
        }
        return data.compactMap { entry in
            guard let id = entry["id"]?.string else { return nil }
            return ModelInfo(id: id, displayName: nil, contextLength: nil)
        }
    }

    // MARK: - Private

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
        if let responseFormat { object["response_format"] = responseFormat }
        return .object(object)
    }

    private func sendForJSON(_ request: URLRequest) async throws -> JSONValue {
        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let transportError as TransportError {
            throw LLMError.from(transportError)
        }
        return try JSONValue.parse(data, context: "OpenAI response")
    }
}
