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

    /// Back of the picture first, the way a document stores its layers. The
    /// panel turns that round and shows the front at the top.
    public static func layers(for sample: TutorialSample) -> [Layer] {
        switch sample {
        case .starterScreen: starterScreen()
        // A window with nothing in it. The app puts no canvas under this one
        // either, so the window opens on its onboarding card, which is the
        // whole point of it.
        case .emptyWindow: []
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
