import Foundation

/// Which per-call path a capture takes for a capped model (Cohere: 35 s).
enum AudioChunkingRoute: Equatable, Sendable {
    case singleCall
    case longForm

    static func route(durationSeconds: Double, maxUtteranceSeconds: Double?) -> AudioChunkingRoute {
        guard let cap = maxUtteranceSeconds, durationSeconds > cap else {
            return .singleCall
        }
        return .longForm
    }
}

/// Murmeln-owned Cohere long-form policy. FluidAudio 0.15.5 uses a five-second
/// overlap, which can start the second decoder mid-thought and lose a phrase at
/// the seam. Ten seconds preserves enough context for both real-voice fixtures.
enum CohereLongFormChunking {
    static let overlapSeconds = 10

    static func ranges(
        sampleCount: Int,
        sampleRate: Int,
        maxChunkSeconds: Int,
        overlapSeconds: Int = overlapSeconds
    ) -> [Range<Int>] {
        guard sampleCount > 0, sampleRate > 0, maxChunkSeconds > 0 else { return [] }

        let chunkSamples = maxChunkSeconds * sampleRate
        let overlapSamples = min(max(overlapSeconds, 0) * sampleRate, max(chunkSamples - 1, 0))
        let hopSamples = chunkSamples - overlapSamples
        var result: [Range<Int>] = []
        var start = 0

        while start < sampleCount {
            let end = min(start + chunkSamples, sampleCount)
            if start > 0, end - start <= overlapSamples {
                break
            }
            result.append(start..<end)
            if end >= sampleCount { break }
            start += hopSamples
        }

        return result
    }

    /// Merge independently decoded chunk text using a normalized word overlap.
    /// If no reliable overlap exists, concatenate: duplicated words are safer
    /// than silently deleting spoken content.
    static func merge(prefix: String, suffix: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSuffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrefix.isEmpty else { return trimmedSuffix }
        guard !trimmedSuffix.isEmpty else { return trimmedPrefix }

        let prefixWords = trimmedPrefix.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let suffixWords = trimmedSuffix.split(whereSeparator: \Character.isWhitespace).map(String.init)
        let prefixWindowStart = max(0, prefixWords.count - 64)
        let prefixWindow = Array(prefixWords[prefixWindowStart...])
        let suffixWindow = Array(suffixWords.prefix(64))
        let normalizedPrefix = prefixWindow.map(normalizedWord)
        let normalizedSuffix = suffixWindow.map(normalizedWord)

        var lengths = [Int](repeating: 0, count: normalizedSuffix.count + 1)
        var bestLength = 0
        var bestPrefixEnd = 0
        var bestSuffixEnd = 0

        for prefixIndex in 1...normalizedPrefix.count {
            var previous = 0
            for suffixIndex in 1...normalizedSuffix.count {
                let oldLength = lengths[suffixIndex]
                if !normalizedPrefix[prefixIndex - 1].isEmpty,
                   normalizedPrefix[prefixIndex - 1] == normalizedSuffix[suffixIndex - 1] {
                    lengths[suffixIndex] = previous + 1
                    if lengths[suffixIndex] > bestLength {
                        bestLength = lengths[suffixIndex]
                        bestPrefixEnd = prefixIndex
                        bestSuffixEnd = suffixIndex
                    }
                } else {
                    lengths[suffixIndex] = 0
                }
                previous = oldLength
            }
        }

        let unmatchedPrefixTail = prefixWindow.count - bestPrefixEnd
        let suffixMatchStart = bestSuffixEnd - bestLength
        guard bestLength >= 4, unmatchedPrefixTail <= 8, suffixMatchStart <= 24 else {
            return "\(trimmedPrefix) \(trimmedSuffix)"
        }

        let suffixRemainder = suffixWords.dropFirst(bestSuffixEnd).joined(separator: " ")
        return suffixRemainder.isEmpty ? trimmedPrefix : "\(trimmedPrefix) \(suffixRemainder)"
    }

    private static func normalizedWord(_ word: String) -> String {
        String(word.unicodeScalars.filter(CharacterSet.alphanumerics.contains)).lowercased()
    }
}
