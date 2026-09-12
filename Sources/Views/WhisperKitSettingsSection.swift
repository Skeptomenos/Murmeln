import SwiftUI

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
