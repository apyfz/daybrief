import ConnectorKit
import DaybriefCore
import Foundation

/// Helpers for reading Slack Web API response envelopes.
///
/// Every Slack Web API method returns HTTP 200 with a top-level `"ok"` boolean; on
/// failure `"ok"` is `false` and `"error"` names the failure (e.g. `"not_authed"`,
/// `"invalid_auth"`, `"ratelimited"`). The transport therefore can't tell success
/// from failure by status code alone — we always inspect the decoded body here and
/// map a not-ok envelope to the right ``ConnectorError``.
enum SlackResponse {
    /// Decodes raw bytes into a ``JSONValue`` and verifies `ok == true`.
    ///
    /// - Throws: ``ConnectorError/decodingFailed(reason:)`` if the bytes aren't JSON,
    ///   or a mapped ``ConnectorError`` (via ``error(forSlackError:method:)``) when the
    ///   envelope reports `ok:false`.
    static func decodeOK(_ data: Data, method: String) throws -> JSONValue {
        let json: JSONValue
        do {
            json = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw ConnectorError.decodingFailed(reason: "\(method): response was not valid JSON")
        }
        guard json["ok"]?.bool == true else {
            let slackError = json["error"]?.string ?? "unknown_error"
            // Slack includes the missing scope's name in `needed` on a missing_scope error.
            throw error(forSlackError: slackError, method: method, needed: json["needed"]?.string)
        }
        return json
    }

    /// Maps a Slack `"error"` string to a ``ConnectorError``.
    ///
    /// Auth-family errors become ``ConnectorError/authFailed(reason:)``; rate limiting
    /// becomes a network error carrying the distributed-app hint (an internal app keeps
    /// Tier-3 limits, so a `ratelimited` reply usually means the app was mis-configured
    /// as publicly distributed). Everything else is ``ConnectorError/other(reason:)``.
    static func error(forSlackError slackError: String, method: String, needed: String? = nil) -> ConnectorError {
        switch slackError {
        case "missing_scope":
            let which = needed.map { " (\($0))" } ?? ""
            return .authFailed(reason: "Slack is missing a permission\(which). Add the User Token Scopes "
                + "(search:read, im:read, im:history, mpim:read, mpim:history, users:read), reinstall the app, "
                + "then paste the new xoxp- token.")
        case "not_authed", "invalid_auth", "account_inactive", "token_revoked",
             "token_expired", "no_permission", "not_allowed_token_type":
            return .authFailed(reason: "Slack rejected the token (\(slackError)). "
                + "Re-create the User OAuth token (xoxp-) and paste it again.")
        case "ratelimited":
            return .network(statusCode: 429, reason: distributedAppHint)
        default:
            return .other(reason: "\(method) failed: \(slackError)")
        }
    }

    /// Guidance shown when Slack throttles the connector — almost always a sign the
    /// user's app was published (distributed) rather than kept internal.
    static let distributedAppHint =
        "Slack is rate-limiting requests. Your Slack app appears to be publicly "
            + "distributed; Daybrief needs an internal (single-workspace) app. In your app "
            + "settings, deactivate public distribution and reinstall to your workspace."
}
