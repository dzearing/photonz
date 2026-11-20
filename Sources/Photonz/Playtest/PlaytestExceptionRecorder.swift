#if PHOTONZ_PLAYTEST
import AppKit
import ObjectiveC

/// Writes down what AppKit said when it crashed the probe on purpose. Probe
/// builds only.
///
/// When AppKit catches an Objective-C exception inside a display cycle (a
/// layout or constraints pass), it hands it to its own crash routine and the
/// app dies with EXC_BREAKPOINT. On macOS 27 the crash report it leaves keeps
/// the exception's backtrace but not its name or reason, so the one sentence
/// that says what went wrong is lost. That happened to the probe on 2026-11-17
/// and 2026-11-19 (an update-constraints pass under
/// `-[NSWindow _postWindowNeedsUpdateConstraints]`), and both reports read
/// "Messages:" with nothing after it.
///
/// `reportException:` is never called on that path (tried 2026-11-19: a view
/// raising in `updateConstraints` crashes without it), so this wraps the class
/// method AppKit does call, `+[NSApplication _crashOnException:]`, writes one
/// line, and then lets AppKit crash exactly as before. The line goes to
/// `~/Library/Logs/Photonz Probe/exceptions.jsonl` with the process id, which
/// is how `Scripts/crash-report.mjs` matches it to the crash report and prints
/// the reason as the report's message. It also records every window's frame
/// and minimum content size, because the 2026-11-19 crash came with the editor
/// window grown to 100000 points wide.
///
/// A private selector, which is why it is compiled into the probe only and
/// never into the app a person runs.
enum PlaytestExceptionRecorder {
    typealias CrashOnException = @convention(c) (AnyClass, Selector, NSException) -> Void

    nonisolated(unsafe) private static var original: CrashOnException?
    nonisolated(unsafe) private static var installed = false

    /// Where the lines go. `PHOTONZ_EXCEPTION_LOG` moves it (a drill).
    static var logURL: URL {
        if let path = ProcessInfo.processInfo.environment["PHOTONZ_EXCEPTION_LOG"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Photonz Probe/exceptions.jsonl")
    }

    /// Once, at launch.
    static func install() {
        guard !installed else { return }
        let selector = NSSelectorFromString("_crashOnException:")
        guard let meta = object_getClass(NSApplication.self),
              let method = class_getInstanceMethod(meta, selector) else { return }
        original = unsafeBitCast(method_getImplementation(method), to: CrashOnException.self)
        let wrapper: @convention(block) (AnyClass, NSException) -> Void = { cls, exception in
            record(exception)
            original?(cls, selector, exception)
        }
        method_setImplementation(method, imp_implementationWithBlock(wrapper))
        installed = true
        watchForARunawayWindow()
    }

    nonisolated(unsafe) private static var sawARunawayWindow = false

    /// Both layout crashes found an editor window grown to about 100000
    /// points wide (the screen is 1728) a moment before AppKit gave up, and
    /// nothing in the app sets a frame that size. So the first time any window
    /// in this process grows wider than four screens, the call stack that
    /// resized it is written down beside the exception, once per process.
    private static func watchForARunawayWindow() {
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification,
                                               object: nil, queue: nil) { note in
            guard !sawARunawayWindow, Thread.isMainThread else { return }
            // Posted on the main thread (checked above), where the window lives.
            let resized = note.object as? NSWindow
            let found: Data? = MainActor.assumeIsolated {
                guard let window = resized,
                      let screen = window.screen ?? NSScreen.main,
                      window.frame.width > screen.frame.width * 4 else { return nil }
                sawARunawayWindow = true
                return encode(["kind": "runawayWindow",
                               "title": window.title,
                               "frame": [Double(window.frame.width), Double(window.frame.height)],
                               "contentMinSize": [Double(window.contentMinSize.width),
                                                  Double(window.contentMinSize.height)],
                               "stack": Array(Thread.callStackSymbols.prefix(48))])
            }
            if let found { append(found) }
        }
    }

    /// One JSON line: who, when, what AppKit said, and the windows as they
    /// stood. Never throws and never stops the crash it is recording.
    private static func record(_ exception: NSException) {
        let name = exception.name.rawValue
        let reason = exception.reason ?? ""
        // AppKit crashes over a display cycle's exception on the main thread;
        // anywhere else the windows are not this code's to read.
        let line: Data? = Thread.isMainThread
            ? MainActor.assumeIsolated { encode(["name": name, "reason": reason, "windows": windowsAsTheyStand()]) }
            : encode(["name": name, "reason": reason, "windows": [[String: Any]]()])
        if let line { append(line) }
        FileHandle.standardError.write(Data("AppKit exception \(name): \(reason)\n".utf8))
    }

    @MainActor
    private static func windowsAsTheyStand() -> [[String: Any]] {
        let rect = { (r: NSRect) -> [Double] in
            [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
        }
        return (NSApp?.windows ?? []).map { window in
            [
                "title": window.title,
                "frame": rect(window.frame),
                "contentMinSize": [Double(window.contentMinSize.width), Double(window.contentMinSize.height)],
                "visible": window.isVisible,
            ]
        }
    }

    /// The fields plus who and when, as one line of JSON.
    private static func encode(_ fields: [String: Any]) -> Data? {
        var line = fields
        line["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        line["atMs"] = Int(Date().timeIntervalSince1970 * 1000)
        return try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])
    }

    private static func append(_ line: Data) {
        var data = line
        data.append(0x0A)
        let url = logURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
