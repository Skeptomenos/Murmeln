import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let original: String
    let refined: String
    let presetName: String?
    let systemPrompt: String?
    let effectiveSystemPrompt: String?
    
    var variants: [String: String]?
    var variantPrompts: [String: String]?
    var effectiveVariantPrompts: [String: String]?

    struct PromptProvenance {
        let basePrompt: String?
        let effectivePrompt: String?

        var showsBasePromptSeparately: Bool {
            guard let basePrompt, let effectivePrompt else { return false }
            return basePrompt != effectivePrompt
        }
    }
    
    init(
        original: String, 
        refined: String, 
        presetName: String, 
        systemPrompt: String, 
        effectiveSystemPrompt: String? = nil,
        variants: [String: String]? = nil,
        variantPrompts: [String: String]? = nil,
        effectiveVariantPrompts: [String: String]? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.original = original
        self.refined = refined
        self.presetName = presetName
        self.systemPrompt = systemPrompt
        self.effectiveSystemPrompt = effectiveSystemPrompt?.isEmpty == false ? effectiveSystemPrompt : nil
        self.variants = variants?.isEmpty == false ? variants : nil
        self.variantPrompts = variantPrompts?.isEmpty == false ? variantPrompts : nil
        self.effectiveVariantPrompts = effectiveVariantPrompts?.isEmpty == false ? effectiveVariantPrompts : nil
    }
    
    var safePresetName: String {
        presetName ?? "Unknown"
    }
    
    var safeSystemPrompt: String {
        systemPrompt ?? "Prompt not saved for this entry."
    }
    
    var displayText: String {
        refined.isEmpty ? original : refined
    }

    var hasParallelAuditTrail: Bool {
        (variants?.count ?? 0) > 1
    }

    var hasDistinctOriginalBaseline: Bool {
        hasParallelAuditTrail || original != refined
    }
    
    var previewText: String {
        let text = displayText
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(47)) + "..."
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var menuPreview: String {
        let text = displayText.replacingOccurrences(of: "\n", with: " ")
        let maxLength = 60
        if text.count <= maxLength {
            return "\(formattedTime) · \(text)"
        }
        return "\(formattedTime) · \(String(text.prefix(maxLength - 3)))..."
    }

    func promptProvenance(for variantName: String) -> PromptProvenance {
        let basePrompt = normalizedPrompt(
            variantPrompts?[variantName] ?? (variantName == safePresetName ? systemPrompt : nil)
        )
        let effectivePrompt = normalizedPrompt(
            effectiveVariantPrompts?[variantName]
                ?? (variantName == safePresetName ? effectiveSystemPrompt : nil)
                ?? basePrompt
        )

        return PromptProvenance(basePrompt: basePrompt, effectivePrompt: effectivePrompt)
    }

    private func normalizedPrompt(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
