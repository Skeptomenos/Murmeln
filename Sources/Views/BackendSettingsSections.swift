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
            .padding(10)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.caption.weight(.medium))
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
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
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
                // Phase 8 / M6: one picker over catalog models + legacy
                // providers, bound through the transcriptionSelection setter —
                // the single path that updates raw values and change signals.
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
                    Section("Cloud & Server (legacy)") {
                        ForEach(TranscriptionProvider.allCases.filter { !$0.isLocalNativeProvider },
                                id: \.rawValue) { provider in
                            HStack {
                                Text(provider.displayName)
                                if provider.supportsRefinementInOneCall {
                                    Text("+ Refinement")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .tag(AppSettings.TranscriptionSelection.legacy(provider))
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.transcriptionProviderRaw) { _, _ in
                    loadTranscriptionModels()
                }

                if case .catalog(let modelID) = settings.transcriptionSelection,
                   let entry = ModelCatalog.entry(for: modelID) {
                    CatalogModelSection(settings: settings, entry: entry)
                        .id(modelID)
                }

                if settings.selectedModelID == nil, settings.transcriptionProvider.supportsRefinementInOneCall {
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

                if Self.showsWhisperKitVariantManagement(for: settings.transcriptionSelection) {
                    WhisperKitSettingsSection(
                        settings: settings,
                        whisperKitService: whisperKitService,
                        showingWhisperKitSetup: $showingWhisperKitSetup,
                        showsLegacyDecodingSettings: settings.selectedModelID == nil
                    )
                }

                if settings.selectedModelID == nil, settings.transcriptionProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        // M5: edit a local draft; persist + discover models only
                        // on commit (Enter / focus loss), never per keystroke.
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
                        KeychainSecurityNoticeBanner(settings: settings)
                    }
                }

                if settings.selectedModelID == nil, !settings.transcriptionProvider.isLocalNativeProvider {
                    ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
                }

                if settings.selectedModelID == nil, !settings.transcriptionProvider.isLocalNativeProvider {
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
    let showsLegacyDecodingSettings: Bool

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

                if showsLegacyDecodingSettings, whisperKitService.modelState == .ready {
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

            if showsLegacyDecodingSettings {
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
                        // M5: edit a local draft; persist + discover models only
                        // on commit (Enter / focus loss), never per keystroke.
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
                        KeychainSecurityNoticeBanner(settings: settings)
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
