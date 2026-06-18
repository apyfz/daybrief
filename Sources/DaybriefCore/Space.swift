import Foundation

/// A user-defined grouping of connections (e.g. Work, Personal, or a custom tag).
///
/// A Space is just a tag carried by each ``Account``; the brief can be filtered
/// or split by Space so personal mail never blends into a work brief.
/// Per-Space schedules/prompts are a later refinement (the data model leaves room).
public struct Space: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// The stable key referenced by ``Account/spaceKey`` (e.g. `"work"`, `"personal"`).
    public let key: String
    /// The human-facing name (e.g. `"Work"`).
    public let displayName: String

    /// Creates a space.
    public init(id: UUID = UUID(), key: String, displayName: String) {
        self.id = id
        self.key = key
        self.displayName = displayName
    }
}
