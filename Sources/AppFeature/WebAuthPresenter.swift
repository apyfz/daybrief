import AppKit
import AuthenticationServices
import ConnectorKit
import Foundation

/// The `AppFeature` implementation of ``ConnectorKit/AuthPresenter`` over
/// `ASWebAuthenticationSession`.
///
/// Two roles, matching the two OAuth strategies (design §11):
/// - **Loopback (Google Desktop) flow** — `callbackScheme` is `nil`. The session is
///   used only to open the consent page in a trusted browser surface; the
///   `http://127.0.0.1` redirect is captured by ``ConnectorKit/LoopbackRedirectListener``,
///   not here. `ASWebAuthenticationSession` cannot receive an `http` loopback redirect,
///   so we open the URL and return a placeholder the caller ignores.
/// - **Custom-scheme flow** — `callbackScheme` is set; the session captures and returns
///   the redirect URL directly.
///
/// Runs on the main actor and owns the presentation anchor, per
/// `ASWebAuthenticationSession`'s requirements.
@MainActor
public final class WebAuthPresenter: NSObject, AuthPresenter {
    /// Creates a web-auth presenter.
    override public init() {
        super.init()
    }

    public func present(authorizationURL: URL, callbackScheme: String?) async throws -> URL {
        // Loopback flow: just open the consent page; the listener captures the
        // redirect. ASWebAuthenticationSession can't catch an http loopback, so we
        // open the URL in the user's browser and return a placeholder.
        guard let callbackScheme else {
            NSWorkspace.shared.open(authorizationURL)
            return authorizationURL
        }

        // Custom-scheme flow: the session captures the redirect itself.
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    if case ASWebAuthenticationSessionError.canceledLogin = error {
                        continuation.resume(throwing: ConnectorError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ConnectorError.invalidRedirect(reason: "no callback URL"))
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: ConnectorError.other(reason: "could not start auth session"))
            }
        }
    }
}

extension WebAuthPresenter: ASWebAuthenticationPresentationContextProviding {
    public nonisolated func presentationAnchor(
        for _: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        // The window the system attaches the auth sheet to. Reading the key/main
        // window must happen on the main thread; this delegate callback is invoked
        // on the main thread by ASWebAuthenticationSession.
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
