import AppKit

/// A snapshot is usable only when every advertised representation was read
/// from the same observed pasteboard generation and can be reconstructed.
@MainActor
struct ClipboardSnapshot {
    private struct Item {
        let types: [NSPasteboard.PasteboardType]
        let dataByType: [NSPasteboard.PasteboardType: Data]
    }
    private let items: [Item]
    let generation: Int
    let isAvailable: Bool
    private let makeItem: () -> NSPasteboardItem
    var itemCount: Int { items.count }
    var typeCount: Int { items.reduce(0) { $0 + $1.types.count } }

    static func capture(
        from pasteboard: NSPasteboard,
        readData: (NSPasteboardItem, NSPasteboard.PasteboardType) -> Data? = { $0.data(forType: $1) },
        makeItem: @escaping () -> NSPasteboardItem = { NSPasteboardItem() }
    ) -> ClipboardSnapshot {
        let generation = pasteboard.changeCount
        func unavailable() -> ClipboardSnapshot {
            ClipboardSnapshot(items: [], generation: generation, isAvailable: false, makeItem: makeItem)
        }
        guard let sourceItems = pasteboard.pasteboardItems else { return unavailable() }
        var items: [Item] = []
        for source in sourceItems {
            let types = source.types
            guard !types.isEmpty else { return unavailable() }
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in types {
                guard let value = readData(source, type) else { return unavailable() }
                data[type] = value
            }
            items.append(Item(types: types, dataByType: data))
        }
        let snapshot = ClipboardSnapshot(items: items, generation: generation,
            isAvailable: true, makeItem: makeItem)
        guard pasteboard.changeCount == generation, snapshot.reconstructedItems() != nil,
              pasteboard.changeCount == generation else { return unavailable() }
        return snapshot
    }

    private func reconstructedItems() -> [NSPasteboardItem]? {
        guard isAvailable else { return nil }
        var result: [NSPasteboardItem] = []
        for saved in items {
            let item = makeItem()
            for type in saved.types {
                guard let data = saved.dataByType[type], item.setData(data, forType: type) else { return nil }
            }
            result.append(item)
        }
        return result
    }

    func restore(
        to pasteboard: NSPasteboard,
        writeObjects: @MainActor ([NSPasteboardItem], NSPasteboard) -> Bool = { $1.writeObjects($0) }
    ) -> Bool {
        restoreOutcome(to: pasteboard, writeObjects: writeObjects) == .restored
    }

    func restoreOutcome(
        to pasteboard: NSPasteboard,
        writeObjects: @MainActor ([NSPasteboardItem], NSPasteboard) -> Bool = { $1.writeObjects($0) }
    ) -> ClipboardDisposition {
        let ownedGeneration = pasteboard.changeCount
        // Reconstruct before the destructive clear, including representation failures.
        guard let restored = reconstructedItems() else { return .restoreFailed }
        guard pasteboard.changeCount == ownedGeneration else { return .externalWritePreserved }
        pasteboard.clearContents()
        if restored.isEmpty { return pasteboard.pasteboardItems?.isEmpty == true ? .restored : .restoreFailed }
        return writeObjects(restored, pasteboard) ? .restored : .restoreFailed
    }
}
