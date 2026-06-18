import CryptoKit
import Foundation

/// A PKCE (Proof Key for Code Exchange, RFC 7636) S256 pair.
///
/// Generate one per authorization with ``generate()``: the ``codeChallenge`` is sent
/// on the authorization request (`code_challenge` + `code_challenge_method=S256`) and
/// the ``codeVerifier`` is sent on the token exchange (`code_verifier`). The verifier
/// is high-entropy secret material — never log it `.public`.
public struct PKCE: Sendable, Equatable, Hashable {
    /// The high-entropy random verifier (43–128 unreserved characters).
    public let codeVerifier: String
    /// The S256 challenge: `BASE64URL(SHA256(codeVerifier))`.
    public let codeChallenge: String
    /// The challenge method — always `"S256"`.
    public let codeChallengeMethod = "S256"

    /// Creates a PKCE pair, deriving the S256 challenge from `codeVerifier`.
    ///
    /// The verifier is used verbatim; callers normally use ``generate()`` instead,
    /// which produces a fresh random verifier. Exposed for deterministic tests.
    public init(codeVerifier: String) {
        self.codeVerifier = codeVerifier
        codeChallenge = Self.challenge(for: codeVerifier)
    }

    /// Generates a fresh PKCE pair with a cryptographically-random 32-byte verifier.
    ///
    /// 32 random bytes base64url-encoded yields a 43-character verifier, the RFC 7636
    /// minimum length, with full 256-bit entropy.
    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // SecRandomCopyBytes only fails on a misuse we don't commit (bad params);
        // fall back to SystemRandomNumberGenerator so generation cannot trap.
        if status != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            bytes = (0 ..< 32).map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        return PKCE(codeVerifier: base64URLEncode(Data(bytes)))
    }

    /// Computes the S256 code challenge for a given verifier.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(digest))
    }

    /// Base64URL-encodes (RFC 4648 §5) without padding: `+`→`-`, `/`→`_`, strip `=`.
    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
