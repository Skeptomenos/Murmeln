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
