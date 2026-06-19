import ConnectorKit
import DaybriefCore
import Foundation
@testable import NotionConnector
import Testing

// MARK: - Fixtures & helpers

private let loader = FixtureLoader(connectorId: .notion)

private func makeAccount(label: String = "Acme") -> Account {
    Account(
        connectorId: .notion,
        label: label,
        spaceKey: "work",
        secretRef: SecretRef(service: "co.daybrief.oauth.notion", account: label)
    )
}

private func makeConnector(transport: MockHTTPTransport, token: String = "ntn_test") -> NotionConnector {
    NotionConnector(transport: transport, tokenProvider: StaticTokenProvider(token: token))
}

/// A request whose window ends midday on 2026-06-19, so "today" is the 19th.
private func makeRequest(_ account: Account = makeAccount()) -> FetchRequest {
    var comps = DateComponents()
    comps.year = 2026; comps.month = 6; comps.day = 19; comps.hour = 12
    let until = Calendar.current.date(from: comps)!
    return FetchRequest(accounts: [account], since: until.addingTimeInterval(-86400), until: until)
}

/// Enqueues the happy-path call sequence: users/me → search → query.
private func enqueueHappyPath(_ transport: MockHTTPTransport, me: String = "users-me") async throws {
    await transport.enqueue(data: try loader.data(me))
    await transport.enqueue(data: try loader.data("search-databases"))
    await transport.enqueue(data: try loader.data("query-tasks"))
}

// MARK: - normalize()

@Test func normalize_task_producesTaskItem() {
    let envelope = NotionRawEnvelope(
        pageId: "p1",
        title: "Ship the release",
        databaseTitle: "Tasks",
        dueISO: "2026-06-19",
        assignees: ["Alim"],
        url: "https://notion.so/p1",
        isOverdue: false
    )
    let raw = RawItem(id: "task:p1", connectorId: .notion, accountLabel: "Acme", json: envelope.json)

    let items = makeConnector(transport: MockHTTPTransport()).normalize([raw])

    #expect(items.count == 1)
    let item = items[0]
    #expect(item.source == .notion)
    #expect(item.type == .unknown("task"))
    #expect(item.title == "Ship the release")
    #expect(item.people == ["Alim"])
    #expect(item.body == "From Tasks")
    #expect(item.url == URL(string: "https://notion.so/p1"))
    #expect(item.urgencyHints == [.dueToday])
}

@Test func normalize_overdueTask_flagsOverdue() {
    let envelope = NotionRawEnvelope(
        pageId: "p2", title: "Reply", databaseTitle: "Tasks",
        dueISO: "2026-06-10", assignees: [], url: nil, isOverdue: true
    )
    let raw = RawItem(id: "task:p2", connectorId: .notion, accountLabel: "Acme", json: envelope.json)
    let item = makeConnector(transport: MockHTTPTransport()).normalize([raw])[0]
    #expect(item.urgencyHints == [.other("overdue")])
}

// MARK: - fetch()

@Test func fetch_keepsMineAndUnassigned_dropsDoneAndForeignAssignee() async throws {
    let transport = MockHTTPTransport()
    try await enqueueHappyPath(transport)

    let items = try await makeConnector(transport: transport).fetch(makeRequest())

    // p1 (mine, due today) + p2 (unassigned, overdue) survive; p3 (done) and p4 (Bob's) dropped.
    #expect(items.map(\.id).sorted() == ["task:p1", "task:p2"])

    let normalized = makeConnector(transport: MockHTTPTransport()).normalize(items)
    let byTitle = Dictionary(uniqueKeysWithValues: normalized.map { ($0.title, $0) })
    #expect(byTitle["Ship the release"]?.urgencyHints == [.dueToday])
    #expect(byTitle["Ship the release"]?.people == ["Alim"])
    #expect(byTitle["Reply to the investor"]?.urgencyHints == [.other("overdue")])
    #expect(byTitle["Reply to the investor"]?.people == [])
}

@Test func fetch_callsUsersMeThenSearchThenQuery() async throws {
    let transport = MockHTTPTransport()
    try await enqueueHappyPath(transport)

    _ = try await makeConnector(transport: transport).fetch(makeRequest())

    let paths = await transport.recordedRequests.map { $0.url?.path ?? "" }
    #expect(paths == ["/v1/users/me", "/v1/search", "/v1/databases/db1/query"])
    // POSTs carry the pinned Notion-Version header.
    let versions = await transport.recordedRequests.map { $0.value(forHTTPHeaderField: "Notion-Version") }
    #expect(versions.allSatisfy { $0 == "2022-06-28" })
}

@Test func fetch_workspaceOwnedIntegration_keepsForeignAssignee() async throws {
    // No human owner → no "me" → the assignee filter excludes no one.
    let workspaceMe = Data(#"{"object":"user","id":"bot1","type":"bot","bot":{"owner":{"type":"workspace"}}}"#.utf8)
    let transport = MockHTTPTransport()
    await transport.enqueue(data: workspaceMe)
    await transport.enqueue(data: try loader.data("search-databases"))
    await transport.enqueue(data: try loader.data("query-tasks"))

    let items = try await makeConnector(transport: transport).fetch(makeRequest())

    // p4 (Bob's) now survives alongside p1 and p2; p3 (done) is still dropped.
    #expect(items.map(\.id).sorted() == ["task:p1", "task:p2", "task:p4"])
}

@Test func fetch_mapsAuthFailureFromSearch() async throws {
    let transport = MockHTTPTransport()
    await transport.enqueue(data: try loader.data("users-me"))
    await transport.enqueueFailure(TransportError.unacceptableStatus(code: 401, body: Data()))

    await #expect(throws: ConnectorError.self) {
        _ = try await makeConnector(transport: transport).fetch(makeRequest())
    }
}

// MARK: - Property detection

@Test func detectDoneProperty_statusComplete_derivesDoneNames() {
    let db = try! loader.json("search-databases")
    let props = db["results"]?[0]?["properties"]?.object ?? [:]
    let done = NotionConnector.detectDoneProperty(in: props)
    #expect(done?.name == "Status")
    #expect(done?.type == "status")
    #expect(done?.doneNames == ["done"])
}

@Test func isDone_respectsStatusAndCheckbox() {
    let doneStatus = JSONValue.object(["status": .object(["name": .string("Done")])])
    #expect(NotionConnector.isDone(doneStatus, type: "status", doneStatusNames: ["done"]))
    let openStatus = JSONValue.object(["status": .object(["name": .string("To Do")])])
    #expect(!NotionConnector.isDone(openStatus, type: "status", doneStatusNames: ["done"]))
    let checked = JSONValue.object(["checkbox": .bool(true)])
    #expect(NotionConnector.isDone(checked, type: "checkbox", doneStatusNames: []))
}
