import DaybriefCore
import Foundation

/// Anthropic backend using the Messages API.
///
/// - Chat: `POST {baseURL}/v1/messages`, headers `x-api-key: <key>` +
///   `anthropic-version: 2023-06-01` (NOT `Authorization: Bearer`). `system` is a
///   top-level field, `max_tokens` is required.
/// - Structured: forced tool-use — a single tool whose `input_schema` is the
///   requested schema, `tool_choice = {type:"tool", name:"emit_brief"}`; the
///   structured value is read from the `tool_use` block's `input`. This path works
///   across model generations (native `output_config` is GA only on recent models).
/// - Streaming: Anthropic SSE with `event:` types; text deltas live in
///   `content_block_delta` events under `delta.text`.
/// - Models: `GET {baseURL}/v1/models`.
public struct AnthropicAdapter: ModelAdapter {
    /// `https://api.anthropic.com`.
    /// Force-unwrap is safe: a compile-time-constant, well-formed URL literal.
    public static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    /// The pinned API version header value.
    public static let apiVersion = "2023-06-01"
    /// Default `max_tokens` when the input doesn't specify one (Anthropic requires it).
    public static let defaultMaxTokens = 4096
    private static let toolName = "emit_structured_output"

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport

    /// Creates an Anthropic adapter.
    public init(
        apiKey: String,
        baseURL: URL = AnthropicAdapter.defaultBaseURL,
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
        ["x-api-key": apiKey, "anthropic-version": Self.apiVersion]
    }

    private func modelOrDefault(_ input: CompletionInput) -> String {
        input.model.isEmpty ? defaultModel : input.model
    }

    private func messagesURL() -> URL {
        baseURL.appending(path: "v1/messages")
    }

    // MARK: complete

    public func complete(_ input: CompletionInput) async throws -> String {
        let request = try RequestBuilder.jsonPOST(
            url: messagesURL(),
            headers: headers,
            body: messagesBody(input, stream: false, tool: nil)
        )
        let json = try await sendForJSON(request)
        try Self.checkRefusal(json)
        return try Self.extractText(from: json)
    }

    // MARK: streamComplete

    public func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error> {
        let body = messagesBody(input, stream: true, tool: nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try RequestBuilder.jsonPOST(
                        url: messagesURL(),
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
        let tool = Self.toolDefinition(for: schema)
        let request = try RequestBuilder.jsonPOST(
            url: messagesURL(),
            headers: headers,
            body: messagesBody(input, stream: false, tool: tool)
        )
        let json = try await sendForJSON(request)
        try Self.checkRefusal(json)
        let raw = try Self.extractToolInput(from: json)

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
                    url: messagesURL(),
                    headers: headers,
                    body: messagesBody(repairInput, stream: false, tool: tool)
                )
                let repairJSON = try await sendForJSON(repairRequest)
                try Self.checkRefusal(repairJSON)
                return try Self.extractToolInput(from: repairJSON)
            }
        )
    }

    // MARK: availableModels

    public func availableModels() async throws -> [ModelInfo] {
        let request = RequestBuilder.get(url: baseURL.appending(path: "v1/models"), headers: headers)
        let json = try await sendForJSON(request)
        guard let data = json["data"]?.array else {
            throw LLMError.malformedResponse("Anthropic /v1/models had no `data` array")
        }
        return data.compactMap { entry in
            guard let id = entry["id"]?.string else { return nil }
            return ModelInfo(id: id, displayName: entry["display_name"]?.string, contextLength: nil)
        }
    }

    // MARK: - Body construction

    private func messagesBody(
        _ input: CompletionInput,
        stream: Bool,
        tool: JSONValue?
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(modelOrDefault(input)),
            "max_tokens": .number(Double(input.maxTokens ?? Self.defaultMaxTokens)),
            "messages": Self.anthropicMessages(input.messages),
            "stream": .bool(stream),
        ]
        if !input.system.isEmpty { object["system"] = .string(input.system) }
        if let temperature = input.temperature { object["temperature"] = .number(temperature) }
        if let tool {
            object["tools"] = .array([tool])
            object["tool_choice"] = .object(["type": "tool", "name": .string(Self.toolName)])
        }
        return .object(object)
    }

    /// Maps canonical messages to Anthropic's `[{role, content}]` (system is top-level).
    static func anthropicMessages(_ messages: [ChatMessage]) -> JSONValue {
        let mapped: [JSONValue] = messages.compactMap { message in
            // Anthropic only accepts `user`/`assistant` in `messages`.
            let role: String
            switch message.role {
            case .assistant: role = "assistant"
            case .user, .system: role = "user"
            }
            return .object(["role": .string(role), "content": .string(message.content)])
        }
        return .array(mapped)
    }

    static func toolDefinition(for schema: JSONSchema) -> JSONValue {
        .object([
            "name": .string(toolName),
            "description": "Emit the requested structured output conforming to the schema.",
            "input_schema": schema.schema,
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
        return try JSONValue.parse(data, context: "Anthropic response")
    }

    /// Throws ``LLMError/refused(_:)`` when the model refused.
    static func checkRefusal(_ json: JSONValue) throws {
        if json["stop_reason"]?.string == "refusal" {
            throw LLMError.refused("Anthropic returned stop_reason=refusal")
        }
    }

    /// Concatenates `content[].text` blocks of `type:"text"`.
    static func extractText(from json: JSONValue) throws -> String {
        guard let blocks = json["content"]?.array else {
            throw LLMError.malformedResponse("Anthropic response had no `content` array")
        }
        let text = blocks
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .joined()
        if text.isEmpty {
            throw LLMError.malformedResponse("Anthropic response had no text content")
        }
        return text
    }

    /// Returns the JSON string of the first `tool_use` block's `input`.
    static func extractToolInput(from json: JSONValue) throws -> String {
        guard let blocks = json["content"]?.array else {
            throw LLMError.malformedResponse("Anthropic response had no `content` array")
        }
        for block in blocks where block["type"]?.string == "tool_use" {
            guard let input = block["input"] else { continue }
            return (try? PrettyJSON.string(from: input)) ?? ""
        }
        throw LLMError.malformedResponse("Anthropic response had no tool_use block")
    }

    /// Extracts a text delta from an Anthropic streaming `data:` payload.
    ///
    /// Text lives in `content_block_delta` events under `delta.text`; other event
    /// types (message_start/ping/content_block_start/stop) carry no text.
    static func streamDelta(from payload: String) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) else {
            return nil
        }
        guard json["type"]?.string == "content_block_delta" else { return nil }
        return json["delta"]?["text"]?.string
    }
}
