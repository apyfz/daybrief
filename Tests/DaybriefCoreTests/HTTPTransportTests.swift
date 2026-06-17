@testable import DaybriefCore
import Foundation
import Testing

@Suite("HTTPTransport infra")
struct HTTPTransportTests {
    @Test("MockHTTPTransport records requests and replays stubs FIFO")
    func mockRecordsAndReplays() async throws {
        let mock = MockHTTPTransport()
        await mock.enqueue(data: Data("first".utf8), statusCode: 200)
        await mock.enqueue(data: Data("second".utf8), statusCode: 201)

        var r1 = try URLRequest(url: #require(URL(string: "https://api.example.com/a")))
        r1.httpMethod = "GET"
        let r2 = try URLRequest(url: #require(URL(string: "https://api.example.com/b")))

        let (d1, resp1) = try await mock.send(r1)
        let (d2, resp2) = try await mock.send(r2)

        #expect(String(decoding: d1, as: UTF8.self) == "first")
        #expect(resp1.statusCode == 200)
        #expect(String(decoding: d2, as: UTF8.self) == "second")
        #expect(resp2.statusCode == 201)

        let recorded = await mock.recordedRequests
        #expect(recorded.count == 2)
        #expect(recorded[0].url?.path == "/a")
        #expect(recorded[1].url?.path == "/b")
    }

    @Test("MockHTTPTransport throws when no stub is queued")
    func mockThrowsWhenEmpty() async throws {
        let mock = MockHTTPTransport()
        let request = try URLRequest(url: #require(URL(string: "https://api.example.com")))
        await #expect(throws: MockTransportError.self) {
            _ = try await mock.send(request)
        }
    }

    @Test("MockHTTPTransport replays a stubbed error")
    func mockReplaysFailure() async throws {
        let mock = MockHTTPTransport()
        await mock.enqueueFailure(TransportError.nonHTTPResponse)
        let request = try URLRequest(url: #require(URL(string: "https://api.example.com")))
        await #expect(throws: TransportError.nonHTTPResponse) {
            _ = try await mock.send(request)
        }
    }
}
