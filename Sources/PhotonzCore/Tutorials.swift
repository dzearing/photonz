import CoreGraphics
import Foundation

// A guide is DATA. Nothing in this file draws anything, and nothing in the app
// knows the name of any particular guide: the menu, the overlay and the
// progress list all read the catalogue below. Adding a tutorial is adding a
// value to `TutorialCatalog.guides`, which is the whole point of the framework.
//
// The three pieces, in the order they matter:
//
//  * `TutorialAnchor` — the NAME of a place in the app a step can point at.
//    Names come off the model (a `Tool`'s raw value, a panel section's id),
//    never off the words on the control, so rewording a label cannot break a
//    guide. Same idea as the playtest harness's steady names, deliberately not
//    the same code: that registry is compiled out of the shipping build and
//    tutorials ship to people.
//  * `TutorialStep` — one anchor, one short thing to say, which side the
//    callout sits on, and how the person moves on.
//  * `TutorialGuide` — a track, a title, how long it takes, the sample
//    document it opens for itself, and its ordered steps.
//
// Placement of the callout is its own file (`TutorialCallout.swift`) because it
// is pure geometry with its own tests.

// MARK: - Anchors

/// The name of a place in the app a tutorial step can point at.
///
/// A name is structural: `tool.measure` is built from `Tool.measure.rawValue`,
/// `panel.layers` from the panel section's id. Renaming the Measure button's
/// words leaves the anchor alone; deleting the tool breaks the build at the
/// call site that built the name, which is exactly where it should break.
///
/// The app hangs these on real controls (`View.tutorialAnchor(_:)`) and the
/// overlay asks the registry where one is on screen right now.
public struct TutorialAnchor: Hashable, Codable, Sendable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) { self.name = name }

    public var description: String { name }

    // MARK: The places, by name

    /// The picture you are working on.
    public static let canvas = TutorialAnchor("canvas")
    /// The floating tool bar as a whole.
    public static let toolBar = TutorialAnchor("toolBar")
    /// The docked panel on the right, as a whole.
    public static let panel = TutorialAnchor("panel")
    /// The window's title bar.
    public static let titleBar = TutorialAnchor("titleBar")

    /// One tool's button in the floating tool bar. Named off the tool, so the
    /// button's words and its tooltip can change freely.
    public static func tool(_ tool: Tool) -> TutorialAnchor {
        TutorialAnchor("tool.\(tool.rawValue)")
    }

    /// One section of the docked panel: Layers, Effects, Colour. Named off the
    /// section's id rather than its heading, for the same reason.
    public static func panelSection(_ id: String) -> TutorialAnchor {
        TutorialAnchor("panel.\(id)")
    }

    /// The panel section this anchor names, or nil when it names something
    /// else. What the app reads to scroll a step's target into view.
    public var panelSectionID: String? {
        let prefix = "panel."
        guard name.hasPrefix(prefix) else { return nil }
        return String(name.dropFirst(prefix.count))
    }

    /// The panel sections a guide is allowed to name. Kept here rather than
    /// read off the app so the catalogue check is a plain unit test: a guide
    /// pointing at a section nobody promised fails before anybody sees it.
    public static let knownPanelSections = ["layers", "geometry", "arrange", "annotation",
                                            "text", "measurements", "library", "component",
                                            "effects", "color", "canvas", "placement"]

    /// Every anchor the app promises to provide. The catalogue check walks each
    /// guide against this, so a typo or a name nothing hangs on is a test
    /// failure rather than a callout pointing at nothing.
    ///
    /// This is the PROMISE. That the app keeps it in a live window is checked
    /// separately, by a walk that drives the real editor.
    public static var all: [TutorialAnchor] {
        [canvas, toolBar, panel, titleBar]
            + Tool.allCases.map(tool)
            + knownPanelSections.map(panelSection)
    }
}

// MARK: - Steps

/// Which side of the control the callout sits on. `automatic` lets the
/// placement pick the side with room, which is the right answer for most
/// steps; a fixed side is for a control whose own picture is above or below it
/// and would be covered.
public enum TutorialSide: String, Codable, Hashable, Sendable, CaseIterable {
    case above, below, leading, trailing, automatic
}

/// Something a person really did, which a waiting step listens for.
///
/// Every case here is wired to a real editor event. Nothing advances on a
/// timer: a step that says "pick the Measure tool" and moves on by itself five
/// seconds later is a lie, and the person notices. When a guide needs to wait
/// for something with no event yet, the event gets added here and wired at the
/// place it actually happens, or the step uses `.next` and says so.
public enum TutorialTrigger: Hashable, Codable, Sendable {
    /// The person picked this tool, by button, key or menu.
    case toolPicked(Tool)
    /// The person selected a layer, on the canvas or in the list.
    case layerSelected
    /// The docked panel came on screen.
    case panelShown
}

/// How a step moves on.
public enum TutorialAdvance: Hashable, Codable, Sendable {
    /// A Next button. For a step that is showing you something.
    case next
    /// The step waits for the person to do the thing, and moves on by itself
    /// when they do. The button reads "Skip this step" meanwhile, so nobody is
    /// ever stuck on a step they cannot perform.
    case waitsFor(TutorialTrigger)

    public var trigger: TutorialTrigger? {
        if case .waitsFor(let trigger) = self { return trigger }
        return nil
    }
}

/// Something a step does to MAKE ITS TARGET VISIBLE before pointing at it.
///
/// The rule, and it is the whole reason this is a closed list: a prepare action
/// may only reveal. It may never do the thing the step is asking the person to
/// do. Showing the panel so a step can point at the Layers list is fine;
/// picking the Measure tool for a step that says "pick the Measure tool" is the
/// timer lie in another costume.
public enum TutorialPrep: String, Hashable, Codable, Sendable, CaseIterable {
    /// Bring the docked panel on screen if it is hidden.
    case showPanel
    /// Bring the Library shelf on screen if it is hidden.
    case showLibrary
    /// Scroll this step's own target into view. The docked panel is routinely
    /// taller than the window, so a step pointing at a section near the top can
    /// find it scrolled away by whatever the person did last. Still reveal
    /// only: it moves the panel, never the person's work.
    case revealTarget
}

/// One step of a guide.
public struct TutorialStep: Identifiable, Hashable, Codable, Sendable {
    /// Stable within its guide. Used for progress and for naming a step in a
    /// failure, so it reads like a step and not like an index.
    public let id: String
    /// The control this step points at.
    public let anchor: TutorialAnchor
    /// The one line heading of the callout.
    public let title: String
    /// One or two short sentences. Product copy: plain words, no dashes
    /// standing in for punctuation, nothing about how the app was built.
    public let body: String
    public let side: TutorialSide
    public let advance: TutorialAdvance
    /// What has to be on screen for the anchor to exist. Reveal only.
    public let prepare: [TutorialPrep]

    public init(id: String, anchor: TutorialAnchor, title: String, body: String,
                side: TutorialSide = .automatic,
                advance: TutorialAdvance = .next,
                prepare: [TutorialPrep] = []) {
        self.id = id
        self.anchor = anchor
        self.title = title
        self.body = body
        self.side = side
        self.advance = advance
        self.prepare = prepare
    }

    /// True while this step is waiting on the person rather than on a button.
    public var waits: Bool { advance.trigger != nil }
}

// MARK: - Tracks

/// The shelf a guide sits on. Tracks are what keep the tutorials from becoming
/// one long list: Help shows the tracks, and a track shows its guides.
public enum TutorialTrack: String, CaseIterable, Codable, Hashable, Sendable {
    case basics
    case redlining
    case looks
    case colorsAndStyles
    case buildingUI
    case components
    case video

    /// What the menu and the hub window call this track.
    public var title: String {
        switch self {
        case .basics: "Basics"
        case .redlining: "Redlining"
        case .looks: "Looks"
        case .colorsAndStyles: "Colours and Styles"
        case .buildingUI: "Building UI"
        case .components: "Components"
        case .video: "Video"
        }
    }

    /// One line under the track's name, for the hub window.
    public var blurb: String {
        switch self {
        case .basics: "Find your way around, open something, and put your first layer down."
        case .redlining: "Measure a screenshot and hand off a spec somebody can build from."
        case .looks: "Shadows, blurs, borders and the rest of what makes a picture look finished."
        case .colorsAndStyles: "Save a colour once and use it everywhere, then change it in one place."
        case .buildingUI: "Frames, grids and layout that behave like real screens."
        case .components: "Build a piece once, reuse it, and override just the bits that differ."
        case .video: "Trim a recording, add a title, and share it."
        }
    }

    /// The order the tracks are shown in, everywhere.
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Guides

/// The document a guide opens for itself so it never depends on what the person
/// happens to have open, and never edits their work.
public enum TutorialSample: String, Codable, Hashable, Sendable {
    /// A small made-up screen: a card, a heading and a button on a white
    /// canvas. Enough to have layers to select and properties to show.
    case starterScreen
}

public struct TutorialGuide: Identifiable, Hashable, Codable, Sendable {
    /// Stable for ever: progress is filed under it.
    public let id: String
    public let track: TutorialTrack
    public let title: String
    /// One line, plain. Shown in the menu's help tag and in the hub window.
    public let summary: String
    /// Roughly how long it takes, in minutes. Shown so nobody starts something
    /// they have not got time for.
    public let minutes: Int
    /// The document this guide opens for itself, or nil when it teaches
    /// something about whatever you already have open. A guide with no sample
    /// must not change the document without saying so in a step first.
    public let sample: TutorialSample?
    public let steps: [TutorialStep]

    public init(id: String, track: TutorialTrack, title: String, summary: String,
                minutes: Int, sample: TutorialSample?, steps: [TutorialStep]) {
        self.id = id
        self.track = track
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.sample = sample
        self.steps = steps
    }

    public func step(id: String) -> TutorialStep? { steps.first { $0.id == id } }
}

// MARK: - The catalogue

/// Every guide the app ships. The menu, the hub window and the progress list
/// read this and nothing else, so a new tutorial is a new value here.
public enum TutorialCatalog {
    public static let guides: [TutorialGuide] = [TutorialGuides.takeTheTour]

    /// The guide the Help menu's own row runs, and the one first launch offers.
    public static let tourID = TutorialGuides.takeTheTour.id

    public static func guide(id: String) -> TutorialGuide? {
        guides.first { $0.id == id }
    }

    /// The guides on one track, in catalogue order.
    public static func guides(in track: TutorialTrack) -> [TutorialGuide] {
        guides.filter { $0.track == track }
    }

    /// The tracks that actually have something on them, in track order. What
    /// the menu builds its submenus from, so an empty track shows no empty
    /// submenu.
    public static var populatedTracks: [TutorialTrack] {
        TutorialTrack.allCases.filter { !guides(in: $0).isEmpty }
    }
}

// MARK: - Running one

/// Where a person is in a guide. A value: the controller holds one, the tests
/// drive one, and nothing about it knows what a window is.
public struct TutorialRun: Hashable, Sendable {
    public let guide: TutorialGuide
    public private(set) var index: Int

    public init(guide: TutorialGuide, startingAt index: Int = 0) {
        self.guide = guide
        self.index = min(max(0, index), max(0, guide.steps.count - 1))
    }

    public var step: TutorialStep { guide.steps[index] }
    public var number: Int { index + 1 }
    public var count: Int { guide.steps.count }
    public var canGoBack: Bool { index > 0 }
    public var isLastStep: Bool { index >= guide.steps.count - 1 }

    /// What the one button on the callout says. A waiting step never shows
    /// Next, because Next would be a way to claim you did something you did
    /// not; it offers to skip the step instead, so nobody is ever stuck.
    public var buttonTitle: String {
        if step.waits { return "Skip This Step" }
        return isLastStep ? "Done" : "Next"
    }

    /// Move on. Returns false when the guide is finished, which is the
    /// controller's cue to close and mark it done.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLastStep else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        guard canGoBack else { return false }
        index -= 1
        return true
    }

    /// Something happened in the editor. Returns true when it is the thing this
    /// step was waiting for, so the caller advances.
    public func isSatisfied(by event: TutorialTrigger) -> Bool {
        step.advance.trigger == event
    }
}

// MARK: - Progress

/// What the app remembers about guides between launches: which ones are
/// finished, and where you stopped in one you left part way. Quitting mid guide
/// loses nothing because this is written on every step.
public struct TutorialProgress: Codable, Hashable, Sendable {
    /// Guide ids finished at least once.
    public private(set) var completed: Set<String>
    /// Guide id to the step index the person was on when they stopped.
    public private(set) var inFlight: [String: Int]

    public init(completed: Set<String> = [], inFlight: [String: Int] = [:]) {
        self.completed = completed
        self.inFlight = inFlight
    }

    public func isCompleted(_ guideID: String) -> Bool { completed.contains(guideID) }

    /// The step a guide should open on: where you left off, or the start.
    public func startIndex(for guide: TutorialGuide) -> Int {
        guard let saved = inFlight[guide.id] else { return 0 }
        return min(max(0, saved), max(0, guide.steps.count - 1))
    }

    /// True when starting this guide would resume rather than begin.
    public func isResumable(_ guide: TutorialGuide) -> Bool {
        guard let saved = inFlight[guide.id] else { return false }
        return saved > 0 && saved < guide.steps.count
    }

    public mutating func record(guide: String, step: Int) {
        inFlight[guide] = step
    }

    public mutating func complete(_ guide: String) {
        completed.insert(guide)
        inFlight[guide] = nil
    }

    /// Closing a guide part way keeps the place. Starting it over forgets it.
    public mutating func restart(_ guide: String) {
        inFlight[guide] = nil
    }

    /// True when nothing has been finished and nothing is part way: there is
    /// nothing to reset, so the window does not offer to.
    public var isEmpty: Bool { completed.isEmpty && inFlight.isEmpty }

    /// Forget one guide completely: its tick and its saved place both go, and
    /// it reads as something you have never run. Every other guide is left
    /// alone.
    public mutating func forget(_ guide: String) {
        completed.remove(guide)
        inFlight[guide] = nil
    }

    /// Forget the lot. What the window's Reset All does.
    public mutating func forgetAll() {
        completed.removeAll()
        inFlight.removeAll()
    }
}

// MARK: - The copy rules, as a check

/// The repo's copy rules applied to tutorial copy, so a guide whose words break
/// them fails a test rather than shipping.
public enum TutorialCopyRules {
    /// Words that give away the tooling rather than talking about the product.
    static let forbiddenWords = ["claude", "anthropic", "agent loop", "llm", "prompt engineering"]

    /// Every complaint about one piece of copy. Empty means it passes.
    public static func problems(in text: String, label: String) -> [String] {
        var found: [String] = []
        if text.contains("—") || text.contains("–") {
            found.append("\(label) uses a dash where punctuation belongs")
        }
        let lower = text.lowercased()
        for word in forbiddenWords where lower.contains(word) {
            found.append("\(label) mentions \(word)")
        }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            found.append("\(label) is empty")
        }
        // Short plain sentences. A tutorial step read off a small card stops
        // being read at about this length.
        if text.count > 180 {
            found.append("\(label) is \(text.count) characters, which is too long to read off a callout")
        }
        return found
    }

    /// Everything wrong with one guide's words.
    public static func problems(in guide: TutorialGuide) -> [String] {
        var found = problems(in: guide.title, label: "\(guide.id) title")
        found += problems(in: guide.summary, label: "\(guide.id) summary")
        for step in guide.steps {
            found += problems(in: step.title, label: "\(guide.id)/\(step.id) title")
            found += problems(in: step.body, label: "\(guide.id)/\(step.id) body")
        }
        return found
    }
}

// MARK: - The catalogue check

/// Walks every guide and reports what would fail a person at run time: an
/// anchor nobody promises, two steps sharing an id, a guide with no steps.
public enum TutorialCatalogCheck {
    public static func problems(in guides: [TutorialGuide] = TutorialCatalog.guides) -> [String] {
        var found: [String] = []
        let promised = Set(TutorialAnchor.all)
        var seenGuideIDs: Set<String> = []
        for guide in guides {
            if !seenGuideIDs.insert(guide.id).inserted {
                found.append("two guides share the id \(guide.id)")
            }
            if guide.steps.isEmpty {
                found.append("\(guide.id) has no steps")
            }
            if guide.minutes <= 0 {
                found.append("\(guide.id) does not say how long it takes")
            }
            var seenStepIDs: Set<String> = []
            for step in guide.steps {
                if !seenStepIDs.insert(step.id).inserted {
                    found.append("\(guide.id) has two steps called \(step.id)")
                }
                if !promised.contains(step.anchor) {
                    found.append("\(guide.id) step \(step.id) points at \(step.anchor.name), which nothing in the app promises")
                }
            }
            found += TutorialCopyRules.problems(in: guide)
        }
        return found
    }
}
