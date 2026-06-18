import DaybriefCore
import Foundation

/// Small helpers shared by the adapters for building `URLRequest`s and JSON bodies.
enum RequestBuilder {
    /// Builds a JSON `POST` request with the given headers and ``JSONValue`` body.
    static func jsonPOST(
        url: URL,
        headers: [String: String],
        body: JSONValue
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // LLM completions can be slow (large prompts, reasoning models). Use a generous
        // timeout so URLSession's 60s default doesn't preempt the pipeline's own
        // synthesis budget with a raw URLError.
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            request.httpBody = try PrettyJSON.data(from: body)
        } catch {
            throw LLMError.requestEncodingFailed(String(describing: error))
        }
        return request
    }

    /// Builds a `GET` request with the given headers.
    static func get(url: URL, headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    /// Converts canonical ``ChatMessage``s to OpenAI-style `[{role, content}]`
    /// ``JSONValue`` array, prepending `system` as a leading system message when non-empty.
    static func openAIMessages(system: String, messages: [ChatMessage]) -> JSONValue {
        var out: [JSONValue] = []
        if !system.isEmpty {
            out.append(.object(["role": "system", "content": .string(system)]))
        }
        for message in messages {
            out.append(.object(["role": .string(message.role.rawValue), "content": .string(message.content)]))
        }
        return .array(out)
    }
}

extension JSONValue {
    /// Parses raw JSON `Data` into a ``JSONValue``, throwing ``LLMError/malformedResponse(_:)``.
    static func parse(_ data: Data, context: String) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw LLMError.malformedResponse("\(context): \(error)")
        }
    }
}
