import ConnectorKit
import DaybriefCore
import Foundation

/// Helpers for reading Notion API responses.
///
/// Unlike Slack (which always returns HTTP 200 and signals failure in the body),
/// Notion uses real status codes: 2xx on success, and 4xx/5xx with an error body of
/// the shape `{ "object": "error", "status": <int>, "code": "<string>", "message":
/// "<string>" }`. The transport throws ``TransportError/unacceptableStatus(code:body:)``
/// on a non-2xx, which we map to a typed ``ConnectorError`` here.
enum NotionResponse {
    /// Decodes raw 2xx bytes into a ``JSONValue``.
    static func decode(_ data: Data, context: String) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ConnectorError.decodingFailed(reason: "\(context): response was not valid JSON")
        }
    }

    /// Maps a non-2xx Notion response to a ``ConnectorError``, reading the error body's
    /// `message` for a human-facing reason when present.
    static func error(statusCode: Int, body: Data, context: String) -> ConnectorError {
        let message = (try? JSONDecoder().decode(JSONValue.self, from: body))?["message"]?.string
        switch statusCode {
        case 401:
            return .authFailed(reason: "Notion rejected the token. Re-copy the internal "
                + "integration secret (ntn_… or secret_…) from notion.so/my-integrations and paste it again.")
        case 403:
            return .authFailed(reason: "Notion denied access\(message.map { " (\($0))" } ?? "")."
                + " Make sure the integration has access: open each database's ••• menu → Connections → "
                + "connect your integration.")
        case 429:
            return .network(statusCode: 429, reason: "Notion is rate-limiting requests; the brief will catch up next run.")
        default:
            return .network(statusCode: statusCode, reason: message ?? "\(context) returned HTTP \(statusCode)")
        }
    }
}
