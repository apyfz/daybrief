import Foundation

/// Shared JSON coders for the value trees stored in TEXT columns
/// (`Brief.sections`, `connectorErrors`, and `BriefItem` list fields).
///
/// Centralized so every record encodes/decodes column JSON identically.
enum JSONColumn {
    // Shared coders, configured once and never mutated. `JSONEncoder`/`JSONDecoder`
    // are `Sendable` in this SDK, so plain `static let` is concurrency-safe.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// Encodes a `Codable` value to a JSON string for storage in a TEXT column.
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        // UTF-8 from JSONEncoder is always valid; guard rather than force-unwrap.
        guard let string = String(data: data, encoding: .utf8) else {
            throw PersistenceError.corruptRow(entity: "\(T.self)", detail: "JSON was not valid UTF-8")
        }
        return string
    }

    /// Decodes a `Codable` value from a JSON string stored in a TEXT column.
    /// - Parameter entity: the owning entity name, for error reporting.
    static func decode<T: Decodable>(_: T.Type, from string: String, entity: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: Data(string.utf8))
        } catch {
            throw PersistenceError.corruptRow(entity: entity, detail: "JSON decode failed: \(error)")
        }
    }
}
