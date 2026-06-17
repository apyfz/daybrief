import DaybriefCore
import Foundation

/// Maps a decoded ``GmailMessage`` into a normalized ``DaybriefCore/BriefItem``.
///
/// Pure and synchronous — it never touches the network (the `Connector` contract requires
/// `normalize(_:)` to be pure). Pulls `title` from the `Subject` header, `body` from the
/// snippet, `people` from the `From` header, and `timestamp` from `internalDate` (falling
/// back to the `Date` header), and derives ``DaybriefCore/UrgencyHint``s from label ids.
enum GmailNormalizer {
    /// Builds a brief item, or `nil` if the payload has no usable id.
    static func briefItem(from message: GmailMessage, accountLabel: String) -> BriefItem? {
        let id = message.id
        guard !id.isEmpty else { return nil }

        let labels = Set(message.labelIDs)
        let title = message.header("Subject")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let people = parseFrom(message.header("From"))

        return BriefItem(
            source: .gmail,
            account: accountLabel,
            // Space is assigned by the pipeline from the account's space tag; the connector
            // does not know spaces, so it emits a neutral default here.
            space: "inbox",
            type: .email,
            title: (title?.isEmpty == false ? title! : "(no subject)"),
            body: message.snippet,
            people: people,
            timestamp: message.internalDate ?? parseRFC822Date(message.header("Date")) ?? Date(),
            // Best-effort Gmail web deep link. The research REFUTED the reliability of the
            // `#all/{id}` route — it is undocumented and assumes browser account index `u/0` —
            // so it is included but never promised; the REST id is the only stable contract.
            url: deepLink(id: id),
            urgencyHints: urgencyHints(labels: labels)
        )
    }

    /// Parses the `From` header into display names/addresses. Gmail rarely sends multiple
    /// senders, but the header is comma-delimited so we split defensively and keep the
    /// human-readable form (e.g. `"Ada Lovelace <ada@example.com>"`).
    static func parseFrom(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func urgencyHints(labels: Set<String>) -> [UrgencyHint] {
        var hints: [UrgencyHint] = []
        if labels.contains("UNREAD") {
            hints.append(.unread)
        }
        return hints
    }

    /// The best-effort Gmail web deep link for `id` (see `briefItem` for the reliability caveat).
    static func deepLink(id: String) -> URL? {
        URL(string: "https://mail.google.com/mail/u/0/#all/\(id)")
    }

    /// Parses an RFC822 mail `Date` header as a fallback when `internalDate` is absent.
    /// `internalDate` is preferred for sorting — the `Date` header is sender-supplied and
    /// unreliable — so this only runs when the epoch field is missing.
    static func parseRFC822Date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Common Gmail `Date` header form: "Tue, 17 Jun 2026 09:30:00 -0700".
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: raw)
    }
}
