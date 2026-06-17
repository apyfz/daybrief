import Foundation

/// The static OAuth 2.0 parameters for a connector.
///
/// For the bring-your-own-client model (Google), `clientID`/`clientSecret` are the
/// user's own Desktop-client credentials — the "secret" is **not** confidential for
/// an installed app, so PKCE (``usesPKCE``) is the real protection for the code
/// exchange. Endpoints are the provider's authorization and token URLs.
public struct OAuthConfig: Sendable, Equatable, Hashable, Codable {
    /// The provider's authorization endpoint (e.g. `https://accounts.google.com/o/oauth2/v2/auth`).
    public let authEndpoint: URL
    /// The provider's token endpoint (e.g. `https://oauth2.googleapis.com/token`).
    public let tokenEndpoint: URL
    /// The OAuth client id (the user's own Desktop client in the BYO model).
    public let clientID: String
    /// The OAuth client secret, if the provider issues one. Not confidential for an
    /// installed app — present only because the token endpoint may still expect it.
    public let clientSecret: String?
    /// The requested scopes (space-delimited on the wire).
    public let scopes: [String]
    /// Whether to harden the flow with PKCE (`code_challenge_method=S256`).
    public let usesPKCE: Bool

    /// Creates an OAuth config.
    public init(
        authEndpoint: URL,
        tokenEndpoint: URL,
        clientID: String,
        clientSecret: String? = nil,
        scopes: [String],
        usesPKCE: Bool = true
    ) {
        self.authEndpoint = authEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.scopes = scopes
        self.usesPKCE = usesPKCE
    }
}
