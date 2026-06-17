import ConnectorKit
import DaybriefCore
import Foundation
import os
import Secrets

/// Stable Keychain coordinates and stored-credential shapes Daybrief mints for each
/// connected account, shared by ``AppModel`` (which writes them on connect) and
/// ``KeychainTokenProvider`` (which reads/refreshes them on fetch).
///
/// One account carries one ``DaybriefCore/SecretRef`` (on ``DaybriefCore/Account/secretRef``).
/// The token blob lives at that ref; the OAuth client parameters needed to refresh it
/// live at a derived `*.client` ref so a refresh never has to round-trip the DB.
public enum AccountSecrets {
    /// The ``SecretRef`` under which an account's token material is stored.
    ///
    /// - For OAuth (Google) accounts this holds a JSON ``ConnectorKit/OAuthToken``.
    /// - For pasted-token (Slack) accounts this holds the raw `xoxp-` user token.
    public static func tokenRef(for accountID: UUID, connector: ConnectorID) -> SecretRef {
        SecretRef(service: "co.daybrief.token.\(connector.rawValue)", account: accountID.uuidString)
    }

    /// The ``SecretRef`` under which an OAuth account's refresh parameters live
    /// (the BYO client id/secret + endpoints + scopes), so the token can be refreshed.
    public static func clientRef(for tokenRef: SecretRef) -> SecretRef {
        SecretRef(service: tokenRef.service + ".client", account: tokenRef.account)
    }
}

/// A connector account's auth kind, persisted alongside its token so the token
/// provider knows whether to refresh an OAuth token or pass a static token through.
public enum StoredAuthKind: String, Sendable, Codable {
    /// OAuth 2.0 with refresh (Google Calendar / Gmail).
    case oauth
    /// A pasted, long-lived user token (Slack `xoxp-`).
    case staticToken
}

/// The OAuth refresh parameters persisted for an OAuth account.
public struct StoredOAuthClient: Sendable, Codable {
    /// The OAuth configuration used to refresh this account's access token.
    public let config: OAuthConfig

    /// Creates stored OAuth client parameters.
    public init(config: OAuthConfig) {
        self.config = config
    }
}

/// The `AppFeature` implementation of ``ConnectorKit/TokenProvider``.
///
/// For every account it reads the stored token from the Keychain. OAuth accounts
/// store a JSON ``ConnectorKit/OAuthToken`` and the refresh parameters; when the
/// access token is expired the provider refreshes it via ``ConnectorKit/OAuthFlow``
/// and writes the new token back. Pasted-token (Slack) accounts store the raw token
/// and it is returned as-is.
public struct KeychainTokenProvider: TokenProvider {
    private static let logger = Logger(subsystem: "co.daybrief.app", category: "KeychainTokenProvider")

    private let keychain: KeychainStore
    private let flow: OAuthFlow

    /// Creates a token provider over `keychain`.
    public init(keychain: KeychainStore) {
        self.keychain = keychain
        flow = OAuthFlow(transport: URLSessionHTTPTransport())
    }

    public func accessToken(for account: Account) async throws -> String {
        let tokenRef = AccountSecrets.tokenRef(for: account.id, connector: account.connectorId)

        // OAuth path: a stored OAuthToken JSON + refresh parameters. A pasted-token
        // (Slack) account stores a raw `xoxp-` string, which is NOT OAuthToken JSON —
        // decoding it would throw. Treat that as "not an OAuth token" and fall through
        // to the raw-token path below instead of failing the whole account.
        let storedOAuth = (try? await keychain.getCodable(OAuthToken.self, for: tokenRef)) ?? nil
        if let stored = storedOAuth {
            guard let clientParams = try await keychain.getCodable(
                StoredOAuthClient.self,
                for: AccountSecrets.clientRef(for: tokenRef)
            ) else {
                // No refresh parameters — return the access token as-is (it may still
                // be valid); if it's expired the connector's call will surface auth.
                return stored.accessToken
            }
            let valid = try await flow.validToken(stored, config: clientParams.config)
            if valid != stored {
                // Persist the refreshed token so the next fetch reuses it. A write failure
                // here is non-fatal: the freshly-refreshed token is still valid in-memory
                // and is returned below, so the current fetch succeeds; the next fetch simply
                // refreshes again. Don't swallow it silently — log the failure (never the
                // token bytes; account coordinates are .private) so a persistent Keychain
                // problem (e.g. a locked/denied keychain) is diagnosable.
                do {
                    try await keychain.setCodable(valid, for: tokenRef)
                } catch {
                    Self.logger.error(
                        "Failed to persist refreshed OAuth token for account \(account.label, privacy: .private); returning the refreshed token without caching. Error: \(error.localizedDescription, privacy: .private)"
                    )
                }
            }
            return valid.accessToken
        }

        // Pasted-token path: the raw token string.
        if let raw = try await keychain.getString(for: tokenRef) {
            return raw
        }

        throw TokenProviderError.noToken(accountLabel: account.label)
    }
}
