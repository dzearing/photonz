import AppKit
// A second process pasting soon after a copy. It puts its own marker on the
// clipboard, waits for anybody else to change it (the copy), waits DELAY ms
// after it saw the change, then reads the PNG: the new picture, the marker
// (the clipboard from before) or nothing. Delays cycle through the list.
let seconds = Double(CommandLine.arguments[1]) ?? 120
let delays = CommandLine.arguments[2].split(separator: ",").compactMap { Double($0) }
let pb = NSPasteboard.general
func mark() -> Int { pb.clearContents(); pb.setString("paster-marker", forType: .string); return pb.changeCount }
var mine = mark()
var n = 0
let end = Date().addingTimeInterval(seconds)
setvbuf(stdout, nil, _IOLBF, 0)
while Date() < end {
    let c = pb.changeCount
    if c != mine {
        let seen = Date().timeIntervalSince1970
        let d = delays[n % delays.count]; n += 1
        let target = seen + d / 1000
        while Date().timeIntervalSince1970 < target { usleep(100) }
        let asked = Date().timeIntervalSince1970
        let types = (pb.types ?? []).map(\.rawValue)
        let data = pb.data(forType: .png)
        let got = Date().timeIntervalSince1970
        let old = pb.string(forType: .string) == "paster-marker"
        var w = -1, h = -1
        if let data, let src = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            w = props[kCGImagePropertyPixelWidth] as? Int ?? -1; h = props[kCGImagePropertyPixelHeight] as? Int ?? -1
        }
        let outcome = w > 0 ? "new" : (old ? "old" : (types.isEmpty ? "empty" : "noPNG"))
        print(String(format: "{\"seen\":%.4f,\"delayMs\":%.0f,\"waitedMs\":%.1f,\"bytes\":%d,\"w\":%d,\"h\":%d,\"outcome\":\"%@\",\"types\":%d}",
                     seen, d, (got - asked) * 1000, data?.count ?? -1, w, h, outcome, types.count))
        usleep(150_000)
        mine = mark()
    }
    usleep(200)
}
