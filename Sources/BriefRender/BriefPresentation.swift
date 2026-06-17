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

    // MARK: - Time

    /// An absolute, locale- and time-zone-aware formatting of `date`.
    static func absoluteTime(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
