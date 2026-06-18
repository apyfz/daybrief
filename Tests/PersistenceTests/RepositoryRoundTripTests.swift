import DaybriefCore
import Foundation
@testable import Persistence
import Testing

@Suite("Repository CRUD round-trips")
struct RepositoryRoundTripTests {
    // MARK: - Fixtures

    private func makeConnection() -> Connection {
        Connection(
            connectorId: .gmail,
            displayName: "Gmail",
            accounts: [
                Account(
                    connectorId: .gmail,
                    label: "alim@crispy.studio",
                    spaceKey: "work",
                    secretRef: SecretRef(service: "com.daybrief.gmail.token", account: "alim@crispy.studio")
                ),
                Account(
                    connectorId: .gmail,
                    label: "alim@personal.com",
                    spaceKey: "personal",
                    secretRef: SecretRef(service: "com.daybrief.gmail.token", account: "alim@personal.com")
                ),
            ],
            isEnabled: true
        )
    }

    private func makeBrief() -> Brief {
        let itemID = UUID()
        return Brief(
            generatedAt: Date(timeIntervalSince1970: 1_750_000_500),
            spaceFilter: "work",
            sections: [
                BriefSection(
                    title: "Priorities",
                    entries: [
                        BriefEntry(
                            headline: "Reply to Jesse about Q3",
                            detail: "He's blocked on your sign-off.",
                            url: URL(string: "https://example.com/1"),
                            priority: 1,
                            sourceItemIDs: [itemID]
                        ),
                        BriefEntry(headline: "Standup at 10:00"),
                    ]
                ),
                BriefSection(title: "What slipped", entries: []),
            ],
            connectorErrors: [
                ConnectorErrorSummary(connectorId: .slack, kind: .timeout, message: "Fetch exceeded budget"),
            ]
        )
    }

    // MARK: - Connection (+ accounts)

    @Test("Connection with accounts saves, loads, updates, and deletes")
    func connectionCRUD() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = ConnectionRepository(queue: manager.queue)
        let connection = makeConnection()

        // Create.
        try await repo.save(connection)

        // Read by id — full graph (including both accounts) round-trips.
        let loaded = try #require(try await repo.connection(id: connection.id))
        #expect(loaded == connection)
        #expect(loaded.accounts.count == 2)

        // List.
        let all = try await repo.all()
        #expect(all == [connection])

        // Update: drop one account, flip enabled, rename.
        let updated = Connection(
            id: connection.id,
            connectorId: connection.connectorId,
            displayName: "Gmail (work only)",
            accounts: [connection.accounts[0]],
            isEnabled: false
        )
        try await repo.save(updated)
        let reloaded = try #require(try await repo.connection(id: connection.id))
        #expect(reloaded == updated)
        #expect(reloaded.accounts.count == 1, "the removed account must be gone")

        // Delete cascades the remaining account away.
        #expect(try await repo.delete(id: connection.id))
        #expect(try await repo.connection(id: connection.id) == nil)
        #expect(try await repo.all().isEmpty)
    }

    // MARK: - Brief

    @Test("Brief saves, loadLatest returns newest, list is newest-first")
    func briefCRUD() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = BriefRepository(queue: manager.queue)

        // No briefs yet.
        #expect(try await repo.loadLatest() == nil)

        let older = makeBrief()
        let newer = Brief(
            generatedAt: older.generatedAt.addingTimeInterval(3600),
            sections: [BriefSection(title: "Today", entries: [BriefEntry(headline: "Ship it")])]
        )

        try await repo.save(older)
        try await repo.save(newer)

        // loadLatest returns the newest by generatedAt.
        let latest = try #require(try await repo.loadLatest())
        #expect(latest == newer)

        // list is newest-first.
        let list = try await repo.list()
        #expect(list == [newer, older])

        // limit caps the result.
        let capped = try await repo.list(limit: 1)
        #expect(capped == [newer])

        // Re-saving the same id updates in place (no duplicate row).
        let edited = Brief(
            id: older.id,
            generatedAt: older.generatedAt,
            spaceFilter: "personal",
            sections: older.sections,
            connectorErrors: []
        )
        try await repo.save(edited)
        #expect(try await repo.list().count == 2)
        let editedReload = try #require(try await repo.list().first { $0.id == older.id })
        #expect(editedReload == edited)

        // Delete.
        #expect(try await repo.delete(id: newer.id))
        #expect(try #require(try await repo.loadLatest()) == edited)
    }

    @Test("Brief items round-trip and link to their brief, cascading on delete")
    func briefItemsCRUD() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = BriefRepository(queue: manager.queue)
        let brief = makeBrief()
        try await repo.save(brief)

        let items = [
            BriefItem(
                source: .gmail,
                account: "alim@crispy.studio",
                space: "work",
                type: .email,
                title: "Q3 planning",
                body: "Let's sync before standup",
                people: ["jesse@example.com"],
                timestamp: Date(timeIntervalSince1970: 1_750_000_000),
                url: URL(string: "https://mail.google.com/#all/abc"),
                urgencyHints: [.unread, .mention]
            ),
            BriefItem(
                source: .slack,
                account: "workspace",
                space: "work",
                type: .message,
                title: "ping",
                timestamp: Date(timeIntervalSince1970: 1_750_000_100),
                urgencyHints: [.mention]
            ),
        ]

        try await repo.saveItems(items, briefID: brief.id)
        let loaded = try await repo.items(forBriefID: brief.id)
        // Newest-first ordering.
        #expect(loaded == [items[1], items[0]])

        // Deleting the brief cascades its items.
        #expect(try await repo.delete(id: brief.id))
        #expect(try await repo.items(forBriefID: brief.id).isEmpty)
    }

    // MARK: - Space

    @Test("Space saves, looks up by key, and deletes")
    func spaceCRUD() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = SpaceRepository(queue: manager.queue)

        let work = Space(key: "work", displayName: "Work")
        let personal = Space(key: "personal", displayName: "Personal")
        try await repo.save(work)
        try await repo.save(personal)

        #expect(try await repo.space(forKey: "work") == work)
        #expect(try await repo.all() == [personal, work]) // ordered by key

        #expect(try await repo.delete(id: personal.id))
        #expect(try await repo.space(forKey: "personal") == nil)
    }

    @Test("Space deletes by stable key, leaving others intact")
    func spaceDeleteByKey() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = SpaceRepository(queue: manager.queue)

        try await repo.save(Space(key: "work", displayName: "Work"))
        try await repo.save(Space(key: "personal", displayName: "Personal"))

        // Deleting an absent key removes nothing and reports false.
        #expect(try await repo.delete(key: "missing") == false)
        #expect(try await repo.all().count == 2)

        // Deleting an existing key removes exactly that space.
        #expect(try await repo.delete(key: "personal"))
        #expect(try await repo.space(forKey: "personal") == nil)
        #expect(try await repo.space(forKey: "work") != nil)
        #expect(try await repo.all().count == 1)
    }

    @Test("deleteConnection(id:) removes the connection and its accounts")
    func connectionDeleteByIdAlias() async throws {
        let manager = try DatabaseManager.inMemory()
        let repo = ConnectionRepository(queue: manager.queue)
        let connection = makeConnection()
        try await repo.save(connection)

        #expect(try await repo.deleteConnection(id: connection.id))
        #expect(try await repo.connection(id: connection.id) == nil)
        // A second delete of the same id is a no-op (false).
        #expect(try await repo.deleteConnection(id: connection.id) == false)
    }

    // MARK: - Settings

    @Test("SettingsStore typed get/set round-trips, including removal and dates")
    func settingsRoundTrip() async throws {
        let manager = try DatabaseManager.inMemory()
        let store = SettingsStore(queue: manager.queue)

        // Unset -> nil.
        #expect(try await store.get(SettingsStore.briefTime) == nil)

        // String key.
        try await store.set("07:00", for: SettingsStore.briefTime)
        #expect(try await store.get(SettingsStore.briefTime) == "07:00")
        try await store.set("06:30", for: SettingsStore.briefTime) // overwrite
        #expect(try await store.get(SettingsStore.briefTime) == "06:30")

        // Bool key.
        try await store.set(true, for: SettingsStore.launchAtLogin)
        #expect(try await store.get(SettingsStore.launchAtLogin) == true)

        // Model id.
        try await store.set("anthropic/claude-opus-4", for: SettingsStore.selectedModel)
        #expect(try await store.get(SettingsStore.selectedModel) == "anthropic/claude-opus-4")

        // Date (ISO-8601) round-trips to the second.
        let day = Date(timeIntervalSince1970: 1_750_000_000)
        try await store.setDate(day, forKey: SettingsStore.lastBriefDateKey)
        let reloaded = try #require(try await store.date(forKey: SettingsStore.lastBriefDateKey))
        #expect(Int(reloaded.timeIntervalSince1970) == Int(day.timeIntervalSince1970))

        // Removal.
        try await store.set(nil, for: SettingsStore.briefTime)
        #expect(try await store.get(SettingsStore.briefTime) == nil)
    }
}
