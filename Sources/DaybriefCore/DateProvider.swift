import Foundation

/// A source of "now", injected so scheduling and fetch-window logic are testable.
///
/// Production code uses ``SystemDateProvider``; tests use ``FixedDateProvider`` to
/// pin the clock and keep assertions deterministic (never read wall-clock in tests).
public protocol DateProvider: Sendable {
    /// The current instant.
    func now() -> Date
}

/// A ``DateProvider`` backed by the system clock.
public struct SystemDateProvider: DateProvider {
    /// Creates a system-clock date provider.
    public init() {}

    public func now() -> Date {
        Date()
    }
}

/// A ``DateProvider`` that always returns a fixed instant, for deterministic tests.
public struct FixedDateProvider: DateProvider {
    /// The instant this provider returns.
    public let fixed: Date

    /// Creates a fixed date provider pinned to `fixed`.
    public init(_ fixed: Date) {
        self.fixed = fixed
    }

    public func now() -> Date {
        fixed
    }
}
