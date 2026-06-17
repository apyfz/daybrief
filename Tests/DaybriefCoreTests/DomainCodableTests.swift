@testable import DaybriefCore
import Foundation
import Testing

@Suite("Domain Codable round-trips")
struct DomainCodableTests {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try decoder.decode(T.self, from: encoder.encode(value))
    }

    @Test("BriefItem round-trips and encodes typed fields as wire strings")
    func briefItemRoundTrips() throws {
        let item = BriefItem(
            id: UUID(),
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
        )

        #expect(try roundTrip(item) == item)

        // The typed enums must serialize to the design's wire strings.
        let object = try decoder.decode(JSONValue.self, from: encoder.encode(item))
        #expect(object["source"]?.string == "gmail")
        #expect(object["type"]?.string == "email")
        #expect(object["urgencyHints"]?.array?.compactMap(\.string) == ["unread", "mention"])
    }

    @Test("forward-compatible enums decode unknown raw values")
    func forwardCompatibleEnums() throws {
        let json = #"""
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "source": "notion",
          "account": "a",
          "space": "work",
          "type": "page",
          "title": "t",
          "people": [],
          "timestamp": 0,
          "urgencyHints": ["snoozed"]
        }
        """#
        let item = try decoder.decode(BriefItem.self, from: Data(json.utf8))
        #expect(item.source == ConnectorID("notion"))
        #expect(item.type == .unknown("page"))
        #expect(item.urgencyHints == [.other("snoozed")])

        // And the unknown value re-encodes losslessly.
        let restored = try roundTrip(item)
        #expect(restored == item)
    }

    @Test("Brief with sections, entries, and connector errors round-trips")
    func briefRoundTrips() throws {
        let itemID = UUID()
        let brief = Brief(
            id: UUID(),
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
                ConnectorErrorSummary(connectorId: .gmail, kind: .auth, message: "Token expired"),
            ]
        )

        #expect(try roundTrip(brief) == brief)
    }

    @Test("Connection / Account / Space / SecretRef round-trip")
    func connectionGraphRoundTrips() throws {
        let connection = Connection(
            connectorId: .gmail,
            displayName: "Gmail",
            accounts: [
                Account(
                    connectorId: .gmail,
                    label: "alim@crispy.studio",
                    spaceKey: "work",
                    secretRef: SecretRef(service: "com.daybrief.gmail.token", account: "alim@crispy.studio")
                ),
            ],
            isEnabled: true
        )
        #expect(try roundTrip(connection) == connection)

        let space = Space(key: "personal", displayName: "Personal")
        #expect(try roundTrip(space) == space)
    }

    @Test("ConnectorErrorSummary.Kind covers every classification")
    func errorKindsRoundTrip() throws {
        for kind in [
            ConnectorErrorSummary.Kind.timeout, .auth, .network, .decode, .other,
        ] {
            let summary = ConnectorErrorSummary(connectorId: .gcal, kind: kind, message: "m")
            #expect(try roundTrip(summary).kind == kind)
        }
    }
}
