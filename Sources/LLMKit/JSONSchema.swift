import DaybriefCore
import Foundation

/// A JSON Schema document handed to ``ModelAdapter/completeStructured(_:schema:as:)``.
///
/// Wraps a ``JSONValue`` schema object together with the `name` and `strict`
/// metadata that providers attach in different ways:
/// - OpenAI / OpenRouter: `response_format.json_schema = {name, strict, schema}`
/// - Anthropic (tool-use fallback): a tool with `name` + `input_schema` = `schema`
/// - Gemini: `generationConfig.responseSchema = schema`
/// - Ollama: `format = schema` (bare)
///
/// For strict OpenAI/OpenRouter mode the wrapped `schema` must set
/// `additionalProperties: false` on every object and list every property in
/// `required` (optional fields modeled as nullable unions); see the design's §8.
public struct JSONSchema: Sendable, Equatable {
    /// A short identifier for the schema (e.g. `"daily_brief"`).
    public let name: String
    /// The JSON Schema document itself. Should be a ``JSONValue/object(_:)``.
    public let schema: JSONValue
    /// Whether providers that support it should enforce the schema strictly.
    public let strict: Bool

    /// Creates a JSON schema wrapper.
    ///
    /// - Parameters:
    ///   - name: A short identifier for the schema.
    ///   - schema: The JSON Schema document (an object).
    ///   - strict: Whether to request strict enforcement (default `true`).
    public init(name: String, schema: JSONValue, strict: Bool = true) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }
}
