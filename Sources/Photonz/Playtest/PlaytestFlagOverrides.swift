// Switching a feature off for the length of one walk, and putting it back.
//
// A tutorial guide is only offered when the feature it teaches is switched on,
// and plenty else in the app reads a flag the same way. So "what this looks
// like switched off" is half of what a walk has to be able to say, and until
// this it could not: the flags live in one JSON blob under
// `experiments.<release>.flags`, and the only way to move one was `defaults
// write` by hand before the run and by memory afterwards. A walk written for
// that passed either way, which is worse than no walk, so it was deleted.
//
// The timing is the whole trick. A walk's `setup` block is performed after the
// app has launched, and by then the menu bar has been built: the Help menu is
// SwiftUI `.commands` rendered once, so a feature switched off at setup time
// would still have its tutorials shelf hanging in Help. So the flags a walk
// names are read straight off the script and applied in `PhotonzApp.init`,
// before the coordinator, the menu bar or any window exists — exactly the state
// a person who set them in Experiments and relaunched would be in.
//
// Everything moved is put back when the run ends, pass or fail, alongside the
// settings `PlaytestSetupRunner` restores.
#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore

@MainActor
enum PlaytestFlagOverrides {
    /// What was moved, and what it was before: `(name, wasEnabled, nowEnabled)`.
    private static var moved: [(name: String, was: Bool, now: Bool)] = []
    /// The whole flag blob as it stood before anything was moved, so the
    /// machine ends up byte for byte where it started. `nil` inside the
    /// optional means there was no blob at all, and there must not be one
    /// afterwards either.
    private static var blobBefore: Data??
    /// Why the walk cannot be trusted, if the flags could not be set. Kept
    /// rather than thrown, because this runs before the harness exists; the
    /// setup step asks for it and fails the walk with it.
    private(set) static var problem: String?
    /// What a run before this one left switched, if it was killed before it
    /// could put anything back. Every walk's setup line says it, whether or
    /// not that walk names any features itself: a machine that had to be
    /// cleaned up is the news, and the walk that finds it is rarely the walk
    /// that caused it.
    private(set) static var recoveryNote: String?

    /// Where the "before" reading is left on disk while a walk runs.
    ///
    /// Restoring in memory covers a walk that fails, which is the usual way one
    /// ends badly. It does not cover the probe being KILLED — `Scripts/
    /// playtest.sh` does exactly that when a walk overruns its timeout — and a
    /// feature left switched off then is inherited by every walk after it, in a
    /// fresh process that has no idea. So the reading is written down as well,
    /// and the next launch puts back whatever it finds before it does anything
    /// else.
    ///
    /// A fixed path rather than the app's own temporary folder, which a
    /// launched app and the shell that launched it do not agree about. It sits
    /// with the walk output under `/tmp/photonz-playtest`, so anybody looking
    /// at a walk that went wrong finds it in the place they are already in.
    private static let marker = URL(fileURLWithPath: PlaytestScript.scratchRoot)
        .appendingPathComponent("flags-before.plist")

    /// Called from `PhotonzApp.init`, before anything reads a flag.
    ///
    /// Silent about a script that does not parse: the harness parses the same
    /// file a moment later and fails the walk with a readable error naming the
    /// step and the field, which is a better report than anything available
    /// here.
    static func applyEarly() {
        guard AppInfo.flavor == .probe else { return }
        // Whatever a killed run left switched goes back first, before anything
        // reads a flag and before this run takes its own reading. Ahead of the
        // check for a script on purpose: ANY launch of the probe tidies up, so
        // somebody opening it by hand after a walk was killed is not quietly
        // looking at an app with a feature missing.
        recoverFromAKilledRun()
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: PlaytestHarness.argument),
              flag + 1 < arguments.count else { return }
        let url = URL(fileURLWithPath: arguments[flag + 1]).standardizedFileURL
        guard let data = try? Data(contentsOf: url),
              let script = try? PlaytestScript.decode(data),
              !script.setup.flags.isEmpty else { return }
        apply(script.setup.flags)
    }

    /// Puts back the reading a run that never finished left behind. Pure
    /// `UserDefaults` work on purpose: it has to happen before `Experiments`
    /// is built, or the app is already holding the leftover.
    private static func recoverFromAKilledRun() {
        guard let left = NSDictionary(contentsOf: marker) as? [String: Any],
              let key = left["key"] as? String else { return }
        if let blob = left["blob"] as? Data { UserDefaults.standard.set(blob, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: marker)
        recoveryNote = "a run before this one was killed with features still switched, so "
            + "\(key) was put back before this walk started"
    }

    private static func writeMarker(key: String, blob: Data?) {
        try? FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        var left: [String: Any] = ["key": key]
        if let blob { left["blob"] = blob }
        try? NSDictionary(dictionary: left).write(to: marker)
    }

    private static func apply(_ choices: [PlaytestFlagChoice]) {
        let release = Experiments.shared.release
        let catalog = FeatureCatalog.flags(for: release)
        // A name the RUNNING release has no feature for would be written into
        // the blob and thrown away again by the next read, so the walk would
        // run with the feature exactly as it came and claim otherwise. That is
        // the failure this whole thing exists to stop, so it stops the walk.
        let strangers = choices.map(\.name).filter { name in
            !catalog.contains { $0.name == name }
        }
        guard strangers.isEmpty else {
            problem = "setup asks for \(strangers.joined(separator: ", ")), which the "
                + "\(release.title) release has no feature for; either name a feature it "
                + "has or run the walk against the release that does"
            return
        }
        let key = ExperimentsStore.settingsKey(for: release)
        blobBefore = UserDefaults.standard.data(forKey: key)
        writeMarker(key: key, blob: blobBefore ?? nil)
        for choice in choices {
            let was = Experiments.shared.isEnabled(choice.name)
            Experiments.shared.setEnabled(choice.isEnabled, flag: choice.name, in: release)
            moved.append((name: choice.name, was: was, now: choice.isEnabled))
        }
    }

    /// The line the setup log carries, or nil when the walk named no flags.
    /// Says what every named feature ended up as, including one that was
    /// already there, because what a walk proves is the configuration it ran
    /// in and not the edit it happened to make.
    static var report: String? {
        guard !moved.isEmpty else { return nil }
        let said = moved.map { "\($0.name) \($0.now ? "on" : "off")" }
        return "ran with " + said.joined(separator: ", ") + " (" + unchangedPhrase + ")"
    }

    private static var unchangedPhrase: String {
        let changed = moved.filter { $0.was != $0.now }
        guard !changed.isEmpty else { return "all of them already so" }
        return "switched " + changed.map(\.name).joined(separator: ", ")
            + "; the rest were already so"
    }

    /// Puts every feature back where the walk found it. Called however the run
    /// ends, so a walk that failed halfway leaves the machine as it was.
    static func restore() -> String? {
        guard let blob = blobBefore else { return nil }
        let release = Experiments.shared.release
        // Through the same door they were changed by, so the running app and
        // the store agree again...
        for move in moved {
            Experiments.shared.setEnabled(move.was, flag: move.name, in: release)
        }
        // ...and then the blob itself, so a walk that ran on a machine with no
        // flag settings at all does not leave one behind.
        let key = ExperimentsStore.settingsKey(for: release)
        if let blob { UserDefaults.standard.set(blob, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.synchronize()
        try? FileManager.default.removeItem(at: marker)
        let names = moved.map(\.name).joined(separator: ", ")
        moved = []
        blobBefore = nil
        return "put \(names) back as the walk found them"
    }
}
#endif
