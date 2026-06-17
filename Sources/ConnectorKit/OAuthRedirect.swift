import Foundation

/// The parsed result of an OAuth 2.0 authorization redirect.
///
/// Produced by ``parse(url:)`` / ``parse(query:)`` from either a captured loopback
/// request line or an `ASWebAuthenticationSession` callback URL. Carries the
/// authorization `code` and `state` on success, or the provider's `error` on failure.
public struct OAuthRedirect: Sendable, Equatable, Hashable {
    /// The authorization code, if the provider returned one.
    public let code: String?
    /// The opaque `state` value echoed back by the provider (validate it against the
    /// value sent on the authorization request to defend against CSRF / loopback MITM).
    public let state: String?
    /// The provider's `error` code (e.g. `access_denied`), if the flow failed.
    public let error: String?
    /// The provider's human-readable `error_description`, if present.
    public let errorDescription: String?

    /// Creates a parsed redirect from its components.
    public init(code: String?, state: String?, error: String?, errorDescription: String?) {
        self.code = code
        self.state = state
        self.error = error
        self.errorDescription = errorDescription
    }

    /// Parses a redirect URL (loopback or custom-scheme) into an ``OAuthRedirect``.
    ///
    /// Reads the URL's query items (OAuth installed-app responses use the query, not
    /// the fragment). Returns `nil` only if the URL has no parseable components at all.
    public static func parse(url: URL) -> OAuthRedirect? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // `URLComponents.queryItems` does not honor the `application/x-www-form-urlencoded`
        // `+`-means-space convention that OAuth responses use, so route the raw query
        // through the form-aware parser rather than reading `queryItems` directly.
        guard let rawQuery = components.percentEncodedQuery else {
            return parse(queryItems: [])
        }
        return parse(query: rawQuery)
    }

    /// Parses a raw query string (e.g. `"code=abc&state=xyz"`, with or without a
    /// leading `?`) into an ``OAuthRedirect``.
    ///
    /// OAuth redirect queries are `application/x-www-form-urlencoded`, where a literal
    /// `+` encodes a space — a convention `URLComponents` does not apply on its own — so
    /// `+` is normalized to `%20` before percent-decoding.
    public static func parse(query: String) -> OAuthRedirect {
        let trimmed = query.hasPrefix("?") ? String(query.dropFirst()) : query
        var components = URLComponents()
        components.percentEncodedQuery = trimmed.replacingOccurrences(of: "+", with: "%20")
        return parse(queryItems: components.queryItems ?? [])
    }

    /// Parses pre-split query items into an ``OAuthRedirect``.
    public static func parse(queryItems: [URLQueryItem]) -> OAuthRedirect {
        var map: [String: String] = [:]
        for item in queryItems {
            // Keep the first occurrence of each key (providers don't duplicate these).
            if map[item.name] == nil, let value = item.value {
                map[item.name] = value
            }
        }
        return OAuthRedirect(
            code: map["code"],
            state: map["state"],
            error: map["error"],
            errorDescription: map["error_description"]
        )
    }

    /// Validates that this redirect carries a usable code and the expected `state`,
    /// returning the code or throwing a ``ConnectorError``.
    ///
    /// - Throws: ``ConnectorError/userCancelled`` for `access_denied`,
    ///   ``ConnectorError/authFailed(reason:)`` for any other provider error or a
    ///   `state` mismatch, and ``ConnectorError/invalidRedirect(reason:)`` if no code
    ///   is present.
    public func authorizationCode(expectedState: String) throws -> String {
        if let error {
            if error == "access_denied" {
                throw ConnectorError.userCancelled
            }
            let detail = errorDescription.map { ": \($0)" } ?? ""
            throw ConnectorError.authFailed(reason: "\(error)\(detail)")
        }
        guard let state else {
            throw ConnectorError.invalidRedirect(reason: "missing state")
        }
        guard state == expectedState else {
            throw ConnectorError.authFailed(reason: "state mismatch")
        }
        guard let code, !code.isEmpty else {
            throw ConnectorError.invalidRedirect(reason: "missing authorization code")
        }
        return code
    }
}
