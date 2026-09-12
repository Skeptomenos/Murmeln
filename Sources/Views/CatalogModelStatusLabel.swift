import SwiftUI

struct CatalogModelStatusLabel: View {
    let downloadActivity: CatalogDownloadActivity
    let runtimeState: RuntimeState
    let entry: CatalogEntry
    let isInstalled: Bool

    @ViewBuilder
    var body: some View {
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
        switch runtimeState {
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
}
