@testable import ConnectorKit
import Foundation
import Testing

/// Exercises the pure HTTP-parsing helpers the loopback listener uses, including the
/// case where a request line arrives split across two `receive()` chunks (a real TCP
/// behavior the listener must accumulate rather than treat the first chunk as the whole
/// request). The accumulation loop's "is the line complete yet?" decision is driven by
/// ``LoopbackRedirectListener/containsLineTerminator(_:)``; once a terminator is present
/// ``LoopbackRedirectListener/firstRequestLine(from:)`` and ``parseRedirect(fromRequestLine:)``
/// recover the same redirect regardless of how the bytes were chunked.
@Suite("Loopback redirect listener parsing")
struct LoopbackRedirectListenerTests {
    @Test("a request line split across two chunks parses once reassembled")
    func splitRequestLineParses() throws {
        // The OAuth callback request line, deliberately broken mid-query — exactly the
        // kind of split a single connection can deliver as two TCP segments.
        let chunk1 = Data("GET /?code=4%2F0Ada".utf8)
        let chunk2 = Data("bc&state=xyz789 HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)

        // First chunk alone has no line terminator: the listener must keep accumulating.
        #expect(!LoopbackRedirectListener.containsLineTerminator(chunk1))

        // After the second chunk lands, the terminator is present and the buffer parses.
        var buffer = chunk1
        buffer.append(chunk2)
        #expect(LoopbackRedirectListener.containsLineTerminator(buffer))

        let requestLine = try #require(LoopbackRedirectListener.firstRequestLine(from: buffer))
        #expect(requestLine == "GET /?code=4%2F0Adabc&state=xyz789 HTTP/1.1")

        let redirect = LoopbackRedirectListener.parseRedirect(fromRequestLine: requestLine)
        #expect(redirect.code == "4/0Adabc") // percent-decoded
        #expect(redirect.state == "xyz789")
        #expect(redirect.error == nil)
    }

    @Test("the reassembled split line parses identically to the same line in one chunk")
    func splitMatchesWhole() throws {
        let whole = Data("GET /?code=abc&state=s HTTP/1.1\r\n\r\n".utf8)
        var split = Data("GET /?code=ab".utf8)
        split.append(Data("c&state=s HTTP/1.1\r\n\r\n".utf8))

        let lineWhole = try #require(LoopbackRedirectListener.firstRequestLine(from: whole))
        let lineSplit = try #require(LoopbackRedirectListener.firstRequestLine(from: split))
        #expect(lineWhole == lineSplit)
        #expect(LoopbackRedirectListener.parseRedirect(fromRequestLine: lineWhole)
            == LoopbackRedirectListener.parseRedirect(fromRequestLine: lineSplit))
    }

    @Test("a partial chunk with no terminator is not yet treated as complete")
    func partialChunkHasNoTerminator() {
        #expect(!LoopbackRedirectListener.containsLineTerminator(Data("GET /?code=partial".utf8)))
        #expect(LoopbackRedirectListener.containsLineTerminator(Data("GET / HTTP/1.1\r\n".utf8)))
        #expect(LoopbackRedirectListener.containsLineTerminator(Data("GET / HTTP/1.1\n".utf8)))
    }

    @Test("an error redirect line parses the provider error")
    func errorRedirectParses() throws {
        let line = try #require(
            LoopbackRedirectListener.firstRequestLine(
                from: Data("GET /?error=access_denied&state=s HTTP/1.1\r\n".utf8)
            )
        )
        let redirect = LoopbackRedirectListener.parseRedirect(fromRequestLine: line)
        #expect(redirect.error == "access_denied")
        #expect(redirect.code == nil)
    }
}
