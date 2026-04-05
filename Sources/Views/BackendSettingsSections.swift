import SwiftUI

struct CohereMLXSettingsSection: View {
    @ObservedObject var cohereService: CohereMLXService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption.weight(.medium))
                    Text("CohereLabs/cohere-transcribe-03-2026")
                        .font(.system(.body, design: .monospaced))
                }

                Spacer()

                statusLabel
            }

            HStack {
                Text("Language")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("English (fixed)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("First-class local-native transcription runs fully on-device via Python/MLX.")
                .font(.caption)
                .foregroundColor(.green)
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

            Text("Requires HuggingFace login and model acceptance. Run `hf auth login` once if not already configured.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch cohereService.modelState {
        case .notLoaded:
            Label("Not Loaded", systemImage: "circle")
                .font(.caption)
                .foregroundColor(.secondary)
        case .loading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .ready:
            Label("Ready", systemImage: "circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failed(let reason):
            Label("Failed: \(reason)", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

struct TranscriptionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var whisperKitService: WhisperKitService
    @ObservedObject var cohereMLXService: CohereMLXService

    @Binding var showingWhisperKitSetup: Bool
    @Binding var transcriptionModels: [ModelInfo]
    @Binding var isLoadingTranscriptionModels: Bool

    let loadTranscriptionModels: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Speech-to-text provider for converting audio to text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $settings.transcriptionProviderRaw) {
                    ForEach(TranscriptionProvider.allCases, id: \.rawValue) { provider in
                        HStack {
                            Text(provider.displayName)
                            if provider.supportsRefinementInOneCall {
                                Text("+ Refinement")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.transcriptionProviderRaw) { _, newValue in
                    if let provider = TranscriptionProvider(rawValue: newValue) {
                        settings.transcriptionBaseURL = provider.defaultBaseURL
                        settings.transcriptionModel = provider == .whisperKit ? settings.whisperKitModel : provider.defaultModel
                    }
                    loadTranscriptionModels()
                }

                if settings.transcriptionProvider.supportsRefinementInOneCall {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.green)
                        Text("This provider handles final text in one call. Separate refinement settings are ignored.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                if settings.transcriptionProvider == .whisperKit {
                    WhisperKitSettingsSection(
                        settings: settings,
                        whisperKitService: whisperKitService,
                        showingWhisperKitSetup: $showingWhisperKitSetup
                    )
                }

                if settings.transcriptionProvider == .cohereMLX {
                    CohereMLXSettingsSection(cohereService: cohereMLXService)
                }

                if settings.transcriptionProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        SecureField("Enter API key", text: $settings.transcriptionAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.transcriptionAPIKey) { _, _ in
                                loadTranscriptionModels()
                            }
                    }
                }

                if !settings.transcriptionProvider.isLocalNativeProvider {
                    ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
                }

                if !settings.transcriptionProvider.isLocalNativeProvider {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.caption.weight(.medium))
                        HStack {
                            if isLoadingTranscriptionModels {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }

                            if transcriptionModels.isEmpty {
                                TextField("Model name", text: $settings.transcriptionModel)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("", selection: $settings.transcriptionModel) {
                                    ForEach(transcriptionModels) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                            }

                            Button(action: loadTranscriptionModels) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .onAppear { loadTranscriptionModels() }
        .sheet(isPresented: $showingWhisperKitSetup) {
            WhisperKitSetupView()
        }
    }
}

struct WhisperKitSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var whisperKitService: WhisperKitService
    @Binding var showingWhisperKitSetup: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Model")
                        .font(.caption.weight(.medium))
                    Text(settings.whisperKitModel)
                        .font(.system(.body, design: .monospaced))
                }

                Spacer()

                if whisperKitService.modelState == .ready {
                    Label("Ready", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Button("Download & Manage Models...") {
                showingWhisperKitSetup = true
            }

            Text("First-class local-native transcription runs fully on-device.")
                .font(.caption)
                .foregroundColor(.green)
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Decoding Strategy")
                    .font(.caption.weight(.medium))

                HStack {
                    Text("Language")
                    Spacer()
                    Picker("Language", selection: Binding(
                        get: { settings.whisperKitLanguageSelectionRaw },
                        set: { settings.whisperKitLanguageSelectionRaw = $0 }
                    )) {
                        Text(AppSettings.whisperKitAutoDetectLanguageSelection)
                            .tag(AppSettings.whisperKitAutoDetectLanguageSelection)
                        ForEach(WhisperKitLanguage.allCases, id: \.self) { language in
                            Text(language.rawValue).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                HStack {
                    Text("Profile")
                    Spacer()
                    Picker("Profile", selection: Binding(
                        get: { settings.whisperKitProfile },
                        set: { settings.whisperKitProfile = $0 }
                    )) {
                        ForEach(WhisperKitProfile.allCases, id: \.self) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct RefinementSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ollamaService: OllamaService

    @Binding var refinementModels: [ModelInfo]
    @Binding var isLoadingRefinementModels: Bool

    let loadRefinementModels: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Refinement")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Optional text cleanup and formatting layer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)

            Toggle(isOn: $settings.skipRefinement) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip Refinement (Raw Mode)")
                        .font(.body.weight(.medium))
                    Text("Use original transcript without LLM processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(settings.skipRefinement ? Color.orange.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.skipRefinement ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )

            Toggle(isOn: $settings.disableSilenceTrimming) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disable Silence Trimming")
                        .font(.body.weight(.medium))
                    Text("Send full audio without trimming silence from start/end")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(settings.disableSilenceTrimming ? Color.orange.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.disableSilenceTrimming ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )

            if settings.transcriptionProvider.supportsRefinementInOneCall && !settings.skipRefinement {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Refinement is handled by your transcription provider")
                            .font(.callout.weight(.medium))
                    }

                    Text("Since you're using \(settings.transcriptionProvider.rawValue), this section is only used if you switch to a transcription-only provider.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            VStack(alignment: .leading, spacing: 12) {
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
                .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)

                if settings.refinementProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        SecureField("Enter API key", text: $settings.refinementAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.refinementAPIKey) { _, _ in
                                loadRefinementModels()
                            }
                    }
                    .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                    .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                }

                ValidatedURLField(title: "Base URL", url: $settings.refinementBaseURL)
                    .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                    .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption.weight(.medium))
                    HStack {
                        if isLoadingRefinementModels {
                            ProgressView()
                                .scaleEffect(0.7)
                        }

                        if refinementModels.isEmpty {
                            TextField("Model name", text: $settings.refinementModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: $settings.refinementModel) {
                                ForEach(refinementModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }

                        Button(action: loadRefinementModels) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)

                if settings.refinementProvider == .ollama {
                    OllamaManagementSection(
                        settings: settings,
                        ollamaService: ollamaService,
                        loadRefinementModels: loadRefinementModels
                    )
                }
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

struct OllamaManagementSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ollamaService: OllamaService

    let loadRefinementModels: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            ValidatedURLField(title: "Ollama URL", url: $settings.ollamaBaseURL)
                .onChange(of: settings.ollamaBaseURL) { _, _ in
                    Task { await ollamaService.checkOllamaStatus() }
                }

            HStack {
                if ollamaService.isOllamaRunning {
                    Label("Ollama Running", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Label("Ollama Not Running", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()

                Button(action: {
                    Task { await ollamaService.checkOllamaStatus() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }

            if !ollamaService.isOllamaRunning {
                Text("To start Ollama: brew install ollama && ollama serve")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            if ollamaService.isOllamaRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommended Models")
                        .font(.caption.weight(.medium))

                    ForEach(OllamaService.recommendedModels, id: \.self) { model in
                        HStack {
                            Text(model)
                                .font(.caption)

                            Spacer()

                            if ollamaService.isModelInstalled(model) {
                                Label("Installed", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)

                                Button("Update") {
                                    Task { await ollamaService.updateModel(model) }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .disabled(ollamaService.isPulling)
                            } else {
                                Button("Download") {
                                    Task {
                                        if await ollamaService.pullModel(model) {
                                            loadRefinementModels()
                                        }
                                    }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(ollamaService.isPulling)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if ollamaService.isPulling {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(ollamaService.pullProgress)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = ollamaService.pullError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Button("Keep Model Loaded") {
                        Task { await ollamaService.keepModelLoaded(settings.refinementModel) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
        .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
    }
}
