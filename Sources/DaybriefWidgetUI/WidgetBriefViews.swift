import AppKit
import BriefRender
import DaybriefCore
import DaybriefUI
import SwiftUI

// The size-specific widget layouts, extracted into a GRDB-free library so they can be
// rendered offscreen (DaybriefWidgetSnapshot) at each widget's exact point size, the way
// the brief panel is. The WidgetKit plumbing (bundle, provider, timeline entry, and the
// family router) stays in the app-extension target — these views are pure SwiftUI.

/// The day's stories in reading order: the lead first when present, then every section
/// entry. Lets a lead-less (or not-yet-regenerated) brief still surface real stories.
private func orderedEntries(_ vm: BriefViewModel) -> [BriefViewModel.Entry] {
    (vm.lead.map { [$0] } ?? []) + vm.sections.flatMap(\.entries)
}

// MARK: - Small

/// systemSmall: the painting, full-bleed, with the masthead over it and a small item
/// count. The picture is the point at this size.
public struct SmallBriefView: View {
    let brief: Brief
    let vm: BriefViewModel
    let heroPNG: Data?

    public init(brief: Brief, vm: BriefViewModel, heroPNG: Data?) {
        self.brief = brief
        self.vm = vm
        self.heroPNG = heroPNG
    }

    public var body: some View {
        let count = orderedEntries(vm).count
        WidgetHero(png: heroPNG)
            .overlay(alignment: .center) {
                WidgetMasthead(text: WidgetFormat.masthead(brief), displaySize: 19, italicSize: 12, onDark: true)
            }
            .overlay(alignment: .bottom) {
                Text(count > 0 ? "\(count) to read · daybrief" : "a clear day")
                    .font(DaybriefTheme.serifBody(8.5).weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Medium

/// systemMedium: the painting on the left (the focus), a compact numbered list of the
/// day's items on the right, closed by the "take action" footer.
public struct MediumBriefView: View {
    let brief: Brief
    let vm: BriefViewModel
    let heroPNG: Data?

    public init(brief: Brief, vm: BriefViewModel, heroPNG: Data?) {
        self.brief = brief
        self.vm = vm
        self.heroPNG = heroPNG
    }

    public var body: some View {
        let entries = orderedEntries(vm)
        HStack(spacing: 11) {
            WidgetHero(png: heroPNG)
                .overlay(
                    WidgetMasthead(text: WidgetFormat.masthead(brief), displaySize: 17, italicSize: 11, onDark: true)
                        .padding(.horizontal, 6)
                )
                .frame(width: 150)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    QuietLine()
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        NumberedItem(index: index + 1, entry: entry, headlineLimit: 2)
                        if index < min(entries.count, 3) - 1 {
                            Spacer(minLength: 4)
                        }
                    }
                    Spacer(minLength: 6)
                    ActionFooter(extraCount: max(0, entries.count - 3))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Large

/// systemLarge: a big hero plate up top (the painting leads), then a numbered list of
/// the day's items below as small editorial lines, closed by the "take action" footer.
public struct LargeBriefView: View {
    let brief: Brief
    let vm: BriefViewModel
    let heroPNG: Data?

    public init(brief: Brief, vm: BriefViewModel, heroPNG: Data?) {
        self.brief = brief
        self.vm = vm
        self.heroPNG = heroPNG
    }

    public var body: some View {
        let entries = orderedEntries(vm)
        VStack(spacing: 18) {
            WidgetHero(png: heroPNG)
                .overlay(alignment: .center) {
                    WidgetMasthead(text: WidgetFormat.masthead(brief), displaySize: 30, italicSize: 18, onDark: true)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(WidgetFormat.dateline(brief.generatedAt))
                        .font(DaybriefTheme.serifBody(9))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.85))
                        // Clear the 12pt rounded corner so the dateline isn't clipped.
                        .padding(12)
                }
                .frame(height: 184)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    QuietLine()
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle().fill(DaybriefTheme.ink.opacity(0.08)).frame(height: 1)
                                .padding(.vertical, 6)
                        }
                        NumberedItem(index: index + 1, entry: entry, headlineLimit: 1)
                    }
                    Spacer(minLength: 8)
                    ActionFooter(extraCount: max(0, entries.count - 4))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Extra Large

/// systemExtraLarge: a magazine spread — a tall hero plate on the left with the
/// masthead, and a longer numbered list of the day's items on the right, closed by the
/// "take action" footer. Twice the width of large, so the list breathes and shows more.
public struct ExtraLargeBriefView: View {
    let brief: Brief
    let vm: BriefViewModel
    let heroPNG: Data?

    public init(brief: Brief, vm: BriefViewModel, heroPNG: Data?) {
        self.brief = brief
        self.vm = vm
        self.heroPNG = heroPNG
    }

    public var body: some View {
        let entries = orderedEntries(vm)
        HStack(spacing: 22) {
            WidgetHero(png: heroPNG)
                .overlay(alignment: .center) {
                    WidgetMasthead(text: WidgetFormat.masthead(brief), displaySize: 34, italicSize: 20, onDark: true)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(WidgetFormat.dateline(brief.generatedAt))
                        .font(DaybriefTheme.serifBody(10))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.85))
                        // Clear the 14pt rounded corner so the dateline isn't clipped.
                        .padding(14)
                }
                .frame(width: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    QuietLine()
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(entries.prefix(6).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Rectangle().fill(DaybriefTheme.ink.opacity(0.08)).frame(height: 1)
                                .padding(.vertical, 8)
                        }
                        NumberedItem(index: index + 1, entry: entry, headlineLimit: 2)
                    }
                    Spacer(minLength: 10)
                    ActionFooter(extraCount: max(0, entries.count - 6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Empty

/// Shown when no snapshot exists yet (the host hasn't generated/loaded a brief).
public struct WidgetEmptyView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DaybriefTheme.accent)
            Text("No edition yet")
                .font(DaybriefTheme.serifDisplay(16))
                .foregroundStyle(DaybriefTheme.ink)
            Text("Open Daybrief to set today's page.")
                .font(DaybriefTheme.serifItalic(11))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pieces

/// A single small numbered item: an accent number, a concise serif headline, and an
/// eyebrow line (the source / section, in letterspaced small caps).
private struct NumberedItem: View {
    let index: Int
    let entry: BriefViewModel.Entry
    /// How many lines the headline may use (1 on large, 2 on medium).
    var headlineLimit: Int = 1

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(DaybriefTheme.serifDisplay(13))
                .foregroundStyle(DaybriefTheme.accent)
                .frame(minWidth: 13, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.headline)
                    .font(DaybriefTheme.serifBody(11.5))
                    .foregroundStyle(DaybriefTheme.ink)
                    .lineLimit(headlineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                if let eyebrow = entry.linkLabel {
                    Text(eyebrow)
                        .font(DaybriefTheme.sansBody(8).weight(.semibold))
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The view-only call to action: a quiet eyebrow line telling the reader where to act,
/// optionally noting how many more items didn't fit.
private struct ActionFooter: View {
    var extraCount: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DaybriefTheme.accent)
            Text("Take action in the Daybrief app")
                .font(DaybriefTheme.serifBody(9).weight(.semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(DaybriefTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .layoutPriority(1)
            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(DaybriefTheme.sansBody(8).weight(.semibold))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            // Trailing flex so the label keeps its room and scales instead of being
            // squeezed/truncated by a mid-row spacer on the narrow medium column.
            Spacer(minLength: 0)
        }
    }
}

/// The hero plate: the host-rendered PNG (or a warm gradient fallback) with the same
/// always-on darkening the panel uses, so a light masthead reads over any painting.
private struct WidgetHero: View {
    let png: Data?

    var body: some View {
        ZStack {
            if let png, let image = NSImage(data: png) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [DaybriefTheme.accent.opacity(0.38), DaybriefTheme.paper, DaybriefTheme.accent.opacity(0.16)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            ZStack {
                Color.black.opacity(0.34)
                LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The masthead, split so a leading "The" sets in italic above the rest in display
/// serif — matching the panel. Used over the (dark) hero, so it carries a soft shadow.
private struct WidgetMasthead: View {
    let text: String
    let displaySize: CGFloat
    let italicSize: CGFloat
    var accent: Color = DaybriefTheme.accent
    var onDark: Bool = false

    private var article: String? { text.hasPrefix("The ") ? "The" : nil }
    private var rest: String { article != nil ? String(text.dropFirst(4)) : text }

    var body: some View {
        VStack(spacing: -displaySize * 0.12) {
            if let article {
                Text(article)
                    .font(DaybriefTheme.serifItalic(italicSize))
                    .foregroundStyle(accent)
            }
            Text(rest)
                .font(DaybriefTheme.serifDisplay(displaySize))
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .shadow(color: .black.opacity(onDark ? 0.5 : 0), radius: 6, y: 1)
        .padding(.horizontal, 4)
    }
}

/// The quiet-day line, when there's nothing demanding attention.
private struct QuietLine: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf")
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(DaybriefTheme.accent.opacity(0.8))
            Text("A clear day. Enjoy the quiet.")
                .font(DaybriefTheme.serifItalic(12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Formatting helpers

/// Pure formatting shared across the widget sizes.
enum WidgetFormat {
    /// The masthead, falling back to a weekday-derived title for legacy briefs.
    static func masthead(_ brief: Brief) -> String {
        brief.masthead.isEmpty ? "The \(weekday.string(from: brief.generatedAt)) Brief" : brief.masthead
    }

    /// e.g. "17 JUN 2026".
    static func dateline(_ date: Date) -> String {
        dateFmt.string(from: date).uppercased()
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd MMM yyyy"; return f
    }()
}
