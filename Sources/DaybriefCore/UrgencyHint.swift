/// A signal about why a brief item may deserve attention.
///
/// Forward-compatible like ``ItemType``: an unrecognized raw value decodes to
/// ``other`` rather than failing, and re-encodes with its original raw value.
public enum UrgencyHint: Sendable, Codable, Equatable, Hashable {
    /// The item is unread.
    case unread
    /// The user was @-mentioned.
    case mention
    /// Something is due today.
    case dueToday
    /// An event is scheduled today.
    case scheduledToday
    /// An unrecognized hint, preserving its original raw value.
    case other(String)

    /// The wire/string representation.
    public var rawValue: String {
        switch self {
        case .unread: return "unread"
        case .mention: return "mention"
        case .dueToday: return "due-today"
        case .scheduledToday: return "scheduled-today"
        case let .other(raw): return raw
        }
    }

    /// Creates an urgency hint from its raw value. Always succeeds (falls back to ``other``).
    public init(rawValue: String) {
        switch rawValue {
        case "unread": self = .unread
        case "mention": self = .mention
        case "due-today": self = .dueToday
        case "scheduled-today": self = .scheduledToday
        default: self = .other(rawValue)
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
