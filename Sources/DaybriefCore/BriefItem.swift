import Foundation

/// A single normalized signal from a connector, before synthesis into a ``Brief``.
///
/// Connectors fetch raw provider payloads and normalize them into `BriefItem`s;
/// the pipeline then feeds these to the LLM. The typed `source`/`type`/`urgencyHints`
/// fields encode to the same JSON strings the design's wire shape uses
/// (`"gmail"`, `"email"`, `"unread"`, …), so they remain interoperable while
/// staying type-safe in Swift.
public struct BriefItem: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// The connector that produced this item (encodes as e.g. `"gmail"`).
    public let source: ConnectorID
    /// The connected account label this item came from.
    public let account: String
    /// The ``Space/key`` this item is filed under (e.g. `"work"`).
    public let space: String
    /// The kind of item (encodes as e.g. `"email"`).
    public let type: ItemType
    /// Subject / event summary / message preview headline.
    public let title: String
    /// Optional body or snippet (mail snippet, message text); never the full mail body in v0.
    public let body: String?
    /// People involved (senders, attendees), as display strings.
    public let people: [String]
    /// When the underlying item occurred (mail date, event start, message ts).
    public let timestamp: Date
    /// Best-effort deep link back to the original item.
    public let url: URL?
    /// Why this item may deserve attention (encodes as e.g. `["unread"]`).
    public let urgencyHints: [UrgencyHint]

    /// Creates a normalized brief item.
    public init(
        id: UUID = UUID(),
        source: ConnectorID,
        account: String,
        space: String,
        type: ItemType,
        title: String,
        body: String? = nil,
        people: [String] = [],
        timestamp: Date,
        url: URL? = nil,
        urgencyHints: [UrgencyHint] = []
    ) {
        self.id = id
        self.source = source
        self.account = account
        self.space = space
        self.type = type
        self.title = title
        self.body = body
        self.people = people
        self.timestamp = timestamp
        self.url = url
        self.urgencyHints = urgencyHints
    }

    /// Returns a copy filed under `space`.
    ///
    /// Connectors cannot know an item's ``Space`` (the `Connector.normalize` contract
    /// has no access to ``Account/spaceKey``), so they emit a neutral placeholder and the
    /// pipeline backfills the real space from the originating account.
    public func settingSpace(_ space: String) -> BriefItem {
        BriefItem(
            id: id, source: source, account: account, space: space, type: type,
            title: title, body: body, people: people, timestamp: timestamp,
            url: url, urgencyHints: urgencyHints
        )
    }
}
