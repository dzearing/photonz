import Foundation

// The setup window as a list of steps.
//
// The window that asks for the macOS permissions is Photonz's one setup
// window. It shows one step at a time, and only the steps this Mac still needs
// AND this person has not seen: a permission already granted, a tool not on
// this Mac, skills already installed, or a step seen and skipped before are
// all left out. Seen is stored per step, so a step added in a later version
// shows once to people who already finished setup, and nothing else comes back.
//
// The rules, and what each one is defending against:
//
//  * A step is seen the moment it is on screen, so quitting or restarting
//    with it up does not show it again: each step is shown once.
//  * CLOSING the window is a no to the whole run, not only the page on show:
//    the counter said how many were left, and the person chose to stop. The
//    one close that is not a no is the one carrying a pending restart, because
//    that close IS the restart: the steps after it are owed a showing on the
//    other side.
//  * The old one page setup is migrated ONCE, on the first launch that knows
//    about steps: an install that finished it (or waved it away) has seen the
//    permission steps. Read every launch instead, it would fire on a new person
//    the moment this window recorded their Screen Recording grant, and eat the
//    microphone and keys steps they were owed after the restart.
//  * Reopening the window from the menu bar is asking for it, so it shows what
//    is still needed whatever was seen, and every step as done when nothing is.

/// One page of the setup window.
public enum SetupStep: String, CaseIterable, Codable, Hashable, Sendable {
    case screenRecording, microphone, screenshotKeys, agents

    /// The steps the old one page setup window held.
    public static let permissionSteps: Set<SetupStep> = [.screenRecording, .microphone, .screenshotKeys]
}

/// What this Mac has already sorted, read fresh by the app.
public struct SetupFacts: Equatable, Sendable {
    public var screenRecordingGranted: Bool
    /// Allowed or turned down in macOS: either way it has been answered.
    public var microphoneAnswered: Bool
    public var screenshotKeysFree: Bool
    /// A tool on this Mac that Photonz is not set up in yet. False when no tool
    /// is here, when every one already has Photonz, or when the release does
    /// not let agents in at all.
    public var agentsToSetUp: Bool

    public init(screenRecordingGranted: Bool, microphoneAnswered: Bool,
                screenshotKeysFree: Bool, agentsToSetUp: Bool) {
        self.screenRecordingGranted = screenRecordingGranted
        self.microphoneAnswered = microphoneAnswered
        self.screenshotKeysFree = screenshotKeysFree
        self.agentsToSetUp = agentsToSetUp
    }
}

/// Which steps show, what a run through them remembers, and their words.
public enum SetupFlow {

    public static func isNeeded(_ step: SetupStep, facts: SetupFacts) -> Bool {
        switch step {
        case .screenRecording: !facts.screenRecordingGranted
        case .microphone: !facts.microphoneAnswered
        case .screenshotKeys: !facts.screenshotKeysFree
        case .agents: facts.agentsToSetUp
        }
    }

    /// The steps a launch shows, in order: still needed and never seen.
    public static func steps(facts: SetupFacts, seen: Set<SetupStep>) -> [SetupStep] {
        SetupStep.allCases.filter { isNeeded($0, facts: facts) && !seen.contains($0) }
    }

    /// The steps the menu bar's Welcome & Permissions shows: what is still
    /// needed, seen or not; or, with nothing left, every step as done, so the
    /// window never opens empty. The agents step is left out of that second
    /// list on a Mac with neither tool, where it has nothing to show.
    public static func reopenedSteps(facts: SetupFacts, agentToolOnThisMac: Bool) -> [SetupStep] {
        let needed = steps(facts: facts, seen: [])
        guard needed.isEmpty else { return needed }
        return SetupStep.allCases.filter { $0 != .agents || agentToolOnThisMac }
    }

    /// Whether the window opens itself at launch.
    public static func presentsAtLaunch(steps: [SetupStep], tourPending: Bool) -> Bool {
        !steps.isEmpty || tourPending
    }

    /// What the first launch that knows about steps adds to `seen`.
    public static func migratedSeen(seen: Set<SetupStep>, setupCompleted: Bool,
                                    setupDismissed: Bool) -> Set<SetupStep> {
        guard setupCompleted || setupDismissed else { return seen }
        return seen.union(SetupStep.permissionSteps)
    }

    /// Seen as stored: one name per step, sorted so the file reads the same
    /// every time.
    public static func encode(_ seen: Set<SetupStep>) -> [String] {
        seen.map(\.rawValue).sorted()
    }

    /// Seen as read back. A name this version does not know (written by a later
    /// one) is left out rather than failing the lot.
    public static func decode(_ stored: [String]) -> Set<SetupStep> {
        Set(stored.compactMap(SetupStep.init(rawValue:)))
    }

    // MARK: - The words

    public static let windowHeading = "Set up Photonz"

    public static func title(_ step: SetupStep) -> String {
        switch step {
        case .screenRecording: "Screen Recording"
        case .microphone: "Microphone"
        case .screenshotKeys: "Free up the screenshot keys"
        case .agents: "Use Photonz from your agents"
        }
    }

    /// What a step says while there is still something to do on it.
    public static func body(_ step: SetupStep, appName: String = "Photonz", keys: String = "the keys") -> String {
        switch step {
        case .screenRecording:
            "Lets \(appName) take screenshots and record video. Everything else works without it."
        case .microphone:
            "Adds your voice to screen recordings. Skip it if you never narrate."
        case .screenshotKeys:
            "macOS still owns \(keys). In Keyboard Settings, open Keyboard Shortcuts, then Screenshots, and turn them off."
        case .agents:
            "Ask Claude Code or Copilot to edit, measure or redline in \(appName). Install sets it up in the tools on this Mac."
        }
    }

    /// What a step says once it is done while the window is up.
    public static func doneBody(_ step: SetupStep, appName: String = "Photonz") -> String {
        switch step {
        case .screenRecording: "\(appName) can capture your screen."
        case .microphone: "Your voice can be included in screen recordings."
        case .screenshotKeys: "The screenshot keys now open \(appName)."
        case .agents: "Your agents can use \(appName)."
        }
    }

    public static func relaunchBody(appName: String = "Photonz") -> String {
        "Access granted. macOS turns it on when \(appName) reopens."
    }

    public static let screenRecordingStuckHint = "Not in the list? Restart your Mac and try again."

    public static let microphoneDeniedBody =
        "Microphone access is off. Turn it on in System Settings to narrate recordings."

    public static let agentsAskLine = "Ask inside Photonz needs no setup until you use it."

    /// What the tour page says. Not the one page window's headline: that one
    /// talks about "the setup below", and here there is none below.
    public static let tourHeadline =
        "Take a quick lap of the window, or jump straight in. The tour is under Help whenever you want it."

    /// The last page's one line about doing any of it later.
    public static let laterLine = "Anything you skip is in Settings and the menu bar menu."

    public static let skipButtonTitle = "Skip"
    public static let continueButtonTitle = "Continue"
    public static let doneButtonTitle = "Done"
    public static let installButtonTitle = "Install"
    public static let installedLabel = "Installed"

    /// Every word above, labelled, so a test runs the copy rules over the lot.
    public static var allCopy: [(String, String)] {
        var all: [(String, String)] = [("heading", windowHeading)]
        for step in SetupStep.allCases {
            all.append(("\(step) title", title(step)))
            all.append(("\(step) body", body(step, keys: "⇧⌘3, ⇧⌘4")))
            all.append(("\(step) done", doneBody(step)))
        }
        all += [("relaunch", relaunchBody()), ("stuck hint", screenRecordingStuckHint),
                ("microphone off", microphoneDeniedBody), ("ask line", agentsAskLine),
                ("later line", laterLine), ("tour headline", tourHeadline), ("skip", skipButtonTitle),
                ("continue", continueButtonTitle), ("done", doneButtonTitle),
                ("install", installButtonTitle), ("installed", installedLabel)]
        return all
    }
}

/// One showing of the setup window: its pages, where the person is, and what
/// they have left behind.
public struct SetupRun: Equatable, Sendable {
    /// The steps, fixed when the window opened so nothing vanishes mid-glance.
    public let pages: [SetupStep]
    /// Whether the tour offer is the page after the last step.
    public let endsWithTour: Bool
    /// Whether moving on passes over a later step that got done meanwhile. A
    /// launch does; a run opened from the menu shows each one as done instead.
    public let passesOverDone: Bool
    public private(set) var index: Int = 0
    /// Steps left with Skip or Continue during this run.
    public private(set) var seen: Set<SetupStep> = []

    public init(pages: [SetupStep], endsWithTour: Bool, passesOverDone: Bool = true) {
        self.pages = pages
        self.endsWithTour = endsWithTour
        self.passesOverDone = passesOverDone
    }

    /// The step on show, or nil on the tour page and once finished.
    public var current: SetupStep? { pages.indices.contains(index) ? pages[index] : nil }

    public var isOnTour: Bool { endsWithTour && index == pages.count }

    public var isFinished: Bool { index > pages.count || (!endsWithTour && index == pages.count) }

    /// Whether moving on from this page closes the window.
    public var isLastPage: Bool {
        endsWithTour ? isOnTour : index == pages.count - 1
    }

    /// "2 of 3" while there is more than one step and a step is on show.
    public var counter: String? {
        guard pages.count > 1, current != nil else { return nil }
        return "\(index + 1) of \(pages.count)"
    }

    /// Leave the page on show (Skip or Continue): it is seen, and the next
    /// page still worth showing comes up.
    public mutating func advance(facts: SetupFacts) {
        if let current { seen.insert(current) }
        index += 1
        while passesOverDone, let next = self.current, !SetupFlow.isNeeded(next, facts: facts) {
            index += 1
        }
    }

    /// Every step that has been on screen in this run, the one on show
    /// included: what the app records as seen while the window is up.
    public var shown: Set<SetupStep> {
        seen.union(pages.prefix(min(index + 1, pages.count)))
    }

    /// What closing the window marks seen. See the note at the top of the file.
    public func seenOnClose(needsRelaunch: Bool) -> Set<SetupStep> {
        needsRelaunch ? shown : seen.union(pages)
    }
}
