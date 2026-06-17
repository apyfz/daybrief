import Foundation

/// Describes how a user obtains and pastes a long-lived token for a
/// ``AuthStrategy/pastedUserToken(_:)`` connector (e.g. Slack).
///
/// Carries onboarding copy and an optional prefix hint so the connect UI can both
/// guide the user and validate the pasted value (e.g. reject an `xoxb-` bot token
/// when an `xoxp-` user token is required).
public struct TokenSpec: Sendable, Equatable, Hashable, Codable {
    /// Human-facing setup instructions (how to create the app, which scopes, where
    /// to copy the token from).
    public let setupInstructions: String
    /// The expected leading characters of a valid token (e.g. `"xoxp-"`), or `nil`
    /// if there's no stable prefix to validate against.
    public let tokenPrefixHint: String?

    /// Creates a token spec.
    public init(setupInstructions: String, tokenPrefixHint: String? = nil) {
        self.setupInstructions = setupInstructions
        self.tokenPrefixHint = tokenPrefixHint
    }

    /// Whether `token` matches ``tokenPrefixHint`` (always `true` when no hint is set).
    public func validatesPrefix(of token: String) -> Bool {
        guard let tokenPrefixHint, !tokenPrefixHint.isEmpty else { return true }
        return token.hasPrefix(tokenPrefixHint)
    }
}
