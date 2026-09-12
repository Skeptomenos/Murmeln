import SwiftUI

/// Phase 8: catalog-driven model section — status, download-with-progress,
/// unified language control (annotated per languageMode), usage notes.
/// One view serves every catalog entry (the WhisperKit setup sheet remains
/// for Whisper variant management).
struct CatalogModelSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var downloads: CatalogDownloadManager
    let entry: CatalogEntry
    private let runtime: any TranscriptionRuntime

    /// Slice 5c/F1: observe the runtime's published state so `.loading→.ready`
    /// repaints the status label instead of leaving a stale "Loading…".
    @StateObject private var status: RuntimeStatusModel
    @State private var showingDeleteConfirmation = false

    init(
        settings: AppSettings,
        entry: CatalogEntry,
        downloads: CatalogDownloadManager = .shared,
        runtimeRegistry: TranscriptionRuntimeRegistry = .shared
    ) {
        self.settings = settings
        self.entry = entry
        _downloads = ObservedObject(wrappedValue: downloads)
        let runtime = Self.resolveRuntime(for: entry, in: runtimeRegistry)
        self.runtime = runtime
        _status = StateObject(wrappedValue: RuntimeStatusModel(runtime: runtime))
    }

    static func resolveRuntime(
        for entry: CatalogEntry,
        in runtimeRegistry: TranscriptionRuntimeRegistry
    ) -> any TranscriptionRuntime {
        guard let runtime = runtimeRegistry.runtime(forModel: entry.id) else {
            preconditionFailure("Catalog entry \(entry.id.rawValue) has no runtime")
        }
        return runtime
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
                CatalogModelStatusLabel(
                    downloadActivity: downloadActivity,
                    runtimeState: status.state,
                    entry: entry,
                    isInstalled: isInstalled
                )
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
                downloads.delete(entry.id, runtime: runtime)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The model will be removed from this Mac. You can download it again later.")
        }
    }

    private func startDownload() {
        downloads.start(entry.id, runtime: runtime)
    }
}
