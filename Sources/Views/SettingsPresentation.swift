import SwiftUI
import AppKit

enum WindowAppearance: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum WindowPalette {
    static let canvas = adaptive(light: 0xF4F5F7, dark: 0x17191D)
    static let sidebar = adaptive(light: 0xEBEDF1, dark: 0x111317)
    static let border = adaptive(light: 0xDDE1E8, dark: 0x363B45)
    static let accent = adaptive(light: 0x3369CC, dark: 0x8BACFA)

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255,
                           blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
}

extension View {
    func windowAppearance(_ appearance: WindowAppearance) -> some View {
        preferredColorScheme(appearance.colorScheme)
            .tint(WindowPalette.accent)
    }
}

// These presentation views have no settings or service dependencies, so the same
// layout can be rendered with inert sample data for visual review.
enum SettingsPage: String, CaseIterable {
    case transcription = "Transcription"
    case refinement = "Refinement"
    case prompt = "Writing"
    case recording = "Recording"

    var icon: String {
        switch self {
        case .transcription: return "waveform"
        case .refinement: return "sparkles"
        case .prompt: return "text.alignleft"
        case .recording: return "mic"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Choose how Murmeln turns your voice into text."
        case .refinement: return "Make each transcript read the way you want."
        case .prompt: return "Your preferred style, names, and terminology."
        case .recording: return "Fine-tune the audio captured while you dictate."
        }
    }

    var accessibilityHint: String {
        switch self {
        case .transcription: return "Configure speech-to-text provider"
        case .refinement: return "Configure text cleanup and formatting"
        case .prompt: return "Manage prompt presets and personal dictionary"
        case .recording: return "Configure audio capture settings"
        }
    }
}

struct SettingsShell<Content: View>: View {
    @Binding var selectedPage: SettingsPage
    @Binding var appearance: WindowAppearance
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 186)
            Divider()
                .overlay(WindowPalette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SettingsPageHeader(title: selectedPage.rawValue, subtitle: selectedPage.subtitle)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(WindowPalette.canvas)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(WindowPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Murmeln")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases, id: \.self) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: page.icon)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 21)
                                .foregroundStyle(selectedPage == page ? WindowPalette.accent : Color.secondary)
                            Text(page.rawValue)
                                .font(.system(size: 13, weight: selectedPage == page ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedPage == page ? WindowPalette.accent.opacity(0.15) : Color.clear)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(page.rawValue) settings")
                    .accessibilityHint(page.accessibilityHint)
                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Settings navigation")

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 7) {
                Text("Appearance")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Picker("Window appearance", selection: $appearance) {
                    ForEach(WindowAppearance.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityHint("Changes Settings and History. System follows macOS appearance.")
            }
        }
        .padding(12)
        .background(WindowPalette.canvas)
    }
}

struct SettingsPageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct SettingsNote: View {
    let text: String
    var icon: String = "info.circle"
    var color: Color = .secondary

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption)
        .foregroundStyle(color)
        .labelStyle(.titleAndIcon)
    }
}
