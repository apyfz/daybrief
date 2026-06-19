import AppKit
import BriefRender
import DaybriefCore
import DaybriefUI
import DaybriefWidgetUI
import Foundation
import SwiftUI

// Offscreen renderer for the desktop widget, mirroring DaybriefSnapshot for the panel.
// Renders each widget family (small / medium / large / extra-large) at its exact point
// size to a PNG, over the widget's paper container background and inside the system
// content margin — so the proportions match what the user sees on the desktop. No GUI,
// no device. Output directory is the first CLI argument (default /tmp).

/// macOS widget point sizes (Tahoe). Width × height per family.
private let familySizes: [(name: String, size: CGSize)] = [
    ("small", CGSize(width: 170, height: 170)),
    ("medium", CGSize(width: 364, height: 170)),
    ("large", CGSize(width: 364, height: 382)),
    ("xlarge", CGSize(width: 742, height: 382)),
]

/// Approximates the system content margin macOS insets widget content by (the container
/// background fills the full tile; content sits inside this margin). Indicative for the
/// offscreen render — the exact value is system-applied on-device.
private let contentMargin: CGFloat = 16

@MainActor
private func makeSampleBrief() -> Brief {
    var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 19; c.hour = 6; c.minute = 38
    let generatedAt = Calendar(identifier: .gregorian).date(from: c) ?? Date()

    let lead = BriefEntry(
        headline: "Decide the enterprise discounting tier before Maya's review",
        detail: "The one open question blocking Thursday's sign-off.",
        url: URL(string: "https://mail.google.com/"),
        priority: 0, ctaLabel: "Make the call", sourceItemIDs: [UUID()]
    )
    let push = BriefSection(title: "Push your work forward", entries: [
        BriefEntry(headline: "Reply to Maya on the Q3 roadmap before standup",
                   detail: "She blocked her review on your pricing take.",
                   url: URL(string: "https://mail.google.com/"), priority: 1, ctaLabel: "Let's do it", sourceItemIDs: [UUID()]),
        BriefEntry(headline: "Confirm the 2:00 PM design review",
                   detail: "Three holds still conflict; the room is double-booked.",
                   url: URL(string: "https://calendar.google.com/"), priority: 2, ctaLabel: "Sort it out", sourceItemIDs: [UUID()]),
    ])
    let glance = BriefSection(title: "Worth a glance", entries: [
        BriefEntry(headline: "Finance approved the contractor budget overnight",
                   detail: "No action needed.", url: URL(string: "https://slack.com/"), priority: 3, ctaLabel: nil, sourceItemIDs: [UUID()]),
        BriefEntry(headline: "Dana shared the launch retro notes",
                   detail: "Skim before the 4pm.", url: URL(string: "https://notion.so/"), priority: 4, ctaLabel: nil, sourceItemIDs: [UUID()]),
        BriefEntry(headline: "Two Notion tasks fall due today",
                   detail: nil, url: URL(string: "https://notion.so/"), priority: 5, ctaLabel: nil, sourceItemIDs: [UUID()]),
    ])

    let hero = HeroArtwork(
        assetName: "", title: "Woman with a Water Jug", artist: "Johannes Vermeer", year: "1662",
        sourceURL: URL(string: "https://www.metmuseum.org/"), accentHex: "#C8A24A"
    )

    return Brief(
        generatedAt: generatedAt, spaceFilter: nil, masthead: "The Friday Brief",
        lede: "A quiet morning with one decision that matters.",
        lead: lead, mood: .steady, hero: hero, sections: [push, glance],
        signalsRead: 12, sources: [.gmail, .gcal, .slack, .notion], connectorErrors: []
    )
}

/// A representative "painting" hero PNG so the masthead-over-hero contrast is realistic.
@MainActor
private func sampleHeroPNG() -> Data? {
    let size = NSSize(width: 600, height: 600)
    let image = NSImage(size: size)
    image.lockFocus()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.26, alpha: 1), // slate
        NSColor(calibratedRed: 0.42, green: 0.33, blue: 0.20, alpha: 1), // ochre
        NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1), // near-black
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -55)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

@MainActor
private func render() throws {
    let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp"
    DaybriefTheme.registerBundledFonts()

    let brief = makeSampleBrief()
    let vm = BriefRenderer().viewModel(brief)
    let hero = sampleHeroPNG()

    for family in familySizes {
        let content: AnyView
        switch family.name {
        case "small": content = AnyView(SmallBriefView(brief: brief, vm: vm, heroPNG: hero))
        case "medium": content = AnyView(MediumBriefView(brief: brief, vm: vm, heroPNG: hero))
        case "large": content = AnyView(LargeBriefView(brief: brief, vm: vm, heroPNG: hero))
        default: content = AnyView(ExtraLargeBriefView(brief: brief, vm: vm, heroPNG: hero))
        }

        let view = ZStack {
            DaybriefTheme.paper
            content.padding(contentMargin)
        }
        .frame(width: family.size.width, height: family.size.height)
        .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else {
            FileHandle.standardError.write(Data("widget-snapshot: no image for \(family.name)\n".utf8)); continue
        }
        guard let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { continue }
        let url = URL(fileURLWithPath: outDir).appendingPathComponent("widget-\(family.name).png")
        try png.write(to: url)
        FileHandle.standardError.write(Data("widget-snapshot: wrote \(url.path) (\(cg.width)×\(cg.height)px)\n".utf8))
    }
}

let task = Task { @MainActor in
    do { try render(); exit(0) } catch {
        FileHandle.standardError.write(Data("widget-snapshot: \(error)\n".utf8)); exit(1)
    }
}
withExtendedLifetime(task) { RunLoop.main.run() }
