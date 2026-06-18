import DaybriefCore
import Foundation
import Persistence

/// The persistence seam the orchestrator writes a finished brief through.
///
/// Abstracting persistence behind a protocol keeps ``BriefGenerator`` testable
/// without a database (tests inject an in-memory spy) while the production path
/// uses ``RepositoryBriefSink`` over `Persistence`'s `BriefRepository`.
public protocol BriefSink: Sendable {
    /// Persists the brief and the items it was synthesized from, and records the
    /// catch-up `lastBriefDate` so the scheduler suppresses a duplicate run today.
    ///
    /// - Parameters:
    ///   - brief: The finished brief.
    ///   - items: The normalized items it was synthesized from (linked for the
    ///     chat-context index).
    func persist(_ brief: Brief, items: [BriefItem]) async throws
}

/// The production ``BriefSink`` backed by `Persistence`'s `BriefRepository` +
/// `SettingsStore`.
///
/// Saves the brief, links its source items, and stamps the `lastBriefDate`
/// setting to the brief's generation day so ``BriefScheduler`` won't re-fire the
/// same calendar day.
public struct RepositoryBriefSink: BriefSink {
    private let repository: BriefRepository
    private let settings: SettingsStore
    private let calendar: Calendar

    /// Creates a sink over the given repository + settings store.
    ///
    /// - Parameters:
    ///   - repository: The brief repository (the GRDB DI seam).
    ///   - settings: The settings store, used to stamp `lastBriefDate`.
    ///   - calendar: Calendar used to derive the local day key (defaults to `.current`).
    public init(
        repository: BriefRepository,
        settings: SettingsStore,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.settings = settings
        self.calendar = calendar
    }

    public func persist(_ brief: Brief, items: [BriefItem]) async throws {
        do {
            try await repository.save(brief)
            try await repository.saveItems(items, briefID: brief.id)
            // Stamp the start-of-day so the once-per-day catch-up guard is timezone-stable.
            let day = calendar.startOfDay(for: brief.generatedAt)
            try await settings.setDate(day, forKey: SettingsStore.lastBriefDateKey)
        } catch {
            throw PipelineError.persistenceFailed(reason: "\(type(of: error))")
        }
    }
}
