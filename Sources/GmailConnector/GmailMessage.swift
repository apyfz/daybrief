import DaybriefCore
import Foundation

/// A thin view over a Gmail `users.messages.get` (metadata-format) payload.
///
/// Wraps the raw ``DaybriefCore/JSONValue`` rather than eagerly decoding into stored
/// fields, so the same value is what gets stashed in ``ConnectorKit/RawItem/json`` during
/// fetch and re-read during normalize — no lossy intermediate representation. All accessors
/// are tolerant of missing/oddly-typed fields (the metadata shape is mostly stable, but a
/// connector must never crash on an unexpected payload).
struct GmailMessage {
    /// The raw message payload as returned by `messages.get?format=metadata`.
    let json: JSONValue

    /// The provider message id.
    var id: String {
        json["id"]?.string ?? ""
    }

    /// The server-side label ids (e.g. `UNREAD`, `IMPORTANT`, `STARRED`).
    var labelIDs: [String] {
        json["labelIds"]?.array?.compactMap(\.string) ?? []
    }

    /// The short preview text Gmail returns even in metadata mode.
    var snippet: String? {
        json["snippet"]?.string
    }

    /// `internalDate` as a `Date`. The field is epoch **milliseconds** as a string (int64);
    /// parse it as such and divide by 1000 (an easy off-by-1000x bug otherwise).
    var internalDate: Date? {
        guard let raw = json["internalDate"]?.string, let ms = Int64(raw) else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    /// The requested headers (`From`/`Subject`/`Date`) as case-insensitive lookups.
    private var headers: [(name: String, value: String)] {
        guard let raw = json["payload"]?["headers"]?.array else { return [] }
        return raw.compactMap { header in
            guard let name = header["name"]?.string, let value = header["value"]?.string else { return nil }
            return (name, value)
        }
    }

    /// The value of the first header matching `name` case-insensitively.
    func header(_ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}
