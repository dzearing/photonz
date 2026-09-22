// Taking back the pictures a KILLED walk lent somebody's Screenshots folder.
//
// A walk's `setup` block can lend the capture folder a fixture for the length
// of the run, and `PlaytestSetupRunner.returnCaptures` takes it away again
// however the run ends. That covers a walk that fails, which is the usual way
// one ends badly. It does not cover the probe being KILLED — `Scripts/
// playtest.sh` does exactly that when a walk overruns its timeout, and a sweep
// that is stopped does it to whatever was running.
//
// What is left then is not a setting nobody can see: it is six files sitting in
// a person's own Screenshots folder, and the next run of that walk REFUSES to
// start, because lending never writes over a name that is already taken. That
// is what happened on 2026-09-22 01:09, and history-thumbnail-shapes-walk was
// still failing at 12:10 with "a file of that name is already there".
//
// So every lend is written down as it happens, and the next launch of the probe
// takes back whatever it finds before it does anything else. Same shape, same
// fixed path and the same reason as `PlaytestFlagOverrides`.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

@MainActor
enum PlaytestLentCaptures {
    /// What a run before this one lent and never took back, if it was killed.
    /// Every walk's setup line says it, whether or not that walk lends
    /// anything itself: a machine that had to be cleaned up is the news, and
    /// the walk that finds it is rarely the walk that caused it.
    private(set) static var recoveryNote: String?

    /// Where the list of lent files is left on disk while a walk runs.
    ///
    /// A fixed path rather than the app's own temporary folder, which a
    /// launched app and the shell that launched it do not agree about. It sits
    /// with the walk output under `/tmp/photonz-playtest`, beside
    /// `flags-before.plist`, so anybody looking at a walk that went wrong finds
    /// it in the place they are already in.
    private static let marker = URL(fileURLWithPath: PlaytestScript.scratchRoot)
        .appendingPathComponent("captures-lent.plist")

    /// Remembers one more lent file. Written after every single lend rather
    /// than once at the end, because the kill can land between any two of them.
    static func remember(_ url: URL) {
        var paths = written()
        guard !paths.contains(url.path) else { return }
        paths.append(url.path)
        write(paths)
    }

    /// The run finished and took its own files back, so there is nothing left
    /// for the next launch to tidy.
    static func forget() {
        try? FileManager.default.removeItem(at: marker)
    }

    /// Called from `PhotonzApp.init`, before any window or capture store
    /// exists, so the shelf this run builds never sees a leftover.
    ///
    /// Ahead of the check for a script on purpose: ANY launch of the probe
    /// tidies up, so somebody opening it by hand after a walk was killed is not
    /// quietly looking at six fixtures in their own Screenshots folder.
    static func recoverFromAKilledRun() {
        guard AppInfo.flavor == .probe else { return }
        let paths = written()
        guard !paths.isEmpty else { return }
        var taken: [String] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            guard (try? FileManager.default.removeItem(atPath: path)) != nil else { continue }
            taken.append(URL(fileURLWithPath: path).lastPathComponent)
        }
        forget()
        guard !taken.isEmpty else { return }
        recoveryNote = "a run before this one was killed with captures still lent, so "
            + taken.joined(separator: ", ") + " was taken back out of "
            + CaptureStore.defaultDirectory.path + " before this walk started"
    }

    private static func written() -> [String] {
        (NSArray(contentsOf: marker) as? [String]) ?? []
    }

    private static func write(_ paths: [String]) {
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? NSArray(array: paths).write(to: marker)
    }
}
#endif
