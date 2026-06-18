import DaybriefCore
import Foundation

/// Supplies a valid access/bearer token for a connector to authenticate a fetch.
///
/// This is the auth seam between connectors (which only know they need a token for an
/// account) and the app's credential machinery. Concrete implementations live in
/// `AppFeature`: the OAuth path refreshes expired tokens via ``OAuthFlow`` + the Keychain,
/// while the pasted-token path (Slack `xoxp-`) returns the stored user token as-is.
public protocol TokenProvider: Sendable {
    /// Returns a currently-valid access token for `account`, refreshing if necessary.
    func accessToken(for account: Account) async throws -> String
}

/// Error thrown when a token cannot be supplied.
public enum TokenProviderError: Error, Sendable, Equatable {
    /// No token is available for the given account label.
    case noToken(accountLabel: String)
}

/// A fixed-token provider for tests and the pasted-token (Slack) path.
public struct StaticTokenProvider: TokenProvider {
    private let resolve: @Sendable (Account) -> String?

    /// Returns the same token for every account.
    public init(token: String) {
        resolve = { _ in token }
    }

    /// Resolves a token per account id; accounts not in the map fail with ``TokenProviderError/noToken(accountLabel:)``.
    public init(tokensByAccountID: [UUID: String]) {
        resolve = { tokensByAccountID[$0.id] }
    }

    public func accessToken(for account: Account) async throws -> String {
        guard let token = resolve(account) else {
            throw TokenProviderError.noToken(accountLabel: account.label)
        }
        return token
    }
}
