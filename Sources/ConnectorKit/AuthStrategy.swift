import Foundation

/// How a connector authenticates.
///
/// Each connector declares its strategy so onboarding and ``OAuthFlow`` know which
/// auth ceremony to run. Google uses ``loopbackOAuth(_:)`` (a `127.0.0.1` listener,
/// because `ASWebAuthenticationSession` cannot receive an `http` loopback redirect);
/// Slack uses ``pastedUserToken(_:)`` (no OAuth dance — the user pastes an `xoxp-`
/// token); ``customSchemeOAuth(_:)`` is reserved for future providers that register
/// a custom URL scheme and can use `ASWebAuthenticationSession` end-to-end.
public enum AuthStrategy: Sendable, Equatable {
    /// OAuth 2.0 installed-app flow with a `127.0.0.1` loopback redirect + PKCE.
    case loopbackOAuth(OAuthConfig)
    /// No OAuth flow — the user pastes a long-lived user token (e.g. Slack `xoxp-`).
    case pastedUserToken(TokenSpec)
    /// OAuth 2.0 flow with a custom-scheme redirect (reserved for future providers).
    case customSchemeOAuth(OAuthConfig)
}

public extension AuthStrategy {
    /// The wrapped ``OAuthConfig`` for the OAuth-based strategies, else `nil`.
    var oauthConfig: OAuthConfig? {
        switch self {
        case let .loopbackOAuth(config), let .customSchemeOAuth(config):
            return config
        case .pastedUserToken:
            return nil
        }
    }

    /// The wrapped ``TokenSpec`` for ``pastedUserToken(_:)``, else `nil`.
    var tokenSpec: TokenSpec? {
        if case let .pastedUserToken(spec) = self { return spec }
        return nil
    }
}
