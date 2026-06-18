import DaybriefCore
import Foundation

/// A presentation-ready projection of a ``Brief`` for the SwiftUI layer to render
/// directly — every display string is pre-computed, entries are pre-ordered, URLs
/// are parsed and link-safety-checked, and times are pre-formatted into hints.
///
/// This type carries **no business logic**: the view layer reads its fields and draws.
/// All ordering, formatting, and link-safety decisions are made by ``BriefRenderer``
/// when it builds the view model, so the same projection drives the in-app panel and
/// can be snapshot-tested deterministically (a clock is injected, never read live).
public struct BriefViewModel: Sendable, Equatable, Hashable, Identifiable {
    /// The originating brief's id.
    public let id: UUID
    /// A short, human-readable summary of when the brief was generated
    /// (e.g. "Generated just now" / "Generated 2 hours ago").
    public let generatedAtRelative: String
    /// An absolute, locale-formatted generation timestamp (e.g. "Jun 17, 2026 at 7:00 AM").
    public let generatedAtAbsolute: String
    /// A display label for the active space filter (e.g. "Work"), or `nil` for all spaces.
    public let spaceFilterDisplay: String?
    /// The single most important item of the day, rendered large as the lead story —
    /// projected from ``DaybriefCore/Brief/lead`` and kept separate from ``sections``
    /// so the edition leads with a real headline. `nil` on a quiet day with nothing to
    /// lead with (design §brief-design-language, "lead story").
    public let lead: Entry?
    /// The lead story's call-to-action label (e.g. "Let's do it"), since ``Entry``
    /// intentionally carries no CTA text; `nil` when the lead has no label.
    public let leadCTALabel: String?
    /// The sections in display order (the brief's own order is preserved). Excludes the
    /// ``lead`` — the engine keeps them separate, so it is never duplicated here.
    public let sections: [Section]
    /// Surfaced connector failures, in display order.
    public let connectorErrors: [ConnectorError]
    /// A small print-style provenance footer computed factually at assembly (never by
    /// the model), e.g. "Filed 7:02 AM · 14 signals read, 4 surfaced · Gmail · Calendar"
    /// — or "Filed 7:02 AM · a clear day" on a quiet day (design §brief-design-language,
    /// "colophon").
    public let colophon: String
    /// The per-edition accent as an `#RRGGBB` hex string, passed through from
    /// ``DaybriefCore/Brief/hero``'s ``DaybriefCore/HeroArtwork/accentHex``; `nil` when
    /// the edition has no hero or curated accent and the UI should fall back to the
    /// app's default accent (design §brief-design-language, "per-edition accent").
    public let accentHex: String?

    /// Whether the brief has no lead and no section entries — the view can show an
    /// empty state. (The lead is separate from ``sections``, so it is checked here.)
    public var isEmpty: Bool {
        lead == nil && sections.allSatisfy { $0.entries.isEmpty }
    }

    /// Creates a brief view model. Normally produced by ``BriefRenderer/viewModel(_:)``.
    public init(
        id: UUID,
        generatedAtRelative: String,
        generatedAtAbsolute: String,
        spaceFilterDisplay: String?,
        lead: Entry? = nil,
        leadCTALabel: String? = nil,
        sections: [Section],
        connectorErrors: [ConnectorError],
        colophon: String = "",
        accentHex: String? = nil
    ) {
        self.id = id
        self.generatedAtRelative = generatedAtRelative
        self.generatedAtAbsolute = generatedAtAbsolute
        self.spaceFilterDisplay = spaceFilterDisplay
        self.lead = lead
        self.leadCTALabel = leadCTALabel
        self.sections = sections
        self.connectorErrors = connectorErrors
        self.colophon = colophon
        self.accentHex = accentHex
    }

    /// A titled group of entries, ready to render.
    public struct Section: Sendable, Equatable, Hashable, Identifiable {
        /// The section's id (from ``BriefSection``).
        public let id: UUID
        /// The section heading.
        public let title: String
        /// The entries in priority-then-original display order.
        public let entries: [Entry]

        /// Creates a section view model.
        public init(id: UUID, title: String, entries: [Entry]) {
            self.id = id
            self.title = title
            self.entries = entries
        }
    }

    /// A single editorial line, ready to render.
    public struct Entry: Sendable, Equatable, Hashable, Identifiable {
        /// The entry's id (from ``BriefEntry``).
        public let id: UUID
        /// The headline the user reads first.
        public let headline: String
        /// Optional supporting detail (`nil`/empty detail is dropped to `nil`).
        public let detail: String?
        /// A parsed, link-safe destination (only `http`/`https` survive), or `nil`.
        ///
        /// A non-`nil` value here is safe to render as an `href` / open in a browser:
        /// `javascript:`, `data:`, `file:` and other non-web schemes are rejected.
        public let link: URL?
        /// The link's display text (its host, e.g. "mail.google.com"), or `nil`.
        public let linkLabel: String?
        /// The raw priority hint (lower = more important), or `nil` when unranked.
        public let priority: Int?

        /// Creates an entry view model.
        public init(
            id: UUID,
            headline: String,
            detail: String?,
            link: URL?,
            linkLabel: String?,
            priority: Int?
        ) {
            self.id = id
            self.headline = headline
            self.detail = detail
            self.link = link
            self.linkLabel = linkLabel
            self.priority = priority
        }
    }

    /// A surfaced connector failure, ready to render.
    public struct ConnectorError: Sendable, Equatable, Hashable, Identifiable {
        /// A stable identity for list diffing (connector id + kind).
        public var id: String {
            "\(connectorId.rawValue).\(kind.rawValue)"
        }

        /// The failing connector's id.
        public let connectorId: ConnectorID
        /// A display name for the connector (e.g. "Gmail").
        public let connectorDisplay: String
        /// The failure classification.
        public let kind: ConnectorErrorSummary.Kind
        /// The human-readable, already-redacted message.
        public let message: String

        /// Creates a connector-error view model.
        public init(
            connectorId: ConnectorID,
            connectorDisplay: String,
            kind: ConnectorErrorSummary.Kind,
            message: String
        ) {
            self.connectorId = connectorId
            self.connectorDisplay = connectorDisplay
            self.kind = kind
            self.message = message
        }
    }
}
