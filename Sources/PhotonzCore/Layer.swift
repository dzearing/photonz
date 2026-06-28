import CoreGraphics
import Foundation

/// Reference to pixel data held outside the document model (in an `ImageStore`).
/// Keeping raw bitmaps out of the model keeps documents value-typed, Sendable,
/// diffable, and serializable.
public struct ImageRef: Hashable, Codable, Sendable {
    public let id: UUID
    public let pixelSize: CGSize

    public init(id: UUID = UUID(), pixelSize: CGSize) {
        self.id = id
        self.pixelSize = pixelSize
    }
}

public enum AnnotationShape: String, CaseIterable, Codable, Sendable {
    case arrow
    case rectangle
    case highlight
    case ellipse
    case line
}

/// Text weight, kept as its own model type (not a CTFont trait value) so the
/// core stays free of CoreText; the rasterizer maps it to font traits.
public enum TextWeight: String, CaseIterable, Hashable, Codable, Sendable {
    case regular
    case medium
    case semibold
    case bold
}

public struct TextContent: Hashable, Codable, Sendable {
    public var string: String
    public var fontName: String
    public var fontSize: CGFloat
    public var colorHex: String
    public var weight: TextWeight

    public init(string: String, fontName: String = "SF Pro", fontSize: CGFloat = 24,
                colorHex: String = "#FFFFFF", weight: TextWeight = .regular) {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.weight = weight
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        string = try container.decode(String.self, forKey: .string)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        // `weight` postdates TextContent; old payloads omit it.
        weight = try container.decodeIfPresent(TextWeight.self, forKey: .weight) ?? .regular
    }
}

public struct AnnotationContent: Hashable, Codable, Sendable {
    public var shape: AnnotationShape
    public var strokeWidth: CGFloat
    public var colorHex: String
    /// For arrows/lines: start and end in layer-local coordinates.
    public var start: CGPoint
    public var end: CGPoint
    /// Arrow-only: user-facing arrowhead size multiplier (1 = the bold default).
    public var arrowheadScale: CGFloat
    /// Rectangle-only: corner radius (layer-local units). 0 = sharp corners. The
    /// rasterizer draws a rounded-rect stroke, so the border follows the corners
    /// instead of being clipped away by a layer-level rounded mask.
    public var cornerRadius: CGFloat

    public init(shape: AnnotationShape, strokeWidth: CGFloat = 4, colorHex: String = "#FF3B30",
                start: CGPoint = .zero, end: CGPoint = .zero, arrowheadScale: CGFloat = 1,
                cornerRadius: CGFloat = 0) {
        self.shape = shape
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
        self.start = start
        self.end = end
        self.arrowheadScale = arrowheadScale
        self.cornerRadius = cornerRadius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = try c.decode(AnnotationShape.self, forKey: .shape)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        // `arrowheadScale` postdates AnnotationContent; old payloads omit it.
        arrowheadScale = try c.decodeIfPresent(CGFloat.self, forKey: .arrowheadScale) ?? 1
        // `cornerRadius` postdates AnnotationContent too.
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
    }
}

/// The silhouette of a zoom callout's box and its source outline. Circle is
/// drawn as a maximal rounded rect (a capsule when the box isn't square), so
/// box and outline read as the same shape at different aspect ratios.
public enum ZoomCalloutShape: String, CaseIterable, Hashable, Codable, Sendable {
    case rectangle
    case circle
}

public struct ZoomCalloutContent: Hashable, Codable, Sendable {
    /// Region of the canvas being magnified, in canvas coordinates.
    public var sourceRect: CGRect
    public var magnification: CGFloat
    public var shape: ZoomCalloutShape

    public init(sourceRect: CGRect, magnification: CGFloat = 2,
                shape: ZoomCalloutShape = .rectangle) {
        self.sourceRect = sourceRect
        self.magnification = magnification
        self.shape = shape
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceRect = try container.decode(CGRect.self, forKey: .sourceRect)
        magnification = try container.decode(CGFloat.self, forKey: .magnification)
        // `shape` postdates ZoomCalloutContent; old payloads omit it.
        shape = try container.decodeIfPresent(ZoomCalloutShape.self, forKey: .shape) ?? .rectangle
    }

    /// The corner radius a box of `boxSize` actually renders with: circles max
    /// it out (capsule on non-square boxes), rectangles follow the style.
    public func effectiveCornerRadius(boxSize: CGSize, styleRadius: CGFloat) -> CGFloat {
        shape == .circle ? min(boxSize.width, boxSize.height) / 2 : styleRadius
    }
}

public enum LayerContent: Hashable, Codable, Sendable {
    case image(ImageRef)
    case text(TextContent)
    case annotation(AnnotationContent)
    case zoomCallout(ZoomCalloutContent)
    case measure(MeasureContent)
}

/// How a layer composites against the content below it.
public enum BlendMode: String, Hashable, Codable, Sendable, CaseIterable {
    case normal
    case multiply
    case screen
}

/// Non-destructive per-layer styling, applied at render time.
public struct LayerStyle: Hashable, Codable, Sendable {
    public var opacity: Double
    public var blurRadius: CGFloat
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var borderColorHex: String
    public var shadow: ShadowStyle?
    public var blendMode: BlendMode

    public init(opacity: Double = 1, blurRadius: CGFloat = 0, cornerRadius: CGFloat = 0,
                borderWidth: CGFloat = 0, borderColorHex: String = "#000000", shadow: ShadowStyle? = nil,
                blendMode: BlendMode = .normal) {
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColorHex = borderColorHex
        self.shadow = shadow
        self.blendMode = blendMode
    }
}

extension LayerStyle {
    /// How far this style's effects can reach past the layer frame, in document
    /// points. Drag-preview sprites pad their canvas by this much so shadows
    /// and blur aren't clipped. 3σ covers a gaussian's visible tail.
    public var previewPadding: CGFloat {
        var padding = blurRadius * 3
        if let shadow, shadow.opacity > 0 {
            padding += shadow.radius * 3 + max(abs(shadow.offset.width), abs(shadow.offset.height))
                + max(shadow.spread, 0)
        }
        return padding.rounded(.up)
    }
}

public struct ShadowStyle: Hashable, Codable, Sendable {
    /// Softness — gaussian blur sigma of the shadow.
    public var radius: CGFloat
    /// Offset of the shadow from the object (model y-down).
    public var offset: CGSize
    /// Spread — how much bigger (>0, dilate) or smaller (<0, erode) the shadow
    /// SHAPE is than the object, before blurring. Distinct from blur (softness)
    /// and offset (distance).
    public var spread: CGFloat
    public var colorHex: String
    public var opacity: Double

    public init(radius: CGFloat = 12, offset: CGSize = CGSize(width: 0, height: 4), spread: CGFloat = 0,
                colorHex: String = "#000000", opacity: Double = 0.4) {
        self.radius = radius
        self.offset = offset
        self.spread = spread
        self.colorHex = colorHex
        self.opacity = opacity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        radius = try c.decode(CGFloat.self, forKey: .radius)
        offset = try c.decode(CGSize.self, forKey: .offset)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        opacity = try c.decode(Double.self, forKey: .opacity)
        // `spread` postdates ShadowStyle; old payloads omit it.
        spread = try c.decodeIfPresent(CGFloat.self, forKey: .spread) ?? 0
    }
}

public struct Layer: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var content: LayerContent
    /// Position and size on the canvas, in canvas coordinates.
    public var frame: CGRect
    /// Optional crop applied to the layer's own content, in layer-local coordinates.
    public var crop: CGRect?
    /// Geometric transform (rotation/skew/flip) applied at render time, around the frame's center.
    public var transform: LayerTransform
    public var style: LayerStyle
    public var isVisible: Bool
    public var isLocked: Bool

    public init(id: UUID = UUID(), name: String, content: LayerContent, frame: CGRect,
                crop: CGRect? = nil, transform: LayerTransform = .identity,
                style: LayerStyle = LayerStyle(), isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.frame = frame
        self.crop = crop
        self.transform = transform
        self.style = style
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    /// A copy with a fresh identity, for duplicate/paste. The frame offset
    /// keeps the copy from landing invisibly on top of the original.
    public func duplicated(offsetBy offset: CGPoint = .zero) -> Layer {
        Layer(name: name + " copy", content: content,
              frame: frame.offsetBy(dx: offset.x, dy: offset.y),
              crop: crop, transform: transform, style: style,
              isVisible: isVisible, isLocked: false)
    }

    /// The blend mode the renderer actually uses: highlight annotations always
    /// multiply so underlying detail shows through; everything else follows
    /// the layer's style.
    public var effectiveBlendMode: BlendMode {
        if case .annotation(let annotation) = content, annotation.shape == .highlight {
            return .multiply
        }
        return style.blendMode
    }

    /// Whether a canvas-space point lands on this layer's transformed shape.
    /// The layer's render-time transform is applied around the frame center,
    /// so hit-testing inverts it and tests against the untransformed frame.
    /// Lines/arrows hit near their stroke, not their whole (mostly empty)
    /// padded bounding box; `zoom` keeps that slop constant in screen points.
    public func contains(canvasPoint point: CGPoint, zoom: CGFloat = 1) -> Bool {
        var p = point
        if !transform.isIdentity {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            p = point.applying(transform.affineTransform(around: center).inverted())
        }
        if let a = annotation, a.shape == .line || a.shape == .arrow {
            let start = CGPoint(x: frame.minX + a.start.x, y: frame.minY + a.start.y)
            let end = CGPoint(x: frame.minX + a.end.x, y: frame.minY + a.end.y)
            let tolerance = a.strokeWidth / 2 + (zoom > 0 ? 6 / zoom : 6)
            return Geometry.distance(from: p, toSegmentFrom: start, to: end) <= tolerance
        }
        if var m = measure {
            // Hit near the drawn strokes (line + witness, or the bracket path),
            // not the padded box. Express endpoints in document space.
            m.start = CGPoint(x: frame.minX + m.start.x, y: frame.minY + m.start.y)
            m.end = CGPoint(x: frame.minX + m.end.x, y: frame.minY + m.end.y)
            let tolerance = m.strokeWidth / 2 + (zoom > 0 ? 6 / zoom : 6)
            var segments: [(CGPoint, CGPoint)] = []
            switch m.form {
            case .line:
                let geo = m.geometry()
                segments = ([geo.dimension] + geo.extensions).map { ($0.a, $0.b) }
            case .bracket:
                let path = m.bracketGeometry().path
                for i in 0..<(path.count - 1) { segments.append((path[i], path[i + 1])) }
            }
            for (a, b) in segments where Geometry.distance(from: p, toSegmentFrom: a, to: b) <= tolerance {
                return true
            }
            return false
        }
        return frame.contains(p)
    }
}
