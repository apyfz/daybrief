import Foundation

/// One editorial line within a ``BriefSection`` — the LLM's synthesized output unit.
///
/// `BriefEntry`/``BriefSection``/``Brief`` double as the LLM structured-output schema,
/// so the field set is deliberately simple and round-trips through JSON cleanly.
public struct BriefEntry: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// The headline the user reads first.
    public let headline: String
    /// Optional supporting detail.
    public let detail: String?
    /// Optional deep link to the originating item.
    public let url: URL?
    /// Optional priority hint (lower = more important); `nil` when unranked.
    public let priority: Int?
    /// Optional call-to-action label for the accent badge, e.g. "Let's do it".
    /// See `docs/design/brief-design-language.md`.
    public let ctaLabel: String?
    /// The ``BriefItem`` ids this entry was synthesized from, for traceability.
    public let sourceItemIDs: [UUID]

    /// Creates a brief entry.
    public init(
        id: UUID = UUID(),
        headline: String,
        detail: String? = nil,
        url: URL? = nil,
        priority: Int? = nil,
        ctaLabel: String? = nil,
        sourceItemIDs: [UUID] = []
    ) {
        self.id = id
        self.headline = headline
        self.detail = detail
        self.url = url
        self.priority = priority
        self.ctaLabel = ctaLabel
        self.sourceItemIDs = sourceItemIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, headline, detail, url, priority, ctaLabel, sourceItemIDs
    }

    /// Decodes an entry, tolerating older payloads that predate `ctaLabel`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        headline = try c.decode(String.self, forKey: .headline)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        ctaLabel = try c.decodeIfPresent(String.self, forKey: .ctaLabel)
        sourceItemIDs = try c.decodeIfPresent([UUID].self, forKey: .sourceItemIDs) ?? []
    }
}
