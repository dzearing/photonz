import CoreGraphics
import Foundation

/// The user's current text styling, fed by the font picker and applied to new
/// text blocks. Mirrors `AnnotationStyles`: Codable so it persists across
/// launches, value-typed so the popover edits are testable.
public struct TextStyles: Equatable, Codable, Sendable {
    public var fontName: String
    public var fontSize: CGFloat
    public var weight: TextWeight
    public var colorHex: String

    public init(fontName: String = "SF Pro",
                fontSize: CGFloat = 24,
                weight: TextWeight = .regular,
                colorHex: String = "#FFFFFF") {
        self.fontName = fontName
        self.fontSize = fontSize
        self.weight = weight
        self.colorHex = colorHex
    }

    /// The font picker's family choices. Curated: families that ship with
    /// macOS and read well as screenshot callouts.
    // Curated set. "SF Pro"/"SF Mono" are the system UI faces (resolved specially
    // in TextRasterizer — they aren't matchable by family name); the rest are
    // installed families. ("New York" was dropped: it's only reachable via
    // AppKit's design API, which the render layer can't import — Baskerville is a
    // real serif that resolves through CoreText.)
    public static let fonts: [String] = [
        "SF Pro",
        "SF Mono",
        "Helvetica Neue",
        "Avenir Next",
        "Georgia",
        "Baskerville",
    ]

    /// A family whose name is longer than the box the Font menu is held to, so
    /// the menu has to shorten it and say the whole thing on hover instead.
    ///
    /// There is no way through the UI to reach a state like this — the menu
    /// only offers a family once a label already wears it — so a scripted walk
    /// checking that behaviour asks for this one directly. It is a stock macOS
    /// family, and it works even where it is not installed: the menu shows the
    /// name it was given whether or not anything can draw it.
    public static let longNameForPlaytest = "Bodoni 72 Smallcaps"

    /// A size of three digits, which is the widest number the Size menu holds
    /// room for. The menu offers seven sizes and every one of them is two
    /// digits, so a walk that wants to see the box at full stretch asks for
    /// this one directly, the way it asks for a long family name.
    public static let threeDigitSizeForPlaytest: CGFloat = 128

    /// The curated family a walk puts the labels back into: one the box has
    /// room for, so the menu shows it whole and says only what the row reaches.
    public static var shortNameForPlaytest: String { fonts[0] }

    /// The size picker's options, smallest first.
    public static let fontSizes: [CGFloat] = [14, 18, 24, 32, 48, 64, 96]

    /// The words a size wears in the Size menu: the number, the unit, and
    /// enough blank after it that every size takes the same room.
    ///
    /// A Mac pop-up takes its width from the widest row in its LIST, not from
    /// the one showing, and it will not accept a frame wider than that, so the
    /// only way the Size box can hold one width is for every row to be the same
    /// width. The list is not fixed — it picks up any size the picked labels
    /// already wear, and it grows the word Mixed when they disagree — so the
    /// box used to change size on an ordinary two-label selection.
    ///
    /// The blank is U+2007 FIGURE SPACE, which is defined as the width of a
    /// digit and measures exactly that in the menu font: one, two and three
    /// digit sizes come out at 62, 69 and 76pt unpadded, and every padded one
    /// at 76pt. Mixed needs 72pt, which is under it. It goes AFTER the unit, so
    /// the number stays flush against the left of the box and the open menu
    /// reads exactly as it always has.
    ///
    /// A size of 1000pt or more has four digits and is wider than the room held
    /// for it, so it still grows the box. It is spelled out anyway: a size
    /// shortened to "102..." is a number nobody can read, which is worse than a
    /// box that grew.
    public static func sizeTitle(_ size: CGFloat) -> String {
        let words = sizeWords(size)
        let digits = words.prefix { $0.isNumber }.count
        return words + String(repeating: sizePad, count: max(0, sizeDigits - digits))
    }

    /// The same words with nothing padding them, for anything that says a size
    /// in a sentence rather than drawing it in a box.
    public static func sizeWords(_ size: CGFloat) -> String {
        DocumentUnit.text(digits: String(Int(size)))
    }

    /// What a padded title says, for anything reading a control back: a walk
    /// asking what the Size menu shows must get the words a person reads, not
    /// the blank held behind them.
    public static func unpadded(_ title: String) -> String {
        String(title.reversed().drop { $0 == sizePad }.reversed())
    }

    /// The blank a size title is padded with: one digit wide, and invisible.
    private static let sizePad: Character = "\u{2007}"

    /// How many digits of room every size title holds. Three covers every size
    /// anyone lays out with; a fourth would cost 7pt of panel width forever.
    private static let sizeDigits = 3

    /// The families the Font menu offers for a selection: the curated list, in
    /// its own order, then any family the picked labels already wear that is
    /// not on it. So a label opened from somewhere else keeps its face instead
    /// of losing it the moment it is picked.
    ///
    /// The curated part comes first and is always all there, which is what lets
    /// the menu hold ONE width: a Mac pop-up takes its size from the widest
    /// name in its list, so as long as the widest curated name is present in
    /// every state, that name, and nothing an opened document brought with it,
    /// decides how wide the box is.
    public static func fontOptions(picked: [String]) -> [String] {
        var seen = Set(fonts)
        return fonts + picked.filter { seen.insert($0).inserted }
    }

    /// Content for a new text block in the current style.
    public func content(string: String = "") -> TextContent {
        TextContent(string: string, fontName: fontName, fontSize: fontSize,
                    colorHex: colorHex, weight: weight)
    }

    /// Takes on an existing text layer's style, so re-editing seeds the picker
    /// with what that layer already looks like.
    public mutating func adopt(_ content: TextContent) {
        fontName = content.fontName
        fontSize = content.fontSize
        weight = content.weight
        colorHex = content.colorHex
    }
}

/// Builds text layers from a click point and a measured natural size.
/// Measurement itself needs CoreText, so it lives in PhotonzRender; this is
/// just the (tested) frame math.
public enum TextBuilder {

    /// What a text layer is called before anybody renames it. Named here so
    /// the places that treat it as "unnamed" agree with the place that sets it.
    public static let defaultLayerName = "Text"

    /// A text layer whose frame's top-left sits at the click point and whose
    /// size hugs the measured text. Degenerate measurements are clamped so the
    /// rasterizer always has at least a pixel to draw into. Every text layer
    /// gets the auto-contrast shadow (3.6) so it stays legible anywhere.
    public static func layer(content: TextContent, at point: CGPoint, naturalSize: CGSize) -> Layer {
        let frame = CGRect(x: point.x, y: point.y,
                           width: max(naturalSize.width, 1),
                           height: max(naturalSize.height, 1))
        var style = LayerStyle()
        style.shadow = autoContrastShadow(forColorHex: content.colorHex)
        return Layer(name: defaultLayerName, content: .text(content), frame: frame, style: style)
    }

    /// Props-panel restyle of an existing text layer (13.1): applies only the
    /// provided font face/size/weight/color, preserving identity and frame.
    /// Mirrors `AnnotationBuilder.restyled`. The frame is intentionally left
    /// untouched — re-measuring needs CoreText, so the app re-derives it via
    /// `TextRasterizer.naturalSize`. When the color changes, the auto-contrast
    /// shadow is refreshed so the new color stays legible; an unchanged color
    /// leaves the existing (possibly custom) shadow alone. Non-text layers pass
    /// through unchanged.
    public static func restyled(layer: Layer, fontName: String? = nil,
                                fontSize: CGFloat? = nil, weight: TextWeight? = nil,
                                colorHex: String? = nil) -> Layer {
        guard case .text(var content) = layer.content else { return layer }
        if let fontName { content.fontName = fontName }
        if let fontSize { content.fontSize = fontSize }
        if let weight { content.weight = weight }
        var updated = layer
        if let colorHex, colorHex != content.colorHex {
            content.colorHex = colorHex
            updated.style.shadow = autoContrastShadow(forColorHex: colorHex)
        }
        updated.content = .text(content)
        return updated
    }

    /// A tight contour shadow opposing the text color's lightness: light text
    /// gets a dark halo, dark text a light one — keeps callouts readable on
    /// backgrounds that match the text.
    public static func autoContrastShadow(forColorHex hex: String) -> ShadowStyle {
        let luminance = (RGBA(hex: hex) ?? RGBA(r: 1, g: 1, b: 1)).relativeLuminance
        return ShadowStyle(radius: 2,
                           offset: CGSize(width: 0, height: 1),
                           colorHex: luminance >= 0.5 ? "#000000" : "#FFFFFF",
                           opacity: 0.6)
    }
}
