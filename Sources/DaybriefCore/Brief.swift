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
    /// The single most important item of the day, rendered large as the lead story —
    /// separate from ``sections`` so the brief leads with a real headline rather than
    /// a flat list (design §brief-design-language, "lead story"). `nil` on a quiet day
    /// with nothing to lead with.
    public let lead: BriefEntry?
    /// The character of the day, read by the synthesizer and used to pick a
    /// tone-matched hero painting and per-edition accent. `nil` on older payloads.
    public let mood: BriefMood?
    /// The public-domain hero artwork for this edition, if assigned.
    public let hero: HeroArtwork?
    /// The structured, prioritized sections.
    public let sections: [BriefSection]
    /// How many normalized signals were read while assembling this brief, for the
    /// colophon's provenance line (computed at assembly, not by the model).
    public let signalsRead: Int
    /// The distinct connectors that contributed to this brief, for the colophon.
    public let sources: [ConnectorID]
    /// Connector failures surfaced to the user (never silent).
    public let connectorErrors: [ConnectorErrorSummary]

    /// Creates a brief.
    public init(
        id: UUID = UUID(),
        generatedAt: Date,
        spaceFilter: String? = nil,
        masthead: String = "",
        lede: String = "",
        lead: BriefEntry? = nil,
        mood: BriefMood? = nil,
        hero: HeroArtwork? = nil,
        sections: [BriefSection] = [],
        signalsRead: Int = 0,
        sources: [ConnectorID] = [],
        connectorErrors: [ConnectorErrorSummary] = []
    ) {
        self.id = id
        self.generatedAt = generatedAt
        self.spaceFilter = spaceFilter
        self.masthead = masthead
        self.lede = lede
        self.lead = lead
        self.mood = mood
        self.hero = hero
        self.sections = sections
        self.signalsRead = signalsRead
        self.sources = sources
        self.connectorErrors = connectorErrors
    }

    private enum CodingKeys: String, CodingKey {
        case id, generatedAt, spaceFilter, masthead, lede, lead, mood, hero
        case sections, signalsRead, sources, connectorErrors
    }

    /// Decodes a brief, tolerating older payloads that predate the editorial fields.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        spaceFilter = try c.decodeIfPresent(String.self, forKey: .spaceFilter)
        masthead = try c.decodeIfPresent(String.self, forKey: .masthead) ?? ""
        lede = try c.decodeIfPresent(String.self, forKey: .lede) ?? ""
        lead = try c.decodeIfPresent(BriefEntry.self, forKey: .lead)
        mood = try c.decodeIfPresent(BriefMood.self, forKey: .mood)
        hero = try c.decodeIfPresent(HeroArtwork.self, forKey: .hero)
        sections = try c.decodeIfPresent([BriefSection].self, forKey: .sections) ?? []
        signalsRead = try c.decodeIfPresent(Int.self, forKey: .signalsRead) ?? 0
        sources = try c.decodeIfPresent([ConnectorID].self, forKey: .sources) ?? []
        connectorErrors = try c.decodeIfPresent([ConnectorErrorSummary].self, forKey: .connectorErrors) ?? []
    }
}
