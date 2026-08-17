import Foundation

/// A titled, ordered group of ``BriefEntry`` values within a ``Brief``.
///
/// In the source-grouped brief, each section represents one connector's updates
/// (Gmail / Calendar / Slack / Notion); ``source`` carries that connector so the UI can
/// show the right icon and a per-source collapsible dropdown. Older payloads leave it
/// `nil`.
public struct BriefSection: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// The section heading (e.g. "Gmail", "Slack").
    public let title: String
    /// The connector this section groups, when the brief is grouped by source.
    public let source: ConnectorID?
    /// The ordered entries in this section.
    public let entries: [BriefEntry]

    /// Creates a brief section.
    public init(id: UUID = UUID(), title: String, source: ConnectorID? = nil, entries: [BriefEntry] = []) {
        self.id = id
        self.title = title
        self.source = source
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case id, title, source, entries }

    /// Decodes a section, tolerating older payloads with no `source`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        source = try c.decodeIfPresent(ConnectorID.self, forKey: .source)
        entries = try c.decodeIfPresent([BriefEntry].self, forKey: .entries) ?? []
    }
}
