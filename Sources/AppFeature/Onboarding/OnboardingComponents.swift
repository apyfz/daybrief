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
