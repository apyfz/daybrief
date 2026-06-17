import DaybriefCore
import Foundation

/// Serializes ``JSONValue`` documents to JSON text/data.
///
/// Used to embed user-supplied schemas into provider request bodies and into the
/// repair prompt. Goes through `JSONEncoder` (``JSONValue`` is `Codable`).
enum PrettyJSON {
    /// Encodes a ``JSONValue`` to compact JSON data.
    static func data(from value: JSONValue) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Encodes a ``JSONValue`` to a pretty-printed JSON string (for prompts).
    static func string(from value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try String(decoding: encoder.encode(value), as: UTF8.self)
    }
}
