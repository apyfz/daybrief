import AppFeature
import AppKit
import BriefRender
import DaybriefCore
import Foundation
import SwiftUI

// Offscreen renderer for the editorial brief panel.
//
// Builds a rich, representative `Brief`, hands it to `AppModel.preview(brief:)`, and
// rasterizes `BriefPanelView` with SwiftUI's `ImageRenderer` (scale 2) straight to a
// PNG — no GUI launch, no live environment, no network. The output path is the first
// CLI argument (default `/tmp/daybrief-panel.png`).

/// A hand-authored sample brief that exercises every editorial surface: masthead,
/// italic lede, a procedural hero, two titled sections (the first with a context-rich
/// entry + a "Let's do it" CTA), and one surfaced connector notice.
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

    let pushSection = BriefSection(
        title: "Push your work forward",
        entries: [
            BriefEntry(
                headline: "Reply to Maya on the Q3 roadmap before standup",
                detail: """
                She blocked her Thursday review on your take on the pricing tiers. \
                Two of the three open questions are answered in last night's thread — \
                the third (enterprise discounting) is the only real decision left.
                """,
                url: URL(string: "https://mail.google.com/mail/u/0/#inbox/q3-roadmap"),
                priority: 0,
                ctaLabel: "Let's do it",
                sourceItemIDs: [UUID()]
            ),
            BriefEntry(
                headline: "Confirm the 2:00 PM design review",
                detail: "Three calendar holds still conflict; the room is double-booked with Growth.",
                url: URL(string: "https://calendar.google.com/calendar/u/0/r/day/2026/6/17"),
                priority: 1,
                ctaLabel: "Sort it out",
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let watchSection = BriefSection(
        title: "Worth a glance",
        entries: [
            BriefEntry(
                headline: "Finance approved the contractor budget overnight",
                detail: "No action needed — onboarding can start whenever you're ready.",
                url: URL(string: "https://app.slack.com/client/T0/C0/finance"),
                priority: 2,
                ctaLabel: nil,
                sourceItemIDs: [UUID()]
            ),
        ]
    )

    let hero = HeroArtwork(
        // Empty assetName → graceful procedural placeholder (this CLI snapshot tool
        // has no bundled asset catalog). Credit text mirrors a real catalog entry.
        assetName: "",
        title: "The Garden of the Tuileries on a Winter Afternoon",
        artist: "Camille Pissarro",
        year: "1899",
        sourceURL: URL(string: "https://www.metmuseum.org/art/collection/search/437314")
    )

    let notices = [
        ConnectorErrorSummary(
            connectorId: .slack,
            kind: .timeout,
            message: "Slack timed out after 8s."
        ),
    ]

    return Brief(
        generatedAt: generatedAt,
        spaceFilter: nil,
        masthead: "The Wednesday Brief",
        lede: """
        A quiet morning with one decision that actually matters. Clear the roadmap \
        reply early and the rest of the day opens up.
        """,
        hero: hero,
        sections: [pushSection, watchSection],
        connectorErrors: notices
    )
}

@MainActor
func render() throws {
    let outputPath = CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : "/tmp/daybrief-panel.png"

    let brief = makeSampleBrief()

    // `ImageRenderer` does not draw the content of the live panel's `ScrollView`, and
    // it does not rasterize the macOS 26 Liquid Glass surface material — both render
    // blank/black offscreen. `BriefPanelSnapshotView` composes the *same* editorial
    // subviews (masthead/lede/hero, sections, connector notices) in a plain, non-
    // scrolling `VStack` over solid paper, so the whole edition rasterizes. It is built
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
