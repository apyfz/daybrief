import Foundation

/// An OAuth 2.0 token set, as returned by a token endpoint.
///
/// Persisted (in the Keychain, never the DB) and refreshed by ``OAuthFlow``. The
/// `accessToken`/`refreshToken` are secret material — callers must always log them
/// with `privacy: .private` and never echo them in error messages.
public struct OAuthToken: Sendable, Equatable, Hashable, Codable {
    /// The bearer access token used on API requests.
    public let accessToken: String
    /// The long-lived refresh token, if the provider issued one (Google requires
    /// `access_type=offline` and returns it only on first consent / with `prompt=consent`).
    public let refreshToken: String?
    /// When ``accessToken`` expires, if known. `nil` for tokens without an expiry.
    public let expiresAt: Date?
    /// The token type the provider declared (usually `"Bearer"`).
    public let tokenType: String

    /// Creates an OAuth token.
    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        tokenType: String = "Bearer"
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.tokenType = tokenType
    }

    /// Whether the access token is expired (or within `leeway` of expiring) at `now`.
    ///
    /// Returns `false` for a token with no known ``expiresAt``. The default `leeway`
    /// refreshes slightly early so an in-flight request doesn't race the expiry.
    public func isExpired(at now: Date, leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}
