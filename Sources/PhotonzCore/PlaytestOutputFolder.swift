import Foundation

/// What a walk deletes out of its output folder before it writes anything.
///
/// A run's folder is read afterwards as if everything in it came from that run:
/// an audit is required to ship a real `<name>-sc.png`, and the runner writing
/// it picks the file out of this folder by name. Until 2026-09-19 a run only
/// deleted `done.json` before it started, so the pictures of every earlier run
/// stayed. `unique-layer-names-walk` stopping at step 17 left a folder holding
/// six pictures when it had taken one, four of them of an app that still
/// worked, with nothing on them to say so.
///
/// So a run empties its folder first. The only question is how much of it the
/// run may claim, and that is decided here rather than at the moment of
/// deleting, so it can be argued with in a test instead of on somebody's disk.
///
/// - A folder under `PlaytestScript.scratchRoot` is the RUN'S OWN: it is made
///   for this walk, named after it, and nothing else ever writes there. It goes
///   whole.
/// - Anywhere else is SHARED until proven otherwise. A walk may point `out` at
///   a folder that holds other things — beside the walk scripts, say, where
///   every walk in the repository lives — and a rule that guessed which files
///   were leavings would eventually guess wrong about 531 of them. Only the
///   handful of files a run writes under a fixed name are removed there, and
///   the run says out loud that the rest may be old.
public enum PlaytestOutputFolder {

    /// The files a run writes under a name that never varies, and so the only
    /// ones that can be deleted from a folder the run does not own.
    ///
    /// Everything else a walk writes is named by the walk (`names-1.png`,
    /// `panel-before.json`), which is exactly what cannot be told apart from a
    /// file that was already there.
    public static let alwaysNamedTheSame = ["log.json", "done.json",
                                            "menu-shot.txt", "row-menu-shot.txt",
                                            "panel-menu-shot.txt"]

    /// Whether this folder belongs to the run alone, so the run may empty it.
    ///
    /// True for a folder INSIDE the scratch root and false for the root itself:
    /// the root holds one folder per walk, and emptying it would take the walks
    /// running beside this one with it.
    public static func isRunsOwn(_ directory: URL) -> Bool {
        let path = plainPath(directory)
        return path.hasPrefix(PlaytestScript.scratchRoot + "/")
    }

    /// The entries in `directory` this run deletes before it writes anything.
    ///
    /// `entries` is what the folder holds now, as file names. Hidden files are
    /// never touched: `.DS_Store` is the Finder's, not the walk's.
    public static func leftovers(in directory: URL, named entries: [String]) -> [String] {
        let mine = isRunsOwn(directory)
        return entries.filter { name in
            guard !name.hasPrefix(".") else { return false }
            return mine || alwaysNamedTheSame.contains(name)
        }
    }

    /// One line for the log saying what was cleared, or nil when there was
    /// nothing to clear and nothing to warn about.
    ///
    /// This is in the run's first log line because the fact it carries — that
    /// every picture in this folder is this run's — is the fact an audit leans
    /// on when it ships one.
    public static func clearedSaid(count: Int, in directory: URL) -> String? {
        let files = count == 1 ? "1 file" : "\(count) files"
        guard isRunsOwn(directory) else {
            return "cleared \(files) this run writes under a fixed name; "
                + "the rest of this folder is shared with something else, so any other "
                + "picture in it may be from an earlier run"
        }
        guard count > 0 else { return nil }
        return "cleared \(files) an earlier run left, so every picture here is this run's"
    }

    /// The path as written, with `.` and `..` settled and the `/private` macOS
    /// puts in front of `/tmp` taken off, so `/tmp/photonz-playtest/redline`
    /// and `/private/tmp/photonz-playtest/redline` are read as one folder.
    private static func plainPath(_ directory: URL) -> String {
        let path = directory.standardizedFileURL.path
        if path.hasPrefix("/private/tmp/") { return String(path.dropFirst("/private".count)) }
        return path
    }
}
