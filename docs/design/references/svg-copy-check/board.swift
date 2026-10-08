// save <dir> | restore <dir> | dump
import AppKit
let args = CommandLine.arguments
let pb = NSPasteboard.general
switch args[1] {
case "save":
    let dir = URL(fileURLWithPath: args[2])
    var manifest: [[String]] = []
    for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
        for (j, t) in item.types.enumerated() {
            if let d = item.data(forType: t) {
                let f = "\(i)-\(j).bin"
                try! d.write(to: dir.appendingPathComponent(f))
                manifest.append([String(i), t.rawValue, f])
            }
        }
    }
    try! JSONSerialization.data(withJSONObject: manifest).write(to: dir.appendingPathComponent("manifest.json"))
    print("saved \(manifest.count) flavors from \(pb.pasteboardItems?.count ?? 0) items")
case "restore":
    let dir = URL(fileURLWithPath: args[2])
    let manifest = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("manifest.json"))) as! [[String]]
    var items: [Int: NSPasteboardItem] = [:]
    for row in manifest {
        let i = Int(row[0])!
        let item = items[i] ?? NSPasteboardItem(); items[i] = item
        item.setData(try! Data(contentsOf: dir.appendingPathComponent(row[2])), forType: .init(row[1]))
    }
    pb.clearContents()
    pb.writeObjects(items.keys.sorted().map { items[$0]! })
    print("restored \(manifest.count) flavors in \(items.count) items")
default:
    for (i, item) in (pb.pasteboardItems ?? []).enumerated() {
        for t in item.types {
            let n = item.data(forType: t)?.count ?? -1
            print("item \(i): \(t.rawValue) \(n) bytes")
        }
    }
    if let s = pb.string(forType: .string) { print("--- text ---\n\(s)") }
}
