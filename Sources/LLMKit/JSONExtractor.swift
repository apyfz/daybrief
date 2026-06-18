import Foundation

/// Pulls a decodable JSON document out of a raw model completion.
///
/// Models wrap structured output in markdown fences, leading prose, or trailing
/// commentary even when asked not to. This strips that noise and returns the first
/// balanced `{…}` or `[…]` span, so the repair layer can attempt a decode before
/// giving up and re-asking.
enum JSONExtractor {
    /// Returns the most likely JSON substring of `raw`, or `nil` if none is found.
    ///
    /// Strategy: strip ```` ```json ```` / ```` ``` ```` fences, then scan for the
    /// first `{` or `[` and return the matching balanced span (string- and
    /// escape-aware so braces inside string literals don't confuse the scanner).
    static func extract(from raw: String) -> String? {
        let unfenced = stripCodeFences(raw)
        return balancedSpan(in: unfenced) ?? balancedSpan(in: raw)
    }

    private static func stripCodeFences(_ text: String) -> String {
        guard text.contains("```") else { return text }
        var result = text
        // Remove an opening fence with optional language tag, then the closing fence.
        if let openRange = result.range(of: #"```[a-zA-Z0-9]*\n?"#, options: .regularExpression) {
            result.removeSubrange(openRange)
        }
        if let closeRange = result.range(of: "```", options: .backwards) {
            result.removeSubrange(closeRange.lowerBound ..< result.endIndex)
        }
        return result
    }

    /// Returns the first balanced object/array span, respecting string literals.
    private static func balancedSpan(in text: String) -> String? {
        guard let startIndex = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return nil
        }
        let open = text[startIndex]
        let close: Character = (open == "{") ? "}" : "]"

        var depth = 0
        var inString = false
        var escaped = false
        var index = startIndex

        while index < text.endIndex {
            let char = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else {
                switch char {
                case "\"":
                    inString = true
                case open:
                    depth += 1
                case close:
                    depth -= 1
                    if depth == 0 {
                        let endIndex = text.index(after: index)
                        return String(text[startIndex ..< endIndex])
                    }
                default:
                    break
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
