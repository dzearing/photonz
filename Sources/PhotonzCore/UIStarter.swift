import CoreGraphics
import Foundation

/// The Design UI start: what an empty window's Design UI row opens
/// (`docs/design/mocks/pages/ui-entry-wt.html`, steps 3 to 7).
///
/// A 1280 by 800 canvas holding one frame, Login, laid out as a column with a
/// headline, a line under it and two fields already in it, so the first thing
/// somebody does is drag a component from the Library onto it rather than
/// draw a frame and lay it out by hand. "The starter frame is an ordinary
/// frame. The template gave you a head start, not a mode": nothing here is a
/// new kind of thing. It is the same frame, the same column, the same text
/// and boxes a person would have made, so selecting, resizing, deleting and
/// undoing it are the app's ordinary commands.
public enum UIStarter {

    /// The canvas: the Laptop screen, what the mock's title bar reads.
    public static let canvasSize = CGSize(width: 1280, height: 800)

    /// What the empty window's card says on the row that starts one.
    public static let rowTitle = "Design UI"

    /// What File says for the same thing, beside New Video.
    public static let menuTitle = "New UI Design"

    /// The frame's name, which is what the Layers list and the canvas tag read.
    public static let frameName = "Login"
    /// How wide the frame is drawn. Its height is what its rows add up to.
    public static let frameWidth: CGFloat = 320
    /// The room between rows and around the edges, the mock's Properties.
    public static let gap: CGFloat = 12
    public static let padding: CGFloat = 24

    /// The window's name before it is saved: "untitled-ui", then
    /// "untitled-ui 2" and on, so two of them open at once are tellable apart.
    public static func documentName(number: Int) -> String {
        number <= 1 ? "untitled-ui" : "untitled-ui \(number)"
    }

    /// The whole document: the canvas with Login in its middle.
    ///
    /// - Parameter measure: how to size a piece of text. The app passes the
    ///   rasterizer's own measurement; everything else gets the estimate the
    ///   starter components use.
    public static func document(measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize)
        -> PhotonzDocument {
        var frame = loginFrame(measure: measure)
        frame.frame.origin = CGPoint(x: ((canvasSize.width - frame.frame.width) / 2).rounded(),
                                     y: ((canvasSize.height - frame.frame.height) / 2).rounded())
        return PhotonzDocument(canvasSize: canvasSize, layers: [frame])
    }

    /// Login on its own, at the origin, already laid out.
    public static func loginFrame(measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize)
        -> Layer {
        let inner = frameWidth - padding * 2
        let children = [
            label("Headline", "Welcome back", size: 21, weight: .bold, colorHex: ink, measure: measure),
            label("Subhead", "Sign in to continue", size: 12, weight: .regular, colorHex: quiet,
                  measure: measure),
            field("Email field", placeholder: "you@example.com", width: inner, measure: measure),
            field("Password field", placeholder: "••••••••", width: inner, measure: measure),
        ]
        var layout = GroupLayout(kind: .stack, direction: .column, gap: gap,
                                 padding: GroupPadding(padding))
        // The frame closes around its rows, so dropping a button into the
        // column makes the screen taller rather than spilling past its foot.
        layout.screenHugsHeight = true
        var made = Layer.frameLayer(name: frameName, origin: .zero,
                                    size: CGSize(width: frameWidth, height: 1),
                                    children: children)
        made.setGroupLayout(layout)
        // Everything in the column runs its width, the rows it starts with and
        // whatever is dropped in after them, so a Button off the shelf lands
        // as the full-width Sign in bar the mock draws, not a pill at the left.
        if case .group(var group) = made.content {
            group.contentPlacement = LayerPlacement(horizontal: .stretch)
            made.content = .group(group)
        }
        made.style.cornerRadius = 16
        // The mock's lift off the canvas: an ordinary Shadow in the frame's
        // Effects, so it can be tuned or taken off like any other.
        made.style.effects.append(.shadow(ShadowStyle(radius: 23, offset: CGSize(width: 0, height: 22),
                                                      spread: -14, opacity: 0.45)))
        return GroupFlow.flowing(made)
    }

    // MARK: - The pieces

    /// The mock's colors: near black for the headline, a grey for the line
    /// under it, a hairline for a field's edge and a quieter grey for what a
    /// field says before anybody types in it. Dark on the frame's white in
    /// both light and dark mode, because the frame is white in both.
    private static let ink = "#1D1D1F"
    private static let quiet = "#6B6B70"
    private static let hairline = "#D6D6DA"
    private static let placeholder = "#8A8A8F"
    private static let fieldHeight: CGFloat = 36

    /// A row of text that runs the width of the column.
    private static func label(_ name: String, _ string: String, size: CGFloat, weight: TextWeight,
                              colorHex: String, measure: StarterTextMeasure) -> Layer {
        let content = TextContent(string: string, fontSize: size, colorHex: colorHex, weight: weight)
        return Layer(name: name, content: .text(content),
                     frame: CGRect(origin: .zero, size: measure(content)),
                     placement: LayerPlacement(horizontal: .stretch))
    }

    /// A field: a white box with a hairline edge, 36 tall, with its quiet
    /// words 12 in from the left and centred down it. Built the way the Text
    /// field starter is, a box behind and words on top, so it takes apart the
    /// same way.
    private static func field(_ name: String, placeholder words: String, width: CGFloat,
                              measure: StarterTextMeasure) -> Layer {
        var box = AnnotationContent(shape: .rectangle, start: .zero,
                                    end: CGPoint(x: width, y: fieldHeight))
        box.strokeWidth = 1
        box.cornerRadius = 9
        box.colorHex = hairline
        box.fillColorHex = "#FFFFFF"
        let background = Layer(name: "Background", content: .annotation(box),
                               frame: CGRect(x: 0, y: 0, width: width, height: fieldHeight),
                               placement: .fill)
        let text = TextContent(string: words, fontSize: 13, colorHex: placeholder, weight: .regular)
        let natural = measure(text)
        let ink = max(natural.height - StarterComponents.textSlack, 1)
        let words = Layer(name: "Placeholder", content: .text(text),
                          frame: CGRect(x: 12, y: ((fieldHeight - ink) / 2).rounded(),
                                        width: natural.width, height: natural.height),
                          placement: LayerPlacement(horizontal: .stretch))
        var content = GroupContent(children: [background, words])
        content.layout = .free(padding: GroupPadding(top: 0, right: 12, bottom: 0, left: 12),
                               height: fieldHeight)
        return Layer(name: name, content: .group(content),
                     frame: CGRect(x: 0, y: 0, width: width, height: fieldHeight),
                     placement: LayerPlacement(horizontal: .stretch))
    }
}
