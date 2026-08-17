import DaybriefCore
import Pipeline
import SlackConnector
import SwiftUI

/// The panes Settings is divided into. One concern each, so no pane is a long scroll
/// of unrelated controls.
public enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case tools, brief, model, app

    public var id: String { rawValue }

    /// The sidebar label.
    public var title: String {
        switch self {
        case .tools: "Tools"
        case .brief: "Brief"
        case .model: "Model"
        case .app: "App"
        }
    }

    /// The pane's own heading, set in the editorial serif.
    public var heading: String {
        switch self {
        case .tools: "Connected tools"
        case .brief: "Your daily brief"
        case .model: "AI model"
        case .app: "App"
        }
    }

    /// One line under the heading saying what this pane decides.
    public var subheading: String {
        switch self {
        case .tools: "What Daybrief reads each morning."
        case .brief: "When the edition is written, and in what voice."
        case .model: "The model that writes it. Your key, your choice."
        case .app: "How Daybrief behaves on your Mac."
        }
    }

    public var symbol: String {
        switch self {
        case .tools: "link"
        case .brief: "sun.max"
        case .model: "sparkles"
        case .app: "gearshape"
        }
    }
}

/// The Settings window: a sidebar of panes beside the selected pane's content.
///
/// Replaces a single scrolling column that stacked five unrelated concerns — and grew
/// with every connector — with somewhere to *be*. The material is the brief's own
/// (paper, the editorial serif, the golden accent) so Settings reads as the same app
/// rather than a system preferences window bolted on.
public struct SettingsView: View {
    @Bindable private var model: AppModel
    @State private var pane: SettingsPane = .tools

    /// Creates the settings screen bound to `model`.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model, selection: $pane)

            SettingsRailDivider()

            ScrollView {
                SettingsPaneContent(model: model, pane: pane)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DaybriefTheme.paper)
        .frame(minWidth: 760, minHeight: 560)
    }
}

/// One pane's content, with no scroll container of its own.
///
/// Kept separate from ``SettingsView`` for the same reason ``BriefPanelSnapshotView``
/// exists: `ImageRenderer` doesn't rasterize `ScrollView` content, so a pane can only
/// be reviewed offscreen if its content can be composed without one.
public struct SettingsPaneContent: View {
    @Bindable var model: AppModel
    let pane: SettingsPane

    /// Creates the content for one pane. Public so the offscreen snapshot tool can
    /// compose panes without the window's scroll container.
    public init(model: AppModel, pane: SettingsPane) {
        self.model = model
        self.pane = pane
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pane.heading)
                    .font(DaybriefTheme.serifDisplay(26))
                    .foregroundStyle(DaybriefTheme.ink)
                Text(pane.subheading)
                    .font(DaybriefTheme.serifBody(13))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }

            switch pane {
            case .tools: ToolsPane(model: model)
            case .brief: BriefPane(model: model)
            case .model: ModelPane(model: model)
            case .app: AppPane(model: model)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sidebar

/// The left rail: the app's own name, the panes, and the next edition's time.
struct SettingsSidebar: View {
    @Bindable var model: AppModel
    @Binding var selection: SettingsPane

    /// The fire time as wall-clock text, in the user's locale (7:00 AM / 07:00).
    private static func timeText(_ time: FireTime) -> String {
        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Daybrief")
                .font(DaybriefTheme.serifDisplay(19))
                .foregroundStyle(DaybriefTheme.ink)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 18)

            VStack(spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(pane: pane, isSelected: pane == selection) { selection = pane }
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 16)

            // The one fact worth standing on a settings window: when the next edition
            // lands. It's what everything here is in service of.
            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT EDITION")
                    .font(DaybriefTheme.sansMedium(9))
                    .tracking(0.6)
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(DaybriefTheme.accent)
                        .frame(width: 6, height: 6)
                    Text(Self.timeText(model.briefTime))
                        .font(DaybriefTheme.serifBody(15))
                        .foregroundStyle(DaybriefTheme.ink)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .frame(width: 188, alignment: .leading)
        .frame(maxHeight: .infinity)
        // A hair darker than the page so the rail reads as a margin rather than a panel.
        // Explicitly on paper, not a bare tint: an alpha over nothing composites onto
        // the window's backing, which renders the rail black.
        .background(DaybriefTheme.paper.overlay(DaybriefTheme.ink.opacity(0.045)))
    }
}

private struct SidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? DaybriefTheme.ink : DaybriefTheme.inkSecondary)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DaybriefTheme.ink : DaybriefTheme.inkSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? DaybriefTheme.accent.opacity(0.28)
                        : DaybriefTheme.ink.opacity(isHovering ? 0.05 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// The Settings window composed for an offscreen snapshot: the real sidebar beside the
/// real pane content, minus the scroll container `ImageRenderer` can't draw.
///
/// The same trick as ``BriefPanelSnapshotView`` — a design this size only gets reviewed
/// if it can be rendered and looked at.
public struct SettingsWindowSnapshotView: View {
    @Bindable private var model: AppModel
    private let pane: SettingsPane

    public init(model: AppModel, pane: SettingsPane) {
        self.model = model
        self.pane = pane
    }

    public var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model, selection: .constant(pane))

            SettingsRailDivider()

            SettingsPaneContent(model: model, pane: pane)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Matches the real window. Without it the rail hairline's alpha composites onto
        // the renderer's black backing and the snapshot shows a rule that isn't there.
        .background(DaybriefTheme.paper)
    }
}

// MARK: - Pane chrome

/// A titled group inside a pane: a small label over hairline-separated rows.
///
/// Deliberately not a card. The old screen nested cards inside cards — a bordered
/// section holding a bordered list — which is most of why it read as busy.
struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(DaybriefTheme.sansMedium(10))
                    .tracking(0.7)
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The vertical hairline between the rail and the page.
///
/// Drawn rather than a tinted `Divider`: `.overlay` paints *over* the system divider
/// instead of replacing it, which reads as a hard black rule against paper.
struct SettingsRailDivider: View {
    var body: some View {
        Rectangle()
            .fill(DaybriefTheme.ink.opacity(0.10))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

/// A hairline between rows in a ``SettingsGroup``.
struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(DaybriefTheme.ink.opacity(0.08))
            .frame(height: 1)
    }
}
