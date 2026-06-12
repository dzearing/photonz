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

public enum AnnotationShape: String, Codable, Sendable {
    case arrow
    case rectangle
    case highlight
    case ellipse
    case line
}

public struct TextContent: Hashable, Codable, Sendable {
    public var string: String
    public var fontName: String
    public var fontSize: CGFloat
    public var colorHex: String

    public init(string: String, fontName: String = "SF Pro", fontSize: CGFloat = 24, colorHex: String = "#FFFFFF") {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
    }
}

public struct AnnotationContent: Hashable, Codable, Sendable {
    public var shape: AnnotationShape
    public var strokeWidth: CGFloat
    public var colorHex: String
    /// For arrows/lines: start and end in layer-local coordinates.
    public var start: CGPoint
    public var end: CGPoint

    public init(shape: AnnotationShape, strokeWidth: CGFloat = 4, colorHex: String = "#FF3B30", start: CGPoint = .zero, end: CGPoint = .zero) {
        self.shape = shape
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
        self.start = start
        self.end = end
    }
}

public struct ZoomCalloutContent: Hashable, Codable, Sendable {
    /// Region of the canvas being magnified, in canvas coordinates.
    public var sourceRect: CGRect
    public var magnification: CGFloat

    public init(sourceRect: CGRect, magnification: CGFloat = 2) {
        self.sourceRect = sourceRect
        self.magnification = magnification
    }
}

public enum LayerContent: Hashable, Codable, Sendable {
    case image(ImageRef)
    case text(TextContent)
    case annotation(AnnotationContent)
    case zoomCallout(ZoomCalloutContent)
}

/// Non-destructive per-layer styling, applied at render time.
public struct LayerStyle: Hashable, Codable, Sendable {
    public var opacity: Double
    public var blurRadius: CGFloat
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var borderColorHex: String
    public var shadow: ShadowStyle?

    public init(opacity: Double = 1, blurRadius: CGFloat = 0, cornerRadius: CGFloat = 0,
                borderWidth: CGFloat = 0, borderColorHex: String = "#000000", shadow: ShadowStyle? = nil) {
        self.opacity = opacity
        self.blurRadius = blurRadius
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColorHex = borderColorHex
        self.shadow = shadow
    }
}

public struct ShadowStyle: Hashable, Codable, Sendable {
    public var radius: CGFloat
    public var offset: CGSize
    public var colorHex: String
    public var opacity: Double

    public init(radius: CGFloat = 12, offset: CGSize = CGSize(width: 0, height: 4), colorHex: String = "#000000", opacity: Double = 0.4) {
        self.radius = radius
        self.offset = offset
        self.colorHex = colorHex
        self.opacity = opacity
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
    public var style: LayerStyle
    public var isVisible: Bool
    public var isLocked: Bool

    public init(id: UUID = UUID(), name: String, content: LayerContent, frame: CGRect,
                crop: CGRect? = nil, style: LayerStyle = LayerStyle(), isVisible: Bool = true, isLocked: Bool = false) {
        self.id = id
        self.name = name
        self.content = content
        self.frame = frame
        self.crop = crop
        self.style = style
        self.isVisible = isVisible
        self.isLocked = isLocked
    }
}
