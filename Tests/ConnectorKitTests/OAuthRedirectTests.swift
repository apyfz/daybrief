@testable import ConnectorKit
import Foundation
import Testing

@Suite("OAuth redirect parsing")
struct OAuthRedirectTests {
    @Test("Parses code and state from a loopback redirect URL")
    func parsesCodeAndState() throws {
        let url = try #require(URL(string: "http://127.0.0.1:54321/?code=4%2F0Adabc&state=xyz789&scope=openid"))
        let redirect = try #require(OAuthRedirect.parse(url: url))
        #expect(redirect.code == "4/0Adabc") // percent-decoded
        #expect(redirect.state == "xyz789")
        #expect(redirect.error == nil)
    }

    @Test("Parses a raw query string with a leading question mark")
    func parsesRawQuery() {
        let redirect = OAuthRedirect.parse(query: "?code=abc&state=s1")
        #expect(redirect.code == "abc")
        #expect(redirect.state == "s1")
    }

    @Test("Parses a provider error and description")
    func parsesError() {
        let redirect = OAuthRedirect.parse(query: "error=access_denied&error_description=The+user+declined")
        #expect(redirect.code == nil)
        #expect(redirect.error == "access_denied")
        #expect(redirect.errorDescription == "The user declined")
    }

    @Test("authorizationCode returns the code when state matches")
    func authorizationCodeSuccess() throws {
        let redirect = OAuthRedirect.parse(query: "code=good&state=expected")
        let code = try redirect.authorizationCode(expectedState: "expected")
        #expect(code == "good")
    }

    @Test("authorizationCode throws userCancelled on access_denied")
    func authorizationCodeAccessDenied() {
        let redirect = OAuthRedirect.parse(query: "error=access_denied")
        #expect(throws: ConnectorError.userCancelled) {
            _ = try redirect.authorizationCode(expectedState: "expected")
        }
    }

    @Test("authorizationCode throws authFailed on state mismatch")
    func authorizationCodeStateMismatch() {
        let redirect = OAuthRedirect.parse(query: "code=good&state=wrong")
        #expect(throws: ConnectorError.self) {
            _ = try redirect.authorizationCode(expectedState: "expected")
        }
    }

    @Test("authorizationCode throws invalidRedirect when code is missing")
    func authorizationCodeMissingCode() {
        let redirect = OAuthRedirect.parse(query: "state=expected")
        #expect(throws: ConnectorError.self) {
            _ = try redirect.authorizationCode(expectedState: "expected")
        }
    }

    @Test("Extracts and parses an HTTP request line into a redirect")
    func parsesFromRequestLine() throws {
        let data = Data("GET /?code=fromline&state=st HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        let line = try? #require(LoopbackRedirectListener.firstRequestLine(from: data))
        #expect(line == "GET /?code=fromline&state=st HTTP/1.1")

        let redirect = try LoopbackRedirectListener.parseRedirect(fromRequestLine: #require(line))
        #expect(redirect.code == "fromline")
        #expect(redirect.state == "st")
    }

    @Test("Request line with no query yields an empty (no-code) redirect")
    func requestLineNoQuery() {
        let redirect = LoopbackRedirectListener.parseRedirect(fromRequestLine: "GET / HTTP/1.1")
        #expect(redirect.code == nil)
        #expect(redirect.state == nil)
        #expect(redirect.error == nil)
    }
}
