import CoreGraphics
import Foundation

// The guides themselves. Data only: every line here is read by the overlay,
// the menu and the hub window, and none of them know what any of it says.
//
// Adding a tutorial is adding a value in this file and listing it in
// `TutorialCatalog.guides`. Nothing else changes. If a guide needs something
// the framework cannot do yet, that is a change to the framework, not a new
// one off surface.
//
// The copy rules apply to every word below, and a test enforces them: short
// plain sentences, no dashes standing in for punctuation, nothing about how the
// app was built.
public enum TutorialGuides {

    /// The one guide the framework is proved with. Six steps, two of them
    /// waiting on something the person actually does.
    public static let takeTheTour = TutorialGuide(
        id: "take-the-tour",
        track: .basics,
        title: "Take the Tour",
        summary: "A quick lap of the window: the tool bar, the panel, and how the two agree.",
        minutes: 2,
        sample: .starterScreen,
        steps: [
            TutorialStep(
                id: "tool-bar",
                anchor: .toolBar,
                title: "The tool bar",
                body: "Everything you draw with lives here. It floats over the picture and stays with the window.",
                side: .above),
            TutorialStep(
                id: "pick-measure",
                anchor: .tool(.measure),
                title: "Pick the Measure tool",
                body: "Click it, or press I. Measure is how you get sizes and gaps off a screenshot.",
                side: .above,
                advance: .waitsFor(.toolPicked(.measure))),
            TutorialStep(
                id: "layers-list",
                anchor: .panelSection("layers"),
                title: "Everything is a layer",
                body: "The panel on the right lists what the picture is made of, with the front of the picture at the top.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-a-layer",
                anchor: .panelSection("layers"),
                title: "Pick a layer",
                body: "Click any row in the list. The canvas and the panel always agree about what is selected.",
                side: .leading,
                advance: .waitsFor(.layerSelected),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "properties",
                anchor: .panelSection("geometry"),
                title: "Its settings show up here",
                body: "Position and size for whatever you picked, with the rest of its settings under them. Change one and the picture changes as you go.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "back-to-select",
                anchor: .tool(.select),
                title: "That is the tour",
                body: "Press V any time to get your pointer back. There are more guides under Help whenever you want them.",
                side: .above),
        ])

    // MARK: - Basics

    /// The three ways a picture gets into Photonz. It opens an EMPTY window on
    /// purpose: the card offering those three ways only exists with nothing
    /// open, and they are the only places in a window where getting a picture
    /// in is a control rather than a key.
    ///
    /// Nothing here waits. A real capture opens a window of its own and would
    /// leave the guide behind in this one, so the guide teaches the key and
    /// lets the person use it when they are ready.
    public static let firstCapture = TutorialGuide(
        id: "first-capture",
        track: .basics,
        title: "Your first capture",
        summary: "The three ways to get a picture in, and which one to reach for.",
        minutes: 1,
        sample: .emptyWindow,
        steps: [
            TutorialStep(
                id: "grab-the-screen",
                anchor: .startHere("capture"),
                title: "Grab part of your screen",
                body: "Press \u{21E7}\u{2318}4 and drag a box round anything on screen. It works from any app, even with no Photonz window open."),
            TutorialStep(
                id: "open-a-file",
                anchor: .startHere("open"),
                title: "Or open one you already have",
                body: "\u{2318}O opens a picture from your disk. Dropping a file onto this window does the same thing."),
            TutorialStep(
                id: "paste-one-in",
                anchor: .startHere("paste"),
                title: "Or paste one in",
                body: "\u{2318}V brings in whatever picture you copied last, from anywhere."),
            TutorialStep(
                id: "where-it-lands",
                anchor: .canvas,
                title: "It lands in a window like this",
                body: "Ready to mark up, measure and send on. Take your first one whenever you like."),
        ])

    /// Draw an arrow, say what it is, and put the result on the clipboard. The
    /// whole daily job of the app in five steps, four of which wait for the
    /// person to really do the thing.
    public static let markItUp = TutorialGuide(
        id: "mark-it-up",
        track: .basics,
        title: "Mark it up and hand it over",
        summary: "Point at something, say what it is, and hand the picture to somebody else.",
        minutes: 2,
        sample: .starterScreen,
        steps: [
            TutorialStep(
                id: "pick-arrow",
                anchor: .tool(.arrow),
                title: "Pick the arrow",
                body: "Click it, or press A. An arrow is the fastest way to point at the thing you are talking about.",
                side: .above,
                advance: .waitsFor(.toolPicked(.arrow))),
            TutorialStep(
                id: "draw-arrow",
                anchor: .canvas,
                title: "Drag one out",
                body: "Start where the arrow should begin and let go on the thing it points at.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "pick-text",
                anchor: .tool(.text),
                title: "Now say what it is",
                body: "Press T, or click the text tool.",
                side: .above,
                advance: .waitsFor(.toolPicked(.text))),
            TutorialStep(
                id: "type-something",
                anchor: .canvas,
                title: "Click and type",
                body: "Click beside the arrow and type a few words. Press \u{2318}Return when you are done.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "copy-it",
                anchor: .canvas,
                title: "Hand it over",
                body: "Press \u{21E7}\u{2318}C. The whole picture goes on the clipboard, ready to paste into a message.",
                advance: .waitsFor(.pictureCopied)),
            TutorialStep(
                id: "back-to-pointer",
                anchor: .tool(.select),
                title: "That is the handoff",
                body: "Press V to get your pointer back. Everything you added is still a layer, so you can move it or take it off later.",
                side: .above),
        ])

    /// The most valuable guide in the app: what the picture is made of, and
    /// why nothing you do to it is permanent. It has to land that a look is
    /// added rather than painted on, and that undo covers the lot, without
    /// saying either of those things in those words.
    public static let layersAndUndo = TutorialGuide(
        id: "layers-and-undo",
        track: .basics,
        title: "Everything is a layer, and undo always works",
        summary: "What the picture is made of, and why nothing you do to it is permanent.",
        minutes: 2,
        sample: .starterScreen,
        steps: [
            TutorialStep(
                id: "the-stack",
                anchor: .panelSection("layers"),
                title: "The picture is a stack",
                body: "Every piece of it is its own layer, with the front of the picture at the top of the list.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-one",
                anchor: .panelSection("layers"),
                title: "Pick the heading",
                body: "Click its row. The canvas and the list always agree about what is picked.",
                side: .leading,
                advance: .waitsFor(.layerSelected),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "a-look-is-added",
                anchor: .panelSection("effects"),
                title: "A look is added, not painted on",
                body: "Effects gives a layer a look it did not have, like a blur or softer corners. Take it off again and the layer is exactly as it was.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "take-it-off",
                anchor: .canvas,
                title: "Take the heading off",
                body: "Press \u{2318}\u{232B}. It goes, and nothing else in the picture moves.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "put-it-back",
                anchor: .canvas,
                title: "Change your mind",
                body: "Press \u{2318}Z. Undo steps back through everything you have done in this window, one press at a time.",
                advance: .waitsFor(.undone)),
            TutorialStep(
                id: "nothing-is-stuck",
                anchor: .panelSection("layers"),
                title: "Nothing here is stuck",
                body: "Any layer can be moved, restyled or taken off later, and the picture you started with is never painted over.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// The three ways a picture leaves, and which one keeps your layers. It
    /// ends on the layers list rather than on the canvas, because keeping that
    /// list is the thing saving actually claims.
    public static let saveExportCopy = TutorialGuide(
        id: "save-export-copy",
        track: .basics,
        title: "Save it, export it, copy it",
        summary: "The three ways a picture leaves Photonz, and which one keeps your layers.",
        minutes: 1,
        sample: .starterScreen,
        steps: [
            TutorialStep(
                id: "three-ways-out",
                anchor: .canvas,
                title: "Three ways out",
                body: "Which one you want depends on where it is going: into a message, off as a file, or back to you tomorrow."),
            TutorialStep(
                id: "copy-it",
                anchor: .canvas,
                title: "Into a message",
                body: "Press \u{21E7}\u{2318}C. The whole picture goes on the clipboard, ready to paste wherever you are talking.",
                advance: .waitsFor(.pictureCopied)),
            TutorialStep(
                id: "export-it",
                anchor: .canvas,
                title: "Off as a file",
                body: "\u{21E7}\u{2318}E writes a PNG or a JPEG of what you can see. That is the one for somebody who does not have Photonz."),
            TutorialStep(
                id: "save-it",
                anchor: .panelSection("layers"),
                title: "Back to you tomorrow",
                body: "\u{2318}S keeps this list. Every layer stays separate, so you can come back and change one word of it.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    // MARK: - Redlining
    //
    // The app's real daily job: read a screen, say how big things are and how
    // far apart, and hand somebody a list they can build from. Five guides, in
    // the order the job is done in.
    //
    // Every one of them brings a FLATTENED screen (`TutorialSample.isFlattened`)
    // rather than the starter drawing the Basics track uses. The Measure tool
    // finds elements and gaps by reading the picture's pixels, and a screen made
    // of live shapes has nothing in its pixels to find: Size and Gap would draw
    // nothing at all under the pointer and every guide here would stall on its
    // first click.
    //
    // Each one also names the feature it needs (`requires`). Measure's modes and
    // its panel are features somebody can switch off, and a guide that points at
    // a mode which is not there is worse than no guide.

    /// The first real redlining move: how far apart are these two things. It
    /// spends its first two steps getting the tool into Gap mode, because that
    /// is the step a first-timer cannot guess: the modes live behind the tool's
    /// own button and nothing on the bar says to press the key twice.
    public static let measureAGap = TutorialGuide(
        id: "measure-a-gap",
        track: .redlining,
        title: "Measure a gap",
        summary: "How far apart two things are, in one click.",
        minutes: 2,
        sample: .redlineScreen,
        requires: [FeatureCatalog.measureModesFlag],
        steps: [
            TutorialStep(
                id: "pick-measure",
                anchor: .tool(.measure),
                title: "Pick up the Measure tool",
                body: "Click it, or press I. This is the tool that reads sizes and spaces off a picture.",
                side: .above,
                advance: .waitsFor(.toolPicked(.measure))),
            TutorialStep(
                id: "switch-to-gap",
                anchor: .tool(.measure),
                title: "Ask it for gaps",
                body: "Press I again until the button reads Gap. Holding the button down lists all its modes too.",
                side: .above,
                advance: .waitsFor(.measureMode(.gap))),
            TutorialStep(
                id: "rest-on-the-space",
                anchor: .canvas,
                title: "Rest on the space between the buttons",
                body: "The space between Cancel and Save lights up with the number it would leave behind. Nothing is placed yet."),
            TutorialStep(
                id: "click-the-gap",
                anchor: .canvas,
                title: "Click to keep it",
                body: "One click leaves the measurement on the picture, number and all.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "it-is-a-layer",
                anchor: .canvas,
                title: "It is a layer like any other",
                body: "Press V to get your pointer back and drag it somewhere better, or press \u{2318}Z to take it off. Nothing was painted onto the picture."),
        ])

    /// How big is this. Size is the mode people reach for most and the one with
    /// a key nobody finds on their own, so the guide spends a whole step on
    /// `[` and `]`.
    public static let measureASize = TutorialGuide(
        id: "measure-a-size",
        track: .redlining,
        title: "Measure something's size",
        summary: "Width and height of the thing under your pointer, in one click.",
        minutes: 2,
        sample: .redlineScreen,
        requires: [FeatureCatalog.measureModesFlag],
        steps: [
            TutorialStep(
                id: "pick-measure",
                anchor: .tool(.measure),
                title: "Pick up the Measure tool",
                body: "Click it, or press I.",
                side: .above,
                advance: .waitsFor(.toolPicked(.measure))),
            TutorialStep(
                id: "switch-to-size",
                anchor: .tool(.measure),
                title: "Ask it for sizes",
                body: "Press I again until the button reads Size. Holding the button down lists all its modes too.",
                side: .above,
                advance: .waitsFor(.measureMode(.size))),
            TutorialStep(
                id: "rest-on-the-button",
                anchor: .canvas,
                title: "Rest on the Save button",
                body: "It is outlined with the width and the height a click would leave behind."),
            TutorialStep(
                id: "take-in-more",
                anchor: .canvas,
                title: "Take in more, or less",
                body: "Press ] to grow the pick out to the box around it, and [ to come back in. Use it when it grabs the label instead of the button."),
            TutorialStep(
                id: "click-to-keep",
                anchor: .canvas,
                title: "Click once for both",
                body: "Width and height land together in one go.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "both-are-yours",
                anchor: .canvas,
                title: "Both numbers are yours now",
                body: "Drag either number somewhere clearer, or press \u{2318}Z once to take the pair of them back off."),
        ])

    /// The guide that stops people mistrusting their numbers. A caliper you
    /// draw by hand catches on edges it can see, and the two keys that govern
    /// that are the difference between a measurement that is right and one that
    /// is two pixels short.
    public static let snapOrFree = TutorialGuide(
        id: "snap-or-free",
        track: .redlining,
        title: "Let it snap, or drag it free",
        summary: "Draw a measurement yourself, and control where its ends land.",
        minutes: 2,
        sample: .redlineScreen,
        // The Snap setting it ends on is the centers flag's, and the mode it
        // starts in is the modes flag's. Neither step has a true version with
        // its feature off, so the guide waits for both.
        requires: [FeatureCatalog.measureModesFlag, FeatureCatalog.measureCenterSnapFlag],
        steps: [
            TutorialStep(
                id: "pick-measure",
                anchor: .tool(.measure),
                title: "Pick up the Measure tool",
                body: "Click it, or press I.",
                side: .above,
                advance: .waitsFor(.toolPicked(.measure))),
            TutorialStep(
                id: "back-to-distance",
                anchor: .tool(.measure),
                title: "Ask it for distances",
                body: "Press I until the button reads Distance. This is the mode where you draw the measurement yourself.",
                side: .above,
                advance: .waitsFor(.measureMode(.distance))),
            // Before the drawing, not after it. Placing a caliper hands you the
            // pointer back, and the Measure Tool section is only in the panel
            // while the tool is in hand: at the end of the guide this step
            // pointed at nothing and the card fell to the middle of the window.
            // Caught by the walk on 2026-09-13.
            TutorialStep(
                id: "what-it-snaps-to",
                anchor: .panelSection("measureTool"),
                title: "What the ends catch on",
                body: "Measure Tool in the panel says whether they catch on edges only, or on middles too.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "draw-one",
                anchor: .canvas,
                title: "Draw across the card",
                body: "Click once where it starts, once where it ends, then once more to park the number. The ends jump to edges they can see.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "free-it",
                anchor: .canvas,
                title: "When you want it somewhere else",
                body: "Hold \u{2318} while you drag an end and the magnets let go, so it lands exactly where your pointer is."),
            TutorialStep(
                id: "hold-the-line",
                anchor: .canvas,
                title: "When it keeps drifting",
                body: "Hold \u{21E7} while you drag an end and it stays on the line it is measuring along. Those two keys are the whole of it."),
        ])

    /// Everything measured, in one place. The sample arrives with three
    /// measurements already on it: a guide about a list that opens on an empty
    /// list teaches nothing.
    public static let measurementsPanel = TutorialGuide(
        id: "measurements-panel",
        track: .redlining,
        title: "The Measurements panel",
        summary: "Everything you have measured in one list, named the way you want it.",
        minutes: 2,
        sample: .measuredScreen,
        requires: [FeatureCatalog.measurePanelFlag],
        steps: [
            TutorialStep(
                id: "the-list",
                anchor: .panelSection("measurements"),
                title: "Everything you measured",
                body: "Measurements collects them all, newest at the top, each with its own colour and its number beside it.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-a-row",
                anchor: .panelSection("measurements"),
                title: "Click a row",
                body: "The caliper on the picture lights up with it. One thing picked, in both places.",
                side: .leading,
                advance: .waitsFor(.layerSelected),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "name-it",
                anchor: .panelSection("measurements"),
                title: "Give it a name",
                body: "Double click the name and type what it really is. A row called Button gap says more than one called Gap.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "hide-one",
                anchor: .panelSection("measurements"),
                title: "Put one away for a moment",
                body: "The eye on a row takes that measurement off the picture without losing it.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "tidy-list-tidy-spec",
                anchor: .panelSection("measurements"),
                title: "This list is the handoff",
                body: "Whatever is showing here is what gets handed to somebody else, in this order, with these names.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// The end of the job: the numbers as words somebody can paste into a
    /// ticket. Two steps wait on a real copy, so nobody finishes this guide
    /// without the thing actually being on their clipboard.
    public static let exportASpecList = TutorialGuide(
        id: "export-a-spec-list",
        track: .redlining,
        title: "Export a spec list",
        summary: "Hand your measurements to somebody else as text they can build from.",
        minutes: 2,
        sample: .measuredScreen,
        requires: [FeatureCatalog.measurePanelFlag],
        steps: [
            TutorialStep(
                id: "what-it-is",
                anchor: .panelSection("measurements"),
                title: "The list, as words",
                body: "A spec list is one line per measurement: what it is, how big, and whether it is a size or a space.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "copy-the-list",
                anchor: .canvas,
                title: "Copy it",
                body: "Press \u{2303}\u{2318}C. Every measurement showing on the picture goes on your clipboard as text.",
                advance: .waitsFor(.specListCopied)),
            TutorialStep(
                id: "paste-it",
                anchor: .canvas,
                title: "Paste it somewhere",
                body: "Try a message or a ticket. It arrives as plain lines, so it reads the same wherever it lands."),
            TutorialStep(
                id: "both-at-once",
                anchor: .canvas,
                title: "Or hand over both at once",
                body: "Press \u{21E7}\u{2318}C. Somewhere that takes pictures you get the marked up picture, somewhere that takes words you get the list.",
                advance: .waitsFor(.pictureCopied)),
            TutorialStep(
                id: "just-one",
                anchor: .panelSection("measurements"),
                title: "Or just one of them",
                body: "Pick a row and press \u{2318}C to copy that single line on its own.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])
}

// MARK: - The sample a guide opens for itself

/// The little made up screen a guide opens so it never has to touch what you
/// already have open. Pure layer data: the app puts a white canvas under it and
/// installs the result as a brand new untitled document.
public enum TutorialSampleScreen {
    /// The canvas the starter screen is drawn on.
    public static let canvasSize = CGSize(width: 720, height: 480)

    /// What a tutorial window is called in its title bar, so it is obvious this
    /// is not your work.
    public static let documentName = "Tutorial Sample"

    private static let ink = "#1F2430"
    private static let quiet = "#6B7280"
    private static let line = "#DCE0E8"
    private static let accent = "#3B7CFF"

    /// The page colour a sample's canvas starts as, under everything else.
    public static func backgroundHex(for sample: TutorialSample) -> String {
        switch sample {
        // A screen sits on something. A white card on a white page has no
        // outer edge to find, and the redlining guides are entirely about
        // edges being findable.
        case .redlineScreen, .measuredScreen: "#EDF0F5"
        case .starterScreen, .emptyWindow: "#FFFFFF"
        }
    }

    /// The part of a sample that is the PICTURE: drawn once, flattened into the
    /// canvas, and from then on made of pixels exactly like a screenshot
    /// somebody took. Empty for a sample that is not flattened, where the
    /// drawing stays live and comes back from `layers(for:)` instead.
    ///
    /// The redlining track depends on this. Measure finds elements and gaps by
    /// reading the picture, so a screen made of live shapes gives it nothing to
    /// find.
    public static func pictureLayers(for sample: TutorialSample) -> [Layer] {
        switch sample {
        case .redlineScreen, .measuredScreen: settingsScreen()
        case .starterScreen, .emptyWindow: []
        }
    }

    /// Back of the picture first, the way a document stores its layers. The
    /// panel turns that round and shows the front at the top.
    ///
    /// For a flattened sample this is what stays LIVE on top of the picture,
    /// which is nothing at all for a plain screen and the measurements for a
    /// screen that arrives already measured.
    public static func layers(for sample: TutorialSample) -> [Layer] {
        switch sample {
        case .starterScreen: starterScreen()
        // A window with nothing in it. The app puts no canvas under this one
        // either, so the window opens on its onboarding card, which is the
        // whole point of it.
        case .emptyWindow: []
        // A screenshot with nothing on it yet: everything it is made of went
        // into the picture.
        case .redlineScreen: []
        case .measuredScreen: sampleMeasurements()
        }
    }

    private static func starterScreen() -> [Layer] {
        [
            box("Card", CGRect(x: 96, y: 112, width: 528, height: 272),
                radius: 16, fill: "#FFFFFF", stroke: line),
            label("Heading", "Weekly report", at: CGPoint(x: 128, y: 152),
                  size: 30, color: ink, weight: .bold),
            label("Subheading", "Everything in this picture is a layer.",
                  at: CGPoint(x: 128, y: 200), size: 15, color: quiet, weight: .regular),
            box("Button", CGRect(x: 128, y: 310, width: 150, height: 40),
                radius: 10, fill: accent, stroke: nil),
            label("Button Label", "Get started", at: CGPoint(x: 150, y: 322),
                  size: 15, color: "#FFFFFF", weight: .semibold),
        ]
    }

    // MARK: The redlining screen

    /// A made up settings pane, drawn the way a real one is: a card on a page,
    /// a heading, two rows with switches, and two buttons side by side. It is
    /// flattened into the picture before the window opens.
    ///
    /// Every number here is chosen to be worth measuring and easy to say out
    /// loud in a step. The two buttons are 24 apart, the Save button is 104
    /// wide and 38 tall, and the two switch rows are 24 apart as well, so a
    /// guide can name what the reader should be seeing.
    private static func settingsScreen() -> [Layer] {
        [
            box("Card", cardFrame, radius: 14, fill: "#FFFFFF", stroke: "#D7DDE8"),
            label("Title", "Notifications", at: CGPoint(x: 104, y: 96),
                  size: 22, color: ink, weight: .bold),
            label("Subtitle", "Choose what you hear about.", at: CGPoint(x: 104, y: 134),
                  size: 14, color: quiet, weight: .regular),
            box("Divider", CGRect(x: 104, y: 172, width: 512, height: 1),
                radius: 0, fill: "#E4E8F0", stroke: nil),
            label("Sound Label", "Play sound", at: CGPoint(x: 104, y: 202),
                  size: 15, color: ink, weight: .regular),
            box("Sound Switch", CGRect(x: 568, y: 198, width: 48, height: 28),
                radius: 14, fill: accent, stroke: nil),
            label("Previews Label", "Show previews", at: CGPoint(x: 104, y: 254),
                  size: 15, color: ink, weight: .regular),
            box("Previews Switch", CGRect(x: 568, y: 250, width: 48, height: 28),
                radius: 14, fill: "#C6CDDA", stroke: nil),
            box("Cancel Button", cancelFrame, radius: 8, fill: "#FFFFFF", stroke: "#C2C9D6"),
            label("Cancel Label", "Cancel", at: CGPoint(x: 133, y: 354),
                  size: 14, color: ink, weight: .medium),
            box("Save Button", saveFrame, radius: 8, fill: accent, stroke: nil),
            label("Save Label", "Save", at: CGPoint(x: 268, y: 354),
                  size: 14, color: "#FFFFFF", weight: .medium),
        ]
    }

    /// The card everything sits on.
    static let cardFrame = CGRect(x: 72, y: 64, width: 576, height: 352)
    /// The two buttons at the bottom of the card, 24 apart.
    static let cancelFrame = CGRect(x: 104, y: 344, width: 104, height: 38)
    static let saveFrame = CGRect(x: 232, y: 344, width: 104, height: 38)

    /// Three measurements already on the picture, so a guide about the LIST of
    /// them opens on a list with something in it. Back of the picture first,
    /// like every other layer list, so the gap ends up at the top of the panel.
    ///
    /// They are exactly what the tool would have left behind: the gap between
    /// the two buttons, and the Save button's width and height.
    private static func sampleMeasurements() -> [Layer] {
        let spacing = MeasureRoleColors.spacingDefault
        let size = MeasureRoleColors.sizeDefault
        return [
            measurement(from: CGPoint(x: saveFrame.minX, y: saveFrame.maxY + 30),
                        to: CGPoint(x: saveFrame.maxX, y: saveFrame.maxY + 30),
                        mode: .horizontal, role: .size, colors: size, headOffset: 18),
            measurement(from: CGPoint(x: saveFrame.maxX + 34, y: saveFrame.minY),
                        to: CGPoint(x: saveFrame.maxX + 34, y: saveFrame.maxY),
                        mode: .vertical, role: .size, colors: size, headOffset: 18),
            measurement(from: CGPoint(x: cancelFrame.maxX, y: cancelFrame.midY),
                        to: CGPoint(x: saveFrame.minX, y: cancelFrame.midY),
                        mode: .horizontal, role: .spacing, colors: spacing, headOffset: -46),
        ]
    }

    private static func measurement(from start: CGPoint, to end: CGPoint,
                                    mode: MeasureMode, role: MeasureRole,
                                    colors: MeasureRoleColors, headOffset: CGFloat) -> Layer {
        let content = MeasureContent(headOffset: headOffset,
                                     mode: mode,
                                     strokeWidth: 2,
                                     strokeColorHex: colors.strokeColorHex,
                                     chipColorHex: colors.chipColorHex,
                                     textColorHex: colors.textColorHex,
                                     unit: .points,
                                     role: role)
        return MeasureBuilder.layer(content: content, from: start, to: end)
    }

    private static func box(_ name: String, _ frame: CGRect, radius: CGFloat,
                            fill: String, stroke: String?) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle,
                                           start: .zero,
                                           end: CGPoint(x: frame.width, y: frame.height))
        annotation.cornerRadius = radius
        annotation.fillColorHex = fill
        annotation.strokeWidth = stroke == nil ? 0 : 1
        annotation.colorHex = stroke ?? line
        return Layer(name: name, content: .annotation(annotation), frame: frame)
    }

    private static func label(_ name: String, _ string: String, at origin: CGPoint,
                              size: CGFloat, color: String, weight: TextWeight) -> Layer {
        let content = TextContent(string: string, fontSize: size, colorHex: color, weight: weight)
        let measured = TextMeasurement.size(of: content, wrappingAt: 420)
        return Layer(name: name, content: .text(content),
                     frame: CGRect(origin: origin, size: measured))
    }
}
