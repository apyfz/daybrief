/// A connector's stable identifier (e.g. `gcal`, `gmail`, `slack`).
///
/// Modeled as an open set: the v0 connectors are exposed as static members,
/// but the wrapped raw value lets future community connectors define their own
/// ids without changing this type. Codable as a plain string.
public struct ConnectorID: Sendable, Codable, Equatable, Hashable, RawRepresentable {
    /// The underlying string id, e.g. `"gmail"`.
    public let rawValue: String

    /// Creates a connector id from a raw string.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a connector id from a raw string (convenience).
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Google Calendar.
    public static let gcal = ConnectorID("gcal")
    /// Gmail.
    public static let gmail = ConnectorID("gmail")
    /// Slack.
    public static let slack = ConnectorID("slack")

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ConnectorID: CustomStringConvertible {
    public var description: String {
        rawValue
    }
}

extension ConnectorID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        rawValue = value
    }
}
