import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - URL Validation

/// Validates and normalizes URL strings for API base URLs
enum URLValidation {
    /// Validation result with normalized URL or error message
    enum Result {
        case valid(normalized: String)
        case invalid(reason: String)
        case empty
    }
    
    /// Validates a URL string for use as an API base URL
    /// - Parameter urlString: The URL string to validate
    /// - Returns: Validation result with normalized URL or error
    static func validate(_ urlString: String) -> Result {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .empty
        }
        
        guard let url = URL(string: trimmed) else {
            return .invalid(reason: "Invalid URL format")
        }
        
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .invalid(reason: "URL must start with http:// or https://")
        }
        
        guard url.host != nil else {
            return .invalid(reason: "URL must include a host")
        }
        
        // Normalize: remove trailing slash
        var normalized = trimmed
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        
        return .valid(normalized: normalized)
    }
    
    /// Quick check if URL is valid (for UI state)
    static func isValid(_ urlString: String) -> Bool {
        switch validate(urlString) {
        case .valid, .empty:
            return true
        case .invalid:
            return false
        }
    }
}

/// A text field with real-time URL validation feedback
struct ValidatedURLField: View {
    let title: String
    @Binding var url: String
    var placeholder: String = "https://..."
    
    private var validationResult: URLValidation.Result {
        URLValidation.validate(url)
    }
    
    private var isValid: Bool {
        switch validationResult {
        case .valid, .empty:
            return true
        case .invalid:
            return false
        }
    }
    
    private var errorMessage: String? {
        switch validationResult {
        case .invalid(let reason):
            return reason
        case .valid, .empty:
            return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
            
            HStack {
                TextField(placeholder, text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: url) { _, newValue in
                        // Auto-normalize on paste or when user finishes typing
                        // We normalize when the field loses focus via onSubmit
                    }
                    .onSubmit {
                        normalizeURL()
                    }
                
                if !url.isEmpty {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                        .accessibilityLabel(isValid ? "Valid URL" : "Invalid URL")
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) URL field")
        .accessibilityValue(url.isEmpty ? "Empty" : (isValid ? "Valid: \(url)" : "Invalid"))
    }
    
    private func normalizeURL() {
        if case .valid(let normalized) = validationResult {
            if normalized != url {
                url = normalized
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("windowAppearance") private var appearance: WindowAppearance = .dark
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ollamaService = OllamaService.shared
    @ObservedObject private var whisperKitService = WhisperKitService.shared
    @State private var selectedPage: SettingsPage = .transcription
    @State private var showingWhisperKitSetup = false

    @State private var transcriptionModels: [ModelInfo] = []
    @State private var refinementModels: [ModelInfo] = []
    @State private var isLoadingTranscriptionModels = false
    @State private var isLoadingRefinementModels = false
    @State private var showingAddPreset = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    @State private var newDictionaryWord = ""

    var body: some View {
        SettingsShell(
            selectedPage: $selectedPage,
            appearance: $appearance
        ) {
            switch selectedPage {
            case .transcription:
                TranscriptionSettingsSection(
                    settings: settings,
                    whisperKitService: whisperKitService,
                    showingWhisperKitSetup: $showingWhisperKitSetup,
                    transcriptionModels: $transcriptionModels,
                    isLoadingTranscriptionModels: $isLoadingTranscriptionModels,
                    loadTranscriptionModels: loadTranscriptionModels
                )
            case .refinement:
                RefinementSettingsSection(
                    settings: settings,
                    ollamaService: ollamaService,
                    refinementModels: $refinementModels,
                    isLoadingRefinementModels: $isLoadingRefinementModels,
                    loadRefinementModels: loadRefinementModels
                )
            case .prompt:
                promptContent
            case .recording:
                recordingContent
            }
        }
        .windowAppearance(appearance)
    }

    private var newPresetNameIsAvailable: Bool {
        AppSettings.isPresetNameAvailable(newPresetName, among: settings.allPresets)
    }

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Writing style", subtitle: "Choose the instructions used to refine your transcript.") {
                HStack(spacing: 12) {
                    Picker("Preset", selection: Binding(
                        get: { settings.selectedPreset },
                        set: { if let p = $0 { settings.selectedPreset = p } }
                    )) {
                        ForEach(settings.allPresets) { preset in
                            Label(
                                settings.isPresetModified(preset) ? "\(preset.name) · Modified" : preset.name,
                                systemImage: preset.icon
                            )
                            .tag(preset as PromptPreset?)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Prompt preset")

                    Button {
                        showingAddPreset = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .help("Add custom preset")
                    .accessibilityLabel("Add custom preset")

                    if let preset = settings.selectedPreset, !preset.isBuiltIn {
                        Button(role: .destructive) {
                            settings.deleteCustomPreset(preset)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Delete preset")
                        .accessibilityLabel("Delete \(preset.name) preset")
                    }
                }

                if let preset = settings.selectedPreset {
                    Text(preset.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                DisclosureGroup("Edit prompt instructions") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Instructions for the refiner")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let preset = settings.selectedPreset, settings.isPresetModified(preset) {
                                Button("Reset to Default") {
                                    settings.resetPresetToDefault(preset)
                                }
                                .controlSize(.small)
                            }
                        }
                        TextEditor(text: Binding(
                            get: { settings.systemPrompt },
                            set: { settings.systemPrompt = $0 }
                        ))
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        }
                        .accessibilityLabel("Prompt instructions")
                    }
                    .padding(.top, 12)
                }
            }

            personalDictionarySection

            SettingsGroup(title: "Advanced") {
                DisclosureGroup("Compare prompt presets") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Parallel audit", isOn: $settings.parallelRefinementEnabled)
                            .toggleStyle(.switch)
                            .help("Process all presets in parallel for the history audit trail")
                        SettingsNote(text: "Process all presets in parallel and keep their results in history. This runs additional refinement requests.")
                    }
                    .padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
    }

    private var personalDictionarySection: some View {
        SettingsGroup(title: "Personal dictionary") {
            Toggle(isOn: $settings.personalDictionaryEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Use custom spelling")
                        .font(.body.weight(.medium))
                    Text("Help the refiner recognize names and specialized terms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Personal Dictionary")
            .accessibilityValue(settings.personalDictionaryEnabled ? "On, \(settings.personalDictionary.count) words" : "Off")
            .accessibilityHint("Toggle to enable custom spelling for names and terms")

            if settings.personalDictionaryEnabled {
                Divider()
                HStack(spacing: 8) {
                    TextField("Add a name or term", text: $newDictionaryWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addDictionaryWord() }
                        .accessibilityLabel("New dictionary word")
                    Button("Add", action: addDictionaryWord)
                        .disabled(newDictionaryWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if settings.personalDictionary.isEmpty {
                    SettingsNote(text: "No words yet. Add a name, brand, or technical term that is often misspelled.", icon: "character.book.closed")
                } else {
                    FlowLayout(spacing: 7) {
                        ForEach(settings.personalDictionary, id: \.self) { word in
                            HStack(spacing: 6) {
                                Text(word)
                                    .font(.caption)
                                Button {
                                    settings.removeFromDictionary(word)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18, height: 18)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(word)")
                                .accessibilityLabel("Remove \(word) from dictionary")
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 4)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                }
                Text("\(settings.personalDictionary.count) of 20 words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addDictionaryWord() {
        let trimmed = newDictionaryWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.addToDictionary(trimmed)
        newDictionaryWord = ""
    }

    private var addPresetSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(title: "New preset", subtitle: "Create a writing style you can make your own.")
            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption.weight(.medium))
                TextField("My Preset", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Preset name")
                if !newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !newPresetNameIsAvailable {
                    Label("Preset names must be unique.", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.caption.weight(.medium))
                TextField("Short description", text: $newPresetDescription)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Preset description")
            }
            HStack {
                Button("Cancel") {
                    showingAddPreset = false
                    newPresetName = ""
                    newPresetDescription = ""
                }
                .keyboardShortcut(.escape)
                Spacer()
                Button("Add Preset") {
                    guard settings.addCustomPreset(
                        name: newPresetName,
                        description: newPresetDescription,
                        icon: "star",
                        prompt: "Fix grammar and punctuation. Output only the cleaned text."
                    ) else {
                        return
                    }
                    showingAddPreset = false
                    newPresetName = ""
                    newPresetDescription = ""
                }
                .keyboardShortcut(.return)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !newPresetNameIsAvailable)
            }
        }
        .padding(28)
        .frame(width: 400)
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Audio quality") {
                Toggle(isOn: $settings.highQualityAudio) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High quality audio")
                            .font(.body.weight(.medium))
                        Text(settings.highQualityAudio ? "44.1 kHz · Larger files · Slower upload" : "16 kHz · Optimized for speech · Faster processing")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("High Quality Audio")
                .accessibilityValue(settings.highQualityAudio ? "On, 44.1 kHz" : "Off, 16 kHz optimized")
                .accessibilityHint("Toggle between high quality 44.1 kHz and optimized 16 kHz recording")
                Divider()
                SettingsNote(text: "16 kHz is recommended for speech. Try high quality if you experience recognition issues.", icon: "waveform")
            }

            SettingsGroup(title: "Silence handling") {
                Toggle(isOn: $settings.disableSilenceTrimming) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keep silence at the edges")
                            .font(.body.weight(.medium))
                        Text("Send the full recording without trimming silence from the start or end.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .accessibilityLabel("Disable Silence Trimming")
                .accessibilityValue(settings.disableSilenceTrimming ? "On, full recording" : "Off, trim silence")
            }
        }
    }

    private func loadTranscriptionModels() {
        isLoadingTranscriptionModels = true
        Task {
            let models = await ModelDiscoveryService.shared.fetchTranscriptionModels(
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL
            )
            await MainActor.run {
                transcriptionModels = models
                if !models.isEmpty && !models.contains(where: { $0.id == settings.transcriptionModel }) {
                    settings.transcriptionModel = models.first?.id ?? ""
                }
                isLoadingTranscriptionModels = false
            }
        }
    }
    
    private func loadRefinementModels() {
        isLoadingRefinementModels = true
        Task {
            let models = await ModelDiscoveryService.shared.fetchModels(
                provider: settings.refinementProvider,
                apiKey: settings.refinementAPIKey,
                baseURL: settings.refinementBaseURL
            )
            await MainActor.run {
                refinementModels = models
                if !models.isEmpty && !models.contains(where: { $0.id == settings.refinementModel }) {
                    settings.refinementModel = models.first?.id ?? ""
                }
                isLoadingRefinementModels = false
            }
        }
    }
}
