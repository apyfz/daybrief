import Foundation
import Security

/// Errors thrown by the ``KeychainStore``.
///
/// Wraps the raw `OSStatus` from the underlying `SecItem*` calls so callers can
/// inspect or branch on specific conditions (e.g. ``itemNotFound`` →
/// "not connected yet", ``interactionNotAllowed`` → "keychain locked, retry
/// after unlock") without re-deriving `OSStatus` constants at call sites.
public enum SecretsError: Error, Sendable, Equatable {
    /// No item exists for the requested ``SecretRef`` (`errSecItemNotFound`).
    ///
    /// `getData`/`getString`/`getCodable` return `nil` for this rather than
    /// throwing; it is surfaced as an error only when an item was expected.
    case itemNotFound

    /// The keychain is locked and a read could not proceed (`errSecInteractionNotAllowed`).
    ///
    /// Possible right at boot before the first unlock. Callers that run after
    /// wake (e.g. the scheduled-brief generator) should treat this as a
    /// transient "waiting for unlock" state, not as "no credentials".
    case interactionNotAllowed

    /// A stored value could not be interpreted as the requested type
    /// (e.g. non-UTF-8 bytes for `getString`, or a `Decodable` failure).
    case malformedData

    /// `SecRandomCopyBytes` failed to produce random key material.
    case randomGenerationFailed(OSStatus)

    /// A wrapping of any other `OSStatus` returned by a `SecItem*` call.
    ///
    /// `message` is the system-provided description when available
    /// (`SecCopyErrorMessageString`); it contains no secret material.
    case unexpectedStatus(OSStatus, message: String?)

    /// Maps an arbitrary `OSStatus` to the most specific case.
    static func from(_ status: OSStatus) -> SecretsError {
        switch status {
        case errSecItemNotFound:
            return .itemNotFound
        case errSecInteractionNotAllowed:
            return .interactionNotAllowed
        default:
            let message = SecCopyErrorMessageString(status, nil) as String?
            return .unexpectedStatus(status, message: message)
        }
    }
}
