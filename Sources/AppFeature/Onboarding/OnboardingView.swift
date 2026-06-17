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

    /// The ordered onboarding steps.
    private enum Step: Int, CaseIterable, Identifiable {
        case apiKey, connect, spaces, briefTime

        var id: Int {
            rawValue
        }

        var title: String {
            switch self {
            case .apiKey: "Connect an AI model"
            case .connect: "Connect your tools"
            case .spaces: "Sort into Spaces"
            case .briefTime: "When should it land?"
            }
        }

        var subtitle: String {
            switch self {
            case .apiKey:
                "Daybrief sends only what you ask it to, to the model you choose. Start with one key."
            case .connect:
                "Each is optional. Connect what you want in your morning brief — you can add more later."
            case .spaces:
                "Keep work and personal apart so a work brief never blends in your personal mail."
            case .briefTime:
                "Your brief is written each morning at this time. It also catches up after sleep."
            }
        }
    }

    /// Creates the onboarding flow bound to `model`.
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DaybriefTheme.ink.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    stepHeading
                    stepContent
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            Divider().overlay(DaybriefTheme.ink.opacity(0.08))
            footer
        }
        .background(DaybriefTheme.paper)
        .frame(minWidth: 640, minHeight: 560)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 12) {
            Text("Daybrief")
                .font(DaybriefTheme.serifDisplay(34))
                .foregroundStyle(DaybriefTheme.ink)
            StepDots(steps: Step.allCases.count, current: step.rawValue)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private var stepHeading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(DaybriefTheme.serifDisplay(26))
                .foregroundStyle(DaybriefTheme.ink)
            Text(step.subtitle)
                .font(DaybriefTheme.serifBody(15))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .apiKey: APIKeyStep(model: model)
        case .connect: ConnectToolsStep(model: model)
        case .spaces: AssignSpacesStep(model: model)
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

/// The progress dots shown under the wordmark.
private struct StepDots: View {
    let steps: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0 ..< steps, id: \.self) { index in
                Capsule()
                    .fill(index == current ? DaybriefTheme.accent : DaybriefTheme.ink.opacity(0.15))
                    .frame(width: index == current ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.18), value: current)
            }
        }
    }
}
