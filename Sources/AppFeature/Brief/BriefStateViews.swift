import SwiftUI

/// The "no brief yet" affordance: a calm, intentional invitation to generate the
/// first edition rather than an empty void. Shown when `model.currentBrief` is nil
/// and nothing is in flight.
struct BriefEmptyStateView: View {
    /// Whether a generation is currently running (disables the button + shows progress).
    let isGenerating: Bool
    /// Invoked when the reader asks for today's brief.
    let onGenerate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(DaybriefTheme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("No edition yet today")
                    .font(DaybriefTheme.serifDisplay(22))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("When you're ready, we'll read through your morning and set the page.")
                    .font(DaybriefTheme.serifBody(13).italic())
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }

            Button(action: onGenerate) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isGenerating ? "Setting the page…" : "Generate today's brief")
                        .font(DaybriefTheme.serifBody(14))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(DaybriefTheme.accent.opacity(isGenerating ? 0.5 : 1))
                )
                .foregroundStyle(DaybriefTheme.ink)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .accessibilityLabel("Generate today's brief")
        }
        .padding(.vertical, 56)
        .frame(maxWidth: .infinity)
    }
}

/// The first-run welcome: shown when setup isn't complete (no AI model yet) and no
/// brief exists. Invites the reader into onboarding instead of failing into an
/// error — you can't synthesize an edition without a model.
struct BriefWelcomeStateView: View {
    /// Opens the setup / onboarding window.
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(DaybriefTheme.accent)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to Daybrief")
                    .font(DaybriefTheme.serifDisplay(24))
                    .foregroundStyle(DaybriefTheme.ink)
                Text("Add an AI model and connect your tools, and each morning we'll read through your day and set the page.")
                    .font(DaybriefTheme.serifBody(13).italic())
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 280)
            }

            Button(action: onGetStarted) {
                Text("Get started")
                    .font(DaybriefTheme.serifBody(14))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DaybriefTheme.accent))
                    .foregroundStyle(DaybriefTheme.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Get started")
        }
        .padding(.vertical, 52)
        .frame(maxWidth: .infinity)
    }
}

/// The loading state shown while the first edition is being assembled, when there
/// is no prior brief to keep on screen. Quietly literary rather than a spinner-only.
struct BriefLoadingStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Reading your morning…")
                .font(DaybriefTheme.serifBody(14).italic())
                .foregroundStyle(DaybriefTheme.inkSecondary)
        }
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating today's brief")
    }
}

/// A calm error banner shown above an (otherwise empty) panel when generation
/// failed outright — with a retry. Phrased gently; the detail comes from the model.
struct BriefErrorStateView: View {
    /// The user-facing error message from `model.lastError`.
    let message: String
    /// Whether a retry is currently running.
    let isGenerating: Bool
    /// Invoked to try generating again.
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.bubble")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("We couldn't set today's edition")
                    .font(DaybriefTheme.serifDisplay(20))
                    .foregroundStyle(DaybriefTheme.ink)
                Text(message)
                    .font(DaybriefTheme.serifBody(13))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }

            Button(action: onRetry) {
                HStack(spacing: 8) {
                    if isGenerating { ProgressView().controlSize(.small) }
                    Text(isGenerating ? "Trying again…" : "Try again")
                        .font(DaybriefTheme.serifBody(13))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().strokeBorder(DaybriefTheme.ink.opacity(0.25), lineWidth: 1))
                .foregroundStyle(DaybriefTheme.ink)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
        }
        .padding(.vertical, 48)
        .frame(maxWidth: .infinity)
    }
}
