// A stand-in for the person at the Mac, for queue/bin/focus-drill.sh.
//
// On 2026-09-26 the user could not type while the loop tested: the probe took
// their keyboard and their focus. This is the measurement behind the fix. It
// opens one ordinary window with a text view, takes the front the way the app
// a person is typing in holds it, and every 100 ms writes one line of JSON:
//
//   front     the app macOS says is active (the one a key press goes to)
//   key       whether this window is still the key window
//   landed    whether a key typed now would reach this window
//   probe     every on-screen window the probe owns: its layer (0 a window,
//             101 a menu) and whether it sits above this one
//
// plus an `activate` line the instant any other app becomes active.
//
// Why `landed` is read rather than typed. A keyboard's key goes to whichever
// app the window server has in front, into that app's key window, unless some
// app holds a menu open, which takes every key until it closes. Typing a
// synthetic key cannot see any of that: a key posted into this app's own queue
// (NSApp.postEvent) or by pid (CGEvent.postToPid) is handed straight to this
// app, skipping the routing, and it landed in the canary's text view 39 times
// out of 39 with Finder in front (measured 2026-09-26). A key through the HID
// tap would see the routing but would type into the probe, needs an
// Accessibility grant, and resets the idle clock the walk gate reads. So
// `landed` is the routing itself: this app is active, this window is key, and
// no probe window sits at a menu layer.
//
//   focus-canary <out.jsonl> <probe-bundle-id> <seconds>
//
// It ends itself after <seconds> whatever happens, and on SIGTERM.
import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 4, let lifetime = Double(args[3]) else {
    FileHandle.standardError.write("usage: focus-canary <out.jsonl> <probe-bundle-id> <seconds>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[1]
let probeBundle = args[2]
FileManager.default.createFile(atPath: outPath, contents: nil)
let out = FileHandle(forWritingAtPath: outPath)!

func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
func emit(_ fields: [String: Any]) {
    var line = fields
    line["ms"] = now()
    if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) {
        out.write(data)
        out.write("\n".data(using: .utf8)!)
    }
}

final class Canary: NSObject, NSApplicationDelegate {
    let lifetime: Double
    init(lifetime: Double) { self.lifetime = lifetime }
    let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 420, height: 160),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
    /// Ticks in a row this window has not had the keys. A person whose
    /// window was taken clicks back into it; so does the canary, after half a
    /// second, so a second theft in the same walk is counted and not hidden
    /// behind the first.
    var lostTicks = 0
    /// Where this window sat in the screen's front-to-back list last tick.
    var canaryAt = -1

    func applicationDidFinishLaunching(_ note: Notification) {
        window.title = "Focus canary"
        // As big as a person's own app usually is: the whole visible screen, so
        // the probe's windows are buried the way they are while somebody works.
        if let visible = NSScreen.main?.visibleFrame { window.setFrame(visible, display: false) }
        window.contentView = text
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        emit(["kind": "start", "pid": Int(getpid())])
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        Timer.scheduledTimer(withTimeInterval: lifetime, repeats: false) { _ in
            emit(["kind": "end"])
            exit(0)
        }
    }

    @objc func activated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        emit(["kind": "activate", "app": app?.bundleIdentifier ?? app?.localizedName ?? "?",
              "pid": Int(app?.processIdentifier ?? 0)])
    }

    /// Every window the probe has on screen, front to back, and whether it is
    /// in front of this canary's window.
    func probeWindows() -> [[String: Any]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        let probePids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: probeBundle)
            .map { Int($0.processIdentifier) })
        var aboveUs = true
        var found: [[String: Any]] = []
        for (at, info) in list.enumerated() {
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            if number == window.windowNumber { aboveUs = false; canaryAt = at; continue }
            let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
            guard probePids.contains(pid) else { continue }
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
            // A window with no size, or entirely off every screen, is nothing a
            // person could see or click.
            let w = bounds["Width"] ?? 0, h = bounds["Height"] ?? 0
            if w < 2 || h < 2 { continue }
            // A window at zero alpha is on screen for AppKit and invisible to
            // a person; walks keep theirs that way.
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            found.append(["layer": layer, "above": aboveUs, "w": Int(w), "h": Int(h), "at": at,
                          "alpha": (alpha * 100).rounded() / 100])
        }
        return found
    }

    func tick() {
        let front = NSWorkspace.shared.frontmostApplication
        let frontId = front?.bundleIdentifier ?? front?.localizedName ?? "?"
        let isKey = window.isKeyWindow
        var line: [String: Any] = ["kind": "tick", "front": frontId, "key": isKey,
                                   "active": NSApp.isActive]
        canaryAt = -1
        let probe = probeWindows()
        if !probe.isEmpty { line["probe"] = probe }
        line["at"] = canaryAt
        let menuOpen = probe.contains { ($0["layer"] as? Int ?? 0) >= Int(CGWindowLevelForKey(.popUpMenuWindow)) }
        line["landed"] = NSApp.isActive && isKey && !menuOpen
        emit(line)
        lostTicks = (line["landed"] as? Bool ?? true) ? 0 : lostTicks + 1
        if lostTicks >= 5 {
            lostTicks = 0
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            emit(["kind": "reclaim"])
        }

    }
}

signal(SIGTERM) { _ in exit(0) }
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let canary = Canary(lifetime: lifetime)
app.delegate = canary
app.run()
