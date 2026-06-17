import DaybriefCore
import Foundation

/// Shared, deterministic presentation helpers used by ``BriefRenderer`` for HTML,
/// Markdown, and the view model alike — so all three outputs order, label, and
/// link-check identically. Internal: not part of the public surface.
enum BriefPresentation {
    /// URL schemes considered safe to surface as a clickable link.
    ///
    /// Anything else (`javascript:`, `data:`, `file:`, `mailto:` schemes we don't
    /// want auto-opening from an archive, missing scheme, …) is dropped so a crafted
    /// entry `url` cannot become a script-injection or unexpected-action vector.
    static let safeLinkSchemes: Set<String> = ["http", "https"]

    /// Returns `url` only if it is a safe, web-navigable link; otherwise `nil`.
    static func safeLink(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased(),
              safeLinkSchemes.contains(scheme),
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// A short label for a link — its host with a leading `www.` stripped.
    static func linkLabel(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Trims whitespace and collapses an empty/whitespace-only optional string to `nil`.
    static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Entries in display order: ascending `priority` (lower = more important),
    /// unranked (`nil`) entries last, ties broken by the original (stable) order.
    static func orderedEntries(_ entries: [BriefEntry]) -> [BriefEntry] {
        entries.enumerated()
            .sorted { lhs, rhs in
                let lp = lhs.element.priority ?? Int.max
                let rp = rhs.element.priority ?? Int.max
                if lp != rp { return lp < rp }
                return lhs.offset < rhs.offset // stable tie-break
            }
            .map(\.element)
    }

    /// A human display name for a connector id (falls back to the raw id, capitalized).
    static func connectorDisplayName(_ id: ConnectorID) -> String {
        switch id {
        case .gcal: return "Google Calendar"
        case .gmail: return "Gmail"
        case .slack: return "Slack"
        default: return id.rawValue.capitalized
        }
    }

    /// A display label for a space key (`nil` filter → `nil`; known keys title-cased).
    static func spaceDisplay(_ key: String?) -> String? {
        guard let key = cleaned(key) else { return nil }
        return key.prefix(1).uppercased() + key.dropFirst()
    }

    // MARK: - Colophon

    /// Builds the print-style provenance footer for a brief, computed factually at
    /// assembly (never from the model): the filing time, how many signals were read and
    /// how many surfaced, and the contributing sources by display name — e.g.
    /// `"Filed 7:02 AM · 14 signals read, 4 surfaced · Gmail · Calendar"`.
    ///
    /// On a quiet day (nothing read and nothing surfaced) it degrades to a calm
    /// `"Filed 7:02 AM · a clear day"`; when signals were read but the day stayed light,
    /// the counts are still shown honestly. Sources are appended only when present, so a
    /// brief with no contributing connector simply omits the trailing source segment.
    ///
    /// - Parameters:
    ///   - generatedAt: When the brief was filed (formatted as a bare time).
    ///   - signalsRead: How many normalized signals were read while assembling.
    ///   - surfaced: How many items the brief surfaced (lead, if any, plus all section
    ///     entries) — computed by the caller, not the model.
    ///   - sources: The contributing connectors, in stable order.
    ///   - calendar: The calendar / locale / time zone used to format the filing time.
    static func colophon(
        generatedAt: Date,
        signalsRead: Int,
        surfaced: Int,
        sources: [ConnectorID],
        calendar: Calendar
    ) -> String {
        var segments = ["Filed \(filedTime(generatedAt, calendar: calendar))"]

        // Quiet day: nothing read and nothing surfaced reads as a clear day rather than
        // a bare "0 signals read, 0 surfaced".
        if signalsRead == 0, surfaced == 0 {
            segments.append("a clear day")
        } else {
            segments.append("\(signalsRead) \(pluralized(signalsRead, "signal")) read, \(surfaced) surfaced")
        }

        if !sources.isEmpty {
            segments.append(contentsOf: sources.map(connectorDisplayName))
        }

        return segments.joined(separator: " · ")
    }

    /// English pluralization for a small set of nouns in the colophon: `1 signal`,
    /// `0 signals`, `14 signals`.
    private static func pluralized(_ count: Int, _ singular: String) -> String {
        count == 1 ? singular : singular + "s"
    }

    // MARK: - Time

    /// A bare, locale- and time-zone-aware *time* (no date) for the colophon's filing
    /// line, e.g. "7:02 AM".
    ///
    /// The output is normalized so the day-period separator is a plain ASCII space:
    /// recent ICU/`DateFormatter` versions place a NARROW NO-BREAK SPACE (U+202F) — and
    /// sometimes a THIN SPACE (U+2009) — before "AM"/"PM", which would otherwise make the
    /// rendered colophon non-deterministic across OS/ICU versions and surface an invisible
    /// glyph in the print-style footer.
    static func filedTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return normalizingSpaces(formatter.string(from: date))
    }

    /// Replaces the narrow/thin no-break spaces ICU may emit (around AM/PM, between
    /// grouping, etc.) with a plain ASCII space so formatted time strings are stable.
    private static func normalizingSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{202F}", with: " ") // narrow no-break space
            .replacingOccurrences(of: "\u{2009}", with: " ") // thin space
    }

    /// An absolute, locale- and time-zone-aware formatting of `date`.
    static func absoluteTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return normalizingSpaces(formatter.string(from: date))
    }

    /// A coarse "X ago" / "in X" relative hint of `date` against `now`, fully
    /// deterministic (no wall-clock read) so it can be snapshot-tested.
    static func relativeTime(of date: Date, now: Date) -> String {
        let delta = now.timeIntervalSince(date) // > 0 ⇒ in the past
        let past = delta >= 0
        let seconds = Int(abs(delta).rounded())

        let phrase: String
        switch seconds {
        case 0 ..< 45:
            return past ? "just now" : "in a moment"
        case 45 ..< 90:
            phrase = "1 minute"
        case 90 ..< 3600:
            phrase = "\(Int((Double(seconds) / 60).rounded())) minutes"
        case 3600 ..< 5400:
            phrase = "1 hour"
        case 5400 ..< 86400:
            phrase = "\(Int((Double(seconds) / 3600).rounded())) hours"
        case 86400 ..< 129_600:
            phrase = "1 day"
        default:
            phrase = "\(Int((Double(seconds) / 86400).rounded())) days"
        }
        return past ? "\(phrase) ago" : "in \(phrase)"
    }
}
