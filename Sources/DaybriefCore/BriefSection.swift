import Foundation

/// A titled, ordered group of ``BriefEntry`` values within a ``Brief``.
public struct BriefSection: Sendable, Codable, Equatable, Hashable, Identifiable {
    /// Stable identity.
    public let id: UUID
    /// The section heading (e.g. "Priorities", "What slipped overnight").
    public let title: String
    /// The ordered entries in this section.
    public let entries: [BriefEntry]

    /// Creates a brief section.
    public init(id: UUID = UUID(), title: String, entries: [BriefEntry] = []) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}
