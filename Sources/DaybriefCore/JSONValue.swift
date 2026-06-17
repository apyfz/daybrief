import Foundation

/// A fully dynamic JSON value.
///
/// Used by `LLMKit` (and connectors) for flexible API payloads whose shape isn't
/// known at compile time and for representing JSON-schema documents. Numbers are
/// stored as `Double`; integer round-trips are exact for values within `Double`'s
/// 53-bit integer range, and ``int`` exposes a whole-number view.
public enum JSONValue: Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

// MARK: - Typed accessors

public extension JSONValue {
    /// The wrapped boolean, or `nil` if this isn't a ``bool``.
    var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    /// The wrapped number, or `nil` if this isn't a ``number``.
    var double: Double? {
        if case let .number(value) = self { return value }
        return nil
    }

    /// The wrapped number as an `Int`, or `nil` if this isn't a whole-number ``number``.
    var int: Int? {
        guard case let .number(value) = self else { return nil }
        guard value.rounded() == value, value.isFinite else { return nil }
        return Int(value)
    }

    /// The wrapped string, or `nil` if this isn't a ``string``.
    var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    /// The wrapped array, or `nil` if this isn't an ``array``.
    var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    /// The wrapped object, or `nil` if this isn't an ``object``.
    var object: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    /// `true` if this is ``null``.
    var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

// MARK: - Subscripts

public extension JSONValue {
    /// Member access for ``object`` values; `nil` for any other case or a missing key.
    subscript(key: String) -> JSONValue? {
        guard case let .object(dict) = self else { return nil }
        return dict[key]
    }

    /// Index access for ``array`` values; `nil` for any other case or an out-of-bounds index.
    subscript(index: Int) -> JSONValue? {
        guard case let .array(values) = self, values.indices.contains(index) else { return nil }
        return values[index]
    }
}

// MARK: - Codable

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Value is not a valid JSON value"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

// MARK: - ExpressibleBy… literals

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
