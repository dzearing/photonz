import AppKit
// Prints one line each time the clipboard moves, for a script that has to act
// on a capture the moment it lands. Reads the count only, never the contents,
// so it cannot make a promised type be made early.
// Usage: clipwatch <seconds>
let seconds = Double(CommandLine.arguments.dropFirst().first ?? "") ?? 120
setvbuf(stdout, nil, _IOLBF, 0)
let pb = NSPasteboard.general
var last = pb.changeCount
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    let c = pb.changeCount
    if c != last { last = c; print("\(c) \(Date().timeIntervalSince1970)") }
    usleep(1000)
}
