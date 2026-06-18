import DaybriefCore
import Foundation
import os

/// Runs the OAuth 2.0 installed-app flow and token refresh for a connector.
///
/// Drives the full ceremony: build the authorization URL (with PKCE + `state`), run the
/// ``AuthPresenter`` and/or ``LoopbackRedirectListener`` to capture the authorization
/// code, then exchange it at the token endpoint for an ``OAuthToken``. Also refreshes
/// expired access tokens. All HTTP goes through the injected ``DaybriefCore/HTTPTransport``
/// so the flow is testable offline; the ``DaybriefCore/DateProvider`` keeps `expiresAt`
/// computation deterministic.
///
/// This type is `Sendable` and stateless beyond its injected collaborators — one
/// instance can serve every account.
public struct OAuthFlow: Sendable {
    private let transport: any HTTPTransport
    private let dateProvider: any DateProvider
    private let stateGenerator: @Sendable () -> String
    private let logger = Logger(subsystem: "co.crispy.daybrief", category: "OAuthFlow")

    /// Creates an OAuth flow.
    ///
    /// - Parameters:
    ///   - transport: The HTTP seam used for the token exchange/refresh.
    ///   - dateProvider: Source of "now" for computing token expiry.
    ///   - stateGenerator: Produces the opaque `state` value (overridable for tests).
    ///     Defaults to a fresh 128-bit random base64url value.
    public init(
        transport: any HTTPTransport,
        dateProvider: any DateProvider = SystemDateProvider(),
        stateGenerator: (@Sendable () -> String)? = nil
    ) {
        self.transport = transport
        self.dateProvider = dateProvider
        self.stateGenerator = stateGenerator ?? Self.defaultStateGenerator
    }

    /// Produces a fresh 128-bit random `state` value, base64url-encoded.
    static let defaultStateGenerator: @Sendable () -> String = {
        PKCE.base64URLEncode(Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max) }))
    }

    // MARK: - Authorization URL

    /// Builds the provider authorization URL for `config` against `redirectURI`.
    ///
    /// Includes `response_type=code`, the space-delimited scopes, `access_type=offline`
    /// and `prompt=consent` (so Google returns a refresh token on every consent), and
    /// — when ``OAuthConfig/usesPKCE`` is set — the PKCE `code_challenge`. `loginHint`
    /// steers the account chooser for multi-account auth.
    ///
    /// - Throws: ``ConnectorError/other(reason:)`` if the URL cannot be formed.
    public func authorizationURL(
        config: OAuthConfig,
        redirectURI: URL,
        state: String,
        pkce: PKCE?,
        loginHint: String? = nil
    ) throws -> URL {
        guard var components = URLComponents(url: config.authEndpoint, resolvingAgainstBaseURL: false) else {
            throw ConnectorError.other(reason: "invalid authorization endpoint")
        }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        if config.usesPKCE, let pkce {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod))
        }
        if let loginHint {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw ConnectorError.other(reason: "could not build authorization URL")
        }
        return url
    }

    // MARK: - End-to-end loopback authorization

    /// Performs the full loopback authorization flow and returns the resulting token.
    ///
    /// Binds a ``LoopbackRedirectListener``, opens consent via `presenter`, captures the
    /// `?code=` on `127.0.0.1`, validates `state`, and exchanges the code (with the PKCE
    /// verifier) at the token endpoint. The listener is always torn down before return.
    ///
    /// - Throws: ``ConnectorError`` on any failure (auth, network, decode, cancellation).
    public func authorizeViaLoopback(
        config: OAuthConfig,
        presenter: any AuthPresenter,
        loginHint: String? = nil
    ) async throws -> OAuthToken {
        let pkce = config.usesPKCE ? PKCE.generate() : nil
        let state = stateGenerator()

        let listener = LoopbackRedirectListener()
        let redirectURI = try await listener.start()
        defer { Task { await listener.cancel() } }

        let authURL = try authorizationURL(
            config: config,
            redirectURI: redirectURI,
            state: state,
            pkce: pkce,
            loginHint: loginHint
        )

        // The presenter just opens the browser for the loopback flow; the listener
        // captures the redirect. Run both concurrently and take the listener's result.
        async let captured = listener.waitForRedirect()
        // Open consent. A user-dismiss surfaces as userCancelled; propagate it.
        _ = try await presenter.present(authorizationURL: authURL, callbackScheme: nil)

        let redirect = try await captured
        let code = try redirect.authorizationCode(expectedState: state)
        return try await exchangeCode(
            code,
            config: config,
            redirectURI: redirectURI,
            codeVerifier: pkce?.codeVerifier
        )
    }

    // MARK: - Token exchange & refresh

    /// Exchanges an authorization `code` for an ``OAuthToken`` at the token endpoint.
    public func exchangeCode(
        _ code: String,
        config: OAuthConfig,
        redirectURI: URL,
        codeVerifier: String?
    ) async throws -> OAuthToken {
        var form: [String: String] = [
            "client_id": config.clientID,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString,
        ]
        if let secret = config.clientSecret { form["client_secret"] = secret }
        if let codeVerifier { form["code_verifier"] = codeVerifier }
        return try await postToken(form, to: config.tokenEndpoint)
    }

    /// Refreshes an access token using a stored refresh token.
    ///
    /// Preserves the original `refreshToken` when the provider's response omits one
    /// (Google reuses the existing refresh token across refreshes).
    ///
    /// - Throws: ``ConnectorError/authFailed(reason:)`` if there is no refresh token.
    public func refresh(
        _ token: OAuthToken,
        config: OAuthConfig
    ) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else {
            throw ConnectorError.authFailed(reason: "no refresh token available")
        }
        var form: [String: String] = [
            "client_id": config.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        if let secret = config.clientSecret { form["client_secret"] = secret }
        let refreshed = try await postToken(form, to: config.tokenEndpoint)
        // Carry the original refresh token forward if the response didn't include one.
        if refreshed.refreshToken == nil {
            return OAuthToken(
                accessToken: refreshed.accessToken,
                refreshToken: refreshToken,
                expiresAt: refreshed.expiresAt,
                tokenType: refreshed.tokenType
            )
        }
        return refreshed
    }

    /// Returns a token guaranteed fresh: refreshes `token` if it's expired, else returns it.
    public func validToken(_ token: OAuthToken, config: OAuthConfig) async throws -> OAuthToken {
        guard token.isExpired(at: dateProvider.now()) else { return token }
        return try await refresh(token, config: config)
    }

    // MARK: - Private

    private func postToken(_ form: [String: String], to endpoint: URL) async throws -> OAuthToken {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formURLEncode(form).utf8)

        let data: Data
        do {
            (data, _) = try await transport.send(request)
        } catch let error as TransportError {
            throw Self.mapTransportError(error)
        } catch is CancellationError {
            throw ConnectorError.network(statusCode: nil, reason: "cancelled")
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw ConnectorError.network(statusCode: nil, reason: "cancelled")
        } catch {
            throw ConnectorError.network(statusCode: nil, reason: "token request failed")
        }

        do {
            let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expiresAt = payload.expires_in.map { dateProvider.now().addingTimeInterval(TimeInterval($0)) }
            return OAuthToken(
                accessToken: payload.access_token,
                refreshToken: payload.refresh_token,
                expiresAt: expiresAt,
                tokenType: payload.token_type ?? "Bearer"
            )
        } catch {
            throw ConnectorError.decodingFailed(reason: "malformed token response")
        }
    }

    /// Maps a transport error, treating a `400`/`401`/`403` token error as an auth failure.
    static func mapTransportError(_ error: TransportError) -> ConnectorError {
        switch error {
        case .nonHTTPResponse:
            return .network(statusCode: nil, reason: "non-HTTP response")
        case let .unacceptableStatus(code, body):
            // OAuth errors arrive as JSON {"error": "...", "error_description": "..."}.
            if let parsed = try? JSONDecoder().decode(TokenErrorResponse.self, from: body) {
                if code == 400 || code == 401 || code == 403 {
                    let detail = parsed.error_description.map { ": \($0)" } ?? ""
                    return .authFailed(reason: "\(parsed.error)\(detail)")
                }
                return .network(statusCode: code, reason: parsed.error)
            }
            if code == 401 || code == 403 {
                return .authFailed(reason: "HTTP \(code)")
            }
            return .network(statusCode: code, reason: "token endpoint error")
        }
    }

    /// Form-encodes a dictionary as `application/x-www-form-urlencoded`.
    static func formURLEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~") // RFC 3986 unreserved
        return form
            .sorted { $0.key < $1.key } // deterministic ordering for tests
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }
}

/// The decodable shape of a token-endpoint success response.
private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
}

/// The decodable shape of a token-endpoint error response.
private struct TokenErrorResponse: Decodable {
    let error: String
    let error_description: String?
}
