import AppFeature
import AppKit
import ConnectorKit
import BriefRender
import DaybriefCore
import SlackConnector
import Foundation
import SwiftUI

// Offscreen renderer for the editorial brief panel.
//
// Builds a rich, representative `Brief`, hands it to `AppModel.preview(brief:)`, and
// rasterizes `BriefPanelView` with SwiftUI's `ImageRenderer` (scale 2) straight to a
// PNG — no GUI launch, no live environment, no network. The output path is the first
// CLI argument (default `/tmp/daybrief-panel.png`).

/// A hand-authored sample brief that exercises every editorial surface: masthead,
/// italic lede, a procedural hero with a per-edition accent, a large lead story, two
/// titled sections (the first with a context-rich entry + a "Let's do it" CTA), one
/// surfaced connector notice, and the factual colophon footer.
@MainActor
func makeSampleBrief() -> Brief {
    // A fixed Wednesday so the masthead reads "The Wednesday Brief".
    var components = DateComponents()
    components.year = 2026
    components.month = 6
    components.day = 17
    components.hour = 5
    components.minute = 32
    let generatedAt = Calendar(identifier: .gregorian).date(from: components) ?? Date()

    let gmailSection = BriefSection(
        title: "Gmail",
        source: .gmail,
        entries: [
            BriefEntry(
                headline: "Maya needs your call on enterprise discounting",
                detail: "She blocked Thursday's review on the pricing tiers; last night's thread narrowed it to two options.",
                url: URL(string: "https://mail.google.com/mail/u/0/#inbox/q3-roadmap"),
                priority: 0,
                ctaLabel: "Reply",
                sourceItemIDs: [UUID()]
            ),
            BriefEntry(
                headline: "Finance approved the contractor budget overnight",
                detail: "No action needed — onboarding can start whenever you're ready.",
                url: URL(string: "https://mail.google.com/mail/u/0/#inbox/finance"),
                priority: 2,
                ctaLabel: nil,
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let calendarSection = BriefSection(
        title: "Calendar",
        source: .gcal,
        entries: [
            BriefEntry(
                headline: "2:00 PM design review — room double-booked",
                detail: "Three holds still conflict; the room clashes with Growth.",
                url: URL(string: "https://calendar.google.com/calendar/u/0/r/day/2026/6/17"),
                priority: 1,
                ctaLabel: "Sort it out",
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let slackSection = BriefSection(
        title: "Slack",
        source: .slack,
        entries: [
            BriefEntry(
                headline: "Unread — 23 messages across 6 channels",
                detail: "Mostly #design ship-review chatter and two #eng threads about the deploy freeze; nothing needs you directly.",
                url: URL(string: "https://app.slack.com/client/T0"),
                priority: 0,
                ctaLabel: "Open Slack",
                sourceItemIDs: [UUID()]
            ),
            BriefEntry(
                headline: "Direct & mentions — Priya and 2 DMs",
                detail: "Priya @-mentioned you on the launch checklist; Sam and Dana sent DMs about Friday.",
                url: URL(string: "https://app.slack.com/client/T0/dms"),
                priority: 1,
                ctaLabel: "Reply",
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let notionSection = BriefSection(
        title: "Notion",
        source: .notion,
        entries: [
            BriefEntry(
                headline: "Draft Q3 OKRs — due today",
                detail: "Overdue by a day on the Planning board; everything else is on track.",
                url: URL(string: "https://www.notion.so/okrs"),
                priority: 0,
                ctaLabel: "Open task",
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let hero = HeroArtwork(
        // Empty assetName → graceful procedural placeholder (this CLI snapshot tool
        // has no bundled asset catalog). Credit text + accent mirror a real catalog
        // entry so the per-edition accent is exercised offscreen.
        assetName: "",
        title: "The Garden of the Tuileries on a Winter Afternoon",
        artist: "Camille Pissarro",
        year: "1899",
        sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437314"),
        accentHex: "#5E7287" // muted winter slate-blue
    )

    let notices: [ConnectorErrorSummary] = []

    return Brief(
        generatedAt: generatedAt,
        spaceFilter: nil,
        masthead: "The Wednesday Brief",
        lede: "A steady Wednesday.",
        summary: """
        One real decision today: Maya needs your call on enterprise discounting before \
        Thursday's review. The 2 PM design review has a room clash to sort, Slack is busy \
        but nothing's urgent, and your Q3 OKRs draft is a day overdue. Otherwise a calm day.
        """,
        lead: nil,
        mood: .steady,
        hero: hero,
        sections: [gmailSection, calendarSection, slackSection, notionSection],
        signalsRead: 31,
        sources: [.gmail, .gcal, .slack, .notion],
        connectorErrors: notices
    )
}

/// A representative connected state for the Settings snapshot: two Google accounts,
/// Slack and Notion, with a handful of Slack channels and some picked.
@MainActor
func makeSettingsModel() -> AppModel {
    let model = AppModel.preview(brief: makeSampleBrief())
    func account(_ id: ConnectorID, _ label: String) -> Account {
        Account(
            connectorId: id,
            label: label,
            spaceKey: "personal",
            secretRef: SecretRef(service: "co.daybrief.token.\(id.rawValue)", account: label)
        )
    }
    let connections = [
        Connection(connectorId: .gcal, displayName: "Google Calendar",
                   accounts: [account(.gcal, "alim@crispy.studio")], isEnabled: true),
        Connection(connectorId: .gmail, displayName: "Gmail",
                   accounts: [account(.gmail, "alim@crispy.studio")], isEnabled: true),
        Connection(connectorId: .slack, displayName: "Slack",
                   accounts: [account(.slack, "Crispy Studio")], isEnabled: true),
        Connection(connectorId: .notion, displayName: "Notion",
                   accounts: [], isEnabled: true),
    ]
    let channels = [
        "core-team", "deendesk", "operations", "pr", "practa", "random", "updates",
    ].enumerated().map { index, name in
        SlackConnector.MemberChannel(id: "C\(index)", name: name, isPrivate: index % 3 == 0)
    }
    model.applyPreviewConnections(
        connections,
        slackChannels: channels,
        selectedSlackChannelIDs: ["C0", "C1", "C2", "C3", "C4"]
    )
    return model
}

@MainActor
func renderSettings(to outputPath: String) throws {
    DaybriefTheme.registerBundledFonts()
    // Renders each pane's content stacked, since `ImageRenderer` can't draw the live
    // window's ScrollView. Pass a pane name to render just that one.
    let model = makeSettingsModel()
    let requested = CommandLine.arguments.compactMap { SettingsPane(rawValue: $0) }
    let panes = requested.isEmpty ? SettingsPane.allCases : requested
    // `--window` composes the real sidebar beside one pane, at the window's own size.
    let view: AnyView
    if CommandLine.arguments.contains("--window") {
        view = AnyView(
            SettingsWindowSnapshotView(model: model, pane: panes.first ?? .tools)
                .frame(width: 820, height: 560)
                .environment(\.colorScheme, .light)
        )
    } else {
        view = AnyView(
            VStack(alignment: .leading, spacing: 34) {
                ForEach(panes) { pane in
                    SettingsPaneContent(model: model, pane: pane)
                }
            }
            .padding(32)
            .frame(width: 620, alignment: .leading)
            .background(DaybriefTheme.paper)
            .environment(\.colorScheme, .light)
        )
    }

    if CommandLine.arguments.contains("--native") {
        try renderNative(view, size: NSSize(width: 820, height: 560), to: outputPath)
        return
    }
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let cgImage = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    else {
        FileHandle.standardError.write(Data("DaybriefSnapshot: could not render Settings.\n".utf8))
        exit(1)
    }
    try png.write(to: URL(fileURLWithPath: outputPath))
    FileHandle.standardError.write(
        Data("DaybriefSnapshot: wrote \(outputPath) (\(cgImage.width)×\(cgImage.height)px)\n".utf8)
    )
}

/// AppKit-hosted rendering includes native text fields, pickers, and steppers that
/// SwiftUI ImageRenderer cannot rasterize. Uses only the isolated preview model.
@MainActor
func renderNative<V: View>(_ view: V, size: NSSize, to path: String) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .light))
    window.contentView = hosting
    window.setContentSize(size)
    window.orderFront(nil)
    hosting.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: URL(fileURLWithPath: path))
    window.orderOut(nil)
}

@MainActor
func render() throws {
    // Load the app's existing artwork when running the package renderer outside its bundle.
    let artURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Assets.xcassets/Art/pissarro-tuileries-winter.imageset/pissarro-tuileries-winter.jpg")
    if let image = NSImage(contentsOf: artURL) {
        image.setName("pissarro-tuileries-winter")
    }
    if CommandLine.arguments.contains("--onboarding") {
        let path = CommandLine.arguments.first { $0.hasSuffix(".png") } ?? "/tmp/daybrief-onboarding.png"
        let step = CommandLine.arguments.compactMap(Int.init).first ?? 0
        let model = AppModel.preview(brief: makeSampleBrief())
        model.selectedModel = ""
        if CommandLine.arguments.contains("--native") {
            try renderNative(OnboardingView(model: model, snapshotStep: step),
                             size: NSSize(width: 680, height: 800), to: path)
            return
        }
        let renderer = ImageRenderer(content:
            OnboardingView(model: model, snapshotStep: step)
                .frame(width: 680, height: 800)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: path))
        return
    }

    // `--settings` renders the Settings window instead of the brief panel, so its
    // layout can be reviewed offscreen the same way the edition is.
    if CommandLine.arguments.contains("--settings") {
        let path = CommandLine.arguments.first { $0.hasSuffix(".png") } ?? "/tmp/daybrief-settings.png"
        try renderSettings(to: path)
        return
    }

    let outputPath = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "/tmp/daybrief-panel.png"

    let brief = makeSampleBrief()

    // Register the bundled editorial serif so the snapshot rasterizes in the real
    // Tiempos face when the (git-ignored) font files are present; a no-op otherwise.
    DaybriefTheme.registerBundledFonts()

    // `ImageRenderer` does not draw the content of the live panel's `ScrollView`, and
    // it does not rasterize the macOS 26 Liquid Glass surface material — both render
    // blank/black offscreen. `BriefPanelSnapshotView` composes the *same* editorial
    // subviews (masthead/lede/hero, lead story, sections, connector notices, colophon)
    // in a plain, non-scrolling `VStack` over solid paper, so the whole edition
    // rasterizes. It is built
    // from `AppModel.preview(brief:)`'s same sample brief. A light color scheme matches
    // the warm-paper editorial design.
    _ = AppModel.preview(brief: brief) // exercises the requested preview affordance
    let view = BriefPanelSnapshotView(brief: brief)
        .environment(\.colorScheme, .light)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true

    guard let cgImage = renderer.cgImage else {
        FileHandle.standardError.write(Data("DaybriefSnapshot: ImageRenderer produced no image.\n".utf8))
        exit(1)
    }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("DaybriefSnapshot: failed to encode PNG.\n".utf8))
        exit(1)
    }

    let url = URL(fileURLWithPath: outputPath)
    try png.write(to: url)

    let pixels = "\(cgImage.width)×\(cgImage.height)px"
    let bytes = png.count
    FileHandle.standardError.write(
        Data("DaybriefSnapshot: wrote \(outputPath) (\(pixels), \(bytes) bytes)\n".utf8)
    )
}

/// `ImageRenderer` is `@MainActor`-isolated; hop onto the main actor to render, then exit.
let task = Task { @MainActor in
    do {
        try render()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("DaybriefSnapshot: \(error)\n".utf8))
        exit(1)
    }
}

// Keep the process alive while the main-actor task runs.
withExtendedLifetime(task) {
    RunLoop.main.run()
}
