/// The kind of a normalized brief item.
///
/// Forward-compatible: decoding an unrecognized raw value yields ``unknown``
/// rather than failing, so a newer connector emitting a novel type never breaks
/// an older client's decode. Encoding ``unknown`` preserves the original raw value.
public enum ItemType: Sendable, Codable, Equatable, Hashable {
    /// An email message (Gmail).
    case email
    /// A chat message (Slack DM / mention).
    case message
    /// A calendar event.
    case event
    /// A comment (e.g. a document or issue comment — future connectors).
    case comment
    /// A draft (e.g. a saved reply — future connectors).
    case draft
    /// An unrecognized type, preserving the original raw value for round-tripping.
    case unknown(String)

    /// The wire/string representation.
    public var rawValue: String {
        switch self {
        case .email: return "email"
        case .message: return "message"
        case .event: return "event"
        case .comment: return "comment"
        case .draft: return "draft"
        case let .unknown(raw): return raw
        }
    }

    /// Creates an item type from its raw value. Always succeeds (falls back to ``unknown``).
    public init(rawValue: String) {
        switch rawValue {
        case "email": self = .email
        case "message": self = .message
        case "event": self = .event
        case "comment": self = .comment
        case "draft": self = .draft
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
