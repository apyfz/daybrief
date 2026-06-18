@testable import AppFeature
import DaybriefCore
import Foundation
import Persistence
import Secrets
import Testing

/// Exercises ``AppModel``'s space/account-management logic over an in-memory
/// dependency graph.
///
/// These paths touch only the (in-memory) repositories and Keychain *deletes*
/// (which are no-ops for absent items, so they neither require Keychain entitlement
/// nor crash in CI). They avoid ``AppModel/bootstrap()`` — which reads
/// `SMAppService`, writes prompt files, and recomputes setup — via the
/// `loadForTesting()` seam.
@MainActor
@Suite("AppModel space & account management")
struct AppModelSpaceManagementTests {
    /// Builds a model over an in-memory environment, returning both so the test can
    /// seed the repositories directly.
    private func makeModel() throws -> (AppModel, AppEnvironment) {
        let environment = try AppEnvironment.preview()
        return (AppModel(environment: environment), environment)
    }

    private func slackAccount(id: UUID = UUID(), label: String, space: String) -> Account {
        Account(
            id: id,
            connectorId: .slack,
            label: label,
            spaceKey: space,
            secretRef: AccountSecrets.tokenRef(for: id, connector: .slack)
        )
    }

    @Test("addSpace derives a stable slug key, ignoring empties and duplicates")
    func addSpaceDerivesKeyAndDedupes() async throws {
        let (model, _) = try makeModel()

        await model.addSpace(displayName: "  Side Project!  ")
        #expect(model.spaces.map(\.key) == ["side-project"])
        #expect(model.spaces.first?.displayName == "Side Project!")

        // Empty / whitespace names are ignored.
        await model.addSpace(displayName: "   ")
        #expect(model.spaces.count == 1)

        // Duplicate by derived key (different punctuation, same slug) is ignored.
        await model.addSpace(displayName: "side project")
        #expect(model.spaces.count == 1)

        // A genuinely new name is added.
        await model.addSpace(displayName: "Clients")
        #expect(Set(model.spaces.map(\.key)) == ["side-project", "clients"])
    }

    @Test("spaceKey slugifies names deterministically")
    func spaceKeySlugifies() {
        #expect(AppModel.spaceKey(from: "Work") == "work")
        #expect(AppModel.spaceKey(from: "Side Project") == "side-project")
        #expect(AppModel.spaceKey(from: "  A & B  ") == "a-b")
        #expect(AppModel.spaceKey(from: "!!!") == "")
    }

    @Test("removeSpace refuses to delete the last remaining space")
    func removeSpaceKeepsLastSpace() async throws {
        let (model, _) = try makeModel()
        await model.addSpace(displayName: "Only")
        #expect(model.spaces.count == 1)

        await model.removeSpace(key: "only")
        #expect(model.spaces.count == 1, "the last space must be kept")
    }

    @Test("removeSpace reassigns the space's accounts to a remaining space, then deletes it")
    func removeSpaceReassignsAccounts() async throws {
        let (model, environment) = try makeModel()

        // Two spaces.
        await model.addSpace(displayName: "Work")
        await model.addSpace(displayName: "Personal")
        #expect(Set(model.spaces.map(\.key)) == ["work", "personal"])

        // Seed a Slack connection with one account filed under "personal" directly via
        // the repository (no Keychain write needed for the reassign/delete path).
        let account = slackAccount(label: "Acme", space: "personal")
        let connection = Connection(
            connectorId: .slack,
            displayName: "Slack",
            accounts: [account],
            isEnabled: true
        )
        try await environment.connectionRepository.save(connection)
        await model.loadForTesting()
        #expect(model.connections.flatMap(\.accounts).first?.spaceKey == "personal")

        // Remove the "personal" space — its account must move to "work".
        await model.removeSpace(key: "personal")

        #expect(model.spaces.map(\.key) == ["work"], "personal is gone")
        let reloadedAccount = try #require(model.connections.flatMap(\.accounts).first { $0.id == account.id })
        #expect(reloadedAccount.spaceKey == "work", "the orphaned account was re-filed under the remaining space")
        #expect(model.lastError == nil)
    }

    @Test("removeAccount drops the account and deletes the connection when it was the last")
    func removeAccountDeletesEmptyConnection() async throws {
        let (model, environment) = try makeModel()
        await model.addSpace(displayName: "Work")

        let account = slackAccount(label: "Acme", space: "work")
        try await environment.connectionRepository.save(
            Connection(connectorId: .slack, displayName: "Slack", accounts: [account], isEnabled: true)
        )
        await model.loadForTesting()
        #expect(model.connections.count == 1)

        await model.removeAccount(accountID: account.id)

        #expect(model.connections.isEmpty, "the connection is deleted once its last account is removed")
        #expect(model.lastError == nil)
    }

    @Test("removeAccount keeps the connection when other accounts remain")
    func removeAccountKeepsNonEmptyConnection() async throws {
        let (model, environment) = try makeModel()
        await model.addSpace(displayName: "Work")

        // Use a multi-account connector (Gmail) so removing one account leaves the
        // connection populated.
        let keep = Account(
            connectorId: .gmail,
            label: "keep@x.com",
            spaceKey: "work",
            secretRef: SecretRef(service: "co.daybrief.token.gmail", account: "keep")
        )
        let drop = Account(
            connectorId: .gmail,
            label: "drop@x.com",
            spaceKey: "work",
            secretRef: SecretRef(service: "co.daybrief.token.gmail", account: "drop")
        )
        try await environment.connectionRepository.save(
            Connection(connectorId: .gmail, displayName: "Gmail", accounts: [keep, drop], isEnabled: true)
        )
        await model.loadForTesting()

        await model.removeAccount(accountID: drop.id)

        let connection = try #require(model.connections.first)
        #expect(connection.accounts.map(\.id) == [keep.id], "only the dropped account is gone")
        #expect(model.lastError == nil)
    }

    @Test("removeAccount on an unknown id is a harmless no-op")
    func removeAccountUnknownIsNoOp() async throws {
        let (model, _) = try makeModel()
        await model.removeAccount(accountID: UUID())
        #expect(model.connections.isEmpty)
        #expect(model.lastError == nil)
    }
}
