import Foundation

/// The provider-agnostic validate-and-repair safety net for structured output.
///
/// Every adapter's `completeStructured` routes its raw model output through
/// ``decode(_:as:input:schema:reAsk:)``, regardless of whether the provider claims
/// native schema enforcement — passthrough fidelity varies by underlying model
/// (design §8 / research "provider-agnostic repair fallback"). The repair ladder:
///
/// 1. Decode the raw string directly.
/// 2. On failure, extract the first balanced JSON span (strip fences/prose) and retry.
/// 3. On a second failure, re-ask the model **once** with the parse error appended,
///    extract again, and decode.
/// 4. Still failing → throw ``LLMError/structuredOutputUnrepairable(detail:)``.
enum StructuredOutputRepair {
    /// A closure that performs one corrective completion (`step 3`), returning the
    /// model's new raw text. Adapters pass their own `complete`-style call here.
    typealias ReAsk = @Sendable (_ correctivePrompt: String) async throws -> String

    /// Decodes `raw` into `T`, repairing and re-asking as needed.
    ///
    /// - Parameters:
    ///   - raw: The model's raw completion text.
    ///   - type: The target `Decodable` type.
    ///   - input: The original request (used to build the corrective re-ask prompt).
    ///   - schema: The schema the output should satisfy.
    ///   - reAsk: Performs the single bounded corrective completion.
    static func decode<T: Decodable & Sendable>(
        _ raw: String,
        as type: T.Type,
        input _: CompletionInput,
        schema: JSONSchema,
        reAsk: ReAsk
    ) async throws -> T {
        let decoder = JSONDecoder()

        // Steps 1 & 2: decode raw, then the extracted balanced span.
        if let value = tryDecode(raw, as: type, decoder: decoder) {
            return value
        }
        var lastError = "Initial output was not decodable JSON"
        if let span = JSONExtractor.extract(from: raw) {
            do {
                return try decoder.decode(type, from: Data(span.utf8))
            } catch {
                lastError = describe(error)
            }
        }

        // Step 3: one bounded corrective re-ask.
        //
        // Preserve the ORIGINAL parse diagnostic: the corrective re-ask is itself a
        // network call that can throw (provider 5xx / timeout / hang). If it does, the
        // useful signal is *why the model's first answer didn't parse* — not the transport
        // failure of the retry — so fold the re-ask failure into the give-up path while
        // keeping `originalParseError` in the thrown ``LLMError``.
        let originalParseError = lastError
        try Task.checkCancellation()
        let correctivePrompt = repairPrompt(originalError: originalParseError, schema: schema)
        let repaired: String
        do {
            repaired = try await reAsk(correctivePrompt)
        } catch is CancellationError {
            // Cancellation is not a repair failure — propagate it unchanged.
            throw CancellationError()
        } catch {
            // The re-ask itself failed; give up but surface the original parse error,
            // noting the re-ask couldn't complete.
            throw LLMError.structuredOutputUnrepairable(
                detail: "\(originalParseError) (corrective re-ask failed: \(describe(error)))"
            )
        }
        if let value = tryDecode(repaired, as: type, decoder: decoder) {
            return value
        }
        if let span = JSONExtractor.extract(from: repaired) {
            do {
                return try decoder.decode(type, from: Data(span.utf8))
            } catch {
                lastError = describe(error)
            }
        }

        // Step 4: give up.
        throw LLMError.structuredOutputUnrepairable(detail: lastError)
    }

    /// Builds the corrective prompt appended on the single re-ask attempt.
    static func repairPrompt(originalError: String, schema: JSONSchema) -> String {
        let schemaText = (try? PrettyJSON.string(from: schema.schema)) ?? ""
        return """
        Your previous response could not be parsed as valid JSON matching the required schema.
        Parser error: \(originalError)

        Respond with ONLY a single JSON value that conforms to this JSON Schema. \
        Do not include markdown code fences, explanations, or any text before or after the JSON.

        JSON Schema (\(schema.name)):
        \(schemaText)
        """
    }

    private static func tryDecode<T: Decodable>(
        _ text: String,
        as type: T.Type,
        decoder: JSONDecoder
    ) -> T? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private static func describe(_ error: any Error) -> String {
        if let decodingError = error as? DecodingError {
            return String(describing: decodingError)
        }
        return error.localizedDescription
    }
}
