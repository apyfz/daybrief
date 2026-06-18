import LLMKit
import SwiftUI

/// Onboarding step 1 (design §14.1): connect an AI model.
///
/// Recommends OpenRouter (one key, any model), but also exposes the direct
/// providers and a local Ollama endpoint. On `Save & load models` it calls
/// `model.saveAPIKey` then `model.availableModels()` so the user can pick a model;
/// selecting a model is what proves the key works and unlocks `Continue`.
struct APIKeyStep: View {
    @Bindable var model: AppModel

    @State private var apiKey = ""
    @State private var ollamaEndpoint = "http://127.0.0.1:11434"
    @State private var models: [ModelInfo] = []
    @State private var isLoading = false
    @State private var showAllModels = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            providerPicker

            if model.selectedProvider == .openRouter {
                recommendationCallout
            }

            credentialField

            HStack(spacing: 12) {
                DBPrimaryButton(
                    title: isLoading ? "Loading models…" : "Save & load models",
                    isBusy: isLoading
                ) {
                    Task { await saveAndLoad() }
                }
                .disabled(isLoading || !canSave)

                if !models.isEmpty {
                    Text("\(models.count) models available")
                        .font(.system(size: 12))
                        .foregroundStyle(DaybriefTheme.inkSecondary)
                }
            }

            if !models.isEmpty {
                modelPicker
            }
        }
        .onChange(of: model.selectedProvider) { _, _ in
            // Switching provider invalidates the loaded list and any pasted key.
            models = []
            apiKey = ""
        }
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Provider")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
            Picker("Provider", selection: $model.selectedProvider) {
                ForEach(Provider.allCases) { provider in
                    Text(displayName(provider)).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var recommendationCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "star.fill")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.accent)
            Text("Recommended. One OpenRouter key reaches every model — Claude, GPT, Gemini and more — so you can switch later without new keys.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(DaybriefTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var credentialField: some View {
        if model.selectedProvider == .ollama {
            DBLabeledField(
                label: "Ollama endpoint",
                placeholder: "http://127.0.0.1:11434",
                text: $ollamaEndpoint
            )
            Text("No key needed — Ollama runs models locally on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
        } else {
            DBLabeledField(
                label: "\(displayName(model.selectedProvider)) API key",
                placeholder: "Paste your key",
                isSecure: true,
                text: $apiKey
            )
            Text("Stored in your macOS Keychain. It never leaves this Mac except in requests to the provider you chose.")
                .font(.system(size: 12))
                .foregroundStyle(DaybriefTheme.inkSecondary)
        }
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DaybriefTheme.inkSecondary)
            Picker("Model", selection: $model.selectedModel) {
                ForEach(models.recommendedFirst(selection: model.selectedModel, showAll: showAllModels)) { info in
                    Text((info.displayName ?? info.id) + (info.isFree ? " · free" : "")).tag(info.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
            .onChange(of: model.selectedModel) { _, _ in
                Task { await model.persistSelectedModel() }
            }

            if models.hasRecommendedAndOthers {
                Toggle("Show all models", isOn: $showAllModels)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
            }
            if models.freeSelection(model.selectedModel) != nil {
                Text("Free models can be rate-limited and may need prompt logging enabled in your OpenRouter privacy settings (openrouter.ai/settings/privacy).")
                    .font(.system(size: 11))
                    .foregroundStyle(DaybriefTheme.inkSecondary)
                    .frame(maxWidth: 360, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canSave: Bool {
        if model.selectedProvider == .ollama {
            return !ollamaEndpoint.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func saveAndLoad() async {
        isLoading = true
        defer { isLoading = false }

        let baseURL: URL? = model.selectedProvider == .ollama
            ? URL(string: ollamaEndpoint.trimmingCharacters(in: .whitespaces))
            : nil
        let key = model.selectedProvider == .ollama
            ? ""
            : apiKey.trimmingCharacters(in: .whitespaces)

        await model.saveAPIKey(key, provider: model.selectedProvider, baseURL: baseURL)
        let loaded = await model.availableModels()
        models = loaded
        // Seed a known-good recommended model rather than whatever sorts first.
        if model.selectedModel.isEmpty, let preferred = loaded.first(where: \.isRecommended) ?? loaded.first {
            model.selectedModel = preferred.id
        }
        // Persist the choice so the app doesn't drop back to onboarding next launch
        // (selectedModel lives in Settings; without this it was only ever in memory).
        if !model.selectedModel.isEmpty {
            await model.persistSelectedModel()
        }
    }

    private func displayName(_ provider: Provider) -> String {
        switch provider {
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Gemini"
        case .ollama: "Ollama (local)"
        }
    }
}
