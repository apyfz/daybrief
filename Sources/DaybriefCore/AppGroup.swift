import Foundation

/// The shared App Group container that bridges the unsandboxed host app and the
/// sandboxed desktop widget extension.
///
/// The host writes a small, display-safe brief snapshot here (the full ``Brief`` as
/// JSON plus a downsampled hero PNG); the sandboxed widget can read *nothing else*
/// on disk, so this container is its only data source. No OAuth tokens, no LLM key,
/// no SQLCipher key, and no raw connector payloads are ever written here — only the
/// already-redacted editorial fields the brief panel itself shows.
///
/// The group identifier is **not** hardcoded: it is read from the running bundle's
/// `AppGroupIdentifier` Info.plist key, which is set at build time to the team-
/// prefixed value (`$(TeamIdentifierPrefix)co.daybrief.shared`). This keeps the
/// literal Apple Team ID out of source and lets a contributor's own team flow through
/// automatically. In contexts without the key (tests, the snapshot CLI), every
/// accessor returns `nil` and callers degrade gracefully.
public enum AppGroup {
    /// The resolved App Group identifier from the running bundle's Info.plist, or
    /// `nil` when absent (a non-app-group build, tests, or the snapshot tool).
    public static var identifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              !id.isEmpty, !id.hasPrefix("$(")
        else { return nil }
        return id
    }

    /// The shared container URL for the App Group, or `nil` if the entitlement /
    /// identifier is unavailable (which is also the symptom of an unsigned / wrong-team
    /// build — `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil`).
    public static var containerURL: URL? {
        guard let id = identifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// The file names the host writes and the widget reads inside the container.
    public enum FileName {
        /// The full ``Brief`` encoded as JSON (carries masthead, lede, lead, hero meta —
        /// fields the persisted DB row drops, so the snapshot must be the in-memory Brief).
        public static let latestBrief = "latest-brief.json"
        /// The edition's hero, pre-downsampled host-side to stay under the widget memory ceiling.
        public static let latestHero = "latest-hero.png"
    }

    /// The URL for `name` inside the shared container, or `nil` if unavailable.
    public static func url(for name: String) -> URL? {
        containerURL?.appendingPathComponent(name)
    }
}
