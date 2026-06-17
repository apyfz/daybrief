import DaybriefCore
import Foundation

/// An injectable seam for *streaming* HTTP, complementing ``DaybriefCore/HTTPTransport``.
///
/// The buffered ``HTTPTransport`` cannot expose a byte stream, so streaming
/// completions need this separate seam. It yields raw bytes (as `Data` chunks);
/// the SSE / NDJSON line readers sit on top. Tests inject a scripted conformer to
/// drive the stream parsers offline.
public protocol StreamingHTTPTransport: Sendable {
    /// Opens `request` and returns the response plus an async byte stream of the body.
    ///
    /// Implementations must validate the status before the caller iterates: a
    /// non-2xx status should surface as a thrown ``LLMError/httpStatus(code:body:)``
    /// (with the drained body) rather than an empty stream. Cooperative
    /// cancellation must be honored.
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error>
}

/// The default ``StreamingHTTPTransport`` over `URLSession.bytes(for:)`.
///
/// Validates the HTTP status (draining the body into ``LLMError/httpStatus(code:body:)``
/// on non-2xx) before vending bytes. `URLSession`'s async byte stream honors
/// cooperative cancellation.
public struct URLSessionStreamingTransport: StreamingHTTPTransport {
    private let session: URLSession

    /// Creates a streaming transport over the given session (defaults to `.shared`).
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<Data, Error> {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.malformedResponse("Streaming response was not an HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            // Drain the error body for diagnostics, then throw.
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= 4096 { break }
            }
            throw LLMError.httpStatus(
                code: http.statusCode,
                body: String(decoding: body, as: UTF8.self)
            )
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // `bytes` is an async sequence of single bytes; coalesce into
                    // newline-delimited `Data` chunks so the line readers above
                    // receive complete frames even when split across reads.
                    var buffer = Data()
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == UInt8(ascii: "\n") {
                            continuation.yield(buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        continuation.yield(buffer)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
