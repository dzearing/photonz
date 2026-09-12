import Foundation

// What Help ▸ Tutorials holds, and what the Tutorials window shows, as values.
//
// Both are read straight off the catalogue. Nothing in the app writes a guide's
// name down: a guide added to `TutorialCatalog.guides` turns up in its track's
// submenu and in the window on its own, which is the promise the framework was
// built to keep. The menu code renders a tree it is handed; the window renders
// a list it is handed. Every word either of them says is generated here, so the
// copy rules can be run over it in a test.
//
// The shape, and why:
//
//  * TRACKS, never a flat list. A flat Tutorials menu is a thirty item list the
//    day the seven track tasks land. Help shows the tracks; a track shows its
//    guides.
//  * A track with nothing on it is not a shelf, it is an empty submenu, so it
//    is not shown at all.
//  * A menu row says the guide's name and nothing else. It is TEMPTING to have
//    it carry where you got to ("Take the Tour (step 3 of 6)"), and that was
//    built and then taken out: a command menu's item titles are fixed when the
//    menu is built, so after finishing the guide the row still said step 3 of
//    6. Measured on 2026-09-12 with `Scripts/playtest/tutorial-hub-walk.json`,
//    which leaves the tour part way and reads the menu bar back. A row that is
//    sometimes wrong is worse than a row that only says its name, so progress,
//    ticks and where you stopped all live in the WINDOW, which is an ordinary
//    view and updates as you watch.

// MARK: - The menu

/// Help ▸ Tutorials: one promoted row, one submenu per populated track, and the
/// way into the window.
public struct TutorialMenuModel: Hashable, Sendable {

    /// One guide as a menu row.
    public struct GuideRow: Hashable, Sendable, Identifiable {
        public let guide: TutorialGuide
        public var id: String { guide.id }
        /// What the row says: the guide's title, and only that.
        public var title: String { guide.title }
        /// What resting on the row says: what the guide is for and how long it
        /// takes. Both are true whatever you have done before, which is why
        /// they can be baked into a menu.
        public let help: String
    }

    /// One track as a submenu.
    public struct TrackMenu: Hashable, Sendable, Identifiable {
        public let track: TutorialTrack
        public var id: String { track.rawValue }
        public var title: String { track.title }
        /// Never empty: a track with no guides is left out of the menu.
        public let rows: [GuideRow]
    }

    /// The guide promoted to the top of the menu, when the catalogue has one.
    /// It is a shortcut, not an exception: the same guide is still listed under
    /// its own track, because a track list that leaves a guide out is a lie.
    public let tour: GuideRow?
    /// The populated tracks, in learning order.
    public let tracks: [TrackMenu]

    /// What the submenu is called.
    public static let menuTitle = "Tutorials"
    /// The row at the bottom that opens the window.
    public static let hubRowTitle = "All Tutorials..."
    /// What resting on that row says.
    public static let hubRowHelp = "Every guide, what each one takes, and which ones you have finished."

    /// Nothing to show at all. The Help menu shows no Tutorials submenu rather
    /// than an empty one.
    public var isEmpty: Bool { tour == nil && tracks.isEmpty }

    public init(guides: [TutorialGuide] = TutorialCatalog.guides,
                tourID: String = TutorialCatalog.tourID) {
        let row = { (guide: TutorialGuide) in
            GuideRow(guide: guide, help: TutorialCopy.menuRowHelp(guide))
        }
        tour = guides.first { $0.id == tourID }.map(row)
        tracks = TutorialTrack.allCases.compactMap { track in
            let inTrack = guides.filter { $0.track == track }
            guard !inTrack.isEmpty else { return nil }
            return TrackMenu(track: track, rows: inTrack.map(row))
        }
    }
}

// MARK: - The window

/// The Tutorials window: every track, the guides on it, how long each takes,
/// and which ones you have finished.
public struct TutorialHubModel: Hashable, Sendable {

    /// Where you are with one guide.
    public enum GuideState: Hashable, Sendable {
        case notStarted
        /// Stopped part way. Both numbers read the way a person counts, from 1.
        case inProgress(step: Int, of: Int)
        case finished
    }

    public struct Row: Hashable, Sendable, Identifiable {
        public let guide: TutorialGuide
        public var id: String { guide.id }
        public var title: String { guide.title }
        public var summary: String { guide.summary }
        /// How long it takes, ready to read: "2 min".
        public let length: String
        public let state: GuideState
        /// What the row's button says: Start, Continue, or Again.
        public let actionTitle: String
        /// The one line under the summary, or nil when there is nothing to say
        /// about a guide nobody has started.
        public let statusLine: String?

        /// True when there is something to forget: a tick, a saved place, or
        /// both. The row offers to forget only then, so a list of guides nobody
        /// has run is not a list of menus.
        public var hasProgress: Bool { state != .notStarted }
    }

    public struct Track: Hashable, Sendable, Identifiable {
        public let track: TutorialTrack
        public var id: String { track.rawValue }
        public var title: String { track.title }
        public var blurb: String { track.blurb }
        /// Never empty: a track with no guides is left out.
        public let rows: [Row]
        public let finished: Int
        public var total: Int { rows.count }
        /// How far through the track you are, in words: "1 of 3 finished".
        public let progressLine: String
        /// The same thing as a number, for a bar to draw.
        public var fraction: Double {
            total == 0 ? 0 : Double(finished) / Double(total)
        }
    }

    public let tracks: [Track]
    /// True when there is anything at all to reset.
    public let anyProgress: Bool
    public var isEmpty: Bool { tracks.isEmpty }

    public static let windowTitle = "Tutorials"
    public static let blurb = "Short walks through the real app. Each one puts a ring round a control and tells you what it is for, and you keep working the whole time."
    /// What the window says when the catalogue has nothing in it.
    public static let emptyLine = "There are no guides yet."
    public static let resetAllTitle = "Reset All Progress"
    public static let forgetOneTitle = "Forget My Progress"
    public static let startOverTitle = "Start from the Beginning"

    public init(guides: [TutorialGuide] = TutorialCatalog.guides,
                progress: TutorialProgress = TutorialProgress()) {
        tracks = TutorialTrack.allCases.compactMap { track in
            let inTrack = guides.filter { $0.track == track }
            guard !inTrack.isEmpty else { return nil }
            let rows = inTrack.map { guide -> Row in
                let state = TutorialHubModel.state(of: guide, progress: progress)
                return Row(guide: guide,
                           length: TutorialCopy.length(minutes: guide.minutes),
                           state: state,
                           actionTitle: TutorialCopy.actionTitle(for: state),
                           statusLine: TutorialCopy.statusLine(for: state))
            }
            let finished = rows.filter { $0.state == .finished }.count
            return Track(track: track, rows: rows, finished: finished,
                         progressLine: TutorialCopy.progressLine(finished: finished,
                                                                 total: rows.count))
        }
        anyProgress = !progress.isEmpty
    }

    static func state(of guide: TutorialGuide, progress: TutorialProgress) -> GuideState {
        // Finished wins over a saved place. Finishing clears the place anyway,
        // so the two only overlap for a guide finished once and left part way
        // through a second run, and there the tick is the truer thing to say.
        if progress.isCompleted(guide.id) { return .finished }
        guard progress.isResumable(guide) else { return .notStarted }
        return .inProgress(step: progress.startIndex(for: guide) + 1, of: guide.steps.count)
    }
}

// MARK: - The words

/// Every word the menu and the window generate, in one place, so a test can run
/// the repo's copy rules over the lot.
enum TutorialCopy {

    static func length(minutes: Int) -> String { "\(minutes) min" }

    /// What resting on a menu row says. Nothing here depends on what you have
    /// done before, because a command menu bakes its words in when it is built
    /// and they would go stale. Where you got to is the window's job.
    static func menuRowHelp(_ guide: TutorialGuide) -> String {
        let minutes = guide.minutes == 1 ? "about a minute" : "about \(guide.minutes) minutes"
        return "\(guide.summary) Takes \(minutes). It carries on from wherever you left it."
    }

    static func actionTitle(for state: TutorialHubModel.GuideState) -> String {
        switch state {
        case .notStarted: "Start"
        case .inProgress: "Continue"
        case .finished: "Again"
        }
    }

    static func statusLine(for state: TutorialHubModel.GuideState) -> String? {
        switch state {
        case .notStarted: nil
        case .inProgress(let step, let of): "Stopped at step \(step) of \(of)"
        case .finished: "Finished"
        }
    }

    static func progressLine(finished: Int, total: Int) -> String {
        if total > 0 && finished == total { return "All finished" }
        if finished == 0 { return "None finished yet" }
        return "\(finished) of \(total) finished"
    }
}
