import DaybriefCore
import Foundation

/// Local Ollama backend. No auth; talks to a daemon on the user's machine.
///
/// - Chat: `POST {baseURL}/api/chat`. Body `{model, messages:[{role,content}], stream, format?}`.
/// - Structured: `format` is the **bare** JSON schema object (NOT wrapped in
///   `response_format`/`json_schema`).
/// - Streaming: **NDJSON** (one JSON object per line, final object has `"done":true`),
///   NOT SSE — uses the sibling ``NDJSONReader``.
/// - Models: `GET {baseURL}/api/tags`.
public struct OllamaAdapter: ModelAdapter {
    /// `http://localhost:11434`.
    /// Force-unwrap is safe: a compile-time-constant, well-formed URL literal.
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!

    private let baseURL: URL
    private let defaultModel: String
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport

    /// Creates an Ollama adapter.
    public init(
        baseURL: URL = OllamaAdapter.defaultBaseURL,
        defaultModel: String,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        streamingTransport: any StreamingHTTPTransport = URLSessionStreamingTransport()
    ) {
        self.baseURL = baseURL
        self.defaultModel = defaultModel
        self.transport = transport
        self.streamingTransport = streamingTransport
    }

    private func modelOrDefault(_ input: CompletionInput) -> String {
        input.model.isEmpty ? defaultModel : input.model
    }

    private func chatURL() -> URL {
        baseURL.appending(path: "api/chat")
    }

    // MARK: complete

    public func complete(_ input: CompletionInput) async throws -> String {
        let request = try RequestBuilder.jsonPOST(
            url: chatURL(),
            headers: [:],
            body: chatBody(input, stream: false, format: nil)
        )
        let json = try await sendForJSON(request)
        return try Self.extractContent(from: json)
    }

    // MARK: streamComplete

    public func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error> {
        let body = chatBody(input, stream: true, format: nil)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try RequestBuilder.jsonPOST(url: chatURL(), headers: [:], body: body)
                    let bytes = try await streamingTransport.stream(request)
                    for try await line in NDJSONReader.frames(from: bytes) {
                        if let delta = Self.streamDelta(from: line), !delta.isEmpty {
                            continuation.yield(delta)
                        }
                        if Self.isDone(line) { break }
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
        let request = try RequestBuilder.jsonPOST(
            url: chatURL(),
            headers: [:],
            body: chatBody(input, stream: false, format: schema.schema)
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
                let repairRequest = try RequestBuilder.jsonPOST(
                    url: chatURL(),
                    headers: [:],
                    body: chatBody(repairInput, stream: false, format: schema.schema)
                )
                let repairJSON = try await sendForJSON(repairRequest)
                return try Self.extractContent(from: repairJSON)
            }
        )
    }

    // MARK: availableModels

    public func availableModels() async throws -> [ModelInfo] {
        let request = RequestBuilder.get(url: baseURL.appending(path: "api/tags"))
        let json = try await sendForJSON(request)
        guard let models = json["models"]?.array else {
            throw LLMError.malformedResponse("Ollama /api/tags had no `models` array")
        }
        return models.compactMap { entry in
            guard let name = entry["model"]?.string ?? entry["name"]?.string else { return nil }
            let context = entry["details"]?["parameter_size"]?.int
            return ModelInfo(id: name, displayName: entry["name"]?.string, contextLength: context)
        }
    }

    // MARK: - Body construction

    private func chatBody(_ input: CompletionInput, stream: Bool, format: JSONValue?) -> JSONValue {
        var object: [String: JSONValue] = [
            "model": .string(modelOrDefault(input)),
            "messages": RequestBuilder.openAIMessages(system: input.system, messages: input.messages),
            "stream": .bool(stream),
        ]
        var options: [String: JSONValue] = [:]
        if let temperature = input.temperature { options["temperature"] = .number(temperature) }
        if let maxTokens = input.maxTokens { options["num_predict"] = .number(Double(maxTokens)) }
        if !options.isEmpty { object["options"] = .object(options) }
        if let format { object["format"] = format } // bare schema, NOT wrapped.
        return .object(object)
    }

    // MARK: - Response parsing

    private func sendForJSON(_ request: URLRequest) async throws -> JSONValue {
        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let transportError as TransportError {
            throw LLMError.from(transportError)
        }
        return try JSONValue.parse(data, context: "Ollama response")
    }

    /// Reads `message.content` from a non-streaming `/api/chat` response.
    static func extractContent(from json: JSONValue) throws -> String {
        guard let content = json["message"]?["content"]?.string else {
            throw LLMError.malformedResponse("Ollama response had no message.content")
        }
        return content
    }

    /// Reads the `message.content` delta from one NDJSON streaming line.
    static func streamDelta(from line: String) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return nil
        }
        return json["message"]?["content"]?.string
    }

    /// `true` if the NDJSON line is the terminal `"done":true` object.
    static func isDone(_ line: String) -> Bool {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            return false
        }
        return json["done"]?.bool == true
    }
}
