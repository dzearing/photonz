import AppKit
// Polls the general pasteboard. On every change: the wall time of the bump,
// then keeps polling until a PNG is readable (or the next bump), and says
// when it appeared and how long a read of it took.
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let pb = NSPasteboard.general
var last = pb.changeCount
let end = Date().addingTimeInterval(seconds)
setvbuf(stdout, nil, _IOLBF, 0)
func now() -> Double { Date().timeIntervalSince1970 }
while now() < end.timeIntervalSince1970 {
    let c = pb.changeCount
    if c != last {
        last = c
        let bump = now()
        var line = String(format: "{\"bump\":%.4f,\"count\":%d", bump, c)
        let firstTypes = (pb.types ?? []).map(\.rawValue)
        line += ",\"typesAtBump\":\(firstTypes.count)"
        var gotPNG = false
        let giveUp = bump + 3
        while now() < giveUp && pb.changeCount == c {
            if (pb.types ?? []).contains(.png) {
                let seen = now()
                let d = pb.data(forType: .png)
                let read = now()
                let types = (pb.types ?? []).map(\.rawValue)
                line += String(format: ",\"pngSeenMs\":%.1f,\"pngReadMs\":%.1f,\"pngBytes\":%d,\"types\":\"%@\"",
                               (seen - bump) * 1000, (read - seen) * 1000, d?.count ?? -1,
                               types.joined(separator: " "))
                gotPNG = true
                break
            }
            usleep(300)
        }
        if !gotPNG { line += ",\"png\":false" }
        print(line + "}")
    }
    usleep(300)
}
