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
