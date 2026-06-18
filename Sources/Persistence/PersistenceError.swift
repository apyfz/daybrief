import Foundation

/// The single typed error surface for the `Persistence` module.
public enum PersistenceError: Error, Sendable, Equatable {
    /// A stored row could not be mapped back into its `DaybriefCore` value
    /// (e.g. an embedded JSON blob failed to decode, or a column held an
    /// unexpected value). Carries the failing entity name for diagnosis.
    case corruptRow(entity: String, detail: String)

    /// An encryption key was supplied but the active SQLite build cannot apply
    /// it (a non-SQLCipher build). The default SPM build is plain GRDB, so
    /// requesting encryption there is a programmer error, surfaced here rather
    /// than silently writing an unencrypted database.
    case encryptionUnavailable
}

extension PersistenceError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .corruptRow(entity, detail):
            return "Persistence.corruptRow(\(entity)): \(detail)"
        case .encryptionUnavailable:
            return "Persistence.encryptionUnavailable: an encryption key was provided "
                + "but this build is not SQLCipher-enabled (see docs/build/grdb-sqlcipher.md)."
        }
    }
}
