import BriefRender
import DaybriefCore
import DaybriefUI
import SwiftUI
import WidgetKit

/// The desktop widget extension's entry point — a real Xcode app-extension
/// `@main WidgetBundle` (an SPM-wrapped one hits a macOS 26 runloop bug and never
/// registers).
///
/// The widget is a read-only **glance** at today's brief. It reads only the small,
/// display-safe snapshot the host writes into the shared App Group container
/// (`latest-brief.json` + a downsampled `latest-hero.png`); it never opens the
/// encrypted database and never holds any secret. Freshness is push-driven: the host
/// calls `WidgetCenter.reloadAllTimelines()` whenever the brief changes, so the
/// timeline policy is `.never`.
@main
struct DaybriefWidgetBundle: WidgetBundle {
    init() {
        // Register the bundled editorial serif (Tiempos) + body sans (Geist) in THIS
        // process so the widget draws in the same faces as the panel. `Bundle.module`
        // now resolves to DaybriefUI's resource bundle embedded in the .appex.
        DaybriefTheme.registerBundledFonts()
    }

    var body: some Widget {
        DaybriefGlanceWidget()
    }
}

/// The single glance widget, offered in small / medium / large desktop sizes.
struct DaybriefGlanceWidget: Widget {
    let kind = "DaybriefGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BriefProvider()) { entry in
            BriefWidgetView(entry: entry)
                .containerBackground(for: .widget) { DaybriefTheme.paper }
        }
        .configurationDisplayName("Daybrief")
        .description("Today's brief at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

/// A timeline entry carrying the decoded brief snapshot (or `nil` when none has been
/// written yet) and the pre-downsampled hero PNG bytes.
struct BriefEntry: TimelineEntry {
    let date: Date
    let brief: Brief?
    let heroPNG: Data?
}

/// Reads the latest snapshot once per reload; `.never` policy since freshness is
/// driven by explicit host pushes, not polling.
struct BriefProvider: TimelineProvider {
    func placeholder(in _: Context) -> BriefEntry {
        BriefEntry(date: Date(), brief: nil, heroPNG: nil)
    }

    func getSnapshot(in _: Context, completion: @escaping (BriefEntry) -> Void) {
        completion(WidgetSnapshotStore.load())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<BriefEntry>) -> Void) {
        completion(Timeline(entries: [WidgetSnapshotStore.load()], policy: .never))
    }
}

/// Loads the host-written brief + hero from the shared App Group container. Any
/// missing/undecodable file degrades to the empty state, never a crash.
enum WidgetSnapshotStore {
    static func load() -> BriefEntry {
        guard let briefURL = AppGroup.url(for: AppGroup.FileName.latestBrief),
              let data = try? Data(contentsOf: briefURL),
              let brief = try? JSONDecoder().decode(Brief.self, from: data)
        else {
            return BriefEntry(date: Date(), brief: nil, heroPNG: nil)
        }
        let hero = AppGroup.url(for: AppGroup.FileName.latestHero).flatMap { try? Data(contentsOf: $0) }
        return BriefEntry(date: Date(), brief: brief, heroPNG: hero)
    }
}
