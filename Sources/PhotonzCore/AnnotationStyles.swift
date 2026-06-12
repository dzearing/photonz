import CoreGraphics
import Foundation

/// The user's current annotation styling, fed by the style popover and applied
/// to every new annotation. Stroke shapes (arrow/line/rectangle/ellipse) share
/// one color; highlight keeps its own so picking blue arrows doesn't produce
/// blue highlights. Codable so it can persist across launches.
public struct AnnotationStyles: Equatable, Codable, Sendable {
    public var strokeColorHex: String
    public var highlightColorHex: String
    public var strokeWidth: CGFloat

    public init(strokeColorHex: String = "#FF3B30",
                highlightColorHex: String = "#FFD60A",
                strokeWidth: CGFloat = 4) {
        self.strokeColorHex = strokeColorHex
        self.highlightColorHex = highlightColorHex
        self.strokeWidth = strokeWidth
    }

    /// The swatch row, in display order (system palette).
    public static let swatches: [String] = [
        "#FF3B30", // red
        "#FF9500", // orange
        "#FFD60A", // yellow
        "#34C759", // green
        "#007AFF", // blue
        "#AF52DE", // purple
        "#FFFFFF", // white
        "#000000", // black
    ]

    /// The stroke width picker's options, thinnest first.
    public static let strokeWidths: [CGFloat] = [2, 4, 6, 10]

    /// The color new annotations from `tool` will get, nil for non-annotation tools.
    public func colorHex(for tool: Tool) -> String? {
        guard let shape = tool.annotationShape else { return nil }
        return colorHex(forShape: shape)
    }

    /// Routes a swatch pick to the bucket the active tool draws from.
    public mutating func setColorHex(_ hex: String, for tool: Tool) {
        guard let shape = tool.annotationShape else { return }
        setColorHex(hex, forShape: shape)
    }

    /// Styled content for a new annotation, nil for non-annotation tools.
    public func content(for tool: Tool) -> AnnotationContent? {
        guard let shape = tool.annotationShape, let color = colorHex(for: tool) else { return nil }
        // Highlight is a filled box; the stroke width slider doesn't touch it.
        let width = tool.usesStrokeWidth ? strokeWidth : AnnotationContent.defaultStrokeWidth
        return AnnotationContent(shape: shape, strokeWidth: width, colorHex: color)
    }
}

extension Tool {
    /// Whether the stroke width control applies to this tool. Highlight is a
    /// fill, everything else strokes.
    public var usesStrokeWidth: Bool {
        guard let shape = annotationShape else { return false }
        return shape != .highlight
    }
}

extension AnnotationContent {
    /// The stroke width annotations start with (also `init`'s default).
    public static let defaultStrokeWidth: CGFloat = 4
}
