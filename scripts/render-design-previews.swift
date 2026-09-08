// Compile with the presentation files, native selectable text, and HistoryEntry.swift. This helper
// does not link app services. All controls use inert data and no-op callbacks.
import AppKit
import SwiftUI

@main
struct DesignPreviews {
    @MainActor
    static func main() {
        do {
            try renderPreviews()
        } catch {
            FileHandle.standardError.write(Data("Preview failed: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func renderPreviews() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/ui-redesign")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try render(SettingsExample(appearance: dark ? .dark : .light), size: NSSize(width: 760, height: 500), dark: dark,
                       to: output.appendingPathComponent("settings-\(suffix).png"))
            try render(HistoryExample(empty: false), size: NSSize(width: 900, height: 560), dark: dark,
                       to: output.appendingPathComponent("history-\(suffix).png"))
        }
        try render(HistoryExample(empty: true), size: NSSize(width: 900, height: 560), dark: false,
                   to: output.appendingPathComponent("history-empty.png"))
    }

    @MainActor
    private static func validateTextLayout(in view: NSView) throws {
        if let text = view as? HistorySelectionTextView,
           let container = text.textContainer, let layout = text.layoutManager {
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            print("Native text layout: frame=\(text.frame.size) container=\(container.size) glyphs=\(used.size)")
            guard abs(container.size.width - text.bounds.width) < 1,
                  used.height <= text.bounds.height + 1 else {
                throw NSError(domain: "DesignPreviews", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Native transcript layout does not fit its assigned view"
                ])
            }
        }
        for child in view.subviews { try validateTextLayout(in: child) }
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: NSSize, dark: Bool, to url: URL) throws {
        let mode: WindowAppearance = dark ? .dark : .light
        let host = NSHostingView(rootView: view.windowAppearance(mode))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        // The window is never ordered onscreen or made key.
        for preference in [WindowAppearance.dark, .light, .system, mode] {
            host.rootView = view.windowAppearance(preference)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
            host.layoutSubtreeIfNeeded()
            guard window.appearance?.name == preference.nativeAppearance?.name else {
                throw NSError(domain: "DesignPreviews", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "\(preference.rawValue) did not reach native window appearance"
                ])
            }
        }
        try validateTextLayout(in: host)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.effectiveAppearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        print(url.path)
        window.contentView = nil
    }
}

private struct SettingsExample: View {
    let appearance: WindowAppearance
    var body: some View {
        SettingsShell(selectedPage: .constant(.transcription), appearance: .constant(appearance)) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsGroup(title: "Speech recognition", subtitle: "Run transcription on this Mac, or connect a cloud service.") {
                    Picker("Model", selection: .constant("Parakeet V3")) {
                        Text("Parakeet V3").tag("Parakeet V3")
                    }
                    .pickerStyle(.menu)
                    SettingsNote(text: "Speech recognition runs on this Mac.", icon: "laptopcomputer")
                }
                SettingsGroup(title: "On-device model") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parakeet V3").font(.body.weight(.medium))
                            Text("470 MB · 25 languages").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Ready", systemImage: "circle.fill").font(.caption).foregroundStyle(.green)
                    }
                    Button(role: .destructive) {} label: {
                        Label("Delete Model", systemImage: "trash")
                    }
                    HStack {
                        Text("Language").font(.caption.weight(.medium))
                        Spacer()
                        Picker("Language", selection: .constant("Auto-detect")) {
                            Text("Auto-detect").tag("Auto-detect")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
        }
    }
}

private struct HistoryExample: View {
    let empty: Bool
    private let samples = [
        HistoryEntry(original: "let's keep the first version focused on a great dictation experience we can add the advanced options once the everyday flow feels right", refined: "Let’s keep the first version focused on a great dictation experience. We can add the advanced options once the everyday flow feels right.", presetName: "Clean & Clear", systemPrompt: "Fix grammar and punctuation. Preserve the speaker’s meaning."),
        HistoryEntry(original: "Can we move our catch up to Thursday afternoon?", refined: "Can we move our catch-up to Thursday afternoon?", presetName: "Clean & Clear", systemPrompt: ""),
        HistoryEntry(original: "The new layout should make the important things easy to find.", refined: "The new layout should make the important things easy to find.", presetName: "Raw", systemPrompt: "")
    ]

    var body: some View {
        HistoryBrowser(entries: empty ? [] : samples, selectedEntryID: .constant(empty ? nil : samples[0].id),
                       onCopy: { _ in }, onClear: {}, notice: { EmptyView() }) { entry in
            HistoryTranscriptDetail(entry: entry, copyFinal: {}, copyOriginal: {}, copyVariant: { _ in }, copyAudit: {},
                                    selectableText: { HistorySelectableText(text: $0, copySelection: { _ in }) },
                                    status: { EmptyView() }, actions: { EmptyView() })
        }
    }
}
