import Foundation

/// Re-frames a byte-chunk stream into complete text lines.
///
/// The ``StreamingHTTPTransport`` already coalesces to newline boundaries, but a
/// single yielded chunk can still contain multiple `\n`-delimited lines (or a
/// trailing partial), so this splits robustly and strips trailing `\r` to handle
/// CRLF framing. Shared by both the SSE and NDJSON readers.
enum LineReader {
    /// Splits a stream of byte chunks into individual UTF-8 lines (newlines removed).
    static func lines(
        from bytes: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var pending = Data()
                do {
                    for try await chunk in bytes {
                        pending.append(chunk)
                        while let newlineIndex = pending.firstIndex(of: UInt8(ascii: "\n")) {
                            let lineData = pending[pending.startIndex ..< newlineIndex]
                            pending.removeSubrange(pending.startIndex ... newlineIndex)
                            continuation.yield(decodeLine(lineData))
                        }
                    }
                    if !pending.isEmpty {
                        continuation.yield(decodeLine(pending))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func decodeLine(_ data: Data) -> String {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }
}
