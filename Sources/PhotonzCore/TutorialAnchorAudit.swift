import Foundation

// The day a control is renamed, moved or put behind a flag, a guide that points
// at it starts pointing at nothing. This file is how that becomes a failure a
// build reports instead of something a person finds mid tour.
//
// There are two halves, and they catch different things.
//
//  * `TutorialWalkCoverage` is the PROMISE THAT EVERY GUIDE IS DRIVEN. It reads
//    the walks in `Scripts/playtest` and holds the catalogue to them: every
//    guide has a walk, and that walk waits on every step the guide has. Cheap
//    enough to run in the test suite, because it is only reading JSON.
//  * `TutorialAnchorAudit` is what the walk itself reports back. While a guide
//    runs over the real app, every step records whether its control was ever
//    found on screen; these rules turn that record into a failure that names
//    the guide, the step and the missing name.
//
// Neither one guesses. The first cannot tell whether a control exists, only
// whether anybody looks; the second cannot run itself, it reads what a live run
// saw. Together they are the whole claim: every guide is walked, and every step
// of it pointed at something real.

// MARK: - What one step's control did

/// What a live run of a guide saw when it pointed at one step's control.
///
/// Written by the app as each step is left, read by the walk that drove it.
public struct TutorialAnchorVerdict: Hashable, Sendable, Codable {
    /// The guide's id, so a failure reads like a guide and not like an index.
    public let guide: String
    /// The step's id, for the same reason.
    public let step: String
    /// The name the step points at.
    public let anchor: TutorialAnchor
    /// Whether the control was ever found on screen while the step was up.
    public let resolved: Bool
    /// How long the step was up, in seconds. A step left in a blink never had
    /// a fair chance to produce its control, and the rules say so.
    public let shownSeconds: Double

    public init(guide: String, step: String, anchor: TutorialAnchor,
                resolved: Bool, shownSeconds: Double) {
        self.guide = guide
        self.step = step
        self.anchor = anchor
        self.resolved = resolved
        self.shownSeconds = shownSeconds
    }
}

/// The rules a live run's verdicts are held to.
public enum TutorialAnchorAudit {
    /// How long a step's control has to turn up before its absence is real.
    ///
    /// Not zero, because a panel section that arrives with a selection, or one
    /// that has to be scrolled to, is a beat behind the callout. Not long
    /// either: a person waiting a second for the ring to land has already
    /// noticed.
    public static let grace: Double = 0.5

    /// Everything a live run found wrong, in plain words. Empty means every
    /// step of every guide it drove pointed at something really on screen.
    ///
    /// `namesOnScreen` is what the app had hanging at the end, which is the
    /// list somebody fixing this wants to read: the name they meant is usually
    /// one line away from the name they typed.
    public static func problems(in verdicts: [TutorialAnchorVerdict],
                                namesOnScreen: [String] = []) -> [String] {
        verdicts.filter { !$0.resolved && $0.shownSeconds >= grace }.map { verdict in
            var said = "\(verdict.guide) step \(verdict.step) points at \(verdict.anchor.name), "
                + "and nothing in the window carries that name "
                + "(the step was up for \(seconds(verdict.shownSeconds)))"
            if !namesOnScreen.isEmpty {
                said += ". The names on screen were: " + namesOnScreen.joined(separator: ", ")
            }
            return said
        }
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }
}

// MARK: - Every guide gets driven

/// The rule that keeps a guide from being written and never run: every guide in
/// the catalogue has a walk, and the walk goes all the way through it.
public enum TutorialWalkCoverage {

    /// One walk, reduced to the two things this cares about: which guides it
    /// starts, and which of their steps it waits on.
    public struct Walk: Hashable, Sendable {
        /// The walk's file name, so a failure says where to go.
        public let name: String
        /// Guide ids this walk starts.
        public let guides: [String]
        /// Step ids this walk waits to arrive on.
        public let waitsOn: [String]

        public init(name: String, guides: [String], waitsOn: [String]) {
            self.name = name
            self.guides = guides
            self.waitsOn = waitsOn
        }
    }

    /// Everything wrong with the walks as cover for the catalogue.
    ///
    /// Three things are checked, and each one is a real way this rots:
    /// a guide nobody walks, a walk that stops part way through one, and a walk
    /// still driving a guide that has been renamed or taken out.
    public static func problems(guides: [TutorialGuide] = TutorialCatalog.guides,
                                walks: [Walk]) -> [String] {
        var found: [String] = []
        let known = Set(guides.map(\.id))

        for walk in walks {
            for started in walk.guides where !known.contains(started) {
                found.append("\(walk.name) runs a guide called \(started), which is not in the catalogue")
            }
        }

        for guide in guides {
            let covering = walks.filter { $0.guides.contains(guide.id) }
            guard !covering.isEmpty else {
                found.append("no walk runs \(guide.id), so nothing checks that its steps point at real controls")
                continue
            }
            let waited = Set(covering.flatMap(\.waitsOn))
            let missed = guide.steps.map(\.id).filter { !waited.contains($0) }
            guard !missed.isEmpty else { continue }
            let where_ = covering.map(\.name).sorted().joined(separator: ", ")
            found.append("\(where_) runs \(guide.id) but never waits on "
                + missed.joined(separator: ", ")
                + ", so \(missed.count == 1 ? "that step is" : "those steps are") never checked")
        }
        return found
    }
}

// MARK: - A guide behind a feature flag

/// What the app is expected to do with a guide that teaches a flagged feature,
/// stated as a rule rather than left to a reader.
///
/// A guide for a feature somebody switched off would ring a control that is not
/// there, so it is not offered at all: no dimmed row, no guide that stops half
/// way. That is the promise, and this is where it is checked with each flag
/// both on and off.
public enum TutorialFlagRules {
    /// Everything wrong with how the catalogue answers to flags.
    public static func problems(in guides: [TutorialGuide] = TutorialCatalog.guides) -> [String] {
        var found: [String] = []
        let everything = TutorialCatalog.guides(enabled: { _ in true }, from: guides)
        for guide in guides {
            if !everything.contains(where: { $0.id == guide.id }) {
                found.append("\(guide.id) is not offered even with everything switched on")
            }
            for flag in guide.requires {
                let offered = TutorialCatalog.guides(enabled: { $0 != flag }, from: guides)
                if offered.contains(where: { $0.id == guide.id }) {
                    found.append("\(guide.id) needs \(flag) and is still offered with \(flag) switched off")
                }
                // And the menu has to agree with the catalogue, or a person can
                // reach from a submenu a guide the app just decided not to
                // offer.
                let menu = TutorialMenuModel(guides: offered)
                let inMenu = menu.tracks.flatMap(\.rows).contains { $0.id == guide.id }
                    || menu.tour?.id == guide.id
                if inMenu {
                    found.append("\(guide.id) needs \(flag) and is still in the menu with \(flag) switched off")
                }
                let hub = TutorialHubModel(guides: offered)
                if hub.tracks.flatMap(\.rows).contains(where: { $0.id == guide.id }) {
                    found.append("\(guide.id) needs \(flag) and is still in the Tutorials window "
                        + "with \(flag) switched off")
                }
            }
        }
        return found
    }
}
