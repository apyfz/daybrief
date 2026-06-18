/// HTML escaping for untrusted brief content (titles, headlines, details, messages).
///
/// The brief is synthesized from user mail/message bodies, so every interpolated
/// string is treated as hostile and escaped before it reaches the HTML archive —
/// there is no path by which a crafted title or body can inject markup or script.
enum HTMLEscaping {
    /// Escapes a string for safe inclusion in HTML **text** and double-quoted
    /// **attribute** contexts.
    ///
    /// `&` is escaped first (so already-escaped entities aren't double-escaped from
    /// the *other* replacements), then `<`, `>`, `"`, and `'`. Escaping the quotes
    /// makes the same routine safe inside `="..."` attribute values (e.g. `href`).
    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
