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
    /// The timing strip across the bottom of the window: one lap of the
    /// animation, with a bar for every moving part.
    ///
    /// A SURFACE rather than a control, like the canvas, and the one name here
    /// that comes and goes with the DOCUMENT rather than with a sheet: a still
    /// picture has no strip at all. So a guide may only point at it while
    /// something in its own sample is moving, which is why the phase guide
    /// brings a bell that already swings.
    public static let timingStrip = TutorialAnchor("timingStrip")

    /// One tool's button in the floating tool bar. Named off the tool, so the
    /// button's words and its tooltip can change freely.
    public static func tool(_ tool: Tool) -> TutorialAnchor {
        TutorialAnchor("tool.\(tool.rawValue)")
    }

    /// The tool bar slot a whole FAMILY of tools shares: the shapes, the
    /// region selectors. The slot wears whichever member you reached for last,
    /// and a guide cannot know which that is, so a step that means "the shapes
    /// button" names the family rather than one member of it.
    ///
    /// This is not a nicety. On a machine nobody has drawn on yet the shapes
    /// slot wears the LINE, so the Building UI guide's step about the rectangle
    /// was pointing at a button that is not on the bar, for exactly the person
    /// a tutorial is written for. Found on 2026-09-13 by the walk that drives
    /// that guide, once a missing control started failing the walk.
    public static func toolGroup(_ group: ToolGroup) -> TutorialAnchor {
        TutorialAnchor("toolGroup.\(group.rawValue)")
    }

    /// One section of the docked panel: Layers, Effects, Colour. Named off the
    /// section's id rather than its heading, for the same reason.
    public static func panelSection(_ id: String) -> TutorialAnchor {
        TutorialAnchor("panel.\(id)")
    }

    /// One part of a recording's window: the picture itself, or a control on
    /// the floating controller that sits over it. Named off the part rather
    /// than off the icon on it, so swapping a glyph cannot break a guide.
    ///
    /// A recording's window is not the picture editor. It has no tool bar, no
    /// docked panel and no layers, so none of the names above reach anything in
    /// it and these are the only ones a video guide may use.
    public static func video(_ part: VideoPart) -> TutorialAnchor {
        TutorialAnchor("video.\(part.rawValue)")
    }

    /// The parts of a recording's window a guide is allowed to point at.
    ///
    /// Deliberately short. Everything here is somewhere a guide really sends
    /// people, and a name nothing ever points at is a promise the app has to
    /// keep for nothing.
    public enum VideoPart: String, CaseIterable, Codable, Hashable, Sendable {
        /// The recording as you watch it, which is a SURFACE rather than a
        /// control: the card goes inside it.
        case preview
        /// Step back, play, step forward, together.
        case transport
        /// The scissors that open the trim.
        case trim
        /// The clip with a handle at each end, which is only there while the
        /// trim is open.
        case timeline
        /// The button that keeps what is between the handles. Trim mode only.
        case trimDone
        /// Writes the edits into the recording. Only there when there is
        /// something to write.
        case save
        /// Puts the recording on the clipboard, as a video or as a GIF.
        case copy
        /// Writes a file: MP4, GIF or HEIC.
        case export
    }

    /// One row of the card an empty window shows: open a file, capture a
    /// rectangle, paste a picture. Named off the action it performs rather
    /// than off the words on the row, for the same reason as everything else
    /// here. These are the only places in a window where getting a picture IN
    /// is a control rather than a key, which is why a guide can point at them.
    public static func startHere(_ action: String) -> TutorialAnchor {
        TutorialAnchor("start.\(action)")
    }

    /// A sheet the app drops over the window, named by what the sheet is FOR
    /// rather than by anything written on it.
    ///
    /// A sheet is the one thing in the app that is not in the window it belongs
    /// to: it is a window of its own, laid over the middle of the editor. So a
    /// step about a sheet that pointed at the canvas would put its card on top
    /// of the very sheet it is talking about, which is the one thing placement
    /// exists to prevent. Pointing at the sheet itself lands the card beside it.
    ///
    /// The name only answers while the sheet is up, which is why a step may
    /// only use one AFTER a step that waited for the sheet to open.
    public static func dialog(_ dialog: Dialog) -> TutorialAnchor {
        TutorialAnchor("dialog.\(dialog.rawValue)")
    }

    /// The sheets a guide is allowed to point at. Short on purpose: each one is
    /// somewhere a guide really sends people.
    public enum Dialog: String, CaseIterable, Codable, Hashable, Sendable {
        /// The size list Layer \u{25B8} New Frame opens, where the icon sizes live.
        case newFrame
        /// The Export sheet: what to write, where it is going, and as what.
        case export
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
                                            "effects", "color", "canvas", "placement",
                                            // A picked screen's own size and surface, and
                                            // the columns it is designed to. Both are in
                                            // the panel only while a screen is the thing
                                            // selected, which is why the Building UI
                                            // guides pick the screen before they point
                                            // here.
                                            "frame", "columns",
                                            // The Measure tool's own settings, which are
                                            // in the panel only while the tool is in hand,
                                            // and a picked measurement's own section.
                                            "measureTool", "measure",
                                            // A lens's own settings, which are in
                                            // the panel while a lens is picked.
                                            "lens",
                                            // What the picked layer has been told to
                                            // change over time. In the panel for every
                                            // layer you pick, so a guide can point at it
                                            // before anything is moving, which is how the
                                            // first motion ever gets made.
                                            "motion"]

    /// The rows of the empty window's card a guide is allowed to name. The
    /// blank canvas row is deliberately absent: it comes and goes with a
    /// feature flag, and a step pointing at a row that is not always there is
    /// a step that sometimes points at nothing.
    public static let knownStartActions = ["open", "capture", "paste"]

    /// Every anchor the app promises to provide. The catalogue check walks each
    /// guide against this, so a typo or a name nothing hangs on is a test
    /// failure rather than a callout pointing at nothing.
    ///
    /// This is the PROMISE. That the app keeps it in a live window is checked
    /// separately, by a walk that drives the real editor.
    public static var all: [TutorialAnchor] {
        [canvas, toolBar, panel, titleBar, timingStrip]
            + Tool.allCases.map(tool)
            + ToolGroup.allCases.map(toolGroup)
            + knownPanelSections.map(panelSection)
            + knownStartActions.map(startHere)
            + VideoPart.allCases.map(video)
            + Dialog.allCases.map(dialog)
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
    /// The person changed the picture: drew something, moved something, took
    /// something off. One event for the lot, raised where every edit already
    /// funnels through, so a step can wait for "do something" without the
    /// framework growing an event per command.
    case editMade
    /// The person pressed undo, and something came back.
    case undone
    /// The person put the whole picture on the clipboard.
    case pictureCopied
    /// The person asked the Measure tool for this mode, by key, by the button's
    /// flyout or from the panel. Raised whether or not the mode CHANGED: the
    /// event is the person asking, and a tool already in the mode a step names
    /// would otherwise leave them pressing the key a full lap round.
    case measureMode(MeasureToolMode)
    /// The person put the spec list on the clipboard.
    case specListCopied
    /// The person opened the trim on a recording.
    case trimModeOpened
    /// The person moved the handle the kept part starts at.
    case trimStartMoved
    /// The person moved the handle it ends at.
    case trimEndMoved
    /// The person kept what was between the handles.
    case trimApplied
    /// The person put a recording on the clipboard, as a video or as a GIF.
    case recordingCopied
    /// The person switched the canvas grid on, by key, by the View menu or from
    /// the grid's own settings. The lines an icon has to land on are the whole
    /// reason the Icons track asks for them, so it waits for them rather than
    /// hoping.
    case gridShown
    /// The person switched the icon keylines on.
    case keylinesShown
    /// The person opened one of the sheets a guide can point at. It is what
    /// stands between a step and the sheet anchor it names: a card pointed at a
    /// sheet that is not up yet has nothing to point at.
    case dialogOpened(TutorialAnchor.Dialog)
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
    /// Bring the Library shelf on screen AND put it on Components.
    ///
    /// The shelf remembers the scope you left it on, and that is the captures
    /// you have taken until somebody changes it. So `showLibrary` alone rings a
    /// shelf of screenshots for a step that is talking about a button, which is
    /// the "pointing at something that is not there" failure wearing a shelf.
    /// Still reveal only: turning to a shelf is not fetching anything off it,
    /// and the Make Component command already does exactly this for the same
    /// reason.
    case showComponentShelf
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
    /// Drawing an icon: the frame it is really used at, the Pen, reshaping what
    /// you drew, and a clean SVG out the other end.
    case icons
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
        case .icons: "Icons"
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
        case .icons: "Draw an icon at the size it will really be used, and hand it over as an SVG."
        case .video: "Cut a recording down to the part worth watching, and send it on."
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
    /// A window with nothing in it, which is a sample too: it is the only
    /// state that shows the card offering the ways to get a picture in, and a
    /// guide about getting a picture in has to be able to point at them.
    case emptyWindow
    /// A made-up settings screen, FLATTENED into the picture itself the way a
    /// screenshot is. The redlining guides need this: the Measure tool finds
    /// elements and gaps by reading the pixels, and a screen drawn as live
    /// shapes has nothing in its pixels to find.
    case redlineScreen
    /// The same screen with two measurements already on it, so a guide about
    /// the list of them does not open on an empty list.
    case measuredScreen
    /// A made-up account screen with somebody's name and address on it,
    /// FLATTENED the way a screenshot is. The lens guide needs a picture worth
    /// hiding part of, because hiding a name before sending a screenshot on is
    /// why most people reach for a lens at all.
    case accountScreen
    /// The same screen with one solid box already lying over a row of it, so a
    /// guide about how a layer MIXES with what is below has something to mix
    /// without a drawing lesson first.
    case tintedScreen
    /// A made up settings card: three rows, each one a heading, a line under
    /// it and a blue switch. Three headings set exactly alike and three
    /// switches painted exactly alike, and nothing linking any of them.
    ///
    /// The whole Colours and Styles track teaches on this one screen. Three of
    /// each is the smallest number that can show what a name DOES: two wearing
    /// it change together and the third, which never had it, stands still. Two
    /// would only show that an edit happened.
    case stylesScreen
    /// A button drawn as two loose layers, a box and the words on it, and
    /// nothing else on the page. The guide that makes a component out of it
    /// needs it NOT to be one yet, and needs clear page beside it to drag a
    /// selection box from.
    case componentPieces
    /// The same button, already a component, with the page to the right of it
    /// empty. The guide that places copies needs an original to fetch and
    /// somewhere to put what it fetches.
    case componentOriginal
    /// The same original with two copies of it already on the page. The
    /// override guide and the versions guide are both about what a copy owns,
    /// and neither is about placing copies, which the guide before them taught.
    case componentCopies
    /// A page with nothing on it at all. The guide that teaches what a screen
    /// IS has you draw one, so it must not arrive with one already drawn, and
    /// it must not be the empty WINDOW either: that has no canvas to draw on.
    case blankPage
    /// A screen with three cards on it, dropped in by hand at slightly
    /// different spacings. The guide that hands the spacing over to the screen
    /// needs contents that were placed by eye, because the whole lesson is
    /// that you stop doing that.
    case handPlacedScreen
    /// The same screen with its three cards already stacked and pressed hard
    /// against its edges. The padding and columns guide is about the room
    /// inside a screen, so it opens on a screen with none.
    case tightScreen
    /// Three boxes loose on a page, none of them in line and none of them
    /// evenly spaced, with clear page round them to drag a selection from.
    case crookedBoxes

    /// A page with one empty icon frame on it, 24 points square, and the view
    /// already up close on it. Every guide in the Icons track after the first
    /// one opens on this frame or on a drawing inside it, so the track reads as
    /// one icon being made rather than five unrelated exercises.
    ///
    /// The first guide has you MAKE the frame, so it does not bring one.
    case iconFrame
    /// The same frame with a bookmark drawn in it: five hard corners, every
    /// point on a crossing of the four point grid. The guide about reshaping
    /// needs corners to bend, and the guide about exporting needs something
    /// worth exporting.
    case iconPath
    /// The same frame with a rounded box in it rather than a drawn path. The
    /// guide about turning a shape into a path needs a shape that is NOT one
    /// yet, and the rounding is the point: the curves you get out of it are the
    /// ones you can then pull on.
    case iconBox

    /// A bell on the same frame, drawn in two parts: the body, and the clapper
    /// hanging under it. Nothing moves.
    ///
    /// The bell is the drawing the whole animating half of the track teaches
    /// on, and it was chosen rather than a checkmark or a spinner because it is
    /// the one everyday icon whose motion is WRONG in the obvious way. A bell
    /// swings about the point it hangs from; turn it about its own middle,
    /// which is the answer a fresh rotation starts on, and it rocks like a
    /// bobblehead. And it is two parts, so the difference between something
    /// that moves and something that feels alive has somewhere to show itself.
    case iconBell
    /// The same bell with its body already swinging, about the point it hangs
    /// from. The guide about timing is about tuning a motion that already
    /// exists, so it must not open by making one.
    case iconBellSwinging
    /// The same bell with BOTH parts swinging, in perfect step, both starting
    /// at the top of the lap. This is the thing that looks wrong, and it is
    /// what the guide about phase opens on: two parts of one drawing moving in
    /// lockstep read as one stamped shape being waved.
    case iconBellInStep
    /// The finished bell: the clapper arrives after the body. What the guide
    /// about handing an animated icon over has to have in front of it.
    case iconBellRinging

    /// A short recording, written to disk before the window opens.
    ///
    /// The one sample that is not a drawing. The video guides teach in a
    /// recording's window, which holds media rather than layers, so there is
    /// nothing here for a layer list to hold and nothing for the renderer to
    /// flatten. What it IS lives in the app, beside the code that can write an
    /// MP4; all this says is that the guide brings one.
    ///
    /// It is made with dead air at each end on purpose, so trimming it has a
    /// visible point rather than being a gesture practised on nothing.
    case sampleRecording

    /// Whether this sample is a recording rather than a picture. A recording
    /// opens in the video window, so the two go different ways from the moment
    /// a guide is started.
    public var isVideo: Bool { self == .sampleRecording }

    /// Whether this sample's drawing is baked into the picture before the
    /// window opens. A guide that measures needs this; a guide about layers
    /// needs the opposite.
    ///
    /// Every component sample is live. A component is made out of layers, and
    /// pixels are not layers: flatten one of these and the guide has nothing to
    /// group, promote or place.
    public var isFlattened: Bool {
        switch self {
        case .redlineScreen, .measuredScreen, .accountScreen, .tintedScreen: true
        case .starterScreen, .emptyWindow: false
        // A recording has no layers to flatten and no canvas to flatten them
        // into. The question does not apply, and false is the answer that keeps
        // the picture path away from it.
        case .sampleRecording: false
        case .componentPieces, .componentOriginal, .componentCopies: false
        // Every Building UI sample is live for the same reason the component
        // ones are: a screen is made of layers, and you cannot group, stack,
        // pad or align pixels.
        case .blankPage, .handPlacedScreen, .tightScreen, .crookedBoxes: false
        // A colour you can give a name to is a colour on a LAYER. Flatten this
        // one and every guide in the styles track has nothing to pick.
        case .stylesScreen: false
        // An icon is shapes, and shapes are the whole point of it: flatten one
        // and there is nothing to reshape and nothing to write into an SVG.
        case .iconFrame, .iconPath, .iconBox: false
        // And a bell that swings is still shapes. Flatten it and there is
        // nothing left to tell to move.
        case .iconBell, .iconBellSwinging, .iconBellInStep, .iconBellRinging: false
        }
    }
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
    /// The features this guide needs switched on, by flag name. A guide for
    /// something somebody has switched off in Experiments is a guide pointing
    /// at a control that is not there, so the app leaves it out of the menu and
    /// out of the window entirely. Empty means it teaches something everybody
    /// has.
    public let requires: [String]
    public let steps: [TutorialStep]

    public init(id: String, track: TutorialTrack, title: String, summary: String,
                minutes: Int, sample: TutorialSample?, requires: [String] = [],
                steps: [TutorialStep]) {
        self.id = id
        self.track = track
        self.title = title
        self.summary = summary
        self.minutes = minutes
        self.sample = sample
        self.requires = requires
        self.steps = steps
    }

    public func step(id: String) -> TutorialStep? { steps.first { $0.id == id } }
}

// MARK: - How long one really takes

/// How long a guide takes, worked out from what is in it rather than guessed.
///
/// The number on the card is a promise, and a guide that says two minutes and
/// takes five is one nobody starts again. So the claim is checked against the
/// work: the words to read, a beat per step to find the ringed control and
/// press the button, and longer again for a step that waits on you really doing
/// something.
///
/// The rates are deliberately plain and a little generous. They are not a
/// stopwatch, they are a floor under the claim, and what they catch is a guide
/// that grew three steps and kept saying two minutes.
public enum TutorialLength {
    /// Careful reading of short UI copy, in words per second.
    public static let wordsPerSecond: Double = 3.3
    /// Finding the ring, reading what it points at, pressing the button.
    public static let secondsPerStep: Double = 6
    /// Extra for a step that waits: picking a tool, drawing something, copying.
    public static let secondsPerAction: Double = 8

    public static func estimatedSeconds(for guide: TutorialGuide) -> Double {
        let words = guide.steps.reduce(0) { total, step in
            total + step.title.split(separator: " ").count + step.body.split(separator: " ").count
        }
        let waits = guide.steps.filter(\.waits).count
        return Double(words) / wordsPerSecond
            + Double(guide.steps.count) * secondsPerStep
            + Double(waits) * secondsPerAction
    }

    /// How far the claim on the card is from the work in the guide, in seconds.
    /// Positive means the card is promising more time than the guide needs.
    public static func claimError(for guide: TutorialGuide) -> Double {
        Double(guide.minutes) * 60 - estimatedSeconds(for: guide)
    }

    /// Whether the card's claim is honest: within a minute of the work, either
    /// way. A whole minute of slack, because the claim is in whole minutes and
    /// people read at different speeds. What this catches is the claim that is
    /// out by a factor: two minutes of steps under a one minute promise.
    public static func claimIsHonest(for guide: TutorialGuide) -> Bool {
        abs(claimError(for: guide)) <= 60
    }
}

// MARK: - The catalogue

/// Every guide the app ships. The menu, the hub window and the progress list
/// read this and nothing else, so a new tutorial is a new value here.
public enum TutorialCatalog {
    public static let guides: [TutorialGuide] = [
        TutorialGuides.takeTheTour,
        TutorialGuides.firstCapture,
        TutorialGuides.markItUp,
        TutorialGuides.layersAndUndo,
        TutorialGuides.saveExportCopy,
        TutorialGuides.measureAGap,
        TutorialGuides.measureASize,
        TutorialGuides.snapOrFree,
        TutorialGuides.measurementsPanel,
        TutorialGuides.exportASpecList,
        TutorialGuides.whatAShapeIsMadeOf,
        TutorialGuides.addAShadowABorderAGlow,
        TutorialGuides.blurWhatIsUnderneath,
        TutorialGuides.mixWithWhatIsBelow,
        TutorialGuides.makeAComponent,
        TutorialGuides.useItAgainAndAgain,
        TutorialGuides.overrideOneCopy,
        TutorialGuides.componentVersions,
        TutorialGuides.saveAColourAsAStyle,
        TutorialGuides.changeItEverywhere,
        TutorialGuides.textStyles,
        TutorialGuides.theLibrary,
        TutorialGuides.framesAreScreens,
        TutorialGuides.letAScreenArrangeItself,
        TutorialGuides.paddingAndColumns,
        TutorialGuides.lineThingsUp,
        TutorialGuides.startOnAnIconFrame,
        TutorialGuides.drawItWithThePen,
        TutorialGuides.reshapeWhatYouDrew,
        TutorialGuides.turnAShapeIntoAPath,
        TutorialGuides.getACleanSVGOut,
        TutorialGuides.makeSomethingMove,
        TutorialGuides.getTheTimingRight,
        TutorialGuides.twoPartsOutOfPhase,
        TutorialGuides.exportAnAnimatedSVG,
        TutorialGuides.trimARecording,
        TutorialGuides.exportARecording,
    ]

    /// The guide the Help menu's own row runs, and the one first launch offers.
    public static let tourID = TutorialGuides.takeTheTour.id

    public static func guide(id: String) -> TutorialGuide? {
        guides.first { $0.id == id }
    }

    /// The guides on one track, in catalogue order.
    public static func guides(in track: TutorialTrack) -> [TutorialGuide] {
        guides.filter { $0.track == track }
    }

    /// The guides worth offering to somebody whose app is switched on the way
    /// `isEnabled` says. A guide teaching a feature that is off would point at
    /// a control that is not there, so it is not offered at all: no dimmed row
    /// explaining a setting, no guide that stops halfway.
    ///
    /// The app passes its own feature flags in. Everything else about the
    /// catalogue is release independent, which is why this is the only place
    /// that has to ask.
    ///
    /// `from` is the list to narrow, which is the shipping catalogue unless a
    /// test hands it a made up one.
    public static func guides(enabled isEnabled: (String) -> Bool,
                              from list: [TutorialGuide] = TutorialCatalog.guides) -> [TutorialGuide] {
        list.filter { $0.requires.allSatisfy(isEnabled) }
    }

    /// The tracks that actually have something on them, in track order. What
    /// the menu builds its submenus from, so an empty track shows no empty
    /// submenu.
    public static var populatedTracks: [TutorialTrack] {
        populatedTracks(in: guides)
    }

    /// The same question asked of a narrowed list: a track whose every guide
    /// needs a feature somebody switched off is not a shelf, it is an empty
    /// submenu, so it goes too.
    public static func populatedTracks(in guides: [TutorialGuide]) -> [TutorialTrack] {
        TutorialTrack.allCases.filter { track in guides.contains { $0.track == track } }
    }
}

// MARK: - Running one

/// Where a person is in a guide. A value: the controller holds one, the tests
/// drive one, and nothing about it knows what a window is.
public struct TutorialRun: Hashable, Sendable {
    public let guide: TutorialGuide
    public private(set) var index: Int
    /// True when this step asks for something that was ALREADY so when it came
    /// up: the tool is already in the mode the step names, say. The step still
    /// says what it says, but the way on is a plain Next, because there is
    /// nothing left to do and "Skip This Step" would be asking somebody to
    /// skip a step they have already finished.
    ///
    /// Only ever set for a trigger that describes a STATE. Nothing can be
    /// already true about "the person made an edit".
    public private(set) var stepWasAlreadyTrue = false

    public init(guide: TutorialGuide, startingAt index: Int = 0) {
        self.guide = guide
        self.index = min(max(0, index), max(0, guide.steps.count - 1))
    }

    /// Said once, as the step comes up.
    public mutating func markStepAlreadyTrue() { stepWasAlreadyTrue = true }

    public var step: TutorialStep { guide.steps[index] }
    public var number: Int { index + 1 }
    public var count: Int { guide.steps.count }
    public var canGoBack: Bool { index > 0 }
    public var isLastStep: Bool { index >= guide.steps.count - 1 }

    /// What the one button on the callout says. A waiting step never shows
    /// Next, because Next would be a way to claim you did something you did
    /// not; it offers to skip the step instead, so nobody is ever stuck.
    public var buttonTitle: String {
        if step.waits && !stepWasAlreadyTrue { return "Skip This Step" }
        return isLastStep ? "Done" : "Next"
    }

    /// Move on. Returns false when the guide is finished, which is the
    /// controller's cue to close and mark it done.
    @discardableResult
    public mutating func advance() -> Bool {
        guard !isLastStep else { return false }
        index += 1
        stepWasAlreadyTrue = false
        return true
    }

    @discardableResult
    public mutating func back() -> Bool {
        guard canGoBack else { return false }
        index -= 1
        stepWasAlreadyTrue = false
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
