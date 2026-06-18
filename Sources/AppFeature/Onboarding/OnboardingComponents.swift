import SwiftUI

/// A filled accent primary button used for the dominant action on each onboarding
/// step and in settings sheets. Utilitarian — readable over the warm paper.
struct DBPrimaryButton: View {
    let title: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DaybriefTheme.ink)
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(DaybriefTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A secondary, outline-style button (e.g. "Connect", "Skip for now").
struct DBSecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule().stroke(DaybriefTheme.ink.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A labelled single-line secure or plain text field with consistent paper styling.
struct DBLabeledField: View {
    let label: String
    var placeholder: String = ""
    var isSecure: Bool = false
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DaybriefTheme.ink.opacity(0.12), lineWidth: 1)
            )
        }
    }
}

/// A numbered, collapsible block of guided setup steps (used for the BYO Google
/// client and the internal Slack app walkthroughs). Keeps the dense provider
/// instructions out of the way until the user expands them.
struct DBGuidedSteps: View {
    let title: String
    let steps: [String]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.number")
                        .font(.system(size: 12))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .foregroundStyle(DaybriefTheme.ink)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DaybriefTheme.ink)
                                .frame(width: 18, height: 18)
                                .background(DaybriefTheme.accent.opacity(0.5), in: Circle())
                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(DaybriefTheme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
        )
    }
}

/// One step in a guided walkthrough: prose plus optional visual emphasis for a
/// "don't get this wrong" gotcha, and an optional inline "Open …" link below it.
struct DBStep: Identifiable {
    let id = UUID()
    /// The step instruction.
    let text: String
    /// When `true`, the step is rendered with the accent emphasis treatment so the
    /// key gotcha stands out at a glance.
    var emphasized: Bool = false
    /// An optional inline link rendered under the step (e.g. "Open the console").
    var link: (label: String, url: URL)?

    init(_ text: String, emphasized: Bool = false, link: (label: String, url: URL)? = nil) {
        self.text = text
        self.emphasized = emphasized
        self.link = link
    }
}

/// An always-visible, scannable numbered walkthrough for the dedicated connector
/// screens. Each step is a numbered chip + prose; an `emphasized` step gets an
/// accent-tinted surface so the critical gotcha is visually unmissable, and a step
/// may carry an inline "Open …" link.
struct DBStepList: View {
    let steps: [DBStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                stepRow(index: index, step: step)
            }
        }
    }

    private func stepRow(index: Int, step: DBStep) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DaybriefTheme.ink)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        step.emphasized ? DaybriefTheme.accent : DaybriefTheme.accent.opacity(0.45)
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(step.text)
                    .font(.system(size: 13))
                    .foregroundStyle(step.emphasized ? DaybriefTheme.ink : DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link = step.link {
                    DBOpenLink(label: link.label, url: link.url)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(step.emphasized ? 12 : 0)
        .background {
            if step.emphasized {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DaybriefTheme.accent.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(DaybriefTheme.accent.opacity(0.55), lineWidth: 1)
                    )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1). \(step.text)")
        .accessibilityHint(step.emphasized ? "Important step" : "")
    }
}

/// A small outline "Open …" link pill that opens `url` in the browser, styled to
/// match ``DBSecondaryButton`` but routed through `openURL` so it is a real link.
struct DBOpenLink: View {
    let label: String
    let url: URL
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DaybriefTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().stroke(DaybriefTheme.ink.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(label)")
        .accessibilityHint("Opens in your browser")
    }
}

/// A plainly-stated requested scope: the scope identifier (monospaced) plus a
/// one-line "why" so the user can see exactly what the connector will read.
struct DBScopeRow: View {
    let scope: String
    let why: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(scope)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DaybriefTheme.ink)
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scope \(scope). \(why)")
    }
}

/// An inline, warm error banner used to surface ``AppModel/lastError`` on a
/// connector screen, so the failure stays next to the action that caused it.
struct DBInlineError: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(.red.opacity(0.25), lineWidth: 1)
        )
        .accessibilityLabel("Error. \(message)")
    }
}

/// A section label + grouped surface for a block on a connector screen (e.g.
/// "Set it up", "What it will read"), keeping the dedicated screens scannable.
struct DBDetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .textCase(.uppercase)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
        )
    }
}

/// A tappable hub row for one connector: icon, name, a one-line "what it surfaces",
/// a status pill (Not connected / ✓ Connected <label>), and a Set up / Edit action.
struct DBConnectorRow: View {
    let symbol: String
    let name: String
    let surfaces: String
    let isConnected: Bool
    let connectedLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DaybriefTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(DaybriefTheme.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DaybriefTheme.ink)
                        if isConnected {
                            statusBadge
                        }
                    }
                    Text(surfaces)
                        .font(.system(size: 12))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(isConnected ? "Edit" : "Set up")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DaybriefTheme.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DaybriefTheme.ink.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(isConnected ? "Connected, \(connectedLabel ?? "")" : "Not connected")
        .accessibilityHint(isConnected ? "Edit this connection" : "Set up this connection")
        .accessibilityAddTraits(.isButton)
    }

    private var statusBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text(connectedLabel ?? "Connected")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DaybriefTheme.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DaybriefTheme.accent.opacity(0.5), in: Capsule())
    }
}

/// A small inline picker of the available Spaces, rendered as selectable pills.
struct DBSpacePills: View {
    let spaces: [String]
    let displayName: (String) -> String
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(spaces, id: \.self) { key in
                let isSelected = key == selection
                Button {
                    selection = key
                } label: {
                    Text(displayName(key))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? DaybriefTheme.ink : DaybriefTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isSelected ? DaybriefTheme.accent.opacity(0.6) : .clear)
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? .clear : DaybriefTheme.ink.opacity(0.15),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
