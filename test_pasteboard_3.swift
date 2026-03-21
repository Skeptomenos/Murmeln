import AppKit

let pasteboard = NSPasteboard.withUniqueName()
print("Initial changeCount: \(pasteboard.changeCount)")

let item1 = NSPasteboardItem()
item1.setString("item1", forType: .string)

let item2 = NSPasteboardItem()
item2.setString("item2", forType: .string)

pasteboard.writeObjects([item1])
print("ChangeCount after item1: \(pasteboard.changeCount)")

pasteboard.writeObjects([item2])
print("ChangeCount after item2: \(pasteboard.changeCount)")
