import Foundation

/// The character of a single day's brief, read by the synthesizer alongside the
/// lede and used to pick a tone-matched hero painting and per-edition accent.
///
/// The brief is editorial, not a dashboard: the same model pass that writes the
/// lede also judges the *shape* of the day, and that judgement drives the visual
/// mood (see `docs/design/brief-design-language.md`). The taxonomy is intentionally
/// small and robust — four broad temperaments rather than a long, brittle list —
/// so the model can pick reliably and the catalog can tag against it.
///
/// Decoding is forward-compatible: an unrecognized raw value (a future mood, or a
/// model that improvises) decodes to ``steady`` rather than throwing, so an older
/// or stricter taxonomy never breaks a persisted or model-supplied brief.
public enum BriefMood: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    /// An empty or light day — little pressing, room to breathe.
    case clear
    /// A normal, balanced day. The default when the day has no strong character.
    case steady
    /// A heavy day with many demands competing for attention.
    case busy
    /// A day defined by something big — a launch, a major meeting, a milestone.
    case eventful

    /// The mood used when none is supplied or an unknown one is decoded.
    public static let `default`: BriefMood = .steady

    /// Decodes a mood, mapping any unrecognized raw value to ``default`` so the
    /// taxonomy can grow (or the model can improvise) without breaking decode.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BriefMood(rawValue: raw) ?? .default
    }
}
