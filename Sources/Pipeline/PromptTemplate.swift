import Foundation
import os

/// The user-editable synthesis prompt + render notes that steer the brief's
/// voice and layout, with bundled defaults as a fallback.
///
/// Files live at `~/Library/Application Support/Daybrief/prompts/`:
/// - `synthesis.md` — the synthesis **system prompt** (editorial voice + rules).
/// - `template.md` — **render notes** appended to the user turn (layout/section
///   guidance for the model).
///
/// On first run the defaults are written to disk via ``writeDefaultsIfNeeded()``
/// so the user can tune voice/layout without forking (design §8). If a file is
/// missing or unreadable, the corresponding bundled default string is used — the
/// app must always be able to synthesize a brief offline.
public struct PromptTemplate: Sendable, Equatable {
    /// The synthesis system prompt (the editorial voice + rules).
    public let systemPrompt: String
    /// The render notes appended to the user turn (layout/section guidance).
    public let renderNotes: String

    /// Creates a prompt template from explicit strings (used by ``load(from:)``
    /// and directly in tests).
    public init(systemPrompt: String, renderNotes: String) {
        self.systemPrompt = systemPrompt
        self.renderNotes = renderNotes
    }

    /// The bundled default template, embedding the brief design language.
    public static let bundledDefault = PromptTemplate(
        systemPrompt: Self.defaultSystemPrompt,
        renderNotes: Self.defaultRenderNotes
    )

    // MARK: - Filesystem

    private static let logger = Logger(subsystem: "co.daybrief.pipeline", category: "PromptTemplate")
    private static let synthesisFileName = "synthesis.md"
    private static let renderNotesFileName = "template.md"

    /// The default prompts directory: `~/Library/Application Support/Daybrief/prompts/`.
    public static func defaultDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Daybrief", isDirectory: true)
            .appendingPathComponent("prompts", isDirectory: true)
    }

    /// Loads the template from `directory`, falling back to the bundled defaults
    /// for any file that is missing or unreadable.
    ///
    /// - Parameters:
    ///   - directory: The prompts directory (defaults to ``defaultDirectory(fileManager:)``).
    ///   - fileManager: Injected for tests.
    public static func load(
        from directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> PromptTemplate {
        let dir = directory ?? defaultDirectory(fileManager: fileManager)
        let system = readFile(named: synthesisFileName, in: dir) ?? defaultSystemPrompt
        let notes = readFile(named: renderNotesFileName, in: dir) ?? defaultRenderNotes
        return PromptTemplate(systemPrompt: system, renderNotes: notes)
    }

    /// Writes the bundled defaults to `directory` for any file that does not yet
    /// exist, creating the directory if necessary. Existing user edits are never
    /// overwritten. Safe to call on every launch.
    ///
    /// - Parameters:
    ///   - directory: The prompts directory (defaults to ``defaultDirectory(fileManager:)``).
    ///   - fileManager: Injected for tests.
    /// - Throws: A filesystem error if the directory or files cannot be created.
    @discardableResult
    public static func writeDefaultsIfNeeded(
        to directory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let dir = directory ?? defaultDirectory(fileManager: fileManager)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeIfAbsent(defaultSystemPrompt, named: synthesisFileName, in: dir, fileManager: fileManager)
        try writeIfAbsent(defaultRenderNotes, named: renderNotesFileName, in: dir, fileManager: fileManager)
        return dir
    }

    private static func readFile(named name: String, in directory: URL) -> String? {
        let url = directory.appendingPathComponent(name)
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : contents
    }

    private static func writeIfAbsent(
        _ contents: String,
        named name: String,
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let url = directory.appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
        logger.debug("Wrote default prompt file \(name, privacy: .public)")
    }
}

// MARK: - Bundled default copy (the editorial voice)

extension PromptTemplate {
    /// The default synthesis system prompt. Encodes the brief design language:
    /// calm, literary, ruthlessly prioritized, context-rich, draft-only.
    static let defaultSystemPrompt = """
    You are the editor of a private morning periodical written for one reader. \
    Each morning you have already gone through that person's inbox, calendar, and \
    messages, and you hand them a single, beautifully set page: the shape of their \
    day, the one or few things worth pushing forward, and enough context that they \
    can simply begin.

    VOICE
    - Editorial register: calm, concise, literate, a little wry. Think a thoughtful \
    newspaper editor, not a notification feed.
    - Warm and human, never anxious, never breathless. No corporate filler, no emoji, \
    no exclamation spam, no hype.
    - Write in prose, not bullet fragments. Full sentences with rhythm.

    PRIORITIZE RUTHLESSLY
    - Surface only the one or few things that genuinely move the day forward. This is \
    an editor's judgment, not an exhaustive log of everything that happened.
    - It is better to name one real priority well than to list ten items shallowly. \
    Omit noise without apology.

    CONTEXT, WRITTEN AS IF YOU READ THE SOURCE
    - Reference people and threads by name. Explain who said what, why it matters, and \
    what is already known, as though you have actually read the messages and invitations.
    - Ground every claim in the provided items. Never invent facts, names, times, \
    commitments, or links that are not present in the source items.

    HONEST ABOUT QUIET DAYS
    - If little or nothing is pressing, say so plainly and let it breathe \
    ("Nothing on the calendar today or tomorrow — two clear days of heads-down time."). \
    Emptiness is a feature, not a gap to pad.

    DRAFT-ONLY / SUGGEST, NEVER ACT
    - You only ever suggest and draft. A call-to-action invites the reader to act; it \
    never implies you have acted, sent, replied, or scheduled anything on their behalf.

    STRUCTURE YOU PRODUCE
    - masthead: a newspaper-style title named for the weekday of the brief, in the form \
    "The <Weekday> Brief" (e.g. "The Wednesday Brief"). Use the weekday provided to you.
    - lede: one or two sentences of editorial prose summarizing the day. Observational, \
    never a list. This is the reader's first impression.
    - sections: a small number of titled movements (e.g. "Push your work forward", \
    "On the calendar", "What slipped overnight"). Prefer few strong sections over many.
    - entries within each section: each has a headline the reader sees first, an optional \
    paragraph of context (detail), an optional url back to the source item, an optional \
    priority (lower number = more important), and an optional short ctaLabel for the accent \
    badge (e.g. "Let's do it", "Open thread", "Reply"). Use the url only when a source item \
    actually provides one.

    Respond ONLY with the JSON object required by the schema — no markdown, no commentary.
    """

    /// The default render notes appended to the user turn — layout guidance the
    /// model uses while filling the structured shape.
    static let defaultRenderNotes = """
    Layout guidance:
    - Open with the lede before any section. Keep it to one or two sentences.
    - Lead with a single "Push your work forward" section when there is a clear \
    priority; give it one well-contextualized entry rather than several thin ones.
    - Group calendar items under one dated section; group what slipped or is unread \
    under another. Do not create a section for a category with nothing in it.
    - Headlines are short and concrete (a verb where natural). Context paragraphs are \
    two to four sentences, naming the people and threads involved.
    - Set a ctaLabel only on entries the reader can act on; keep it to a few words.
    """
}
