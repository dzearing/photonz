import AppKit
let pb = NSPasteboard.general
print("types:", (pb.types ?? []).map(\.rawValue).joined(separator: " "))
for t in [NSPasteboard.PasteboardType.png, .tiff] {
    let d = pb.data(forType: t)
    var dims = ""
    if let d, let s = CGImageSourceCreateWithData(d as CFData, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) { dims = "\(i.width)x\(i.height)" }
    print(t.rawValue, d?.count ?? -1, dims)
}
print("NSImage reads:", NSImage(pasteboard: pb).map { "\($0.size)" } ?? "nothing")
