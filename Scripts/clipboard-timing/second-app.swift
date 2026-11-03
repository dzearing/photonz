import AppKit
import UniformTypeIdentifiers
// A stand-in for a SECOND Photonz answering the same capture shortcut, the
// way the installed 0.21.0 and Photonz Dev both did on 2026-11-03: each took
// every screenshot, under the same file name, and each put it on the
// clipboard. This one copies exactly as 0.21.0's CaptureStore.copyToPasteboard
// did: clear the clipboard, read the picture back, make its PNG and TIFF on
// the main thread, then write one item. It reacts to the new screenshot file
// appearing, after AFTER_MS (the history reload 0.21.0 did before copying).
// Usage: second-app <seconds> <afterMs>
let seconds = Double(CommandLine.arguments[1]) ?? 60
let afterMs = Double(CommandLine.arguments[2]) ?? 200
let pb = NSPasteboard.general
setvbuf(stdout, nil, _IOLBF, 0)
func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest) ? data as Data : nil
}
let folder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Screenshots", isDirectory: true)
func screenshots() -> Set<String> {
    Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        .filter { $0.hasPrefix("Screenshot") && $0.hasSuffix(".png") })
}
var seen = screenshots()
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    let now = screenshots()
    let fresh = now.subtracting(seen)
    seen = now
    if let name = fresh.sorted().last {
        let url = folder.appendingPathComponent(name)
        usleep(useconds_t(afterMs * 1000))
        let t0 = Date()
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            if let data = png(image) { item.setData(data, forType: .png) }
            let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            if let tiff = ns.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        }
        let ok = pb.writeObjects([item])
        print(String(format: "{\"cleared\":%.4f,\"emptyMs\":%.0f,\"wrote\":%@,\"file\":\"%@\"}",
                     t0.timeIntervalSince1970, Date().timeIntervalSince(t0) * 1000, ok ? "true" : "false", name))
    }
    usleep(5000)
}
