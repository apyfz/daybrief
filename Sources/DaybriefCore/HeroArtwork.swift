import Foundation

/// A public-domain fine-art painting used as a brief edition's hero image.
///
/// v0 ships a small curated catalog of CC0 / public-domain works (Met & Art Institute
/// open access) bundled as app assets and selected deterministically by date — no network
/// art fetch, so the brief stays private and offline. See `docs/design/brief-design-language.md`.
public struct HeroArtwork: Sendable, Codable, Equatable, Hashable {
    /// The bundled image asset name (resolved against the app bundle in `AppFeature`).
    public let assetName: String
    /// Painting title, for the credit line.
    public let title: String
    /// Artist name, for the credit line.
    public let artist: String
    /// Year or period, for the credit line (e.g. "1873"); `nil` if unknown.
    public let year: String?
    /// Public source/attribution URL (museum open-access page), if any.
    public let sourceURL: URL?

    /// Creates a hero artwork reference.
    public init(
        assetName: String,
        title: String,
        artist: String,
        year: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.assetName = assetName
        self.title = title
        self.artist = artist
        self.year = year
        self.sourceURL = sourceURL
    }

    /// A single-line credit, e.g. "The Card Players — Paul Cézanne, 1890–92".
    public var creditLine: String {
        let base = "\(title) — \(artist)"
        return year.map { "\(base), \($0)" } ?? base
    }
}
