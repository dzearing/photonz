import CoreGraphics
import Foundation

/// The persisted, per-shape styling new annotations start with. Each annotation
/// type (arrow, line, rectangle, ellipse, highlight) remembers its OWN color,
/// stroke width, and (arrows) arrowhead scale — so picking a bold blue arrow
/// doesn't change your lines, and the next arrow you draw reuses the last arrow
/// settings. Codable so it survives launches.
public struct AnnotationStyles: Equatable, Codable, Sendable {
    /// Per-shape defaults, keyed by `AnnotationShape.rawValue`.
    private var shapes: [String: ShapeDefaults]

    public init() {
        var shapes: [String: ShapeDefaults] = [:]
        for shape in AnnotationShape.allCases {
            shapes[shape.rawValue] = ShapeDefaults.standard(for: shape)
        }
        self.shapes = shapes
    }

    private enum CodingKeys: String, CodingKey {
        case shapes
        // Legacy single-bucket keys (pre per-shape); migrated on decode.
        case strokeColorHex, highlightColorHex, strokeWidth, arrowheadScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try c.decodeIfPresent([String: ShapeDefaults].self, forKey: .shapes) {
            var shapes = decoded
            // Backfill any shape added after the prefs were written.
            for shape in AnnotationShape.allCases where shapes[shape.rawValue] == nil {
                shapes[shape.rawValue] = ShapeDefaults.standard(for: shape)
            }
            self.shapes = shapes
        } else {
            // Migrate the old shared-bucket format: one stroke color/width for
            // all stroke shapes, a separate highlight color, one arrowhead scale.
            let strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColorHex) ?? "#FF3B30"
            let highlightColor = try c.decodeIfPresent(String.self, forKey: .highlightColorHex) ?? "#FFD60A"
            let width = try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? AnnotationContent.defaultStrokeWidth
            let headScale = try c.decodeIfPresent(CGFloat.self, forKey: .arrowheadScale)
                ?? AnnotationStyles.defaultArrowheadScale
            var shapes: [String: ShapeDefaults] = [:]
            for shape in AnnotationShape.allCases {
                shapes[shape.rawValue] = ShapeDefaults(
                    colorHex: shape == .highlight ? highlightColor : strokeColor,
                    strokeWidth: width,
                    arrowheadScale: headScale)
            }
            self.shapes = shapes
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shapes, forKey: .shapes)
    }

    // MARK: - Per-shape accessors

    private func defaults(forShape shape: AnnotationShape) -> ShapeDefaults {
        shapes[shape.rawValue] ?? ShapeDefaults.standard(for: shape)
    }

    public func colorHex(forShape shape: AnnotationShape) -> String { defaults(forShape: shape).colorHex }

    public func strokeWidth(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).strokeWidth }

    public func arrowheadScale(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).arrowheadScale }

    /// The non-destructive effects (shadow, opacity, blur, …) a NEW annotation
    /// of this shape starts with — captured from the last one the user styled,
    /// so e.g. adding a drop shadow to one arrow carries to the next.
    public func layerStyle(forShape shape: AnnotationShape) -> LayerStyle { defaults(forShape: shape).layerStyle }

    public mutating func setColorHex(_ hex: String, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].colorHex = hex
    }

    public mutating func setLayerStyle(_ style: LayerStyle, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].layerStyle = style
    }

    public mutating func setStrokeWidth(_ width: CGFloat, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].strokeWidth = width
    }

    public mutating func setArrowheadScale(_ scale: CGFloat, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].arrowheadScale = scale
    }

    // MARK: - Tool-keyed convenience (nil for non-annotation tools)

    public func colorHex(for tool: Tool) -> String? {
        guard let shape = tool.annotationShape else { return nil }
        return colorHex(forShape: shape)
    }

    /// The stroke width `tool` draws with: the shape's width for stroke tools,
    /// the fixed default for highlight/non-annotation tools.
    public func strokeWidth(for tool: Tool) -> CGFloat {
        guard let shape = tool.annotationShape, tool.usesStrokeWidth else {
            return AnnotationContent.defaultStrokeWidth
        }
        return strokeWidth(forShape: shape)
    }

    public func arrowheadScale(for tool: Tool) -> CGFloat {
        guard let shape = tool.annotationShape else { return AnnotationStyles.defaultArrowheadScale }
        return arrowheadScale(forShape: shape)
    }

    /// Routes a swatch pick to the bucket the active tool draws from.
    public mutating func setColorHex(_ hex: String, for tool: Tool) {
        guard let shape = tool.annotationShape else { return }
        setColorHex(hex, forShape: shape)
    }

    /// Styled content for a new annotation, nil for non-annotation tools.
    public func content(for tool: Tool) -> AnnotationContent? {
        guard let shape = tool.annotationShape else { return nil }
        let d = defaults(forShape: shape)
        // Highlight is a filled box; the stroke width slider doesn't touch it.
        let width = tool.usesStrokeWidth ? d.strokeWidth : AnnotationContent.defaultStrokeWidth
        return AnnotationContent(shape: shape, strokeWidth: width, colorHex: d.colorHex,
                                 arrowheadScale: d.arrowheadScale)
    }

    // MARK: - Defaults & palettes

    /// New arrows start at the head's base proportions (×1.0). See
    /// `Geometry.arrowhead`; the user scales from there with the Arrowhead slider.
    public static let defaultArrowheadScale: CGFloat = 1.0

    /// Adjustable ranges for the popover/inspector sliders.
    public static let strokeWidthRange: ClosedRange<CGFloat> = 1...40
    public static let arrowheadScaleRange: ClosedRange<CGFloat> = 0.5...5

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

    /// The arrowhead-size picker's options (multipliers), smallest first.
    public static let arrowheadScales: [CGFloat] = [0.7, 1.0, 1.5, 2.2]
}

/// One annotation type's persisted defaults.
public struct ShapeDefaults: Equatable, Codable, Sendable {
    public var colorHex: String
    public var strokeWidth: CGFloat
    public var arrowheadScale: CGFloat
    /// Non-destructive effects (shadow/opacity/blur/border/corner) new objects
    /// of this shape inherit.
    public var layerStyle: LayerStyle

    public init(colorHex: String, strokeWidth: CGFloat, arrowheadScale: CGFloat,
                layerStyle: LayerStyle = LayerStyle()) {
        self.colorHex = colorHex
        self.strokeWidth = strokeWidth
        self.arrowheadScale = arrowheadScale
        self.layerStyle = layerStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        // `arrowheadScale` may be absent in early per-shape prefs.
        arrowheadScale = try c.decodeIfPresent(CGFloat.self, forKey: .arrowheadScale)
            ?? AnnotationStyles.defaultArrowheadScale
        // `layerStyle` postdates per-shape prefs.
        layerStyle = try c.decodeIfPresent(LayerStyle.self, forKey: .layerStyle) ?? LayerStyle()
    }

    /// The smart default for a shape: red strokes, yellow highlight (system
    /// palette), 4pt stroke, ×1.0 arrowhead, no effects.
    static func standard(for shape: AnnotationShape) -> ShapeDefaults {
        ShapeDefaults(colorHex: shape == .highlight ? "#FFD60A" : "#FF3B30",
                      strokeWidth: AnnotationContent.defaultStrokeWidth,
                      arrowheadScale: AnnotationStyles.defaultArrowheadScale)
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
