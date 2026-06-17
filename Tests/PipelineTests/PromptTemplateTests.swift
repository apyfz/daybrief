import Foundation
@testable import Pipeline
import Testing

@Suite("PromptTemplate defaults and disk loading")
struct PromptTemplateTests {
    /// A fresh temp directory per test for filesystem isolation.
    private func makeTempDir() throws -> URL {
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("daybrief-prompt-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("bundled default encodes the editorial voice")
    func bundledDefaultEncodesVoice() {
        let template = PromptTemplate.bundledDefault
        // Voice anchors from the brief design language.
        #expect(template.systemPrompt.contains("The <Weekday> Brief"))
        #expect(template.systemPrompt.lowercased().contains("prioritize"))
        #expect(template.systemPrompt.lowercased().contains("draft"))
        #expect(template.systemPrompt.lowercased().contains("quiet"))
        #expect(!template.renderNotes.isEmpty)
    }

    @Test("loads bundled defaults when no files exist on disk")
    func loadFallsBackToDefaults() throws {
        let dir = try makeTempDir()
        let loaded = PromptTemplate.load(from: dir)
        #expect(loaded == PromptTemplate.bundledDefault)
    }

    @Test("writeDefaultsIfNeeded creates both files, then load reads them back")
    func writeThenLoad() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try PromptTemplate.writeDefaultsIfNeeded(to: dir)

        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("synthesis.md").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("template.md").path))

        let loaded = PromptTemplate.load(from: dir)
        #expect(loaded == PromptTemplate.bundledDefault)
    }

    @Test("writeDefaultsIfNeeded never overwrites a user edit")
    func doesNotOverwriteUserEdits() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let custom = "MY CUSTOM SYSTEM PROMPT"
        try custom.write(to: dir.appendingPathComponent("synthesis.md"), atomically: true, encoding: .utf8)

        try PromptTemplate.writeDefaultsIfNeeded(to: dir)

        let loaded = PromptTemplate.load(from: dir)
        #expect(loaded.systemPrompt == custom)
        // The render-notes file was absent, so it got the default.
        #expect(loaded.renderNotes == PromptTemplate.bundledDefault.renderNotes)
    }

    @Test("an empty file falls back to the default rather than yielding blank")
    func emptyFileFallsBack() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "   \n".write(to: dir.appendingPathComponent("synthesis.md"), atomically: true, encoding: .utf8)

        let loaded = PromptTemplate.load(from: dir)
        #expect(loaded.systemPrompt == PromptTemplate.bundledDefault.systemPrompt)
    }
}
