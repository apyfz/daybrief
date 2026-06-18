import Foundation

/// A non-UI ``AuthPresenter`` for tests and the loopback flow.
///
/// Instead of opening a browser, it invokes a caller-supplied handler with the
/// authorization URL. In the loopback flow the handler can drive a fake "browser"
/// (e.g. issue the redirect to the local listener); for a custom-scheme flow it can
/// return a canned callback URL. Public so connector/OAuth test targets can reuse it.
public struct StubAuthPresenter: AuthPresenter {
    /// Called with the authorization URL (and callback scheme); returns the redirect URL.
    public let handler: @Sendable (_ authorizationURL: URL, _ callbackScheme: String?) async throws -> URL

    /// Creates a stub presenter from a handler closure.
    public init(
        handler: @escaping @Sendable (_ authorizationURL: URL, _ callbackScheme: String?) async throws -> URL
    ) {
        self.handler = handler
    }

    /// Creates a stub presenter that resolves with a fixed redirect URL, ignoring input.
    public init(returning redirect: URL) {
        handler = { _, _ in redirect }
    }

    public func present(authorizationURL: URL, callbackScheme: String?) async throws -> URL {
        try await handler(authorizationURL, callbackScheme)
    }
}
