import AppKit

let pasteboard = NSPasteboard.general
pasteboard.clearContents()

let item1 = NSPasteboardItem()
item1.setString("item1", forType: .string)

let item2 = NSPasteboardItem()
item2.setString("item2", forType: .string)

print("Writing item1...")
pasteboard.writeObjects([item1])
print("Count after item1: \(pasteboard.pasteboardItems?.count ?? 0)")

print("Writing item2...")
pasteboard.writeObjects([item2])
print("Count after item2: \(pasteboard.pasteboardItems?.count ?? 0)")

if let items = pasteboard.pasteboardItems {
    for (i, item) in items.enumerated() {
        print("Item \(i): \(item.string(forType: .string) ?? "nil")")
    }
}
