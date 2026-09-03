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

    /// The id a document's copy of this style takes when the document does not
    /// already have one. Fixed, so two starters dropped a week apart share one
    /// Accent rather than each bringing their own.
    public var styleID: UUID { StarterComponents.fixedID(kind: 0x01, index: index) }

    /// This style as the document would hold it, before anybody edits it.
    public var colorStyle: ColorStyle {
        ColorStyle(id: styleID, name: name, colorHex: colorHex)
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
    public static let textSlack: CGFloat = 4

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
        return Layer(name: kind.name,
                     content: .group(GroupContent(children: children,
                                                  componentID: kind.componentID)),
                     frame: .zero)
    }

    /// About how big a piece of text is, without CoreText. Only used where the
    /// real thing is not available: it is close enough that a test can check
    /// the ordering of the pieces, and never what the app draws with.
    public static func estimatedTextSize(_ text: TextContent) -> CGSize {
        let perGlyph: CGFloat = text.weight == .regular ? 0.52 : 0.55
        let width = CGFloat(text.string.count) * text.fontSize * perGlyph
        return CGSize(width: max(width, text.fontSize / 2).rounded() + textSlack,
                      height: (text.fontSize * 1.22).rounded() + textSlack)
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
                 strokeWidth: CGFloat = 0) -> Layer {
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
                         colorStyleBindings: bindings)
        }

        /// A piece of text, hung from its vertical middle so it sits where a
        /// person expects however tall the line turns out to be. No contrast
        /// halo: that belongs on a caption over a screenshot, not on a label
        /// inside a control.
        func label(_ name: String, _ string: String, x: CGFloat, centerY: CGFloat,
                   size: CGFloat, weight: TextWeight = .regular, color: StarterStyle) -> Layer {
            let content = TextContent(string: string, fontSize: px(size),
                                      colorHex: palette.style(color).colorHex, weight: weight)
            let natural = measure(content)
            let frame = CGRect(x: x, y: (px(centerY) - natural.height / 2).rounded(),
                               width: natural.width, height: natural.height)
            return Layer(name: name, content: .text(content), frame: frame,
                         colorStyleBindings: [ColorStyleBinding(slot: .text,
                                                                styleID: palette.style(color).id)])
        }

        /// The same, centred across a width: the glyphs are centred, not the
        /// frame, so the measuring slack does not push the word off centre.
        func centeredLabel(_ name: String, _ string: String, across width: CGFloat,
                           centerY: CGFloat, size: CGFloat, weight: TextWeight = .regular,
                           color: StarterStyle) -> Layer {
            var layer = label(name, string, x: 0, centerY: centerY, size: size,
                              weight: weight, color: color)
            let ink = max(layer.frame.width - textSlack, 1)
            layer.frame.origin.x = ((px(width) - ink) / 2).rounded()
            return layer
        }
    }

    // MARK: The five drawings

    /// 128 × 36. One filled box and a word in the middle of it.
    private static func button(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 128, height: 36, radius: 8, fill: .accent),
         pen.centeredLabel("Label", "Button", across: 128, centerY: 18, size: 14,
                           weight: .semibold, color: .surface)]
    }

    /// 220 × 32. A hairline box with quiet wording sitting in from the left.
    private static func textField(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 220, height: 32, radius: 6,
                 fill: .surface, stroke: .border, strokeWidth: 1),
         pen.label("Placeholder", "Placeholder", x: pen.px(10), centerY: 16, size: 13,
                   color: .muted)]
    }

    /// 260 × 180. A picture well, a title and a line under it — the shape most
    /// cards are, and the one that shows what a show-or-hide knob is for.
    private static func card(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 260, height: 180, radius: 12,
                 fill: .surface, stroke: .border, strokeWidth: 1),
         pen.box("Picture", x: 12, y: 12, width: 236, height: 96, radius: 8, fill: .border),
         pen.label("Title", "Card title", x: pen.px(14), centerY: 126, size: 16,
                   weight: .semibold, color: .text),
         pen.label("Body", "Supporting text goes here.", x: pen.px(14), centerY: 152,
                   size: 13, color: .muted)]
    }

    /// 320 × 48. A surface, a hairline along the bottom, a centred title and a
    /// back label you can turn off.
    private static func navBar(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 320, height: 48, fill: .surface),
         pen.box("Divider", x: 0, y: 47, width: 320, height: 1, fill: .border),
         pen.label("Back", "Back", x: pen.px(14), centerY: 24, size: 15, color: .accent),
         pen.centeredLabel("Title", "Title", across: 320, centerY: 24, size: 15,
                           weight: .semibold, color: .text)]
    }

    /// 26 × 20. The smallest thing on the shelf, and the one that shows a
    /// component does not have to be big.
    private static func badge(_ pen: Pen) -> [Layer] {
        [pen.box("Background", x: 0, y: 0, width: 26, height: 20, radius: 10, fill: .accent),
         pen.centeredLabel("Count", "3", across: 26, centerY: 10, size: 12,
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
