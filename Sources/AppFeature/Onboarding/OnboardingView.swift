import DaybriefCore
import LLMKit
import Pipeline
import SwiftUI

/// The first-run setup flow (design §14): enter an AI key, connect tools, assign
/// each connection to a Space, set the brief time, then generate the first brief.
///
/// Each step is optional except the API key (the brief needs a model to synthesize).
/// Connecting tools is encouraged but the flow generates a "quiet day" brief with
/// zero connectors, so the user can always reach `Finish`.
public struct OnboardingView: View {
    @Bindable private var model: AppModel
    @State private var step: Step = .apiKey
    private var snapshot = false

    /// The ordered onboarding steps.
    private enum Step: Int, CaseIterable, Identifiable {
        case apiKey, connect, briefTime

        var id: Int {
            rawValue
        }

        var title: String {
            switch self {
            case .apiKey: "Connect an AI model"
            case .connect: "Connect your tools"
            case .briefTime: "When should it land?"
            }
        }

        var subtitle: String {
            switch self {
            case .apiKey:
                "Daybrief sends only what you ask it to, to the model you choose. Start with one key."
            case .connect:
                "Each is optional. Connect what you want in your morning brief — you can add more later."
            case .briefTime:
                "Your brief is written each morning at this time. It also catches up after sleep."
            }
        }
    }

    /// Creates the onboarding flow bound to `model`.
    public init(model: AppModel) {
        self.model = model
    }

    /// Composes the real setup content without a ScrollView for offscreen review.
    public init(model: AppModel, snapshotStep: Int) {
        self.model = model
        self._step = State(initialValue: Step(rawValue: snapshotStep) ?? .apiKey)
        self.snapshot = true
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            SettingsRowDivider()

            if snapshot {
                pageContent
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView { pageContent }
            }

            SettingsRowDivider()
            footer
        }
        .background(.white)
        .frame(minWidth: 680, minHeight: 720)
        .tint(DaybriefTheme.ink)
    }

    // MARK: - Chrome

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeading
            stepContent
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(spacing: 0) {
            SetupArtwork(title: "A better start to your day.", subtitle: "Your morning, thoughtfully put together by Daybrief.")
                .frame(height: 150)
            HStack(spacing: 20) {
                ForEach(Step.allCases) { item in
                    HStack(spacing: 7) {
                        Group {
                            if item.rawValue < step.rawValue {
                                Image(systemName: "checkmark")
                            } else {
                                Text("\(item.rawValue + 1)")
                            }
                        }
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 23, height: 23)
                            .background(item == step ? DaybriefTheme.accent : DaybriefTheme.ink.opacity(0.06), in: Circle())
                        Text(["AI model", "Your tools", "Delivery"][item.rawValue])
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(item == step ? DaybriefTheme.ink : DaybriefTheme.inkSecondary)
                    if item != .briefTime { Spacer(minLength: 0) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of 3: \(step.title)")
        }
    }

    private var stepHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DaybriefTheme.ink)
            Text(step.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .apiKey: APIKeyStep(model: model)
        case .connect: ConnectToolsStep(model: model)
        case .briefTime: BriefTimeStep(model: model)
        }
    }

    private var footer: some View {
        HStack {
            if step != .apiKey {
                Button("Back") { goBack() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            Spacer()
            if let error = model.lastError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
            }
            primaryButton
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .briefTime:
            DBPrimaryButton(
                title: model.isGenerating ? "Generating…" : "Finish & write my brief",
                isBusy: model.isGenerating
            ) {
                Task { await model.generateBriefNow() }
            }
            .disabled(model.isGenerating)
        case .apiKey:
            DBPrimaryButton(title: "Continue") { goNext() }
                // Can't advance until a model is selected (proves the key works).
                .disabled(model.selectedModel.isEmpty)
        default:
            DBPrimaryButton(title: "Continue") { goNext() }
        }
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = next }
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.easeInOut(duration: 0.18)) { step = prev }
    }
}
