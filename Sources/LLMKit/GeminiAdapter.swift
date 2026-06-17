import DaybriefCore
import Foundation

/// Google Gemini backend using the `generateContent` API.
///
/// - Chat: `POST {baseURL}/v1beta/models/{model}:generateContent?key=<key>`.
///   Body uses `contents:[{role, parts:[{text}]}]` (roles are `user`/`model`),
///   `systemInstruction`, and `generationConfig`.
/// - Structured: `generationConfig = {responseMimeType:"application/json", responseSchema:<schema>}`.
/// - Streaming: `:streamGenerateContent?alt=sse&key=<key>`; SSE frames carry
///   `candidates[0].content.parts[0].text`.
/// - Models: `GET {baseURL}/v1beta/models?key=<key>`.
public struct GeminiAdapter: ModelAdapter {
    /// `https://generativelanguage.googleapis.com`.
    /// Force-unwrap is safe: a compile-time-constant, well-formed URL literal.
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com")!

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let transport: any HTTPTransport
    private let streamingTransport: any StreamingHTTPTransport

    /// Creates a Gemini adapter.
    public init(
        apiKey: String,
        baseURL: URL = GeminiAdapter.defaultBaseURL,
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

    private func modelOrDefault(_ input: CompletionInput) -> String {
        input.model.isEmpty ? defaultModel : input.model
    }

    private func generateURL(model: String, method: String, sse: Bool) throws -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: "v1beta/models/\(model):\(method)"),
            resolvingAgainstBaseURL: false
        )
        var query = [URLQueryItem(name: "key", value: apiKey)]
        if sse { query.append(URLQueryItem(name: "alt", value: "sse")) }
        components?.queryItems = query
        guard let url = components?.url else {
            throw LLMError.invalidBaseURL(provider: Provider.gemini.rawValue)
        }
        return url
    }

    // MARK: complete

    public func complete(_ input: CompletionInput) async throws -> String {
        let url = try generateURL(model: modelOrDefault(input), method: "generateContent", sse: false)
        let request = try RequestBuilder.jsonPOST(
            url: url,
            headers: [:],
            body: generateBody(input, structured: nil)
        )
        let json = try await sendForJSON(request)
        return try Self.extractText(from: json)
    }

    // MARK: streamComplete

    public func streamComplete(_ input: CompletionInput) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = try generateURL(
                        model: modelOrDefault(input),
                        method: "streamGenerateContent",
                        sse: true
                    )
                    let request = try RequestBuilder.jsonPOST(
                        url: url,
                        headers: [:],
                        body: generateBody(input, structured: nil)
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
        let url = try generateURL(model: modelOrDefault(input), method: "generateContent", sse: false)
        let request = try RequestBuilder.jsonPOST(
            url: url,
            headers: [:],
            body: generateBody(input, structured: schema.schema)
        )
        let json = try await sendForJSON(request)
        let raw = try Self.extractText(from: json)

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
                let repairURL = try generateURL(
                    model: modelOrDefault(repairInput),
                    method: "generateContent",
                    sse: false
                )
                let repairRequest = try RequestBuilder.jsonPOST(
                    url: repairURL,
                    headers: [:],
                    body: generateBody(repairInput, structured: schema.schema)
                )
                let repairJSON = try await sendForJSON(repairRequest)
                return try Self.extractText(from: repairJSON)
            }
        )
    }

    // MARK: availableModels

    public func availableModels() async throws -> [ModelInfo] {
        var components = URLComponents(
            url: baseURL.appending(path: "v1beta/models"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else {
            throw LLMError.invalidBaseURL(provider: Provider.gemini.rawValue)
        }
        let json = try await sendForJSON(RequestBuilder.get(url: url))
        guard let models = json["models"]?.array else {
            throw LLMError.malformedResponse("Gemini /models had no `models` array")
        }
        return models.compactMap { entry in
            // `name` is "models/<id>"; prefer `baseModelId`, else strip the prefix.
            let id: String?
            if let base = entry["baseModelId"]?.string {
                id = base
            } else if let name = entry["name"]?.string {
                id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
            } else {
                id = nil
            }
            guard let resolved = id else { return nil }
            return ModelInfo(
                id: resolved,
                displayName: entry["displayName"]?.string,
                contextLength: entry["inputTokenLimit"]?.int
            )
        }
    }

    // MARK: - Body construction

    private func generateBody(_ input: CompletionInput, structured schema: JSONValue?) -> JSONValue {
        var object: [String: JSONValue] = [
            "contents": Self.geminiContents(input.messages),
        ]
        if !input.system.isEmpty {
            object["systemInstruction"] = .object([
                "parts": .array([.object(["text": .string(input.system)])]),
            ])
        }
        var generationConfig: [String: JSONValue] = [:]
        if let temperature = input.temperature { generationConfig["temperature"] = .number(temperature) }
        if let maxTokens = input.maxTokens { generationConfig["maxOutputTokens"] = .number(Double(maxTokens)) }
        if let schema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = schema
        }
        if !generationConfig.isEmpty {
            object["generationConfig"] = .object(generationConfig)
        }
        return .object(object)
    }

    /// Maps canonical messages to Gemini `contents` (`user`/`model` roles, `parts:[{text}]`).
    static func geminiContents(_ messages: [ChatMessage]) -> JSONValue {
        let mapped: [JSONValue] = messages.map { message in
            let role: String
            switch message.role {
            case .assistant: role = "model"
            case .user, .system: role = "user"
            }
            return .object([
                "role": .string(role),
                "parts": .array([.object(["text": .string(message.content)])]),
            ])
        }
        return .array(mapped)
    }

    // MARK: - Response parsing

    private func sendForJSON(_ request: URLRequest) async throws -> JSONValue {
        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let transportError as TransportError {
            throw LLMError.from(transportError)
        }
        return try JSONValue.parse(data, context: "Gemini response")
    }

    /// Concatenates `candidates[0].content.parts[*].text`.
    static func extractText(from json: JSONValue) throws -> String {
        guard let parts = json["candidates"]?[0]?["content"]?["parts"]?.array else {
            throw LLMError.malformedResponse("Gemini response had no candidates[0].content.parts")
        }
        let text = parts.compactMap { $0["text"]?.string }.joined()
        if text.isEmpty {
            throw LLMError.malformedResponse("Gemini response had no text parts")
        }
        return text
    }

    /// Extracts the text delta from a Gemini SSE chunk payload.
    static func streamDelta(from payload: String) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) else {
            return nil
        }
        guard let parts = json["candidates"]?[0]?["content"]?["parts"]?.array else { return nil }
        let text = parts.compactMap { $0["text"]?.string }.joined()
        return text.isEmpty ? nil : text
    }
}
