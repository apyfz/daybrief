@testable import ConnectorKit
import Foundation
import Testing

@Suite("PKCE S256")
struct PKCETests {
    /// RFC 7636 Appendix B reference vector: a known verifier maps to a known S256 challenge.
    @Test("Derives the RFC 7636 reference S256 challenge from the reference verifier")
    func referenceVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

        let pkce = PKCE(codeVerifier: verifier)
        #expect(pkce.codeVerifier == verifier)
        #expect(pkce.codeChallenge == expectedChallenge)
        #expect(pkce.codeChallengeMethod == "S256")
    }

    @Test("Generated verifier is base64url (no padding, URL-safe alphabet) and 43 chars")
    func generatedVerifierShape() {
        let pkce = PKCE.generate()
        // 32 bytes base64url, unpadded = 43 chars.
        #expect(pkce.codeVerifier.count == 43)
        #expect(!pkce.codeVerifier.contains("="))
        #expect(!pkce.codeVerifier.contains("+"))
        #expect(!pkce.codeVerifier.contains("/"))
        // Challenge derives from this exact verifier.
        #expect(pkce.codeChallenge == PKCE.challenge(for: pkce.codeVerifier))
    }

    @Test("Each generated pair is unique")
    func generatedUniqueness() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        #expect(a.codeVerifier != b.codeVerifier)
        #expect(a.codeChallenge != b.codeChallenge)
    }

    @Test("base64URLEncode strips padding and uses URL-safe alphabet")
    func base64URLEncoding() {
        // 0xFB 0xFF -> standard base64 "+/8=" -> url-safe unpadded "-_8"
        let encoded = PKCE.base64URLEncode(Data([0xFB, 0xFF]))
        #expect(encoded == "-_8")
    }
}
