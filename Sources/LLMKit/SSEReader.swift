import Foundation

/// A Server-Sent-Events frame parser shared by the SSE-based adapters.
///
/// Reads `data:` lines from the line stream, ignores keep-alive comments
/// (lines beginning with `:`) and `event:`/`id:`/`retry:` fields, and stops on the
/// OpenAI/OpenRouter `[DONE]` sentinel. The per-frame JSON payload is handed back
/// as a raw string for the adapter to decode into its provider-specific delta shape
/// (Anthropic, OpenAI, Gemini differ on where the text delta lives).
enum SSEReader {
    /// Yields the JSON payload string of each `data:` frame.
    ///
    /// - Parameter bytes: The byte-chunk stream from a ``StreamingHTTPTransport``.
    /// - Returns: A stream of `data:` payloads (the `[DONE]` sentinel ends the stream).
    static func frames(
        from bytes: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in LineReader.lines(from: bytes) {
                        // Comments / keep-alives.
                        if line.isEmpty || line.hasPrefix(":") { continue }
                        guard line.hasPrefix("data:") else { continue }
                        // Tolerate both `data:` and `data: ` framing.
                        var payload = Substring(line.dropFirst(5))
                        if payload.hasPrefix(" ") { payload = payload.dropFirst() }
                        if payload == "[DONE]" { break }
                        continuation.yield(String(payload))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// A newline-delimited-JSON frame reader for Ollama, the sibling of ``SSEReader``.
///
/// Ollama streams one JSON object per line (no `data:` prefix, no `[DONE]`
/// sentinel); the final object carries `"done": true`. Each non-empty line is
/// yielded verbatim for the adapter to decode.
enum NDJSONReader {
    /// Yields each non-empty JSON line from the byte stream.
    static func frames(
        from bytes: AsyncThrowingStream<Data, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in LineReader.lines(from: bytes) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty { continue }
                        continuation.yield(trimmed)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
