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

    /// The size picker's options, smallest first.
    public static let fontSizes: [CGFloat] = [14, 18, 24, 32, 48, 64, 96]

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
        return Layer(name: "Text", content: .text(content), frame: frame, style: style)
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
