import AppKit
// A second process pasting a new screenshot the way each kind of app reads
// the clipboard. It marks the clipboard, waits for anybody else to change it
// (a capture), waits the delay, then reads it in ONE style, so every read is
// the first anybody in this process asks of that copy:
//   web       Chrome or Safari pasting into a page: public.png
//   native    Preview, Pages, Notes: NSImage(pasteboard:) (TIFF or PNG)
//   file      Finder, Mail, Claude: the file URL, and the file must be there,
//             whole, and decode to a picture
//   electron  Slack, Teams: NSFilenamesPboardType, then public.png
// Styles cycle fastest, then delays, so 20 captures per style and delay need
// styles x delays x 20 captures. One JSON line per paste.
// Usage: targets <seconds> <delaysMs,comma> <styles,comma> [expectedWidth]
let seconds = Double(CommandLine.arguments[1]) ?? 120
let delays = CommandLine.arguments[2].split(separator: ",").compactMap { Double($0) }
let styles = CommandLine.arguments[3].split(separator: ",").map(String.init)
let expectedWidth = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4]) : nil
let pb = NSPasteboard.general
let marker = "targets-marker"
func mark() -> Int { pb.clearContents(); pb.setString(marker, forType: .string); return pb.changeCount }
func width(of data: Data?) -> Int? {
    guard let data, let src = CGImageSourceCreateWithData(data as CFData, nil),
          let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
    return p[kCGImagePropertyPixelWidth] as? Int
}
func width(ofFile path: String) -> (exists: Bool, bytes: Int, width: Int?) {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return (false, 0, nil) }
    let bytes = (attrs[.size] as? Int) ?? 0
    // Decode the whole picture, the way an attachment preview does: a file
    // still being written reads its header but not its pixels.
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { return (true, bytes, nil) }
    return (true, bytes, image.width)
}
func describe(_ w: Int?) -> String {
    guard let w else { return "noImage" }
    if let expectedWidth, w != expectedWidth { return "wrongSize" }
    return "new"
}
var mine = mark()
var n = 0
let end = Date().addingTimeInterval(seconds)
setvbuf(stdout, nil, _IOLBF, 0)
while Date() < end {
    let c = pb.changeCount
    if c != mine {
        let seen = Date().timeIntervalSince1970
        let style = styles[n % styles.count]
        let delay = delays[(n / styles.count) % delays.count]
        n += 1
        let target = seen + delay / 1000
        while Date().timeIntervalSince1970 < target { usleep(200) }
        let asked = Date().timeIntervalSince1970
        let types = (pb.types ?? []).map(\.rawValue)
        let old = types.contains(NSPasteboard.PasteboardType.string.rawValue) && pb.string(forType: .string) == marker
        var outcome = "noImage", detail = ""
        switch style {
        case "web":
            let d = pb.data(forType: .png)
            outcome = describe(width(of: d)); detail = "png=\(d?.count ?? -1)"
        case "native":
            let image = NSImage(pasteboard: pb)
            let w = image?.representations.first?.pixelsWide
            outcome = describe(w); detail = "nsimage=\(w ?? -1)"
        case "file", "electron":
            var path: String?
            if style == "file" {
                let urls = pb.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL]
                path = urls?.first?.path
            } else {
                path = (pb.propertyList(forType: .init("NSFilenamesPboardType")) as? [String])?.first
            }
            if let path {
                let f = width(ofFile: path)
                outcome = f.exists ? describe(f.width) : "missingFile"
                if f.exists && f.width == nil { outcome = "badFile" }
                detail = "file=\((path as NSString).lastPathComponent) bytes=\(f.bytes)"
            } else {
                outcome = "noFile"
            }
            if style == "electron" {
                let d = pb.data(forType: .png)
                if outcome == "new" && describe(width(of: d)) != "new" { outcome = "noPNG" }
                detail += " png=\(d?.count ?? -1)"
            }
        default: break
        }
        if outcome != "new" && old { outcome = "old" }
        if outcome != "new" && types.isEmpty { outcome = "empty" }
        let got = Date().timeIntervalSince1970
        let line: [String: Any] = [
            "n": n, "seen": seen, "style": style, "delayMs": delay,
            "waitedMs": ((got - asked) * 1000).rounded(), "outcome": outcome,
            "detail": detail, "types": types.count,
        ]
        if let json = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
           let text = String(data: json, encoding: .utf8) { print(text) }
        // A second app may still be writing its own copy of this capture:
        // mark only once the clipboard has been still for 0.7 s, so the
        // marker never lands in the middle of a race and decides it.
        var quietSince = Date(), count = pb.changeCount
        while Date().timeIntervalSince(quietSince) < 0.7 && Date() < end {
            if pb.changeCount != count { count = pb.changeCount; quietSince = Date() }
            usleep(2000)
        }
        mine = mark()
    }
    usleep(200)
}
