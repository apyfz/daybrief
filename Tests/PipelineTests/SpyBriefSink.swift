import DaybriefCore
import Foundation
@testable import Pipeline

/// A ``BriefSink`` that records what it was asked to persist — no database.
///
/// `PipelineTests` does not link `Persistence`, so the orchestrator's persistence
/// path is verified through this in-memory spy (an `actor` for safe concurrent
/// recording).
actor SpyBriefSink: BriefSink {
    private(set) var persistedBriefs: [Brief] = []
    private(set) var persistedItems: [[BriefItem]] = []

    func persist(_ brief: Brief, items: [BriefItem]) async throws {
        persistedBriefs.append(brief)
        persistedItems.append(items)
    }
}

enum TestAccounts {
    /// Builds a single account for the given connector id.
    static func one(connectorId: ConnectorID, label: String? = nil) -> Account {
        Account(
            connectorId: connectorId,
            label: label ?? "\(connectorId.rawValue)@example.com",
            spaceKey: "work",
            secretRef: SecretRef(service: "co.daybrief.test", account: "\(connectorId.rawValue)-token")
        )
    }
}
