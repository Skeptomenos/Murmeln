import SwiftUI

struct RefinementSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ollamaService: OllamaService

    @Binding var refinementModels: [ModelInfo]
    @Binding var isLoadingRefinementModels: Bool

    let loadRefinementModels: () -> Void

    @State private var apiKeyDraft = ""
    @FocusState private var apiKeyFocused: Bool

    private func commitAPIKey() {
        let previous = settings.refinementAPIKey
        guard apiKeyDraft != previous else { return }
        settings.refinementAPIKey = apiKeyDraft
        if AppSettings.shouldTriggerModelDiscovery(committedKey: apiKeyDraft, previousKey: previous) {
            loadRefinementModels()
        }
    }

    private var refinementControlsDisabled: Bool {
        settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Text cleanup") {
                Toggle(isOn: $settings.skipRefinement) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Use the original transcript")
                            .font(.body.weight(.medium))
                        Text("Skip refinement and keep the words as transcribed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Skip Refinement, Raw Mode")

                if settings.transcriptionProvider.supportsRefinementInOneCall && !settings.skipRefinement {
                    Divider()
                    SettingsNote(text: "\(settings.transcriptionProvider.rawValue) handles transcription and refinement together. The separate provider below is used only with transcription-only models.", icon: "sparkles")
                }
            }

            SettingsGroup(title: "Refinement provider", subtitle: "Clean up grammar and formatting with your selected writing style.") {
                Picker("Provider", selection: $settings.refinementProviderRaw) {
                    ForEach(Provider.allCases, id: \.rawValue) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.refinementProviderRaw) { _, newValue in
                    if let provider = Provider(rawValue: newValue) {
                        settings.refinementBaseURL = provider.defaultBaseURL
                    }
                    loadRefinementModels()
                }
                .disabled(refinementControlsDisabled)

                if settings.refinementProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API key")
                            .font(.caption.weight(.medium))
                        // M5: persist and discover models only on Enter or
                        // focus loss, never for each keystroke.
                        SecureField("Enter API key", text: $apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($apiKeyFocused)
                            .onSubmit { commitAPIKey() }
                            .onChange(of: apiKeyFocused) { _, focused in
                                if !focused { commitAPIKey() }
                            }
                            .onAppear { apiKeyDraft = settings.refinementAPIKey }
                            .onChange(of: settings.refinementProviderRaw) { _, _ in
                                apiKeyDraft = settings.refinementAPIKey
                            }
                            .accessibilityLabel("Refinement API key")
                            .disabled(refinementControlsDisabled)
                        KeychainSecurityNoticeBanner(settings: settings)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.caption.weight(.medium))
                    HStack(spacing: 10) {
                        if isLoadingRefinementModels {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Loading refinement models")
                        }

                        if refinementModels.isEmpty {
                            TextField("Model name", text: $settings.refinementModel)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Refinement model name")
                        } else {
                            Picker("Refinement model", selection: $settings.refinementModel) {
                                ForEach(refinementModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }

                        Button(action: loadRefinementModels) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh refinement models")
                        .accessibilityLabel("Refresh refinement models")
                    }
                    if refinementModels.isEmpty && !isLoadingRefinementModels {
                        Text("Enter a model name, or refresh to load available models.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(refinementControlsDisabled)

                Divider()
                DisclosureGroup("Server connection") {
                    ValidatedURLField(title: "Base URL", url: $settings.refinementBaseURL)
                        .disabled(refinementControlsDisabled)
                        .padding(.top, 12)
                }
                if !URLValidation.isValid(settings.refinementBaseURL) {
                    SettingsNote(text: "The server URL is invalid. Open Server connection to correct it.", icon: "exclamationmark.circle", color: .red)
                }
            }

            if settings.refinementProvider == .ollama {
                OllamaManagementSection(
                    settings: settings,
                    ollamaService: ollamaService,
                    loadRefinementModels: loadRefinementModels
                )
            }
        }
        .onAppear {
            loadRefinementModels()
            if settings.refinementProvider == .ollama {
                Task { await ollamaService.checkOllamaStatus() }
            }
        }
    }
}
