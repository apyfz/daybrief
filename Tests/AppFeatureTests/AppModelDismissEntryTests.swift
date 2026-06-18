@testable import AppFeature
import DaybriefCore
import Foundation
import Persistence
import Testing

/// Exercises ``AppModel/dismissEntry(id:)`` — removing a single item from the current
/// edition (the lead or a section entry) and persisting the trimmed brief.
///
/// These tests seed the model's display state directly via the `applyPreviewState`
/// seam (no ``AppModel/bootstrap()`` side effects) and read the persisted result back
/// through the in-memory ``BriefRepository`` to prove the overwrite landed.
@MainActor
@Suite("AppModel dismissEntry")
struct AppModelDismissEntryTests {
    private func makeModel() throws -> (AppModel, AppEnvironment) {
        let environment = try AppEnvironment.preview()
        return (AppModel(environment: environment), environment)
    }

    /// A brief with a lead plus two sections (the first holds two entries, the second
    /// holds one) so a removal can empty-and-drop a section.
    private func seededBrief() -> Brief {
        let leadEntry = BriefEntry(headline: "Sign the lease before noon", detail: "From your inbox.")
        let a1 = BriefEntry(headline: "Reply to Dana about the PR")
        let a2 = BriefEntry(headline: "Confirm the 2pm sync")
        let b1 = BriefEntry(headline: "Renew the domain")
        return Brief(
            generatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            masthead: "The Wednesday Brief",
            lede: "A calm morning with a few things to settle.",
            lead: leadEntry,
            sections: [
                BriefSection(title: "Push your work forward", entries: [a1, a2]),
                BriefSection(title: "Loose ends", entries: [b1]),
            ]
        )
    }

    @Test("dismissing the lead clears it and persists the trimmed brief")
    func dismissLead() async throws {
        let (model, environment) = try makeModel()
        let brief = seededBrief()
        model.applyPreviewState(brief: brief, setup: .ready)
        let leadID = try #require(brief.lead?.id)

        await model.dismissEntry(id: leadID)

        // In-memory: the lead is gone, the sections are untouched.
        #expect(model.currentBrief?.lead == nil)
        #expect(model.currentBrief?.sections.count == 2)
        #expect(model.currentBrief?.id == brief.id, "the edition keeps its id (overwrite, not new)")

        // Persisted: the same brief id was overwritten with the lead removed.
        let saved = try #require(try await environment.briefRepository.loadLatest())
        #expect(saved.id == brief.id)
        #expect(saved.lead == nil)
        #expect(saved.sections.count == 2)
    }

    @Test("dismissing a section entry that empties the section drops the section")
    func dismissEntryEmptiesAndDropsSection() async throws {
        let (model, environment) = try makeModel()
        let brief = seededBrief()
        model.applyPreviewState(brief: brief, setup: .ready)
        // The lone entry in the second section ("Loose ends").
        let loneEntryID = try #require(brief.sections[1].entries.first?.id)

        await model.dismissEntry(id: loneEntryID)

        // The now-empty "Loose ends" section is dropped; the first section survives intact.
        #expect(model.currentBrief?.sections.count == 1)
        #expect(model.currentBrief?.sections.first?.title == "Push your work forward")
        #expect(model.currentBrief?.sections.first?.entries.count == 2)
        #expect(model.currentBrief?.lead?.id == brief.lead?.id, "the lead is untouched")

        let saved = try #require(try await environment.briefRepository.loadLatest())
        #expect(saved.sections.map(\.title) == ["Push your work forward"])
    }

    @Test("dismissing one of several entries keeps the section, removing only that entry")
    func dismissEntryKeepsPopulatedSection() async throws {
        let (model, _) = try makeModel()
        let brief = seededBrief()
        model.applyPreviewState(brief: brief, setup: .ready)
        let firstEntryID = try #require(brief.sections[0].entries.first?.id)

        await model.dismissEntry(id: firstEntryID)

        let firstSection = try #require(model.currentBrief?.sections.first { $0.title == "Push your work forward" })
        #expect(firstSection.entries.count == 1)
        #expect(firstSection.entries.first?.id != firstEntryID)
        #expect(model.currentBrief?.sections.count == 2, "both sections remain")
    }

    @Test("dismissing an unknown id is a harmless no-op")
    func dismissUnknownIDIsNoOp() async throws {
        let (model, _) = try makeModel()
        let brief = seededBrief()
        model.applyPreviewState(brief: brief, setup: .ready)

        await model.dismissEntry(id: UUID())

        #expect(model.currentBrief == brief, "the edition is unchanged")
    }

    @Test("dismissing with no current brief never crashes")
    func dismissWithoutBriefIsNoOp() async throws {
        let (model, _) = try makeModel()
        await model.dismissEntry(id: UUID())
        #expect(model.currentBrief == nil)
    }
}
