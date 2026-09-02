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
    /// Rectangle/ellipse-only: interior fill color. Nil = no fill (the classic
    /// outline-only redline). Highlight ignores it (its color IS the fill).
    public var fillColorHex: String?
    /// Arrow-only: label text rendered as a pill at the arrow's tail, matching
    /// the measure tool's readout treatment. Nil = plain arrow.
    public var caption: String?
    /// Arrow-only: the caption's text size in image pixels.
    public var captionFontSize: CGFloat
    /// Arrow-only: where the pill centers, relative to the TAIL (`start`), when
    /// the default spot behind the tail would leave the picture. Nil = the
    /// default. Relative to the tail so an endpoint rebuild keeps it valid;
    /// `AnnotationBuilder.planningCaption` picks it against the canvas.
    public var captionOffset: CGSize?
    /// Arrow-only: true once the pill was dragged by hand. `captionOffset` is
    /// then the spot the user chose (relative to the tail) and the planner
    /// leaves it alone, only pulling it back onto the picture; false means
    /// the planner owns the offset and re-picks it whenever the arrow changes.
    public var captionPinned: Bool

    public init(shape: AnnotationShape, strokeWidth: CGFloat = 4, colorHex: String = "#FF3B30",
                start: CGPoint = .zero, end: CGPoint = .zero, arrowheadScale: CGFloat = 1,
                cornerRadius: CGFloat = 0, fillColorHex: String? = nil,
                caption: String? = nil, captionFontSize: CGFloat = Self.captionFontSizeDefault) {
        self.shape = shape
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
        self.start = start
        self.end = end
        self.arrowheadScale = arrowheadScale
        self.cornerRadius = cornerRadius
        self.fillColorHex = fillColorHex
        self.caption = caption
        self.captionFontSize = captionFontSize
        self.captionOffset = nil
        self.captionPinned = false
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
        // `fillColorHex` postdates both; legacy shapes are outline-only.
        fillColorHex = try c.decodeIfPresent(String.self, forKey: .fillColorHex)
        // Captions postdate everything above; legacy arrows are caption-free.
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        captionFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .captionFontSize)
            ?? Self.captionFontSizeDefault
        // Planned placement postdates captions; absent = the tail default.
        captionOffset = try c.decodeIfPresent(CGSize.self, forKey: .captionOffset)
        // Hand placement postdates planning; an old offset was the planner's.
        captionPinned = try c.decodeIfPresent(Bool.self, forKey: .captionPinned) ?? false
    }
}

extension AnnotationContent {
    /// Default caption text size (image pixels) — the measure label's default.
    public static let captionFontSizeDefault: CGFloat = 20
    /// Clearance between the arrow's tail and the caption pill's near edge.
    public static let captionGap: CGFloat = 6
    /// Extra frame slack around the chip reservation so the pill's drop shadow
    /// never clips at the layer edge.
    public static let captionShadowPadding: CGFloat = 12

    /// Whether this annotation renders a caption pill: arrows only, and only
    /// when the caption has real text.
    public var hasCaption: Bool {
        guard shape == .arrow, let caption else { return false }
        return !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Padding inside the caption pill, each side — the measure chip's
    /// proportions (8px of padding per 18px of text) at the caption's size.
    public var captionPadding: CGFloat {
        captionFontSize * MeasureContent.labelPadding / MeasureContent.labelFontSize
    }

    /// The pill's fill tone: the arrow color darkened the way the measure
    /// defaults pair #FF3B30 ink with a #8C201A chip, so any arrow color gets
    /// a matching dark pill that white text stays legible on.
    public var captionChipColor: RGBA {
        let rgba = RGBA(hex: colorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        var tone = RGBA(r: rgba.r * 0.55, g: rgba.g * 0.55, b: rgba.b * 0.55)
        // White text sits on the chip, so a light ink (white, yellow) keeps
        // darkening until the chip is dark enough for it to read.
        let luminance = tone.relativeLuminance
        if luminance > Self.captionChipMaxLuminance {
            let k = Self.captionChipMaxLuminance / luminance
            tone = RGBA(r: tone.r * k, g: tone.g * k, b: tone.b * k)
        }
        return tone
    }

    /// The lightest a caption chip gets: dark enough that white text reads on
    /// it. The default red pair (#8C201A) sits just under this.
    public static let captionChipMaxLuminance: Double = 0.24

    /// The pill's fill opacity — the measure chip's default translucency.
    public static let captionChipOpacity: Double = 0.92

    /// A generous estimate of the caption pill's footprint, used for frame
    /// reservation and hit-testing. The rasterizer measures the real text and
    /// centers the (smaller) pill at the same anchor, so geometry derived from
    /// this estimate never disagrees with what gets drawn.
    public var estimatedCaptionSize: CGSize {
        let chars = CGFloat(max(caption?.count ?? 0, 1) + 1)
        let w = chars * captionFontSize * 0.75 + 2 * captionPadding
        let h = captionFontSize * 1.3 + 2 * captionPadding
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }

    /// Where the caption pill centers (same coordinate space as `start`/`end`):
    /// past the arrow's tail, along the shaft away from the head, clear of the
    /// tail by `captionGap`. A zero-length arrow anchors above the point. A
    /// planned `captionOffset` (the default spot left the picture) wins.
    public func captionAnchor() -> CGPoint {
        if let captionOffset {
            return CGPoint(x: start.x + captionOffset.width, y: start.y + captionOffset.height)
        }
        let size = estimatedCaptionSize
        var dx = start.x - end.x
        var dy = start.y - end.y
        let length = hypot(dx, dy)
        if length > 0 {
            dx /= length
            dy /= length
        } else {
            dx = 0
            dy = -1
        }
        // Support extent of the pill rect along the shaft direction.
        let extent = (abs(dx) * size.width + abs(dy) * size.height) / 2
        let distance = Self.captionGap + extent
        return CGPoint(x: start.x + dx * distance, y: start.y + dy * distance)
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
    case collage(CollageContent)

    /// True when this content's rendered appearance scales uniformly with the
    /// frame. Photos and collages do — every pixel is frame-relative. Annotation
    /// strokes, text glyphs, zoom-callout chrome, and measure ticks are all sized
    /// in fixed points, so scaling a start-frame sprite stretches them; a resize
    /// of that content must re-render rather than scale a sprite.
    var scalesUniformlyOnResize: Bool {
        switch self {
        case .image, .collage: true
        case .annotation, .text, .zoomCallout, .measure: false
        }
    }
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

    /// True when this style carries no decoration whose pixel size is fixed in
    /// document points (border stroke, corner radius, blur, drop shadow). Such
    /// decoration can't be represented by uniformly scaling a start-frame sprite
    /// during a resize — the stroke would stretch, the blur/shadow would bloat —
    /// so a resize of a layer with any of it must re-render the frame instead.
    var hasNoFixedSizeDecoration: Bool {
        borderWidth == 0 && cornerRadius == 0 && blurRadius == 0
            && (shadow?.opacity ?? 0) == 0
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

    /// Whether "Rasterize Layer" applies: the layer is a vector shape/annotation
    /// that can be baked into pixels. Image layers are already pixels; the other
    /// vector kinds (text, measure, zoom callout, collage) draw chrome outside
    /// their frame or carry semantics that a lone bitmap can't reproduce, so
    /// they're excluded for now.
    public var isRasterizable: Bool {
        if case .annotation = content { return true }
        return false
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

    /// Whether a frame resize can be faithfully previewed by uniformly scaling a
    /// bitmap of the layer captured at its *start* frame. True only when both the
    /// content (photo/collage) and the styling scale uniformly with the frame.
    /// When false — annotation strokes, text, callouts, measures, or any
    /// border/corner-radius/blur/shadow decoration — a scaled sprite would
    /// stretch the fixed-size detail (and drift the anchored edge once padding is
    /// scaled too), so the live drag must re-render the frame each move instead.
    public var resizeScalesUniformly: Bool {
        content.scalesUniformlyOnResize && style.hasNoFixedSizeDecoration
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
            if Geometry.distance(from: p, toSegmentFrom: start, to: end) <= tolerance {
                return true
            }
            // The caption pill hangs off the tail with no stroke of its own, so
            // its footprint is hittable too — same rule as the measure chip.
            if a.hasCaption {
                let anchor = a.captionAnchor()
                let size = a.estimatedCaptionSize
                let chip = CGRect(x: frame.minX + anchor.x - size.width / 2,
                                  y: frame.minY + anchor.y - size.height / 2,
                                  width: size.width, height: size.height)
                if chip.insetBy(dx: -tolerance, dy: -tolerance).contains(p) { return true }
            }
            return false
        }
        if var m = measure {
            // Hit near the drawn strokes (the squared-U outline), not the padded
            // box. Express feet in document space, then walk the caliper path.
            m.start = CGPoint(x: frame.minX + m.start.x, y: frame.minY + m.start.y)
            m.end = CGPoint(x: frame.minX + m.end.x, y: frame.minY + m.end.y)
            let tolerance = m.strokeWidth / 2 + (zoom > 0 ? 6 / zoom : 6)
            let geo = m.caliperGeometry()
            let path = geo.path // footA → headA → headB → footB
            for i in 0..<(path.count - 1)
            where Geometry.distance(from: p, toSegmentFrom: path[i], to: path[i + 1]) <= tolerance {
                return true
            }
            // The label chip sits in the head-line gap (no stroke there), so make
            // its footprint hittable too — otherwise clicking the pill's blank
            // background selects nothing. `estimatedLabelSize` is a generous
            // upper bound, which makes the biggest visual target easy to click.
            if m.showLabel {
                let size = m.estimatedLabelSize
                let chip = CGRect(x: geo.labelAnchor.x - size.width / 2,
                                  y: geo.labelAnchor.y - size.height / 2,
                                  width: size.width, height: size.height)
                if chip.insetBy(dx: -tolerance, dy: -tolerance).contains(p) { return true }
            }
            return false
        }
        return frame.contains(p)
    }
}
