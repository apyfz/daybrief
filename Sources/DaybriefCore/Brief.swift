import Foundation

/// A single generated daily brief: the editorial output of the pipeline.
///
/// Its shape (``BriefSection`` → ``BriefEntry``) doubles as the LLM structured-output
/// schema. Connector failures are surfaced in ``connectorErrors`` rather than dropped.
public struct Brief: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// When this brief was generated.
    public let generatedAt: Date
    /// The ``Space/key`` this brief was filtered to, or `nil` for all spaces.
    public let spaceFilter: String?
    /// Newspaper-style masthead for this edition, e.g. "The Wednesday Brief".
    /// See `docs/design/brief-design-language.md`.
    public let masthead: String
    /// One or two sentences of editorial prose summarizing the day (the italic lede).
    public let lede: String
    /// The public-domain hero artwork for this edition, if assigned.
    public let hero: HeroArtwork?
    /// The structured, prioritized sections.
    public let sections: [BriefSection]
    /// Connector failures surfaced to the user (never silent).
    public let connectorErrors: [ConnectorErrorSummary]

    /// Creates a brief.
    public init(
        id: UUID = UUID(),
        generatedAt: Date,
        spaceFilter: String? = nil,
        masthead: String = "",
        lede: String = "",
        hero: HeroArtwork? = nil,
        sections: [BriefSection] = [],
        connectorErrors: [ConnectorErrorSummary] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.spaceFilter = spaceFilter
        self.masthead = masthead
        self.lede = lede
        self.hero = hero
        self.sections = sections
        self.connectorErrors = connectorErrors
    }

    private enum CodingKeys: String, CodingKey {
        case id, generatedAt, spaceFilter, masthead, lede, hero, sections, connectorErrors
    }

    /// Decodes a brief, tolerating older payloads that predate the editorial fields.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        spaceFilter = try c.decodeIfPresent(String.self, forKey: .spaceFilter)
        masthead = try c.decodeIfPresent(String.self, forKey: .masthead) ?? ""
        lede = try c.decodeIfPresent(String.self, forKey: .lede) ?? ""
        hero = try c.decodeIfPresent(HeroArtwork.self, forKey: .hero)
        sections = try c.decodeIfPresent([BriefSection].self, forKey: .sections) ?? []
        connectorErrors = try c.decodeIfPresent([ConnectorErrorSummary].self, forKey: .connectorErrors) ?? []
    }
}
