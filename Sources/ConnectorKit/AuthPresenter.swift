import Foundation

/// Presents the OAuth consent UI in a system browser surface.
///
/// Implemented later in `AppFeature` over `ASWebAuthenticationSession` (which must run
/// on the main actor and own an `ASWebAuthenticationPresentationContextProviding`).
/// ``OAuthFlow`` depends on this abstraction so the flow logic stays nonisolated and
/// unit-testable — a test or the loopback path can supply a stub presenter.
///
/// For the loopback (Google Desktop) flow, the presenter is used **only** to open the
/// authorization URL in a trusted browser; the `http://127.0.0.1` redirect is captured
/// by ``LoopbackRedirectListener``, not by the presenter. In that mode `callbackScheme`
/// is `nil` and the returned `URL` is ignored by the caller (it may be a placeholder).
/// For the custom-scheme flow, `callbackScheme` is the registered scheme and the
/// returned `URL` is the captured redirect.
public protocol AuthPresenter: Sendable {
    /// Opens `authorizationURL` for consent and resolves with the captured redirect URL.
    ///
    /// - Parameters:
    ///   - authorizationURL: The provider authorization URL (with PKCE + state).
    ///   - callbackScheme: The custom callback scheme to match, or `nil` for the
    ///     loopback flow (where the listener captures the redirect instead).
    /// - Returns: The redirect URL the session received.
    /// - Throws: ``ConnectorError/userCancelled`` if the user dismisses the session.
    func present(authorizationURL: URL, callbackScheme: String?) async throws -> URL
}
