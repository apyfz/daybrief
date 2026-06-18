@testable import ConnectorKit
import DaybriefCore
import Foundation
import Testing

@Suite("OAuthFlow (offline)")
struct OAuthFlowTests {
    private func makeConfig(pkce: Bool = true) -> OAuthConfig {
        OAuthConfig(
            authEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: "client-123",
            clientSecret: "secret-xyz",
            scopes: ["https://www.googleapis.com/auth/calendar.readonly", "openid"],
            usesPKCE: pkce
        )
    }

    @Test("authorizationURL includes scopes, PKCE, state, and offline-access params")
    func buildsAuthorizationURL() throws {
        let flow = OAuthFlow(transport: MockHTTPTransport())
        let pkce = PKCE(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = try flow.authorizationURL(
            config: makeConfig(),
            redirectURI: #require(URL(string: "http://127.0.0.1:5000/")),
            state: "state-1",
            pkce: pkce,
            loginHint: "alim@crispy.studio"
        )
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let map = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })

        #expect(map["client_id"] == "client-123")
        #expect(map["redirect_uri"] == "http://127.0.0.1:5000/")
        #expect(map["response_type"] == "code")
        #expect(map["scope"] == "https://www.googleapis.com/auth/calendar.readonly openid")
        #expect(map["access_type"] == "offline")
        #expect(map["prompt"] == "consent")
        #expect(map["state"] == "state-1")
        #expect(map["code_challenge"] == pkce.codeChallenge)
        #expect(map["code_challenge_method"] == "S256")
        #expect(map["login_hint"] == "alim@crispy.studio")
    }

    @Test("authorizationURL omits PKCE params when usesPKCE is false")
    func omitsPKCEWhenDisabled() throws {
        let flow = OAuthFlow(transport: MockHTTPTransport())
        let url = try flow.authorizationURL(
            config: makeConfig(pkce: false),
            redirectURI: #require(URL(string: "http://127.0.0.1:5000/")),
            state: "s",
            pkce: nil
        )
        let names = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name)
        #expect(!names.contains("code_challenge"))
        #expect(!names.contains("code_challenge_method"))
    }

    @Test("exchangeCode posts the code and decodes the returned token with expiry")
    func exchangeCodeDecodesToken() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let transport = MockHTTPTransport()
        let body = """
        {"access_token":"ya29.access","refresh_token":"1//refresh","expires_in":3600,"token_type":"Bearer"}
        """
        await transport.enqueue(data: Data(body.utf8), statusCode: 200)

        let flow = OAuthFlow(transport: transport, dateProvider: FixedDateProvider(now))
        let token = try await flow.exchangeCode(
            "auth-code",
            config: makeConfig(),
            redirectURI: #require(URL(string: "http://127.0.0.1:5000/")),
            codeVerifier: "verifier-abc"
        )

        #expect(token.accessToken == "ya29.access")
        #expect(token.refreshToken == "1//refresh")
        #expect(token.tokenType == "Bearer")
        #expect(token.expiresAt == now.addingTimeInterval(3600))

        // The request carried the expected form body.
        let recorded = await transport.recordedRequests
        let sent = try #require(recorded.first)
        let bodyString = String(decoding: sent.httpBody ?? Data(), as: UTF8.self)
        #expect(bodyString.contains("grant_type=authorization_code"))
        #expect(bodyString.contains("code=auth-code"))
        #expect(bodyString.contains("code_verifier=verifier-abc"))
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    }

    @Test("refresh preserves the original refresh token when the response omits one")
    func refreshPreservesRefreshToken() async throws {
        let transport = MockHTTPTransport()
        let body = #"{"access_token":"new.access","expires_in":3599,"token_type":"Bearer"}"#
        await transport.enqueue(data: Data(body.utf8), statusCode: 200)

        let flow = OAuthFlow(transport: transport, dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 0)))
        let stale = OAuthToken(accessToken: "old", refreshToken: "keep-me", expiresAt: nil)
        let refreshed = try await flow.refresh(stale, config: makeConfig())

        #expect(refreshed.accessToken == "new.access")
        #expect(refreshed.refreshToken == "keep-me")
    }

    @Test("token endpoint 400 invalid_grant maps to authFailed")
    func invalidGrantMapsToAuth() async throws {
        let transport = MockHTTPTransport()
        let body = #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#
        await transport.enqueue(.failure(TransportError.unacceptableStatus(code: 400, body: Data(body.utf8))))

        let flow = OAuthFlow(transport: transport)
        await #expect(throws: ConnectorError.self) {
            _ = try await flow.refresh(
                OAuthToken(accessToken: "a", refreshToken: "r"),
                config: makeConfig()
            )
        }
        // Confirm the mapped kind is .auth.
        let mapped = OAuthFlow.mapTransportError(.unacceptableStatus(code: 400, body: Data(body.utf8)))
        #expect(mapped.kind == .auth)
    }

    @Test("validToken refreshes only when expired")
    func validTokenRefreshesWhenExpired() async throws {
        let now = Date(timeIntervalSince1970: 10000)
        let transport = MockHTTPTransport()
        await transport.enqueue(data: Data(#"{"access_token":"refreshed","expires_in":3600}"#.utf8), statusCode: 200)
        let flow = OAuthFlow(transport: transport, dateProvider: FixedDateProvider(now))

        // Fresh token: returned unchanged, no transport call.
        let fresh = OAuthToken(accessToken: "fresh", refreshToken: "r", expiresAt: now.addingTimeInterval(3600))
        let unchanged = try await flow.validToken(fresh, config: makeConfig())
        #expect(unchanged.accessToken == "fresh")
        #expect(await transport.recordedRequests.isEmpty)

        // Expired token: refreshed.
        let expired = OAuthToken(accessToken: "old", refreshToken: "r", expiresAt: now.addingTimeInterval(-10))
        let renewed = try await flow.validToken(expired, config: makeConfig())
        #expect(renewed.accessToken == "refreshed")
    }

    @Test("formURLEncode percent-encodes and orders keys deterministically")
    func formEncoding() {
        let encoded = OAuthFlow.formURLEncode(["b": "two", "a": "x y", "c": "a+b"])
        #expect(encoded == "a=x%20y&b=two&c=a%2Bb")
    }
}
