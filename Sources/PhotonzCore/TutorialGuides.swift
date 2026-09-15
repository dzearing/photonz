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

    // MARK: - Looks

    /// The split the whole panel turns on, taught on one shape: Appearance is
    /// what a layer simply IS, Effects is the list you added to. Get this
    /// across and the rest of the panel explains itself.
    ///
    /// It teaches on a shape the sample brought, rather than asking anybody to
    /// draw one: the shapes share one slot in the tool bar and the slot wears
    /// whichever member you used last, so a step pointing at the rectangle
    /// points at nothing on an app whose slot is wearing the line.
    public static let whatAShapeIsMadeOf = TutorialGuide(
        id: "what-a-shape-is-made-of",
        track: .looks,
        title: "What a shape is made of",
        summary: "Appearance is what a shape is. Effects is the list you add to.",
        minutes: 2,
        sample: .starterScreen,
        requires: [FeatureCatalog.shapePartsFlag],
        steps: [
            TutorialStep(
                id: "pick-the-card",
                anchor: .canvas,
                title: "Pick the white card",
                body: "Click it on the picture, anywhere clear of the words. The panel on the right fills up with what that one layer is made of.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "appearance",
                anchor: .panelSection("color"),
                title: "Appearance is what it is",
                body: "How solid it is, how it mixes with what is under it, and the colour it is filled with. Every shape has these, so they are always here.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "paint-it",
                anchor: .panelSection("color"),
                title: "Change its fill",
                body: "Click the colour beside Fill and pick another one. The card changes while you choose.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "effects",
                anchor: .panelSection("effects"),
                title: "Effects is what you add",
                body: "The line round this card is a border, and a border is something you added. The plus on the heading adds more.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "which-is-which",
                anchor: .panel,
                title: "That is the whole split",
                body: "If the shape simply has it, it is in Appearance. If you added it, it is in Effects and you can take it off again.",
                side: .leading,
                prepare: [.showPanel]),
        ])

    /// The list you add to, used for real: two things added, the edge named
    /// where it actually lives now, and the two facts about the list that are
    /// not obvious (the top paints nearest you, and the tool remembers).
    public static let addAShadowABorderAGlow = TutorialGuide(
        id: "add-a-shadow-a-border-a-glow",
        track: .looks,
        title: "Add a shadow, a border, a glow",
        summary: "Effects is a list. Add what you want, in the order you want it.",
        minutes: 2,
        sample: .starterScreen,
        requires: [FeatureCatalog.shapePartsFlag],
        steps: [
            TutorialStep(
                id: "pick-the-button",
                anchor: .canvas,
                title: "Pick the blue button",
                body: "Click it on the picture. Whatever you add lands on the layer you have picked.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "the-plus",
                anchor: .panelSection("effects"),
                title: "The plus adds one",
                body: "It rides the Effects heading, and it offers a shadow, a glow, a border and a blur.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "add-a-shadow",
                anchor: .panelSection("effects"),
                title: "Add a shadow",
                body: "It arrives looking like one already, with its own settings on the lines under it.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "add-a-glow",
                anchor: .panelSection("effects"),
                title: "Now add a glow",
                body: "The same plus, one row lower. Both sit in the list together, each keeping its own colour and settings.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "add-a-border",
                anchor: .panelSection("effects"),
                title: "And a border",
                body: "The line a shape is drawn with is one of these as well, so this row is how you change that line or take it off.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "order-and-memory",
                anchor: .panelSection("effects"),
                title: "Order counts, and it sticks",
                body: "The top of the list paints nearest you, and a row drags. The next shape you draw comes out wearing what you left this one in.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// The reason most people will ever want a lens: an address in a screenshot
    /// they are about to send on. It brings a screen with one in it, and it is
    /// straight about what really leaves the app.
    public static let blurWhatIsUnderneath = TutorialGuide(
        id: "blur-what-is-underneath",
        track: .looks,
        title: "Blur or pixelate what is underneath",
        summary: "Hide an address or a name before you send a screenshot on.",
        minutes: 2,
        sample: .accountScreen,
        requires: [FeatureCatalog.lensFlag],
        steps: [
            TutorialStep(
                id: "the-picture",
                anchor: .canvas,
                title: "Somebody's address, in a screenshot",
                body: "A lens is a layer that changes what is under it. Nothing beneath it is touched, so you can move it or take it off later."),
            TutorialStep(
                id: "pick-the-lens",
                anchor: .tool(.lens),
                title: "Pick up the lens",
                body: "Press K, or click it in the tool bar.",
                side: .above,
                advance: .waitsFor(.toolPicked(.lens))),
            TutorialStep(
                id: "drag-over-it",
                anchor: .canvas,
                title: "Drag a box across the address",
                body: "Start at one end of it and let go at the other. Everything under the box goes soft.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "how-hard",
                anchor: .panelSection("lens"),
                title: "How hard it does it",
                body: "Lens in the panel says what it does and how much. Pull Strength up until the address cannot be read at all.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pixelate",
                anchor: .panelSection("lens"),
                title: "Or blocks instead",
                body: "Set Does to Pixelate. Blocks read as hidden on purpose, which is why people reach for them over a name.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "what-leaves-the-app",
                anchor: .canvas,
                title: "What leaves the app",
                body: "Exporting and copying flatten the picture, so the hidden part really is gone from what you send. Your saved document keeps the original."),
        ])

    /// The other way a layer reaches what is below it: not changing it, mixing
    /// with it. One setting, five choices, and a sample that arrives with a
    /// solid box already lying over a row so the whole lesson is the change.
    public static let mixWithWhatIsBelow = TutorialGuide(
        id: "mix-with-what-is-below",
        track: .looks,
        title: "Mix a layer with what is below it",
        summary: "One setting turns a solid box into a highlighter.",
        minutes: 2,
        sample: .tintedScreen,
        requires: [FeatureCatalog.shapePartsFlag, FeatureCatalog.blendModeFlag],
        steps: [
            TutorialStep(
                id: "pick-the-box",
                anchor: .canvas,
                title: "Pick the yellow box",
                body: "It lies across the address and hides it. That is what a layer does until you tell it otherwise.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "where-it-lives",
                anchor: .panelSection("color"),
                title: "Blending, under Opacity",
                body: "Opacity says how much of what is below shows through. Blending says how the two colours meet.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "multiply",
                anchor: .panelSection("color"),
                title: "Choose Multiply",
                body: "Open Blending and choose Multiply. The colour burns into the row and the words come back through it, the way a highlighter pen works.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "screen",
                anchor: .panelSection("color"),
                title: "Now try Screen",
                body: "Open it again and choose Screen. The same box lightens what is under it instead of darkening it.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "each-one-says-what-it-does",
                anchor: .panelSection("color"),
                title: "Every choice says what it does",
                body: "There is a plain sentence beside each one, so you can pick the one you want without trying all five.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    // MARK: - Components
    //
    // Build a piece of UI once, fetch it as often as you like, and change one
    // copy without cutting it loose. Four guides in the order the job is done
    // in: make one, use it, override one, and hold two looks under one name.
    //
    // The hard idea, and the reason the last two guides exist at all, is what a
    // copy OWNS. A copy's contents are not its own: they are refilled from the
    // original after every edit, and the few things somebody set on the copy
    // are written back over the top. Everything the track teaches falls out of
    // that one sentence, and nothing on screen ever says it, so the guides do.

    /// The first rung: something you drew becomes something you can fetch.
    ///
    /// It teaches the order, because the order is the part that stops people:
    /// Make Component is dead until the pieces are one group, so a person who
    /// reaches for it on two selected shapes finds a row that does nothing and
    /// no reason why.
    public static let makeAComponent = TutorialGuide(
        id: "make-a-component",
        track: .components,
        title: "Make a component",
        summary: "Turn something you drew into something you can fetch again and again.",
        minutes: 2,
        sample: .componentPieces,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.libraryFlag,
                   FeatureCatalog.componentsFlag],
        steps: [
            TutorialStep(
                id: "two-loose-layers",
                anchor: .canvas,
                title: "A button, drawn as two layers",
                body: "A box and the words on it. Right now it is a drawing. A component is a drawing you can fetch off a shelf whenever you want another one."),
            TutorialStep(
                id: "pick-both",
                anchor: .canvas,
                title: "Pick them both",
                body: "Start on the clear page beside the button and drag a box round it. Both layers get picked.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "group-them",
                anchor: .canvas,
                title: "Make them one thing",
                body: "Press \u{2318}G. The box and its words have to travel together before they can be reused together.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "promote",
                anchor: .canvas,
                title: "Now make it a component",
                body: "Press \u{2325}\u{2318}K. Nothing moves. The group picks up four violet diamonds, which is how the original is marked from here on.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "name-it",
                anchor: .panelSection("component"),
                title: "Name it",
                body: "The Name box is waiting with the name selected, so just type. Call it Save Button and press Return.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "on-the-shelf",
                anchor: .panelSection("library"),
                title: "There it is on the shelf",
                body: "The Library opened itself on Components, where your button now sits beside the ones the app came with. Fetching one is the next guide.",
                side: .leading,
                prepare: [.showPanel, .showComponentShelf, .revealTarget]),
        ])

    /// The other half of the bargain: the shelf hands things back, and one edit
    /// to the original reaches every copy of it.
    ///
    /// It reaches inside the original through the LAYERS LIST rather than by
    /// double clicking the canvas. A double click's first click already selects
    /// the group, which raises the event a waiting step is listening for, so
    /// the card moves on before the person has got inside anything.
    public static let useItAgainAndAgain = TutorialGuide(
        id: "use-it-again-and-again",
        track: .components,
        title: "Use it again and again",
        summary: "Fetch copies off the shelf, then change every one of them from one place.",
        minutes: 2,
        sample: .componentOriginal,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.libraryFlag,
                   FeatureCatalog.componentsFlag],
        steps: [
            TutorialStep(
                id: "the-shelf",
                anchor: .panelSection("library"),
                title: "Your button is on the shelf",
                body: "Save Button sits on Components beside the ones the app came with. The drawing on the page wearing four diamonds is the original.",
                side: .leading,
                prepare: [.showPanel, .showComponentShelf, .revealTarget]),
            TutorialStep(
                id: "place-one",
                anchor: .panelSection("library"),
                title: "Put a copy on the page",
                body: "Double click the Save Button tile. A copy lands wearing one diamond instead of four, which is how a copy is marked.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .showComponentShelf, .revealTarget]),
            TutorialStep(
                id: "place-another",
                anchor: .panelSection("library"),
                title: "And another",
                body: "Double click it again, or drag the tile onto the page to choose where it lands.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .showComponentShelf, .revealTarget]),
            TutorialStep(
                id: "pick-the-original",
                anchor: .canvas,
                title: "Now go to the original",
                body: "Click the drawing wearing four diamonds. It is an ordinary group, sitting where you left it.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "change-it-once",
                anchor: .panelSection("color"),
                title: "Change it once",
                body: "Double click its box, clear of the words, to reach the shape itself. Then give it another colour here. Every copy repaints with it.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "one-place",
                anchor: .canvas,
                title: "That is the whole point",
                body: "Copies stay in step with the original wherever they are. Twenty buttons on twenty screens, changed in one place."),
        ])

    /// The part everybody gets wrong: a copy cannot simply be edited, and the
    /// way in is a PROPERTY the ORIGINAL offers.
    ///
    /// The order of the steps is the model. The original decides which
    /// properties it has, because the decision applies to every copy at once;
    /// the copy answers, and its answer survives the next edit to the original
    /// because it is written back over the top after the refill.
    public static let overrideOneCopy = TutorialGuide(
        id: "override-one-copy",
        track: .components,
        title: "Override one copy",
        summary: "Let one copy say something of its own without cutting it loose.",
        minutes: 2,
        sample: .componentCopies,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.libraryFlag,
                   FeatureCatalog.componentsFlag],
        steps: [
            TutorialStep(
                id: "pick-the-original",
                anchor: .canvas,
                title: "The original decides",
                body: "What is inside a copy belongs to the original, so the original says which parts a copy may set. Click the drawing wearing four diamonds.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "add-a-knob",
                anchor: .panelSection("component"),
                title: "Give it a Wording property",
                body: "Under Properties, open Add and pick the Label's Wording. Every copy gets that one property and nothing else.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-a-copy",
                anchor: .canvas,
                title: "Now pick one copy",
                body: "Click the copy just under it, the one wearing a single diamond.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "give-it-its-own-words",
                anchor: .panelSection("component"),
                title: "Give it its own words",
                body: "Type new words into the Label box. This copy alone changes, and the one below it carries on following the original.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "still-a-copy",
                anchor: .canvas,
                title: "It is still a copy",
                body: "Only the words it was given are its own. Everything else about it is still refilled from the original every time you edit one."),
            TutorialStep(
                id: "the-way-back",
                anchor: .panelSection("component"),
                title: "There is always a way back",
                body: "The arrow beside the property puts this copy back on the original's words. Nothing is ever stuck.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// A component holds more than one drawing of itself, and a copy picks
    /// which one it shows.
    ///
    /// The looks are the options of the component's VARIANT property, which is
    /// one row of its Properties list (`ComponentVariantProperty`). The guide
    /// keeps its id, because an id is what a saved place in a track points at,
    /// and nobody reads it.
    public static let componentVersions = TutorialGuide(
        id: "component-versions",
        track: .components,
        title: "One name, two looks",
        summary: "A button needs a disabled look too. Both live under one component.",
        minutes: 3,
        sample: .componentCopies,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.libraryFlag,
                   FeatureCatalog.componentsFlag],
        steps: [
            TutorialStep(
                id: "pick-the-original",
                anchor: .canvas,
                title: "One button, two looks",
                body: "A button needs a switched off look as well. Keeping both under one name stops the two drifting apart. Click the original to start.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "add-a-version",
                anchor: .panelSection("component"),
                title: "Add a second drawing",
                body: "Under Properties, open Add and pick A second look. A copy of this drawing lands beside it on clear page, and it is an ordinary drawing you can edit.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "name-it",
                anchor: .panelSection("component"),
                title: "Name it",
                body: "Its name is waiting to be typed over. Call it Disabled and press Return.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "grey-it-out",
                anchor: .panelSection("color"),
                title: "Make it look switched off",
                body: "Double click the new drawing's box, clear of the words. Give it a grey here. The drawing you started with is untouched.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-a-copy",
                anchor: .canvas,
                title: "Now pick a copy",
                body: "Click one of the copies on the page.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "switch-it",
                anchor: .panelSection("component"),
                title: "Switch it to Disabled",
                body: "Variant is the top row of a copy's properties. Choose Disabled and this copy redraws. The other one carries on as it was.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "under-one-name",
                anchor: .panelSection("library"),
                title: "One tile, two looks",
                body: "The shelf still holds one component. Every copy of it says which drawing it is showing, and you can change that any time.",
                side: .leading,
                prepare: [.showPanel, .showComponentShelf, .revealTarget]),
        ])

    // MARK: - Colours and Styles
    //
    // Name a colour or a piece of type once, use the name wherever you like,
    // and change it in one place. Four guides: make a name, change the name
    // and watch everything wearing it move, the same bargain for type, and the
    // shelf all of it lands on.
    //
    // The payoff is the second guide's last step, and it needs the switch that
    // never had the name. Two switches repainting together says an edit reached
    // two layers; only the third one standing still says why.

    /// The first rung: a colour stops being a colour and becomes a name.
    ///
    /// It ends on the row rather than on the picture, because the thing that
    /// changed is not what the switch looks like, it is what the switch is
    /// FOLLOWING, and the only place that shows is the row.
    public static let saveAColourAsAStyle = TutorialGuide(
        id: "save-a-colour-as-a-style",
        track: .colorsAndStyles,
        title: "Save a colour as a style",
        summary: "Give a colour a name, so everything painted with it can be changed at once.",
        minutes: 2,
        sample: .stylesScreen,
        requires: [FeatureCatalog.libraryFlag, FeatureCatalog.stylesFlag],
        steps: [
            TutorialStep(
                id: "the-same-blue-three-times",
                anchor: .canvas,
                title: "The same blue, three times",
                body: "The three switches on this card are painted the same blue, and nothing links them. Changing that blue today means changing three layers."),
            TutorialStep(
                id: "pick-a-switch",
                anchor: .canvas,
                title: "Pick the first switch",
                body: "Click the blue switch beside Notifications.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "save-it",
                anchor: .panelSection("color"),
                title: "Give the colour a name",
                body: "The Fill row ends in a small button. Open it, choose Save as Style, type Brand and press Return.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "on-the-shelf",
                anchor: .panelSection("library"),
                title: "There it is",
                body: "The Library turned to Styles by itself, and Brand is the tile that just landed. Every colour you save under a name turns up here.",
                side: .leading,
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                id: "the-row-says-so",
                anchor: .panelSection("color"),
                title: "The row says its name now",
                body: "The end of the Fill row reads Brand now, beside a small palette mark. That is how a row that follows a name is told from one with a colour of its own.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "that-is-a-style",
                anchor: .canvas,
                title: "That is a style",
                body: "A colour with a name on it. Next you put that name on more than one thing and change all of them at once."),
        ])

    /// The payoff, and the reason anybody bothers naming a colour.
    ///
    /// The last step is the whole guide: two switches move together and the
    /// third does not. Without the one that stays put, a person sees an edit
    /// that happened to reach two layers rather than two layers that follow a
    /// name.
    public static let changeItEverywhere = TutorialGuide(
        id: "change-it-everywhere",
        track: .colorsAndStyles,
        title: "Change it everywhere",
        summary: "Put one name on several layers, then change the name once and watch them all move.",
        minutes: 2,
        sample: .stylesScreen,
        requires: [FeatureCatalog.libraryFlag, FeatureCatalog.stylesFlag],
        steps: [
            TutorialStep(
                id: "one-name-two-switches",
                anchor: .canvas,
                title: "One name on two of them",
                body: "Three switches again. You are going to put one name on two of them, leave the third alone, and then change the name."),
            TutorialStep(
                id: "pick-two",
                anchor: .panelSection("layers"),
                title: "Pick two of them",
                body: "In this list click Notifications Switch, then hold Shift and click Privacy Switch. Two layers are picked.",
                side: .leading,
                advance: .waitsFor(.layerSelected),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "save-for-both",
                anchor: .panelSection("color"),
                title: "Save what they share",
                body: "Open the button at the end of the Fill row. It offers to save for both. Choose it, type Brand and press Return.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "both-wear-it",
                anchor: .panelSection("library"),
                title: "Both wear it now",
                body: "Brand is on the Styles shelf and both switches follow it. The third switch is still its own colour, which is the point of leaving it.",
                side: .leading,
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                id: "change-the-name",
                anchor: .panelSection("library"),
                title: "Change the colour once",
                body: "Click the Brand tile. Its settings open under the shelf. Press the swatch there and pick a different colour.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                id: "two-moved-one-did-not",
                anchor: .canvas,
                title: "Two moved, one did not",
                body: "Both switches on Brand repainted together. The third never had the name, so it stayed as it was. That is the whole of what a style does."),
        ])

    /// The same bargain for type, and the guide that teaches the fast way to
    /// put a style on something.
    ///
    /// A saved text style can be carried out of the Library and let go on the
    /// words themselves, which is the route people actually use once they know
    /// it is there. It needs the dragging switch, so the guide asks for it.
    public static let textStyles = TutorialGuide(
        id: "text-styles",
        track: .colorsAndStyles,
        title: "Text styles",
        summary: "Keep a font, a size and a weight under one name, and set any words to it.",
        minutes: 2,
        sample: .stylesScreen,
        requires: [FeatureCatalog.libraryFlag, FeatureCatalog.stylesFlag,
                   FeatureCatalog.colorDragFlag],
        steps: [
            TutorialStep(
                id: "three-headings",
                anchor: .canvas,
                title: "Three headings, set by hand",
                body: "Notifications is set the way a heading should be. Privacy and Storage were typed in a hurry and never matched it."),
            TutorialStep(
                id: "pick-a-heading",
                anchor: .canvas,
                title: "Pick the first one",
                body: "Click the word Notifications on the picture.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "save-the-type",
                anchor: .panelSection("text"),
                title: "Save how it is set",
                body: "Style is the top row here. Open its button, choose Save as Style, type Section Heading and press Return.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "pick-another",
                anchor: .canvas,
                title: "Now pick Privacy",
                body: "Click the word Privacy.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "use-the-name",
                anchor: .panelSection("text"),
                title: "Set it by the name",
                body: "Open the same button and choose Section Heading. It grows into place: the font, the size, the weight and the colour all come from the name now.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "drag-it-on",
                anchor: .panelSection("library"),
                title: "Or just drag it on",
                body: "Quicker: drag the Section Heading tile off the shelf and let go on the word Storage. It matches the other two, and no menus were opened.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                id: "all-three-one-name",
                anchor: .canvas,
                title: "All three, one name",
                body: "Change Section Heading on the shelf now and all three headings change with it, the way everything wearing a saved colour does."),
        ])

    /// What the shelf is, and the two things people never find on their own:
    /// that a colour can be put down ON it, and that removing a style repaints
    /// nothing.
    public static let theLibrary = TutorialGuide(
        id: "the-library",
        track: .colorsAndStyles,
        title: "The Library",
        summary: "One shelf for everything you save, and the quickest way to put something on it.",
        minutes: 2,
        sample: .stylesScreen,
        requires: [FeatureCatalog.libraryFlag, FeatureCatalog.stylesFlag,
                   FeatureCatalog.colorDragFlag],
        steps: [
            TutorialStep(
                id: "one-shelf",
                anchor: .panelSection("library"),
                title: "One shelf for everything",
                body: "Four scopes. Media holds every capture you have taken, Comps your components, Styles your saved colours and type, Systems your design systems.",
                side: .leading,
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                id: "pick-a-switch",
                anchor: .canvas,
                title: "Pick something with a colour on it",
                body: "Click the blue switch beside Privacy.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                // It rings the SHELF rather than the whole dock, even though
                // the drag starts on the Fill row above. Ringing the dock left
                // the shelf scrolled off the bottom of it, so the step said
                // "let go anywhere on the Library" over a panel with no
                // Library in it (measured on the probe on 2026-09-13). Asking
                // for the shelf scrolls it up and leaves the Fill row above it
                // on screen, which is what the drag needs.
                id: "drop-it-on-the-shelf",
                anchor: .panelSection("library"),
                title: "Drop a colour straight on it",
                body: "Drag the swatch off the Fill row above and let go anywhere on the Library. It turns to Styles and asks for a name. Call it Brand.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .showLibrary, .revealTarget]),
            TutorialStep(
                // One step rather than two. The second one used to name the
                // Remove button, which only exists once a tile has been
                // clicked, and nothing makes somebody click one: pressing Next
                // took them to a card naming a button that was not on screen.
                id: "a-tile-is-a-handle",
                anchor: .panelSection("library"),
                title: "A tile is a handle",
                body: "Click Brand and its settings open below: rename it, change its colour, or pick out every layer using it. Remove takes it off the shelf and every layer keeps the colour it has.",
                side: .leading,
                prepare: [.showPanel, .showLibrary, .revealTarget]),
        ])

    // MARK: - Building UI
    //
    // How to build a screen rather than annotate one. Four guides in the order
    // a screen actually gets built: draw the screen, hand it the spacing, give
    // it room and the columns you design to, and line up by hand whatever is
    // left.
    //
    // The one idea underneath all four, and the one nothing on screen says out
    // loud, is that a screen is a GROUP with a size. Everything a group can do
    // it can do, everything you draw inside it joins it, and the numbers that
    // arrange a group arrange a screen.

    /// The first rung: a screen is a thing you draw, not a document setting.
    ///
    /// It has you draw one rather than showing you one, because the frame tool
    /// is at the end of the tool bar and nobody finds it by accident. The
    /// second half is the part that pays: what you draw inside a screen joins
    /// the screen, which is the whole reason to have drawn it.
    public static let framesAreScreens = TutorialGuide(
        id: "frames-are-screens",
        track: .buildingUI,
        title: "Frames are screens",
        summary: "Draw the box a screen is built on, and watch what you draw inside it join it.",
        minutes: 2,
        sample: .blankPage,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag],
        steps: [
            TutorialStep(
                id: "a-clear-page",
                anchor: .canvas,
                title: "A page with nothing on it",
                body: "A screen here is a frame: a box with a size, a name and a surface of its own. This page has none yet."),
            TutorialStep(
                id: "take-the-frame-tool",
                anchor: .tool(.frame),
                title: "Take the frame tool",
                body: "Press F, or click this button at the end of the tool bar.",
                advance: .waitsFor(.toolPicked(.frame))),
            TutorialStep(
                id: "drag-one-out",
                anchor: .canvas,
                title: "Drag out a screen",
                body: "Drag a tall box in the middle of the page. It paints itself white and writes its name above its top left corner.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "what-a-screen-has",
                anchor: .panelSection("frame"),
                title: "What a screen has",
                body: "A size you can type, the surface it paints, and whether it cuts off anything hanging past its edge.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "take-the-rectangle",
                // The shapes SLOT, not the rectangle: the slot wears whichever
                // shape was last used, and on a fresh machine that is the line.
                anchor: .toolGroup(.shapes),
                title: "Now draw on it",
                body: "Press R for the rectangle.",
                advance: .waitsFor(.toolPicked(.rectangle))),
            TutorialStep(
                id: "draw-a-card",
                anchor: .canvas,
                title: "Drag a card inside the screen",
                body: "Anything you draw inside a screen joins it, so dragging the screen later takes the card with it.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "it-belongs-to-the-screen",
                anchor: .panelSection("layers"),
                title: "It belongs to the screen",
                body: "The list shows your card sitting inside the screen. That is what a screen is for, and the next guide has it do the spacing too.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// The rung people feel the difference on: the spacing stops being
    /// something you maintain.
    ///
    /// It hands the arrangement to the SCREEN rather than stacking a loose
    /// selection, because a screen is the container somebody already has and
    /// stacking a selection would make a second container inside it. The last
    /// step takes a card away instead of adding one: adding means picking up a
    /// drawing tool, and a drawing tool picked up straight after typing in a
    /// number field types into the field instead.
    public static let letAScreenArrangeItself = TutorialGuide(
        id: "let-a-screen-arrange-itself",
        track: .buildingUI,
        title: "Let a screen arrange its contents",
        summary: "Hand the spacing to the screen once, and stop nudging things into place.",
        minutes: 2,
        sample: .handPlacedScreen,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag,
                   FeatureCatalog.autoLayoutFlag],
        steps: [
            TutorialStep(
                id: "placed-by-hand",
                anchor: .canvas,
                title: "Three cards, nudged into place",
                body: "Each one dragged until it looked about right, which is why they are not quite evenly spaced."),
            TutorialStep(
                id: "pick-the-screen",
                anchor: .canvas,
                title: "Pick the screen",
                body: "Click its name, just above its top left corner.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "stack-them",
                anchor: .panelSection("placement"),
                title: "Set Arrangement to Stack",
                body: "In Layout. Nothing jumps: the screen reads the spacing you already had and carries on with it.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "type-a-gap",
                anchor: .panelSection("placement"),
                title: "Now type the gap",
                body: "Put 24 in Gap and press Return. All three move at once, and the spacing is a number you chose rather than one you eyeballed.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "take-one-away",
                anchor: .canvas,
                title: "Take the middle card away",
                body: "Click it, then press Delete.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "nothing-to-tidy",
                anchor: .canvas,
                title: "Nothing needed tidying",
                body: "The two left closed up on their own, still 24 apart. Add one, hide one, reorder them: the screen does the spacing every time."),
        ])

    /// The guide that exists because these two were a real source of
    /// confusion: a screen has ONE inset from its edge, and the columns are
    /// drawn inside it. Taught together for that reason, and in that order.
    public static let paddingAndColumns = TutorialGuide(
        id: "padding-and-columns",
        track: .buildingUI,
        title: "Padding and columns",
        summary: "Give a screen room inside its edges, then lay it out on the columns you design to.",
        minutes: 2,
        sample: .tightScreen,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag,
                   FeatureCatalog.autoLayoutFlag],
        steps: [
            TutorialStep(
                id: "flush-to-the-edges",
                anchor: .canvas,
                title: "Everything runs to the edges",
                body: "This screen keeps no room inside it, so its cards touch both sides. Real screens almost never look like this."),
            TutorialStep(
                id: "pick-the-screen",
                anchor: .canvas,
                title: "Pick the screen",
                body: "Click its name, just above its top left corner.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "give-it-room",
                anchor: .panelSection("placement"),
                title: "Give it room inside",
                body: "Type 24 into Padding, in Layout. That is the room kept clear inside all four of its edges.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "show-the-columns",
                anchor: .panelSection("columns"),
                title: "Turn its columns on",
                body: "Tick Show columns. The screen is drawn over with the columns a layout is designed to.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "columns-start-at-the-padding",
                anchor: .panelSection("columns"),
                title: "They start where the padding does",
                body: "Not at the screen's edge. A screen has one inset, so the columns sit inside the room you just gave it, and the line here says so.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "set-the-count",
                anchor: .panelSection("columns"),
                title: "The numbers are yours",
                body: "Four columns came ready for a screen this narrow. Put 24 in Gutter and watch the line underneath work out what each one comes to.",
                side: .leading,
                advance: .waitsFor(.editMade),
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "drag-pulls-to-them",
                anchor: .canvas,
                title: "Now a drag pulls to them",
                body: "Draw anything on this screen and it snaps to the column edges. Hold Command while you drag to ignore them."),
        ])

    /// The last rung, and the one that covers everything the other three do
    /// not: two loose things that have to agree with each other.
    ///
    /// It teaches the keys rather than the buttons. The buttons are shown
    /// once, because somebody has to know the row exists, but a person lining
    /// up a screen has one hand on the mouse and the whole point is not going
    /// to the panel for it.
    public static let lineThingsUp = TutorialGuide(
        id: "line-things-up",
        track: .buildingUI,
        title: "Line things up",
        summary: "Put loose layers on one edge and give them equal gaps, with two keys.",
        minutes: 2,
        sample: .crookedBoxes,
        requires: [FeatureCatalog.alignLayersFlag],
        steps: [
            TutorialStep(
                id: "three-crooked-boxes",
                anchor: .canvas,
                title: "Three boxes, none of them in line",
                body: "Three different heights and two different gaps. Two keys fix both of those."),
            TutorialStep(
                id: "pick-all-three",
                anchor: .canvas,
                title: "Pick all three",
                body: "Start on the clear page to the left of them and drag a box round the lot.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "the-arrange-row",
                anchor: .panelSection("arrange"),
                title: "Every way to line things up",
                body: "Arrange holds the six edges and the two spacings. Worth knowing it is here, though the keys are quicker.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
            TutorialStep(
                id: "line-their-tops-up",
                anchor: .canvas,
                title: "Line their tops up",
                body: "Press \u{2325}W. All three jump to the topmost one. \u{2325}A, \u{2325}S and \u{2325}D are the other edges.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "space-them-evenly",
                anchor: .canvas,
                title: "Space them evenly",
                body: "Press \u{2303}\u{2325}H. The two gaps come out equal and the boxes on the ends stay where they are.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "and-while-you-drag",
                anchor: .canvas,
                title: "And while you drag",
                body: "Drag one of them around. It sticks as it comes into line with the others, so most of the time you never reach for a key at all."),
        ])

    // MARK: - Icons

    // Drawing an icon end to end, which is a different job from everything
    // above it: you set up the square it will really be used in, you draw the
    // outline yourself rather than dragging a ready made shape, you bend it
    // until it is right, and you hand it over as a file somebody else's app
    // can read.
    //
    // Five guides, in the order the job is done in, and every one of them
    // teaches on the SAME 24 point icon frame, so the track reads as one icon
    // being made rather than as five exercises. The first has you make the
    // frame; the rest bring it with them.
    //
    // 24 by 24 is not an arbitrary size. It is what interface iconography is
    // designed at, it is the artboard the keylines are worked out from
    // (`IconKeylines`), and it is the size where a two point line is the right
    // weight (`IconStrokeWeight`). Teaching on anything else would teach
    // numbers nobody meets again.

    /// Where an icon starts: the square it will really be used in, the lines it
    /// has to land on, and the margin every icon in a set keeps to.
    ///
    /// It has you make the frame from the SIZE LIST rather than by dragging one
    /// out with the frame tool, because a 24 point box dragged on a page the
    /// size of a screen is a speck. A frame made from a picked size brings the
    /// camera with it, which is the only way somebody ends this guide looking
    /// at something they can draw in.
    public static let startOnAnIconFrame = TutorialGuide(
        id: "start-on-an-icon-frame",
        track: .icons,
        title: "Start on an icon frame",
        summary: "Make the square your icon really lives in, and turn on the lines that keep it sharp.",
        minutes: 2,
        sample: .blankPage,
        requires: [FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag,
                   FeatureCatalog.iconFramesFlag, FeatureCatalog.iconPreviewsFlag,
                   FeatureCatalog.canvasGridFlag],
        steps: [
            TutorialStep(
                id: "a-clear-page",
                anchor: .canvas,
                title: "An icon needs a size first",
                body: "An icon is drawn at the size it will be used. That size is a frame, and this page has not got one yet."),
            TutorialStep(
                id: "open-the-size-list",
                anchor: .canvas,
                title: "Open the size list",
                body: "In the Layer menu, choose New Frame. It offers screens, and under them the sizes icons are really drawn at.",
                advance: .waitsFor(.dialogOpened(.newFrame))),
            TutorialStep(
                id: "take-twenty-four",
                anchor: .dialog(.newFrame),
                title: "Take 24, then Add Frame",
                body: "24 by 24 is where most interface icons are designed. The view goes and gets the frame, so you can actually draw in it.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "the-previews",
                anchor: .canvas,
                title: "The same icon, small",
                body: "The little squares in the corner are your frame at the sizes it will really be used. A hairline that vanishes there vanishes everywhere."),
            TutorialStep(
                id: "show-the-grid",
                anchor: .canvas,
                title: "Turn the pixels on",
                body: "Press \u{2318}'. The lines are what an icon has to land on, and a point you place sticks to the nearest crossing.",
                advance: .waitsFor(.gridShown)),
            TutorialStep(
                id: "show-the-keylines",
                anchor: .canvas,
                title: "Keep inside the keylines",
                body: "Show Icon Keylines, in the View menu, draws the margin every icon in a set keeps to, and the two lines through the middle.",
                advance: .waitsFor(.keylinesShown)),
            TutorialStep(
                id: "what-the-frame-knows",
                anchor: .panelSection("frame"),
                title: "The frame itself",
                body: "Its size is here, and it cuts off anything hanging over the edge. Whatever you draw inside it belongs to it.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// The Pen, taught as drawing an icon rather than as a tour of a tool.
    ///
    /// Two shapes, because one of them cannot teach both things: a run of
    /// clicks makes the hard edges, and a press that DRAGS makes the curve.
    /// Not being able to find the curve at all is what a real first session
    /// with the Pen ran aground on, so it gets a shape of its own and a step
    /// that waits until it has really been drawn.
    public static let drawItWithThePen = TutorialGuide(
        id: "draw-it-with-the-pen",
        track: .icons,
        title: "Draw it with the Pen",
        summary: "Click the corners, drag the curves, and close the shape up.",
        minutes: 2,
        sample: .iconFrame,
        requires: [FeatureCatalog.penFlag, FeatureCatalog.layerGroupsFlag,
                   FeatureCatalog.framesFlag, FeatureCatalog.iconFramesFlag,
                   FeatureCatalog.canvasGridFlag],
        steps: [
            TutorialStep(
                id: "up-close",
                anchor: .canvas,
                title: "Your frame, up close",
                body: "24 points square, drawn big enough to work in. Everything you draw inside it belongs to it and leaves with it."),
            // Its own step rather than a sentence on the one above, because
            // somebody who already works with the grid on passes straight
            // through a step that waits on it, and the card above is the one
            // carrying the context.
            TutorialStep(
                id: "lines-to-land-on",
                anchor: .canvas,
                title: "Lines to land on",
                body: "Press \u{2318}' if the grid is not showing. Every point the Pen puts down sticks to the nearest crossing of it.",
                advance: .waitsFor(.gridShown)),
            TutorialStep(
                id: "take-the-pen",
                anchor: .tool(.pen),
                title: "Take the Pen",
                body: "Press P. It stays in your hand after each shape, because an icon is five or six shapes in a row.",
                advance: .waitsFor(.toolPicked(.pen))),
            TutorialStep(
                id: "the-line-underneath",
                anchor: .canvas,
                title: "Read the line under the canvas",
                body: "It says what the Pen will do next, and it changes as the shape grows. It is the quickest way out of being stuck."),
            TutorialStep(
                id: "click-the-corners",
                anchor: .canvas,
                title: "Click out a shape",
                body: "Click three or four corners, then click the first point again to close it. Each click lands on a crossing of the lines.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "pull-a-curve",
                anchor: .canvas,
                title: "Now pull a curve",
                body: "Start another one. Click a point, then press where the next goes and drag before you let go. Close it on the first point.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "each-shape-is-a-layer",
                anchor: .panelSection("layers"),
                title: "Each shape is a layer",
                body: "A finished outline is its own layer, with a fill and a line you can repaint. Escape puts the Pen down again.",
                side: .leading,
                prepare: [.showPanel, .revealTarget]),
        ])

    /// Changing a shape after it is drawn, which is where an icon is really
    /// made: nobody clicks the right five points first time.
    ///
    /// The two gestures nobody guesses are the two the guide waits on. A double
    /// click on a POINT bends it, and a double click on a LEVER straightens
    /// that side, and between them they are how a rounded corner gets made.
    public static let reshapeWhatYouDrew = TutorialGuide(
        id: "reshape-what-you-drew",
        track: .icons,
        title: "Reshape what you drew",
        summary: "Move the points, bend the corners, and straighten the sides you did not want curved.",
        minutes: 2,
        sample: .iconPath,
        requires: [FeatureCatalog.penFlag, FeatureCatalog.reshapePathFlag,
                   FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag,
                   FeatureCatalog.iconFramesFlag],
        steps: [
            TutorialStep(
                id: "a-run-of-points",
                anchor: .canvas,
                title: "A shape is a run of points",
                body: "This bookmark was drawn with the Pen: five hard corners, with a straight run between each pair of them."),
            TutorialStep(
                id: "pick-it",
                anchor: .canvas,
                title: "Click the shape",
                body: "Pick it with the pointer and its points appear on it. No second tool to find, and no mode to be in.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "drag-a-point",
                anchor: .canvas,
                title: "Drag one of them",
                body: "The point moves, and the outline either side of it travels with it. Undo puts it back where it was.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "bend-a-corner",
                anchor: .canvas,
                title: "Double click a point",
                body: "The hard corner becomes a smooth bend and two levers appear to steer it. Double click it again to turn it back.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "straighten-one-side",
                anchor: .canvas,
                title: "Double click a lever",
                body: "That side runs straight again. Curved on one side and straight on the other is exactly what a rounded corner is.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "read-the-dots",
                anchor: .canvas,
                title: "The dots say what each point is",
                body: "A square dot is a hard corner, a round one is a bend, and a rounded square is a point curved on one side only."),
        ])

    /// The other way to get an outline, and for most icons the faster one:
    /// draw a box, round it, and turn it into points.
    ///
    /// It sits after the reshaping guide on purpose. What Turn Into Path hands
    /// you is a shape you reshape, so it means nothing until you know what to
    /// do with the points.
    public static let turnAShapeIntoAPath = TutorialGuide(
        id: "turn-a-shape-into-a-path",
        track: .icons,
        title: "Turn a shape into a path",
        summary: "Round a box the easy way, then take its corners somewhere a box could never go.",
        minutes: 2,
        sample: .iconBox,
        requires: [FeatureCatalog.turnIntoPathFlag, FeatureCatalog.reshapePathFlag,
                   FeatureCatalog.penFlag, FeatureCatalog.layerGroupsFlag,
                   FeatureCatalog.framesFlag, FeatureCatalog.iconFramesFlag],
        steps: [
            TutorialStep(
                id: "a-rounded-box",
                anchor: .canvas,
                title: "A box, and only a box",
                body: "You can resize it and round it further, but you cannot take one corner of it and pull it somewhere else."),
            TutorialStep(
                id: "pick-the-box",
                anchor: .canvas,
                title: "Pick it",
                body: "Click the box. Its rounding is a setting, and a setting is as much shape as a box is ever going to have.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "turn-it",
                anchor: .canvas,
                title: "Turn it into a path",
                body: "In the Layer menu, choose Turn Into Path. It asks you first, because the box stops being a box.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "nothing-moved",
                anchor: .canvas,
                title: "The same picture",
                body: "Not a pixel moved. The rounded corners are real curves now, and every point in them is yours to pull."),
            TutorialStep(
                id: "pull-one",
                anchor: .canvas,
                title: "Pull one",
                body: "Drag a point, or double click a lever to straighten a side. Rounding a box first is how most icons really get made.",
                advance: .waitsFor(.editMade)),
            TutorialStep(
                id: "one-undo-back",
                anchor: .canvas,
                title: "One undo puts the box back",
                body: "With its rounding row, exactly as it was. Nothing about this turn is a trap door."),
        ])

    /// The end of the errand: the icon leaves as an icon.
    ///
    /// The sheet is explained BEFORE it is opened, so nobody is reading a card
    /// over the top of the thing it is describing, and the last card points at
    /// the sheet itself rather than at the canvas underneath it.
    public static let getACleanSVGOut = TutorialGuide(
        id: "get-a-clean-svg-out",
        track: .icons,
        title: "Get a clean SVG out",
        summary: "Hand the icon over as real shapes, not as a picture of them.",
        minutes: 2,
        sample: .iconPath,
        requires: [FeatureCatalog.svgExportFlag, FeatureCatalog.penFlag,
                   FeatureCatalog.layerGroupsFlag, FeatureCatalog.framesFlag,
                   FeatureCatalog.iconFramesFlag],
        steps: [
            TutorialStep(
                id: "shapes-not-pixels",
                anchor: .canvas,
                title: "Shapes, not pixels",
                body: "What you drew is geometry, so it can leave as geometry: sharp at any size, and small enough to sit inside a web page."),
            TutorialStep(
                id: "pick-the-frame",
                anchor: .canvas,
                title: "Pick the frame",
                body: "Click its name, just above the top left corner. Export opens on the frame you are in, so the file is the icon alone.",
                advance: .waitsFor(.layerSelected)),
            TutorialStep(
                id: "what-it-asks",
                anchor: .canvas,
                title: "Export asks what, and as what",
                body: "The top row is what to write: this frame, or the whole page. SVG then sits in the format row beside PNG, JPEG and HEIC."),
            TutorialStep(
                id: "before-you-save",
                anchor: .canvas,
                title: "It says what it cannot draw",
                body: "Anything with no vector answer, a shadow for instance, is named in the sheet as going out as a picture, before you save."),
            TutorialStep(
                id: "open-export",
                anchor: .canvas,
                title: "Press \u{21E7}\u{2318}E",
                body: "The Export sheet comes down over the window.",
                advance: .waitsFor(.dialogOpened(.export))),
            TutorialStep(
                id: "choose-svg-and-save",
                anchor: .dialog(.export),
                title: "Choose SVG and save it",
                body: "What lands on disk is the shapes you drew, laid out so a person can read them. Any site or icon set will take it."),
        ])

    // MARK: The Video track

    /// The smallest track, and the only one that teaches in a window with no
    /// canvas in it: a recording opens in the video window, which is one
    /// picture and one floating controller over it.
    ///
    /// Trimming is the one edit in the app that is baked in when you save, and
    /// the last card says so rather than leaving somebody to discover it. It
    /// does not make anybody save: a guide that quietly rewrites a file on
    /// its way past is not a guide.
    public static let trimARecording = TutorialGuide(
        id: "trim-a-recording",
        track: .video,
        title: "Trim a recording",
        summary: "Cut a recording down to the part worth watching, and know what saving does to it.",
        minutes: 2,
        sample: .sampleRecording,
        steps: [
            TutorialStep(
                id: "what-you-have",
                anchor: .video(.preview),
                title: "A recording, mostly waiting",
                body: "It starts playing as soon as it opens. The first and last few seconds are nothing happening, which is what you are about to cut off."),
            TutorialStep(
                id: "getting-around-it",
                anchor: .video(.transport),
                title: "Getting around it",
                body: "Space plays and pauses. Paused, the arrow keys step one frame at a time, which is how you land on the exact moment to cut at."),
            TutorialStep(
                id: "open-the-trim",
                anchor: .video(.trim),
                title: "Open the trim",
                body: "Click the scissors. The playback line turns into the whole clip with a handle at each end.",
                advance: .waitsFor(.trimModeOpened)),
            TutorialStep(
                id: "bring-the-start-in",
                anchor: .video(.timeline),
                title: "Bring the start in",
                body: "Drag the left handle along to where something starts happening. The picture follows the handle, so you can see where you are landing.",
                side: .above,
                advance: .waitsFor(.trimStartMoved)),
            TutorialStep(
                id: "bring-the-end-back",
                anchor: .video(.timeline),
                title: "And the end back",
                body: "Drag the right handle in to where it stops being worth watching. The length you are keeping reads out beside the scissors.",
                side: .above,
                advance: .waitsFor(.trimEndMoved)),
            TutorialStep(
                id: "keep-whats-between",
                anchor: .video(.trimDone),
                title: "Keep what is between them",
                body: "Done throws the ends away and leaves you the middle. It plays from its new start, and you can trim it again from there.",
                advance: .waitsFor(.trimApplied)),
            TutorialStep(
                id: "saving-writes-it-in",
                anchor: .video(.save),
                title: "Saving writes it into the file",
                body: "Nothing on disk has changed yet. Saving puts the trim into the recording and keeps the original beside it, so Revert to Original in the Video menu brings the clip back."),
        ])

    /// The decision rather than the gesture: which of three shapes a recording
    /// leaves the app in, and the one that skips the file entirely.
    ///
    /// It rings the Export button and says what is inside it. The rows are in a
    /// menu, which is its own window and cannot be ringed, and picking one runs
    /// a save dialog that would sit on top of the card. So the guide ends on
    /// Copy, which is what most people want when they say send this to
    /// somebody, and asks for no dialog at all.
    public static let exportARecording = TutorialGuide(
        id: "export-a-recording",
        track: .video,
        title: "Export MP4, GIF or HEIC",
        summary: "Pick the shape a recording leaves in, or put it straight on the clipboard.",
        minutes: 1,
        sample: .sampleRecording,
        steps: [
            TutorialStep(
                id: "three-ways-out",
                anchor: .video(.export),
                title: "Three ways out",
                body: "MP4 keeps the picture and the sound and plays anywhere. GIF loops silently and needs no player. HEIC is a small animation for Apple devices."),
            TutorialStep(
                id: "how-good",
                anchor: .video(.export),
                title: "GIF and HEIC ask how good",
                body: "High, Standard or Small. Standard is the one to start with, High is worth it when small text has to stay readable, and Small keeps the file down."),
            TutorialStep(
                id: "copy-it-instead",
                anchor: .video(.copy),
                title: "For a chat, copy it",
                body: "This puts the recording straight on the clipboard with no file to find afterwards. Try Copy GIF, and paste it wherever you were going to send it.",
                advance: .waitsFor(.recordingCopied)),
            TutorialStep(
                id: "what-comes-out",
                anchor: .video(.preview),
                title: "What you see is what comes out",
                body: "A trim or a crop goes into everything you copy or export from here. The recording on disk stays as it was until you save."),
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
        case .redlineScreen, .measuredScreen, .accountScreen, .tintedScreen: "#EDF0F5"
        case .starterScreen, .emptyWindow: "#FFFFFF"
        // The styles track's card is a screen too, and for the same reason:
        // a white card on a white page has no edge, and the whole track is
        // about looking at one card.
        case .stylesScreen: "#EDF0F5"
        // The component samples are a work surface rather than a screenshot:
        // what you are designing is a control, and a control on a white page
        // has no edge to it. A soft grey reads as the desk it is lying on.
        case .componentPieces, .componentOriginal, .componentCopies: "#EDF0F5"
        // The Building UI samples are a desk you build a screen on. A screen
        // paints its own white surface, so the page under it has to be
        // something else or the screen has no edge, and the guide that has you
        // draw one would look like nothing happened.
        case .blankPage, .handPlacedScreen, .tightScreen, .crookedBoxes: "#EDF0F5"
        // An icon frame paints its own white surface, exactly as a screen does,
        // so the page under it has to be something else or the frame has no
        // edge at all.
        case .iconFrame, .iconPath, .iconBox: "#EDF0F5"
        // A recording is not drawn on a page. Its window holds media, and this
        // is never asked of it.
        case .sampleRecording: "#FFFFFF"
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
        case .accountScreen, .tintedScreen: accountScreen()
        case .starterScreen, .emptyWindow: []
        case .componentPieces, .componentOriginal, .componentCopies: []
        case .stylesScreen: []
        case .blankPage, .handPlacedScreen, .tightScreen, .crookedBoxes: []
        case .iconFrame, .iconPath, .iconBox: []
        case .sampleRecording: []
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
        // A screenshot with somebody's address on it, and nothing on top of it
        // yet: the lens the guide teaches is the thing you add.
        case .accountScreen: []
        // The same screenshot with one solid box lying over the address, which
        // is the layer the mixing guide is about.
        case .tintedScreen: [tintBox()]
        // The three stages of the components track, each one the state the
        // guide that brings it starts from.
        case .componentPieces: loosePieces()
        case .componentOriginal: [buttonComponent()]
        case .componentCopies: buttonWithCopies()
        // The one screen the whole Colours and Styles track teaches on.
        case .stylesScreen: stylesScreen()
        // The Building UI desk: a clear page to draw a screen on, the same
        // screen with its cards dropped in by hand, that screen with them
        // stacked and flush to its edges, and three boxes to line up.
        case .blankPage: []
        case .handPlacedScreen: [handPlacedScreen()]
        case .tightScreen: [tightScreen()]
        case .crookedBoxes: crookedBoxes()
        // The Icons track's workbench: one icon frame, empty, with a bookmark
        // drawn in it, or with a rounded box in it waiting to be turned into
        // one.
        case .iconFrame: [iconFrame(holding: [])]
        case .iconPath: [iconFrame(holding: [drawnBookmark()])]
        case .iconBox: [iconFrame(holding: [iconRoundedBox()])]
        // A recording, which has no layers at all. What it IS lives in the
        // app, beside the code that can write an MP4.
        case .sampleRecording: []
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

    // MARK: The account screen

    /// A made up account pane with a person's name and address on it, drawn the
    /// way a real one is and then flattened into the picture. This is the
    /// screenshot somebody is about to send on, which is the moment they want a
    /// lens: the address is the thing they mean to hide.
    ///
    /// Made up on purpose. Nothing here belongs to anybody, and the address is
    /// at example.com, which exists to be written down and never delivers mail.
    private static func accountScreen() -> [Layer] {
        [
            box("Card", accountCardFrame, radius: 14, fill: "#FFFFFF", stroke: "#D7DDE8"),
            label("Title", "Account", at: CGPoint(x: 104, y: 96),
                  size: 22, color: ink, weight: .bold),
            label("Subtitle", "Signed in on this Mac.", at: CGPoint(x: 104, y: 134),
                  size: 14, color: quiet, weight: .regular),
            box("Divider", CGRect(x: 104, y: 172, width: 512, height: 1),
                radius: 0, fill: "#E4E8F0", stroke: nil),
            label("Name Label", "Name", at: CGPoint(x: 104, y: 200),
                  size: 13, color: quiet, weight: .regular),
            label("Name", "Jordan Avery", at: CGPoint(x: 104, y: 222),
                  size: 17, color: ink, weight: .medium),
            label("Email Label", "Email", at: CGPoint(x: 104, y: 272),
                  size: 13, color: quiet, weight: .regular),
            label("Email", "jordan.avery@example.com", at: CGPoint(x: 104, y: 294),
                  size: 17, color: ink, weight: .medium),
            box("Sign Out Button", CGRect(x: 104, y: 348, width: 120, height: 38),
                radius: 8, fill: "#FFFFFF", stroke: "#C2C9D6"),
            label("Sign Out Label", "Sign out", at: CGPoint(x: 128, y: 358),
                  size: 14, color: ink, weight: .medium),
        ]
    }

    /// The card the account screen is built on.
    static let accountCardFrame = CGRect(x: 72, y: 64, width: 576, height: 352)
    /// The one live layer the mixing sample brings: a solid box lying across
    /// the address row. Solid on purpose, because the lesson is what changes
    /// when the mixing setting does, and a box you can already see through has
    /// given half the answer away before the guide starts.
    static let tintFrame = CGRect(x: 96, y: 288, width: 316, height: 34)

    private static func tintBox() -> Layer {
        box("Marker", tintFrame, radius: 4, fill: "#FFD25E", stroke: nil)
    }

    // MARK: The styles card

    /// The screen the whole Colours and Styles track teaches on: a settings
    /// card with three rows, each a heading, a line under it and a blue switch.
    ///
    /// THREE of each, and that is the point of it. Two switches on one name
    /// would show a change reaching two layers; the third, which never had the
    /// name and so does not move, is the only thing on screen that says WHY.
    /// The headings are set identically for the same reason one rung up.
    ///
    /// The switches carry no words. A click aimed at a box with a label on it
    /// lands on the label and picks the text layer, which the Looks track found
    /// in August and the Components track found again in September, so every
    /// target this track asks for by click is a switch.
    private static func stylesScreen() -> [Layer] {
        var layers: [Layer] = [
            box("Card", CGRect(x: 56, y: 56, width: 608, height: 320),
                radius: 16, fill: "#FFFFFF", stroke: line),
            label("Title", "Team settings", at: CGPoint(x: 88, y: 84),
                  size: 24, color: ink, weight: .bold),
        ]
        for row in settingsRows {
            // Only the first heading is set the way a heading should be. The
            // other two were "typed in a hurry", which is what gives the text
            // guide something to SEE: set the second one by the name and it
            // visibly grows into place. Three headings already identical would
            // have made every step of that guide invisible, which is how it
            // read on the probe on 2026-09-13 before this.
            let heading = row.top == settingsRows[0].top
            layers.append(label(row.heading, row.heading, at: CGPoint(x: 88, y: row.top),
                                size: heading ? 17 : 15, color: ink,
                                weight: heading ? .semibold : .regular))
            layers.append(label("\(row.heading) Note", row.note,
                                at: CGPoint(x: 88, y: row.top + 26),
                                size: 13, color: quiet, weight: .regular))
            layers.append(box("\(row.heading) Switch",
                              CGRect(x: 572, y: row.top + 2, width: 48, height: 28),
                              radius: 14, fill: accent, stroke: nil))
        }
        return layers
    }

    /// The three rows of the card, in the order they are drawn down it. Named
    /// after ordinary settings so the screen reads as something somebody would
    /// really have open, and so a step can say "the switch beside Privacy"
    /// and be pointing at one thing.
    ///
    /// The first row's heading is the one that is set properly. The other two
    /// are the same words set smaller and lighter, which is the ordinary mess
    /// a real file is in and the thing the text guide fixes on screen.
    private static let settingsRows: [(heading: String, note: String, top: CGFloat)] = [
        ("Notifications", "Choose what you hear about.", 144),
        ("Privacy", "Decide what other people can see.", 224),
        ("Storage", "Photos and videos on this Mac.", 304),
    ]

    // MARK: The components desk

    /// The button every guide on the Components track is about: a box with a
    /// word on it, which is the smallest thing anybody actually builds twice.
    ///
    /// It is drawn as two layers on purpose. A component that was one shape
    /// would make grouping look like a formality, and the whole first lesson is
    /// that a component is made out of a group of things that travel together.
    /// Wide enough that the box has clear room on both sides of its word. The
    /// first cut was 176 across and the label filled the middle of it, so a
    /// double click aimed at "the box" landed on the words and picked the text
    /// layer instead: the same trap the Looks track hit in August. Measured on
    /// the probe on 2026-09-13.
    static let buttonSize = CGSize(width: 240, height: 52)

    /// Where the original sits on every component sample, with the page to the
    /// right of it left clear: a second version lands beside the drawing it
    /// came from, and it has to land somewhere the person is looking.
    static let componentOrigin = CGPoint(x: 88, y: 88)
    /// Where the two copies sit under it on the samples that bring copies.
    static let firstCopyOrigin = CGPoint(x: 88, y: 192)
    static let secondCopyOrigin = CGPoint(x: 88, y: 296)

    /// The identity the sample's component is known by. Fixed rather than
    /// minted, so the same sample opened twice is the same sample.
    static let buttonComponentID = UUID(uuidString: "5B5D3A28-1C0E-4E3E-9B1E-9E7C1C7A0001")
        ?? UUID()

    /// What the sample's component is called, and what the guide that makes one
    /// asks you to call it.
    ///
    /// Not "Button". The shelf arrives stocked with the app's five starters and
    /// one of them is called Button, so a sample component of that name puts
    /// two tiles reading Button side by side and every step that says "your
    /// button's tile" points at either of them. Measured on the probe on
    /// 2026-09-13, where the shelf came up reading Button, Button, Text Field,
    /// Card, Nav Bar, Badge.
    ///
    /// The pieces inside it are called Box and Label for the same reason: a
    /// document's own picture is a layer called Background, so a piece of that
    /// name would put two Background rows in the list.
    public static let componentName = "Save Button"

    /// The two pieces of the button, in the space of whatever holds them.
    private static func buttonPieces(in frame: CGRect) -> [Layer] {
        [
            box("Box", frame, radius: 10, fill: accent, stroke: nil),
            centered("Label", "Save changes", in: frame, size: 16,
                     color: "#FFFFFF", weight: .semibold),
        ]
    }

    /// The first guide's page: the button drawn, and nothing done to it yet.
    /// Two loose layers sitting on clear space, so a selection box dragged
    /// round them catches both and catches nothing else.
    private static func loosePieces() -> [Layer] {
        buttonPieces(in: CGRect(origin: CGPoint(x: 112, y: 208), size: buttonSize))
    }

    /// The same button, already promoted: one group carrying a component id,
    /// which is all a main component is.
    private static func buttonComponent() -> Layer {
        let box = CGRect(origin: .zero, size: buttonSize)
        let content = GroupContent(children: buttonPieces(in: box),
                                   componentID: buttonComponentID)
        return Layer(name: componentName, content: .group(content),
                     frame: CGRect(origin: componentOrigin, size: buttonSize))
    }

    /// One copy of it. Its contents are not its own, so they are exactly the
    /// original's: the first edit in the window puts them formally in step, and
    /// a copy that arrived drawing something else would be a lie on screen
    /// before the guide had said a word.
    private static func buttonCopy(at origin: CGPoint) -> Layer {
        let box = CGRect(origin: .zero, size: buttonSize)
        var content = GroupContent(children: buttonPieces(in: box))
        content.instanceOf = buttonComponentID
        return Layer(name: componentName, content: .group(content),
                     frame: CGRect(origin: origin, size: buttonSize))
    }

    /// The original with two copies under it. Two rather than one: a single
    /// copy following its original shows nothing a duplicate would not, and the
    /// override guide's whole point is the copy that did NOT change.
    private static func buttonWithCopies() -> [Layer] {
        [buttonComponent(), buttonCopy(at: firstCopyOrigin), buttonCopy(at: secondCopyOrigin)]
    }

    // MARK: The Building UI desk

    /// The screen every Building UI guide that brings one is built on: a phone
    /// shaped box on a grey page, with room either side of it so the guide that
    /// has you DRAW one has somewhere to drag.
    ///
    /// It sits 120 down the page on purpose, and that is not a taste decision.
    /// A step that points at the whole canvas has no side of the canvas to sit
    /// beside, so its callout is drawn INSIDE the picture, along the top
    /// (`TutorialCalloutLayout.insideSurface`). At this window size that card
    /// reaches about 113 points down, dead centre. A screen starting any higher
    /// has its first card read out from behind the very card talking about it.
    static let screenFrame = CGRect(x: 200, y: 120, width: 320, height: 344)

    /// How far down a sample's picture the callout of a step that points at the
    /// whole CANVAS reaches, measured on the probe at the size a tutorial
    /// window opens at.
    ///
    /// A canvas fills the window bar the panel, so no side of it has room for a
    /// card and the placement draws the card inside the picture instead, along
    /// the top and centred (`TutorialCalloutLayout.insideSurface`). Nothing a
    /// step is talking about may sit in that band, which is why every screen
    /// here starts below it. Generous: the band is about 113 points at the
    /// window size these guides open at, and a wordier step is a taller card.
    public static let calloutSkirt: CGFloat = 120
    /// What that screen is called. A name, not "Frame 1": the canvas draws it
    /// above the top left corner and two guides ask you to click it.
    static let screenName = "Home"
    /// One of the three cards down it, inset from the screen's left and right
    /// edges by hand. The padding guide is the one that hands those insets over
    /// to the screen itself.
    static let cardInset: CGFloat = 24
    static let cardHeight: CGFloat = 72

    /// The three cards, in the screen's own space, at the tops given.
    private static func screenCards(tops: [CGFloat], inset: CGFloat) -> [Layer] {
        let width = screenFrame.width - inset * 2
        return zip(cardNames, tops).map { name, top in
            // A soft grey, not white. A white card on a white screen is a
            // hairline, and every guide here is about watching cards MOVE.
            box(name, CGRect(x: inset, y: top, width: width, height: cardHeight),
                radius: 12, fill: "#E4E9F2", stroke: nil)
        }
    }

    /// Named after what a row of a screen usually is, so a step can say "the
    /// middle card" and a person can see which one that is.
    private static let cardNames = ["Today", "This Week", "Everything"]

    private static func screen(children: [Layer], layout: GroupLayout?,
                              stretches: Bool = false) -> Layer {
        var content = GroupContent(children: children, isFrame: true, backgroundHex: "#FFFFFF")
        content.layout = layout
        // A card on a real screen is as wide as the screen lets it be, and
        // that is the whole reason the padding guide works: type a number and
        // the cards come IN rather than sliding sideways and being cut off at
        // the far edge, which is what a fixed width card does inside a screen
        // that clips.
        if stretches { content.contentPlacement = LayerPlacement(horizontal: .stretch) }
        return Layer(name: screenName, content: .group(content), frame: screenFrame)
    }

    /// The arranging guide's page: a screen whose three cards were dropped in
    /// one at a time, at 44 and then 36 apart, which is exactly what spacing by
    /// eye looks like. Handing it to the screen reads the average back, so
    /// nothing jumps and the row tidies itself in one press.
    ///
    /// Too LOOSE rather than too tight, so the gap the guide then types is a
    /// smaller number. A screen is a fixed box: growing the gap on a screen
    /// whose cards already fill it pushes the last one past the bottom, and the
    /// guide would be teaching a number that breaks the thing it is teaching on.
    private static func handPlacedScreen() -> Layer {
        screen(children: screenCards(tops: [24, 140, 248], inset: cardInset), layout: nil)
    }

    /// The padding guide's page: the same three cards, already stacked evenly
    /// and running the full width of the screen with nothing clear at its
    /// edges. A screen with room already at its edges has nothing to show when
    /// you type a number into Padding.
    private static func tightScreen() -> Layer {
        let layout = GroupLayout(kind: .stack, direction: .column, gap: 24)
        return screen(children: screenCards(tops: [0, 96, 192], inset: 0), layout: layout,
                      stretches: true)
    }

    /// The lining-up guide's page: three boxes at three different heights,
    /// spaced 32 and then 84 apart, with clear page down the left of them to
    /// start a selection from. Down the LEFT rather than above: a step pointing
    /// at the canvas puts its callout across the top middle of the picture, so
    /// the room above them is room somebody cannot reach.
    private static func crookedBoxes() -> [Layer] {
        [
            box("Left", CGRect(x: 96, y: 180, width: 140, height: 84),
                radius: 12, fill: "#E4E9F2", stroke: nil),
            box("Middle", CGRect(x: 268, y: 216, width: 140, height: 84),
                radius: 12, fill: "#E4E9F2", stroke: nil),
            box("Right", CGRect(x: 492, y: 164, width: 140, height: 84),
                radius: 12, fill: "#E4E9F2", stroke: nil),
        ]
    }

    /// A label sitting in the middle of a box, measured first so it really is
    /// in the middle. A button whose words are off to one side reads as a
    /// mistake in the sample rather than as a button.
    private static func centered(_ name: String, _ string: String, in frame: CGRect,
                                 size: CGFloat, color: String, weight: TextWeight) -> Layer {
        let content = TextContent(string: string, fontSize: size, colorHex: color, weight: weight)
        let measured = TextMeasurement.size(of: content, wrappingAt: frame.width)
        let origin = CGPoint(x: frame.midX - measured.width / 2,
                             y: frame.midY - measured.height / 2)
        return Layer(name: name, content: .text(content),
                     frame: CGRect(origin: origin, size: measured))
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

    // MARK: The icon workbench

    /// The frame the whole Icons track is drawn on: 24 points square, which is
    /// the size interface iconography is designed at and the size the keylines
    /// are worked out from.
    ///
    /// Its corner sits on a whole number of grid cells, so the four point lines
    /// the canvas draws run along the frame's own edges. A frame parked half a
    /// cell off would teach the opposite of what the track is for.
    public static let iconFrameBox = CGRect(x: 348, y: 228, width: 24, height: 24)

    /// The line a shape takes on a 24 point frame (`IconStrokeWeight`), so a
    /// sample looks exactly like something you had just drawn there.
    private static let iconStroke: CGFloat = 2

    private static func iconFrame(holding children: [Layer]) -> Layer {
        Layer.frameLayer(name: "Icon", origin: iconFrameBox.origin,
                         size: iconFrameBox.size, children: children)
    }

    /// A bookmark, five hard corners, every one of them on a crossing of the
    /// four point grid and every one inside the keylines.
    ///
    /// Corners rather than curves on purpose: the reshaping guide's first real
    /// lesson is double clicking a point to bend it, and a shape that arrived
    /// bent has nothing to bend.
    private static func drawnBookmark() -> Layer {
        let points = [CGPoint(x: 4, y: 4), CGPoint(x: 20, y: 4), CGPoint(x: 20, y: 20),
                      CGPoint(x: 12, y: 16), CGPoint(x: 4, y: 20)]
        let content = PathContent(anchors: points.map { PathAnchor(point: $0) },
                                  isClosed: true,
                                  paint: Paint(hex: PathContent.defaultColorHex),
                                  strokeWidth: iconStroke,
                                  fill: Paint(hex: PathContent.defaultColorHex))
        return PathBuilder.layer(content, at: CGPoint(x: 4, y: 4), name: "Bookmark")
    }

    /// A rounded box on the same frame, which is a box and nothing more until
    /// somebody turns it into a path.
    private static func iconRoundedBox() -> Layer {
        box("Box", CGRect(x: 4, y: 4, width: 16, height: 16),
            radius: 4, fill: PathContent.defaultColorHex, stroke: nil)
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
