import Foundation
import Testing

@Suite("Settings Source Layout Tests")
struct SettingsSourceLayoutTests {
    private let expectedLayout = [
        (file: "KeychainSecurityNoticeBanner.swift", type: "KeychainSecurityNoticeBanner"),
        (file: "CatalogModelSection.swift", type: "CatalogModelSection"),
        (file: "CatalogModelStatusLabel.swift", type: "CatalogModelStatusLabel"),
        (file: "TranscriptionSettingsSection.swift", type: "TranscriptionSettingsSection"),
        (file: "WhisperKitSettingsSection.swift", type: "WhisperKitSettingsSection"),
        (file: "RefinementSettingsSection.swift", type: "RefinementSettingsSection"),
        (file: "OllamaManagementSection.swift", type: "OllamaManagementSection"),
    ]

    @Test("Each settings view has one exact source file")
    func eachSettingsViewHasOneExactSourceFile() throws {
        let viewsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Views", isDirectory: true)
        let legacyAggregate = viewsDirectory.appendingPathComponent("BackendSettingsSections.swift")

        guard !FileManager.default.fileExists(atPath: legacyAggregate.path) else {
            Issue.record("BackendSettingsSections.swift must be removed after its views are split")
            return
        }

        let swiftFiles = try FileManager.default.contentsOfDirectory(
            at: viewsDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }

        for expected in expectedLayout {
            let expectedFile = viewsDirectory.appendingPathComponent(expected.file)
            #expect(
                FileManager.default.fileExists(atPath: expectedFile.path),
                "Missing expected settings view file: \(expected.file)"
            )

            if FileManager.default.fileExists(atPath: expectedFile.path) {
                let source = try String(contentsOf: expectedFile, encoding: .utf8)
                #expect(
                    topLevelViewNames(in: source) == [expected.type],
                    "\(expected.file) must contain only the top-level view \(expected.type)"
                )
            }

            let definingFiles = try swiftFiles.compactMap { file -> String? in
                let source = try String(contentsOf: file, encoding: .utf8)
                return topLevelViewNames(in: source).contains(expected.type)
                    ? file.lastPathComponent
                    : nil
            }
            .sorted()
            #expect(
                definingFiles == [expected.file],
                "\(expected.type) must be defined only in \(expected.file)"
            )
        }
    }

    private func topLevelViewNames(in source: String) -> [String] {
        source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = String(rawLine)
            guard line.hasPrefix("struct "), let marker = line.range(of: ": View") else {
                return nil
            }
            let nameStart = line.index(line.startIndex, offsetBy: "struct ".count)
            return String(line[nameStart..<marker.lowerBound])
        }
    }
}
