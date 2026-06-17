import DaybriefCore
import Foundation

/// The bundled catalog of public-domain / CC0 fine-art paintings used as a brief
/// edition's hero image, and a deterministic by-date selector.
///
/// Every work here is a public-domain painting released under The Metropolitan
/// Museum of Art's Open Access program (CC0), so it is license-safe to bundle and
/// ship offline (design §brief-design-language). Each entry was fetched from the
/// Met Collection API, confirmed `isPublicDomain == true`, downscaled to ~1200px,
/// and bundled as `App/Assets.xcassets/Art/<assetName>.imageset/`. `assetName` is
/// the bundle asset name `AppFeature` resolves via `NSImage(named:)` (e.g.
/// `"vermeer-water-pitcher"`); the imageset name matches it exactly. `sourceURL`
/// points at the Met object page, and the title/artist/year credit the actual
/// fetched work.
///
/// Selection is deterministic by calendar day (day-of-year modulo the catalog
/// count) so a given date always shows the same painting — stable, offline, and
/// unit-testable.
public enum HeroArtworkCatalog {
    /// The curated catalog. Order is stable; the date selector indexes into it,
    /// so do not reorder without accepting that each day's painting shifts.
    public static let all: [HeroArtwork] = tagged.map(\.artwork)

    /// A catalog entry: a ``HeroArtwork`` plus the day-moods it suits.
    ///
    /// Mood is a *catalog-level* concern (the painting's temperament against the
    /// day), not a property of the artwork value itself, so it is paired here rather
    /// than baked into `HeroArtwork`. Each artwork also carries a curated `accentHex`
    /// sampled from the painting — moderate saturation so it reads as a text/badge
    /// color on the warm cream background.
    struct Tagged {
        let artwork: HeroArtwork
        let moods: Set<BriefMood>
    }

    /// The mood-tagged catalog. Order is stable; the date selectors index into it.
    static let tagged: [Tagged] = [
        Tagged(
            artwork: HeroArtwork(
                assetName: "pissarro-tuileries-winter",
                title: "The Garden of the Tuileries on a Winter Afternoon",
                artist: "Camille Pissarro",
                year: "1899",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437314"),
                accentHex: "#5E7287" // muted winter slate-blue
            ),
            moods: [.clear, .steady]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "sisley-marly-le-roi",
                title: "View of Marly-le-Roi from Coeur-Volant",
                artist: "Alfred Sisley",
                year: "1876",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437682"),
                accentHex: "#6E7F5B" // sage / meadow green
            ),
            moods: [.clear, .steady]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "renoir-girls-piano",
                title: "Two Young Girls at the Piano",
                artist: "Auguste Renoir",
                year: "1892",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/459112"),
                accentHex: "#B06A55" // warm terracotta rose
            ),
            moods: [.steady, .clear]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "vangogh-wheat-cypresses",
                title: "Wheat Field with Cypresses",
                artist: "Vincent van Gogh",
                year: "1889",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/436535"),
                accentHex: "#2F7A6B" // turbulent cypress teal-green
            ),
            moods: [.eventful, .busy]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "seurat-grande-jatte-study",
                title: "Study for \"A Sunday on La Grande Jatte\"",
                artist: "Georges Seurat",
                year: "1884",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437658"),
                accentHex: "#A8772E" // sunlit ochre
            ),
            moods: [.steady, .busy]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "turner-whalers",
                title: "Whalers",
                artist: "Joseph Mallord William Turner",
                year: "ca. 1845",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437854"),
                accentHex: "#C06A2E" // Turner sunset orange
            ),
            moods: [.eventful, .busy]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "hokusai-great-wave",
                title: "Under the Wave off Kanagawa (The Great Wave)",
                artist: "Katsushika Hokusai",
                year: "ca. 1830–32",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/45434"),
                accentHex: "#2C5A78" // Prussian wave blue
            ),
            moods: [.eventful, .busy]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "degas-dance-class",
                title: "The Dance Class",
                artist: "Edgar Degas",
                year: "1874",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/438817"),
                accentHex: "#9C7B3A" // worn rehearsal-room gold
            ),
            moods: [.busy, .eventful]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "renoir-charpentier",
                title: "Madame Georges Charpentier and Her Children",
                artist: "Auguste Renoir",
                year: "1878",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/438815"),
                accentHex: "#8C3F46" // formal deep burgundy
            ),
            moods: [.eventful, .steady]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "cezanne-card-players",
                title: "The Card Players",
                artist: "Paul Cézanne",
                year: "1890–92",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/435868"),
                accentHex: "#7A6A3C" // quiet olive umber
            ),
            moods: [.steady, .clear]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "homer-northeaster",
                title: "Northeaster",
                artist: "Winslow Homer",
                year: "1895",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/11130"),
                accentHex: "#3A5C6E" // deep sea blue-grey
            ),
            moods: [.eventful, .busy]
        ),
        Tagged(
            artwork: HeroArtwork(
                assetName: "vermeer-water-pitcher",
                title: "Young Woman with a Water Pitcher",
                artist: "Johannes Vermeer",
                year: "ca. 1662",
                sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437881"),
                accentHex: "#B58A2E" // Vermeer ochre-gold
            ),
            moods: [.clear, .steady]
        ),
    ]

    /// Returns the hero artwork for `date`, chosen deterministically by the local
    /// day-of-year so a given calendar day is stable.
    ///
    /// - Parameters:
    ///   - date: The edition date.
    ///   - calendar: The calendar used to derive the day-of-year (injectable for
    ///     deterministic tests; defaults to `.current`).
    /// - Returns: A catalog entry; never `nil` because the catalog is non-empty.
    public static func heroForDate(_ date: Date, calendar: Calendar = .current) -> HeroArtwork {
        // Catalog is a non-empty compile-time literal; the guard documents the
        // invariant and keeps this total even if the list is later edited down.
        guard !all.isEmpty else {
            return HeroArtwork(assetName: "", title: "", artist: "")
        }
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        // ordinality is 1-based; shift to 0-based before the modulo.
        let index = (dayOfYear - 1) % all.count
        return all[index]
    }

    /// Returns a hero painting whose temperament matches `mood`, chosen
    /// deterministically by the local day-of-year among the matching works.
    ///
    /// This is the tone-matched selector: the synthesizer reads the day's mood and
    /// the brief's hero art reflects that character rather than being purely random
    /// (design §brief-design-language, "tone-matched hero art"). When `mood` is `nil`
    /// or no painting carries it, it falls back to the existing date-based pick so a
    /// hero is always returned and the result stays stable for a given day.
    ///
    /// - Parameters:
    ///   - mood: The day's mood, or `nil` to use the plain date-based pick.
    ///   - date: The edition date (drives the deterministic choice within the match set).
    ///   - calendar: The calendar used to derive the day-of-year (injectable for tests).
    /// - Returns: A catalog entry; never `nil` because the catalog is non-empty.
    public static func heroForMood(
        _ mood: BriefMood?,
        date: Date,
        calendar: Calendar = .current
    ) -> HeroArtwork {
        guard let mood else {
            return heroForDate(date, calendar: calendar)
        }
        // Preserve catalog order so selection is stable and matches the by-date
        // intuition (same painting on the same day for the same mood).
        let matches = tagged.filter { $0.moods.contains(mood) }.map(\.artwork)
        guard !matches.isEmpty else {
            return heroForDate(date, calendar: calendar)
        }
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = (dayOfYear - 1) % matches.count
        return matches[index]
    }
}
