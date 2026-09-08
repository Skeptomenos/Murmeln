import SwiftUI

/// M4: shown while an API key is parked in UserDefaults because the Keychain
/// rejected the write.
struct KeychainSecurityNoticeBanner: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        if let notice = settings.keychainSecurityNotice {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// Phase 8: catalog-driven model section — status, download-with-progress,
/// unified language control (annotated per languageMode), usage notes.
/// One view serves every catalog entry (the WhisperKit setup sheet remains
/// for Whisper variant management).
struct CatalogModelSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var downloads: CatalogDownloadManager
    let entry: CatalogEntry

    /// Slice 5c/F1: observe the runtime's published state so `.loading→.ready`
    /// repaints the status label instead of leaving a stale "Loading…".
    @StateObject private var status: RuntimeStatusModel
    @State private var showingDeleteConfirmation = false

    init(
        settings: AppSettings,
        entry: CatalogEntry,
        downloads: CatalogDownloadManager = .shared
    ) {
        self.settings = settings
        self.entry = entry
        _downloads = ObservedObject(wrappedValue: downloads)
        let runtime: any TranscriptionRuntime = switch entry.runtime {
        case .fluidAudio: FluidAudioRuntime.shared
        case .whisperKit: WhisperKitRuntime.shared
        }
        _status = StateObject(wrappedValue: RuntimeStatusModel(runtime: runtime))
    }

    private var runtime: any TranscriptionRuntime {
        switch entry.runtime {
        case .fluidAudio: return FluidAudioRuntime.shared
        case .whisperKit: return WhisperKitRuntime.shared
        }
    }

    private var downloadActivity: CatalogDownloadActivity {
        downloads.activity(for: entry.id)
    }

    private var isInstalled: Bool {
        runtime.isInstalled(entry.id)
    }

    private var isDownloading: Bool {
        if case .downloading = downloadActivity { return true }
        return false
    }

    var body: some View {
        SettingsGroup(title: "On-device model") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.body.weight(.medium))
                    Text("\(entry.approxDownloadMB >= 1000 ? String(format: "%.1f GB", Double(entry.approxDownloadMB) / 1000) : "\(entry.approxDownloadMB) MB") · \(entry.languages.count) language\(entry.languages.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                statusLabel
            }

            if !isInstalled && !isDownloading {
                Button {
                    startDownload()
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle")
                }
            }

            if case .downloading(let progress) = downloadActivity {
                ProgressView(value: progress) {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.caption)
                }

                Button(role: .cancel) {
                    downloads.cancel(entry.id)
                } label: {
                    Label("Cancel Download", systemImage: "xmark.circle")
                }
            }

            if isInstalled && !isDownloading && downloadActivity != .deleting {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete Model", systemImage: "trash")
                }
            }

            if downloadActivity == .deleting {
                ProgressView("Deleting model…")
                    .font(.caption)
            }

            if case .failed(let errorMessage) = downloadActivity {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Text("Language")
                    .font(.caption.weight(.medium))
                Spacer()
                Picker("Language", selection: Binding(
                    get: {
                        entry.languages.contains(settings.preferredLanguage)
                            ? settings.preferredLanguage
                            : "auto"
                    },
                    set: { settings.preferredLanguage = $0 }
                )) {
                    Text(entry.languageMode == .hintRequired ? "Default (English)" : "Auto-detect").tag("auto")
                    ForEach(entry.languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            if entry.languageMode == .hintRequired {
                Text("This model needs the language up front — pick the language you dictate in.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let note = entry.usageNote {
                SettingsNote(text: note, icon: "info.circle")
            }
        }
        .confirmationDialog(
            "Delete \(entry.displayName)?",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Delete Model", role: .destructive) {
                Task {
                    await downloads.delete(entry.id, runtime: runtime)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model will be removed from this Mac. You can download it again later.")
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch downloadActivity {
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.caption).foregroundColor(.orange)
            }
        case .failed(let reason):
            Label("Failed: \(reason)", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        case .deleting:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text("Deleting…")
                    .font(.caption).foregroundColor(.orange)
            }
        case .idle, .downloaded:
            runtimeStatusLabel
        }
    }

    @ViewBuilder
    private var runtimeStatusLabel: some View {
        switch status.state {
        case .ready(let readyID) where readyID == entry.id:
            Label("Ready", systemImage: "circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .loading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                // Cohere's ~4-min first-launch CoreML specialization (Discovery
                // G) is expected, not a hang — say so instead of a bare spinner.
                Text(entry.usageNote != nil ? "Preparing model…" : "Loading…")
                    .font(.caption).foregroundColor(.orange)
            }
        case .downloading(let progress):
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.6)
                Text(progress >= 0 ? "Downloading… \(Int(progress * 100))%" : "Downloading…")
                    .font(.caption).foregroundColor(.orange)
            }
        case .failed(let reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
        default:
            if isInstalled {
                Label("Downloaded", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Label("Not Downloaded", systemImage: "circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func startDownload() {
        downloads.start(entry.id, runtime: runtime)
    }
}

struct TranscriptionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var whisperKitService: WhisperKitService

    @Binding var showingWhisperKitSetup: Bool
    @Binding var transcriptionModels: [ModelInfo]
    @Binding var isLoadingTranscriptionModels: Bool

    let loadTranscriptionModels: () -> Void

    @State private var apiKeyDraft = ""
    @FocusState private var apiKeyFocused: Bool

    static func showsWhisperKitVariantManagement(
        for selection: AppSettings.TranscriptionSelection
    ) -> Bool {
        switch selection {
        case .catalog(let modelID):
            return modelID == .whisperKit
        case .legacy(let provider):
            return provider == .whisperKit
        }
    }

    private func commitAPIKey() {
        let previous = settings.transcriptionAPIKey
        guard apiKeyDraft != previous else { return }
        settings.transcriptionAPIKey = apiKeyDraft
        if AppSettings.shouldTriggerModelDiscovery(committedKey: apiKeyDraft, previousKey: previous) {
            loadTranscriptionModels()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Speech recognition", subtitle: "Run transcription on this Mac, or connect a cloud service.") {
                // Keep the existing selection setter as the only path that
                // updates provider values and model change signals.
                Picker("Model", selection: Binding(
                    get: { settings.transcriptionSelection },
                    set: { settings.transcriptionSelection = $0 }
                )) {
                    Section("On-Device") {
                        ForEach(ModelCatalog.entries, id: \.id) { entry in
                            Text(entry.displayName)
                                .tag(AppSettings.TranscriptionSelection.catalog(entry.id))
                        }
                    }
                    Section("Cloud & Server") {
                        ForEach(TranscriptionProvider.allCases.filter { !$0.isLocalNativeProvider },
                                id: \.rawValue) { provider in
                            Text(provider.supportsRefinementInOneCall ? "\(provider.displayName) + Refinement" : provider.displayName)
                                .tag(AppSettings.TranscriptionSelection.legacy(provider))
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.transcriptionProviderRaw) { _, _ in
                    loadTranscriptionModels()
                }

                if case .catalog = settings.transcriptionSelection {
                    SettingsNote(text: "Speech recognition runs on this Mac.", icon: "laptopcomputer")
                }

                if settings.selectedModelID == nil, settings.transcriptionProvider.supportsRefinementInOneCall {
                    SettingsNote(text: "This provider handles final text in one call. Separate refinement settings are ignored.", icon: "sparkles")
                }
            }

            if case .catalog(let modelID) = settings.transcriptionSelection,
               let entry = ModelCatalog.entry(for: modelID) {
                CatalogModelSection(settings: settings, entry: entry)
                    .id(modelID)
            }

            if Self.showsWhisperKitVariantManagement(for: settings.transcriptionSelection) {
                WhisperKitSettingsSection(
                    settings: settings,
                    whisperKitService: whisperKitService,
                    showingWhisperKitSetup: $showingWhisperKitSetup,
                    showsLegacyDecodingSettings: settings.selectedModelID == nil
                )
            }

            if settings.selectedModelID == nil, !settings.transcriptionProvider.isLocalNativeProvider {
                SettingsGroup(title: "Cloud & server") {
                    if settings.transcriptionProvider.requiresAPIKey {
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
                                .onAppear { apiKeyDraft = settings.transcriptionAPIKey }
                                .onChange(of: settings.transcriptionProviderRaw) { _, _ in
                                    apiKeyDraft = settings.transcriptionAPIKey
                                }
                                .accessibilityLabel("Transcription API key")
                            KeychainSecurityNoticeBanner(settings: settings)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model")
                            .font(.caption.weight(.medium))
                        HStack(spacing: 10) {
                            if isLoadingTranscriptionModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Loading transcription models")
                            }

                            if transcriptionModels.isEmpty {
                                TextField("Model name", text: $settings.transcriptionModel)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Transcription model name")
                            } else {
                                Picker("Transcription model", selection: $settings.transcriptionModel) {
                                    ForEach(transcriptionModels) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                            }

                            Button(action: loadTranscriptionModels) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh transcription models")
                            .accessibilityLabel("Refresh transcription models")
                        }
                        if transcriptionModels.isEmpty && !isLoadingTranscriptionModels {
                            Text("Enter a model name, or refresh to load available models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                    DisclosureGroup("Server connection") {
                        ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
                            .padding(.top, 12)
                    }
                    if !URLValidation.isValid(settings.transcriptionBaseURL) {
                        SettingsNote(text: "The server URL is invalid. Open Server connection to correct it.", icon: "exclamationmark.circle", color: .red)
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
    let showsLegacyDecodingSettings: Bool

    var body: some View {
        SettingsGroup(title: "Whisper models") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current variant")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(settings.whisperKitModel)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                if showsLegacyDecodingSettings, whisperKitService.modelState == .ready {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Button("Download & Manage Models…") {
                showingWhisperKitSetup = true
            }

            SettingsNote(text: "Whisper speech recognition runs entirely on this Mac.", icon: "laptopcomputer")

            if showsLegacyDecodingSettings {
                Divider()
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
                DisclosureGroup("Decoding options") {
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
                    .padding(.top, 12)
                }
            }
        }
    }
}

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

struct OllamaManagementSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ollamaService: OllamaService

    let loadRefinementModels: () -> Void

    var body: some View {
        SettingsGroup(title: "Ollama service") {
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
                .help("Refresh Ollama status")
                .accessibilityLabel("Refresh Ollama status")
            }

            if !ollamaService.isOllamaRunning {
                Text("To start Ollama: brew install ollama && ollama serve")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Ollama connection") {
                ValidatedURLField(title: "Ollama URL", url: $settings.ollamaBaseURL)
                    .padding(.top, 12)
            }
            if !URLValidation.isValid(settings.ollamaBaseURL) {
                SettingsNote(text: "The Ollama URL is invalid. Open Ollama connection to correct it.", icon: "exclamationmark.circle", color: .red)
            }

            if ollamaService.isOllamaRunning {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
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
            }
        }
        .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
        .onChange(of: settings.ollamaBaseURL) { _, _ in
            Task { await ollamaService.checkOllamaStatus() }
        }
    }
}
