import Foundation

/// The Codable DTO the LLM returns for ``Synthesizer`` to map into a
/// ``DaybriefCore/Brief``.
///
/// This is the *wire* shape constrained by the strict JSON schema in
/// ``Synthesizer/schema``. It deliberately omits ids, `generatedAt`, hero, and
/// `connectorErrors` — those are pipeline-assigned metadata, not the model's job.
/// Optionals are decoded leniently so a model that emits `null` (as strict mode
/// requires for absent fields) round-trips cleanly.
public struct SynthesizedBrief: Codable, Sendable, Equatable {
    /// One titled movement of the brief.
    public struct Section: Codable, Sendable, Equatable {
        /// The section heading, e.g. "Push your work forward".
        public let title: String
        /// The ordered entries in this section.
        public let entries: [Entry]

        public init(title: String, entries: [Entry]) {
            self.title = title
            self.entries = entries
        }
    }

    /// One editorial line within a section.
    public struct Entry: Codable, Sendable, Equatable {
        /// The headline the reader sees first.
        public let headline: String
        /// Optional paragraph of context.
        public let detail: String?
        /// Optional deep link back to the source item.
        public let url: String?
        /// Optional priority hint (lower = more important).
        public let priority: Int?
        /// Optional short call-to-action label for the accent badge.
        public let ctaLabel: String?

        public init(
            headline: String,
            detail: String? = nil,
            url: String? = nil,
            priority: Int? = nil,
            ctaLabel: String? = nil
        ) {
            self.headline = headline
            self.detail = detail
            self.url = url
            self.priority = priority
            self.ctaLabel = ctaLabel
        }
    }

    /// The newspaper-style masthead, e.g. "The Wednesday Brief".
    public let masthead: String
    /// One or two sentences of editorial prose (the italic lede).
    public let lede: String
    /// The titled movements of the brief.
    public let sections: [Section]

    public init(masthead: String, lede: String, sections: [Section]) {
        self.masthead = masthead
        self.lede = lede
        self.sections = sections
    }
}
