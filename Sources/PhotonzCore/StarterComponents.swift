import CoreGraphics
import Foundation

/// The components the app brings with it (`docs/design/ui-building.md`,
/// step D7, "Useful on arrival").
///
/// A Library that starts empty is a chore: the first thing it asks of you is
/// to build the thing you came to use. So the shelf ships with five ordinary
/// components on it — a button, a text field, a card, a nav bar and a badge —
/// and the first thing you do is drag one out.
///
/// Three rules hold this together:
///
/// - **They are data, not views.** A starter is a plain subtree of the same
///   boxes and text layers a person draws by hand, so once it is in a document
///   nothing about it is special: it takes knobs, it takes copies, it takes
///   overrides, it comes apart. Nothing downstream learns a new word.
/// - **A starter's id IS its component id**, fixed for the life of the app. So
///   dropping the same one twice places a COPY of the first rather than a
///   second original, one shelf tile covers both the untaken and the taken
///   case, and a document saved today opens tomorrow still pointing at it.
/// - **They paint from named styles.** Every color a starter wears is a style
///   the drop brings into the document, so re-coloring "Accent" once repaints
///   every starter wearing it — which is the whole argument for styles, made
///   with something you did not have to build first.
///
/// Deliberately a NEUTRAL KIT rather than a convincing set of macOS controls.
/// A button that looks exactly like the system's invites people to expect the
/// system's behaviour from it — focus rings, pressed states, real hit testing —
/// and this is a drawing, not a control. Looking like a starting point is the
/// honest thing for it to look like.

// MARK: - The colors they are painted from

/// One of the named colors the starter set paints from. Five is enough to
/// build all of them and few enough that the Styles shelf is still readable
/// the first time you look at it.
public enum StarterStyle: String, CaseIterable, Hashable, Sendable {
    /// The one color that says "this is the important thing on screen".
    case accent
    /// What a control or a card sits on.
    case surface
    /// Reading text.
    case text
    /// Secondary text, and the quiet things beside it.
    case muted
    /// Hairlines and the edges of things.
    case border

    /// The name it wears on the Styles shelf. Plain words, and short enough to
    /// fit under a swatch.
    public var name: String {
        switch self {
        case .accent: return "Accent"
        case .surface: return "Surface"
        case .text: return "Text"
        case .muted: return "Muted"
        case .border: return "Border"
        }
    }

    /// What it is painted before anybody changes it.
    public var colorHex: String {
        switch self {
        case .accent: return "#3B7DF5"
        case .surface: return "#FFFFFF"
        case .text: return "#1C1C1E"
        case .muted: return "#8A8A8E"
        case .border: return "#D8D8DE"
        }
    }

    /// The parts of a layer this one is offered for, so a color row only shows
    /// the colors that belong in it. Accent is the one that goes both ways: it
    /// is the fill of a button and the color of a link, and pretending
    /// otherwise would make somebody save the same blue twice.
    public var roles: [ColorStyleRole] {
        switch self {
        case .accent: return [.ink, .surface]
        case .surface: return [.surface]
        case .text, .muted, .border: return [.ink]
        }
    }

    /// The id a document's copy of this style takes when the document does not
    /// already have one. Fixed, so two starters dropped a week apart share one
    /// Accent rather than each bringing their own.
    public var styleID: UUID { StarterComponents.fixedID(kind: 0x01, index: index) }

    /// This style as the document would hold it, before anybody edits it.
    public var colorStyle: ColorStyle {
        ColorStyle(id: styleID, name: name, colorHex: colorHex, roles: roles)
    }

    private var index: UInt8 {
        switch self {
        case .accent: return 1
        case .surface: return 2
        case .text: return 3
        case .muted: return 4
        case .border: return 5
        }
    }
}

/// The colors a starter is being built with right now: the app's own, or the
/// document's, when the document already keeps a style of that name.
public struct StarterPalette: Hashable, Sendable {
    private var styles: [StarterStyle: ColorStyle]

    public init(_ styles: [StarterStyle: ColorStyle] = [:]) {
        self.styles = styles
    }

    /// The app's own colors, which is what a preview on the shelf is drawn in.
    public static let standard = StarterPalette()

    /// The style a slot paints from, the document's if it has one.
    public func style(_ style: StarterStyle) -> ColorStyle {
        styles[style] ?? style.colorStyle
    }
}

// MARK: - The five

/// One of the components the app ships with.
public enum StarterComponent: String, CaseIterable, Identifiable, Hashable, Sendable {
    case button
    case textField
    case card
    case navBar
    case badge

    public var id: String { rawValue }

    /// The name the shelf tile, the layers list and the canvas mark all print.
    public var name: String {
        switch self {
        case .button: return "Button"
        case .textField: return "Text Field"
        case .card: return "Card"
        case .navBar: return "Nav Bar"
        case .badge: return "Badge"
        }
    }

    /// One line for the tile's tooltip and the shelf section: what it is for,
    /// not what it is made of.
    public var summary: String {
        switch self {
        case .button: return "A filled button with a label you can change."
        case .textField: return "An empty field with placeholder wording."
        case .card: return "A picture, a title and a line of supporting text."
        case .navBar: return "A title bar with a back label you can hide."
        case .badge: return "A small count that sits on top of something."
        }
    }

    /// This component's identity, the same in every document and every launch.
    public var componentID: UUID { StarterComponents.fixedID(kind: 0x02, index: index) }

    /// The starter a component id belongs to, nil for one somebody drew.
    public init?(componentID: UUID) {
        guard let match = StarterComponent.allCases.first(where: { $0.componentID == componentID })
        else { return nil }
        self = match
    }

    /// The knobs a copy of it offers, named for the thing they adjust and in
    /// the order a copy's panel lists them. Wording first, because it is the
    /// one everybody reaches for.
    public var knobs: [StarterKnob] {
        switch self {
        case .button:
            return [StarterKnob(name: "Label", kind: .text, target: "Label")]
        case .textField:
            return [StarterKnob(name: "Placeholder", kind: .text, target: "Placeholder")]
        case .card:
            return [StarterKnob(name: "Title", kind: .text, target: "Title"),
                    StarterKnob(name: "Body", kind: .text, target: "Body"),
                    StarterKnob(name: "Picture", kind: .visible, target: "Picture")]
        case .navBar:
            return [StarterKnob(name: "Title", kind: .text, target: "Title"),
                    StarterKnob(name: "Back", kind: .visible, target: "Back")]
        case .badge:
            return [StarterKnob(name: "Count", kind: .text, target: "Count")]
        }
    }

    /// The named colors this one actually paints from, so a drop brings those
    /// and nothing else: a document that only ever took a Button has no
    /// Border style sitting unused on its shelf.
    public var usedStyles: [StarterStyle] {
        var found: [StarterStyle] = []
        let byID = Dictionary(StarterStyle.allCases.map { ($0.styleID, $0) },
                              uniquingKeysWith: { first, _ in first })
        for layer in StarterComponents.layer(self).selfAndDescendants {
            for binding in layer.colorStyleBindings ?? [] {
                guard let style = byID[binding.styleID], !found.contains(style) else { continue }
                found.append(style)
            }
        }
        return found
    }

    /// How this starter lines its contents up when somebody drags it wider or
    /// taller. A control centres its label; a card and a field start their
    /// contents at the left, because that is where a title and a first line
    /// begin; a bar is a row, which already decides across for itself, so all
    /// it says is halfway down. Any one piece inside says something different for itself where
    /// it needs to (`docs/design/ui-building.md`, "Resizing places the pieces").
    var contentPlacement: LayerPlacement {
        switch self {
        case .button, .badge: LayerPlacement(horizontal: .center, vertical: .center)
        case .textField: LayerPlacement(horizontal: .left, vertical: .center)
        // The bar is a row, and a row decides where its contents sit across
        // for itself. All the bar has left to say is that they sit halfway
        // down it, whatever it is told to be.
        case .navBar: LayerPlacement(vertical: .center)
        case .card: LayerPlacement(horizontal: .left, vertical: .top)
        }
    }

    /// One plain sentence saying which of this one's sides is the size of what
    /// is inside it and which is a number it was given.
    ///
    /// Written FROM the layout it is actually built with rather than typed out
    /// beside it, so it can never drift into describing a card that no longer
    /// exists. The Layout section says the same thing live for whatever is
    /// selected; this is the sentence for a page that has to explain the set.
    public var sizing: String { StarterComponents.sizing(self) }

    /// What the sentence above calls the things inside this one, on a side
    /// that is the size of them.
    var contentsNoun: String {
        switch self {
        case .button: "its label"
        case .textField: "its placeholder"
        case .card: "everything on it"
        case .navBar: "its title"
        case .badge: "its count"
        }
    }

    private var index: UInt8 {
        switch self {
        case .button: return 1
        case .textField: return 2
        case .card: return 3
        case .navBar: return 4
        case .badge: return 5
        }
    }
}

/// A knob a starter arrives with: what it is called, what it adjusts, and the
/// name of the piece inside it that it reaches.
public struct StarterKnob: Hashable, Sendable {
    public var name: String
    public var kind: ComponentPropertyKind
    /// The child layer's name. Names rather than ids because the subtree is
    /// built fresh on every drop, so there are no ids to quote until then.
    public var target: String

    public init(name: String, kind: ComponentPropertyKind, target: String) {
        self.name = name
        self.kind = kind
        self.target = target
    }
}

// MARK: - Drawing one

/// How wide a piece of text will be. The app hands in the real thing
/// (`TextRasterizer.naturalSize`); `PhotonzCore` is pure, so its own answer is
/// an estimate, good enough for a test and for the ordering of the pieces.
public typealias StarterTextMeasure = @Sendable (TextContent) -> CGSize

public enum StarterComponents {

    /// What a starter tile writes under its picture while it is still the
    /// app's rather than the document's.
    public static let shelfDetail = "starter"

    /// The slack `TextRasterizer.naturalSize` leaves around the glyphs
    /// (`frameInset` on each side). Centring reads the ink, not the slack,
    /// or every centred label sits two points right of centre.
    public static let textSlack: CGFloat = TextMeasurement.slack

    /// A starter's subtree, ready to be dropped into a document.
    ///
    /// - Parameters:
    ///   - scale: bitmap pixels per point. A capture's canvas is measured in
    ///     image pixels, so a Retina document builds its starters at 2.
    ///   - palette: the colors to paint from, the document's where it has them.
    ///   - measure: how to size a piece of text.
    public static func layer(_ kind: StarterComponent, scale: CGFloat = 1,
                             palette: StarterPalette = .standard,
                             measure: @escaping StarterTextMeasure = estimatedTextSize) -> Layer {
        let pen = Pen(scale: max(scale, 0.01), palette: palette, measure: measure)
        let children: [Layer]
        switch kind {
        case .button: children = button(pen)
        case .textField: children = textField(pen)
        case .card: children = card(pen)
        case .navBar: children = navBar(pen)
        case .badge: children = badge(pen)
        }
        var content = GroupContent(children: children,
                                   componentID: kind.componentID,
                                   contentPlacement: kind.contentPlacement)
        content.layout = layout(kind, pen)
        // A control that closes around its label is drawn already closed, so
        // the shelf tile, the drop outline and the thing that lands on the
        // canvas are all the same size before anything has been edited.
        return GroupFlow.flowing(Layer(name: kind.name, content: .group(content), frame: .zero))
    }

    /// How a starter sizes itself: which of its sides is a number somebody
    /// chose, and which is the size of what is inside it.
    ///
    /// Every one of the five answers that question, and none of them answers
    /// it the same way, because the honest answer depends on what the thing
    /// IS:
    ///
    /// - A **button** and a **badge** are a word with room around it, so they
    ///   are as wide as that word and as tall as a control that size is. Give
    ///   either a longer label and it gets wider on its own.
    /// - A **text field** is a place to type into, and how wide it is, is a
    ///   decision the person building the screen makes — a field 74 points
    ///   wide because "Name" is short is not a field. So the width is a
    ///   number, the wording wraps inside it, and the box grows downward to
    ///   hold whatever it wraps to.
    /// - A **card** is the same bargain one step up: 260 wide because that is
    ///   the card, and as tall as the picture, the title and the line under
    ///   them add up to. It is the one that ARRANGES rather than just closing
    ///   around things, because a title that wraps to two lines has to push
    ///   the line under it down rather than grow through it.
    /// - A **nav bar** is a box on both sides. A bar is as wide as the screen
    ///   it sits on and as tall as a bar is; neither is anything to do with
    ///   what its title says, and a title too long for it stays centred and
    ///   overhangs, exactly as it would in a real one.
    ///
    /// `pen` scales every number to the document, so a Retina capture gets a
    /// card 520 pixels wide rather than a half-size one.
    private static func layout(_ kind: StarterComponent, _ pen: Pen) -> GroupLayout? {
        switch kind {
        case .button:
            .free(padding: GroupPadding(top: pen.px(10), right: pen.px(16),
                                        bottom: pen.px(10), left: pen.px(16)),
                  height: pen.px(36))
        case .badge:
            .free(padding: GroupPadding(top: pen.px(3), right: pen.px(8),
                                        bottom: pen.px(3), left: pen.px(8)),
                  height: pen.px(20))
        case .textField:
            .free(padding: GroupPadding(top: pen.px(8), right: pen.px(10),
                                        bottom: pen.px(8), left: pen.px(10)),
                  width: pen.px(220))
        case .card:
            GroupLayout(kind: .stack, direction: .column, gap: pen.px(8),
                        padding: GroupPadding(pen.px(12)), width: pen.px(260))
        case .navBar:
            GroupLayout(kind: .stack, direction: .row, gap: pen.px(12),
                        padding: GroupPadding(top: 0, right: pen.px(14),
                                              bottom: 0, left: pen.px(14)),
                        width: pen.px(320), height: pen.px(48))
        }
    }

    /// The layout a starter is built with, at the size it is drawn at. What
    /// `StarterComponent.sizing` reads to write its sentence, and what a test
    /// checks that sentence against.
    public static func layout(_ kind: StarterComponent, scale: CGFloat = 1) -> GroupLayout? {
        layout(kind, Pen(scale: max(scale, 0.01), palette: .standard, measure: estimatedTextSize))
    }

    /// One sentence about one starter's two sides, written from the layout
    /// above so the words and the thing can never disagree.
    static func sizing(_ kind: StarterComponent) -> String {
        let layout = layout(kind)
        let noun = kind.contentsNoun
        let width = layout?.usedWidth
        let height = layout?.usedHeight
        switch (width, height) {
        case (let w?, let h?):
            return "A box \(number(w)) points wide and \(number(h)) points tall."
        case (let w?, nil):
            return "\(number(w)) points wide, and as tall as \(noun) "
                + "with the room above and below."
        case (nil, let h?):
            return "As wide as \(noun) with the room either side, and \(number(h)) points tall."
        case (nil, nil):
            return "As wide as \(noun) with the room either side, "
                + "and as tall as it with the room above and below."
        }
    }

    /// A measurement as somebody would say it out loud: no trailing nought on
    /// a number that is a whole one, which all of these are.
    private static func number(_ value: CGFloat) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", Double(value))
    }

    /// How big a piece of text is: the real measurement where the app has
    /// installed one, and the same estimate every other piece of this module
    /// falls back to where it has not.
    ///
    /// It goes through `TextMeasurement` rather than guessing on its own,
    /// because two estimates that disagree by a single point is enough to make
    /// a label look like a paragraph somebody had already narrowed — and then
    /// a longer word wraps down the page instead of making the control wider.
    public static func estimatedTextSize(_ text: TextContent) -> CGSize {
        TextMeasurement.size(of: text)
    }

    /// An id that is the same in every launch and every document, built from
    /// bytes rather than parsed from a string so there is no failure to
    /// swallow and no chance of a fresh id being minted behind our back.
    static func fixedID(kind: UInt8, index: UInt8) -> UUID {
        UUID(uuid: (0x5E, 0xED, 0x00, kind, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, index))
    }

    // MARK: The pen

    /// Everything the five drawings are written against: points scaled to the
    /// document, colors resolved to styles, text measured. Every number in a
    /// drawing below is in POINTS, which is what makes them readable.
    private struct Pen {
        let scale: CGFloat
        let palette: StarterPalette
        let measure: StarterTextMeasure

        func px(_ points: CGFloat) -> CGFloat { (points * scale).rounded() }

        /// A filled box. `radius` and `stroke` are in points too; a stroke
        /// width of zero means no border at all, which is what the rasterizer
        /// already reads it as.
        func box(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                 radius: CGFloat = 0, fill: StarterStyle?, stroke: StarterStyle? = nil,
                 strokeWidth: CGFloat = 0, placement: LayerPlacement? = nil) -> Layer {
            let size = CGSize(width: px(width), height: px(height))
            var annotation = AnnotationContent(shape: .rectangle,
                                               start: .zero,
                                               end: CGPoint(x: size.width, y: size.height))
            annotation.strokeWidth = stroke == nil ? 0 : max(px(strokeWidth), 1)
            annotation.cornerRadius = px(radius)
            annotation.fillColorHex = fill.map { palette.style($0).colorHex }
            // A box with no border still carries an ink color it does not
            // draw; painting it the border color keeps the inspector honest
            // when somebody turns the border on.
            annotation.colorHex = palette.style(stroke ?? .border).colorHex
            var bindings: [ColorStyleBinding] = []
            if let fill { bindings.append(ColorStyleBinding(slot: .fill, styleID: palette.style(fill).id)) }
            if let stroke {
                bindings.append(ColorStyleBinding(slot: .stroke, styleID: palette.style(stroke).id))
            }
            return Layer(name: name, content: .annotation(annotation),
                         frame: CGRect(origin: CGPoint(x: px(x), y: px(y)), size: size),
                         colorStyleBindings: bindings, placement: placement)
        }

        /// A piece of text, hung from its vertical middle so it sits where a
        /// person expects however tall the line turns out to be. No contrast
        /// halo: that belongs on a caption over a screenshot, not on a label
        /// inside a control.
        func label(_ name: String, _ string: String, x: CGFloat, centerY: CGFloat,
                   size: CGFloat, weight: TextWeight = .regular, color: StarterStyle,
                   align: TextAlign? = nil, placement: LayerPlacement? = nil) -> Layer {
            var content = TextContent(string: string, fontSize: px(size),
                                      colorHex: palette.style(color).colorHex, weight: weight)
            content.alignment = align
            let natural = measure(content)
            let frame = CGRect(x: x, y: (px(centerY) - natural.height / 2).rounded(),
                               width: natural.width, height: natural.height)
            return Layer(name: name, content: .text(content), frame: frame,
                         colorStyleBindings: [ColorStyleBinding(slot: .text,
                                                                styleID: palette.style(color).id)],
                         placement: placement)
        }

        /// The same, centred across a width: the glyphs are centred, not the
        /// frame, so the measuring slack does not push the word off centre.
        func centeredLabel(_ name: String, _ string: String, across width: CGFloat,
                           centerY: CGFloat, size: CGFloat, weight: TextWeight = .regular,
                           color: StarterStyle, placement: LayerPlacement? = nil) -> Layer {
            var layer = label(name, string, x: 0, centerY: centerY, size: size,
                              weight: weight, color: color, placement: placement)
            let ink = max(layer.frame.width - textSlack, 1)
            layer.frame.origin.x = ((px(width) - ink) / 2).rounded()
            return layer
        }
    }

    // MARK: The five drawings

    /// A word with 16 points either side of it, 36 tall. The fill behind the
    /// word stretches both ways, which makes it the SURFACE: it takes whatever
    /// box the word and its room add up to rather than deciding that box. So a
    /// longer label makes a wider button on its own, and dragging the button
    /// wider still keeps the word in the middle of a full-width pill.
    private static func button(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 128, height: 36, radius: 8, fill: .accent,
                 placement: .fill),
         pen.label("Label", "Button", x: pen.px(16), centerY: 18, size: 14,
                   weight: .semibold, color: .surface)]
    }

    /// 220 wide, and as tall as its wording needs. A hairline box with quiet
    /// words sitting in from the left; the words stretch across the room
    /// inside it, so a long placeholder wraps into the field rather than
    /// running out of the right-hand edge.
    private static func textField(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 220, height: 32, radius: 6,
                 fill: .surface, stroke: .border, strokeWidth: 1, placement: .fill),
         pen.label("Placeholder", "Placeholder", x: pen.px(10), centerY: 16, size: 13,
                   color: .muted, placement: LayerPlacement(horizontal: .stretch))]
    }

    /// 260 wide and as tall as what is on it: a picture well, a title and a
    /// line under it — the shape most cards are, and the one that shows what a
    /// show-or-hide knob is for.
    ///
    /// It is a COLUMN, unlike the other four, and that is the whole reason it
    /// works: a title long enough to wrap has to push the line under it down.
    /// A box that only closes around its contents would leave everything where
    /// it was put and let the second line of the title run through the first
    /// line of the body.
    ///
    /// The well says "stretch across", not "fill": a piece that stretches BOTH
    /// ways is read as the surface behind everything and painted to the card's
    /// own edges, which for the picture would mean covering the card.
    private static func card(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 260, height: 180, radius: 12,
                 fill: .surface, stroke: .border, strokeWidth: 1, placement: .fill),
         pen.box("Picture", x: 12, y: 12, width: 236, height: 96, radius: 8, fill: .border,
                 placement: LayerPlacement(horizontal: .stretch)),
         pen.label("Title", "Card title", x: pen.px(12), centerY: 126, size: 16,
                   weight: .semibold, color: .text,
                   placement: LayerPlacement(horizontal: .stretch)),
         pen.label("Body", "Supporting text goes here.", x: pen.px(12), centerY: 152,
                   size: 13, color: .muted,
                   placement: LayerPlacement(horizontal: .stretch))]
    }

    /// 320 × 48, both of them numbers. A bar is as wide as the screen it sits
    /// on and as tall as a bar is, so a longer title stays centred in it
    /// rather than stretching it. A surface, a hairline along the bottom, that
    /// centred title, and a back label you can turn off.
    ///
    /// It is a ROW, and it is the one starter that shows what a bar is made
    /// of. Three of its four pieces are not things the row lines up at all:
    /// the surface is painted to the bar's own edges, the hairline spans it
    /// and hugs its bottom, and the title spans it and centres its words on
    /// the whole bar rather than on the room the back label leaves. What is
    /// left in the row is the leading end of the bar, which starts with one
    /// label — drop a second control beside it and the row lines it up with no
    /// numbers typed anywhere.
    ///
    /// The three all say the same thing to get there: Stretch, along the way
    /// the row runs. See `GroupChromeTests`.
    private static func navBar(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 320, height: 48, fill: .surface,
                 placement: .fill),
         // A hairline stays a hairline: it spans the bar and hugs the bottom
         // rather than fattening up when the bar gets taller.
         pen.box("Divider", x: 0, y: 47, width: 320, height: 1, fill: .border,
                 placement: LayerPlacement(horizontal: .stretch, vertical: .bottom)),
         // The title is UNDER the controls, not over them. Its box is the
         // whole bar, so drawn on top it would swallow every click meant for
         // the back label and a title long enough to reach one would print
         // over it (found on 2026-09-05, driving the built bar).
         pen.label("Title", "Title", x: 0, centerY: 24, size: 15,
                   weight: .semibold, color: .text, align: .center,
                   placement: LayerPlacement(horizontal: .stretch, vertical: .center)),
         pen.label("Back", "Back", x: pen.px(14), centerY: 24, size: 15, color: .accent)]
    }

    /// The smallest thing on the shelf, 20 tall and as wide as the number in
    /// it: a count going from 3 to 128 is the plainest case there is for a
    /// control that closes around what it says.
    private static func badge(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 26, height: 20, radius: 10, fill: .accent,
                 placement: .fill),
         pen.label("Count", "3", x: pen.px(8), centerY: 10, size: 12,
                   weight: .semibold, color: .surface)]
    }
}

// MARK: - Taking one off the shelf

extension PhotonzDocument {

    /// The starters this document has not taken yet, as shelf items. One that
    /// HAS been taken is dropped from this list because the document already
    /// lists it — one tile per component, whether it came from the app or from
    /// your own hands.
    public var starterComponentEntries: [LibraryEntry] {
        // One walk of the tree, not one per starter: this is read on every
        // draw of the shelf, and a screen built out of fifty components is
        // exactly when it must not be counted five times over.
        let taken = Set(mainComponents.compactMap(\.componentID))
        return StarterComponent.allCases
            .filter { !taken.contains($0.componentID) }
            .map { LibraryEntry(id: $0.componentID.uuidString, scope: .components,
                                name: $0.name, detail: StarterComponents.shelfDetail) }
    }

    /// Puts a starter in the picture, centred on a canvas point, and returns
    /// the layer it placed.
    ///
    /// The first drop brings the ORIGINAL in, along with the named colors it
    /// paints from and the knobs it offers, and from then on it is an ordinary
    /// component of this document: edit it and every copy follows. Every drop
    /// after that places a copy, exactly as the shelf does for a component you
    /// made yourself, so there is never a second original claiming the name.
    @discardableResult
    public mutating func insertStarterComponent(
        _ kind: StarterComponent, at point: CGPoint,
        measure: @escaping StarterTextMeasure = StarterComponents.estimatedTextSize) -> UUID? {
        if mainComponent(componentID: kind.componentID) != nil {
            return insertComponentInstance(of: kind.componentID, at: point)
        }
        let palette = adoptStarterStyles(kind.usedStyles)
        var main = StarterComponents.layer(kind, scale: max(pixelScale, 1),
                                           palette: palette, measure: measure)
        let box = main.localBounds
        main.frame.origin = CGPoint(x: (point.x - box.width / 2).rounded(),
                                    y: (point.y - box.height / 2).rounded())
        addLayerDrawnOnFrame(main)
        addStarterKnobs(kind, to: main.id)
        return main.id
    }

    /// The styles a starter will paint from, brought into the document.
    ///
    /// A style already here wins, matched first by id and then by name, so
    /// somebody who has re-colored Accent gets their Accent on the next thing
    /// they drop, and somebody who named their own Accent does not end up with
    /// two of them.
    private mutating func adoptStarterStyles(_ wanted: [StarterStyle]) -> StarterPalette {
        var resolved: [StarterStyle: ColorStyle] = [:]
        for style in wanted {
            if let mine = colorStyle(id: style.styleID) ?? colorStyles.first(where: { $0.name == style.name }) {
                resolved[style] = mine
            } else {
                let fresh = style.colorStyle
                colorStyles.append(fresh)
                resolved[style] = fresh
            }
        }
        return StarterPalette(resolved)
    }

    /// The knobs a starter arrives with, hung on the pieces they adjust. Added
    /// through the ordinary command, so a starter's knobs are the same kind of
    /// thing as the ones you add by hand and nothing about them is privileged.
    private mutating func addStarterKnobs(_ kind: StarterComponent, to mainID: UUID) {
        guard let main = layer(id: mainID) else { return }
        for knob in kind.knobs {
            guard let target = main.children.first(where: { $0.name == knob.target }) else { continue }
            addComponentProperty(componentID: kind.componentID, target: target.id,
                                 kind: knob.kind, name: knob.name)
        }
    }
}
