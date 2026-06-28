import CoreGraphics
import Foundation

/// What a measure reports and how its witness lines are drawn. `free` measures
/// the straight point-to-point distance; `horizontal`/`vertical` measure only
/// the dx/dy span (CAD-style redline) with extension lines projecting from any
/// off-axis reference point onto the dimension line.
public enum MeasureMode: String, CaseIterable, Hashable, Codable, Sendable {
    case free
    case horizontal
    case vertical
}

/// How a measure is drawn. `line` is a straight dimension line (with witness
/// lines in the locked modes). `bracket` is a squared "U" that wraps the gap
/// between two opposite corners — legs reach in from the start corner, the
/// closed connector spans the measured gap on the far side, and the label sits
/// outside it. Built for redlining the space between two UI elements.
public enum MeasureForm: String, CaseIterable, Hashable, Codable, Sendable {
    case line
    case bracket
}

/// The unit a measure's readout is shown in. `points` divides the raw bitmap
/// distance by the document's `pixelScale` (a 2× Retina capture reads in logical
/// points); `pixels` shows the raw bitmap distance.
public enum MeasureUnit: String, CaseIterable, Hashable, Codable, Sendable {
    case points
    case pixels

    public var suffix: String {
        switch self {
        case .points: "pt"
        case .pixels: "px"
        }
    }
}

/// How the ends of the dimension line are terminated.
public enum MeasureCapStyle: String, CaseIterable, Hashable, Codable, Sendable {
    /// Perpendicular serif/tick marks (the redline / CAD convention).
    case ticks
    /// Inward-pointing arrowheads.
    case arrows
}

/// A directed line segment, used for a measure's dimension and witness lines.
/// A small named type (not a tuple) so geometry results stay `Equatable`.
public struct MeasureSegment: Equatable, Sendable {
    public var a: CGPoint
    public var b: CGPoint

    public init(_ a: CGPoint, _ b: CGPoint) {
        self.a = a
        self.b = b
    }
}

/// The drawable geometry of a measure: the main dimension line, zero–two
/// extension (witness) lines connecting off-axis reference points to it, and
/// the anchor where the numeric label is centered. All in the same coordinate
/// space as the input points (layer-local or document).
public struct MeasureGeometry: Equatable, Sendable {
    public var dimension: MeasureSegment
    public var extensions: [MeasureSegment]
    public var labelAnchor: CGPoint

    public init(dimension: MeasureSegment, extensions: [MeasureSegment], labelAnchor: CGPoint) {
        self.dimension = dimension
        self.extensions = extensions
        self.labelAnchor = labelAnchor
    }
}

/// A measurement annotation: two reference points plus how the span between
/// them is reported. Mirrors `AnnotationContent`'s two-endpoint shape (start/end
/// are layer-local once built), but carries its own readout model — mode, unit,
/// decimals, and a toggleable label — so it can live as its own `LayerContent`.
public struct MeasureContent: Hashable, Codable, Sendable {
    /// Reference points, layer-local once placed by `MeasureBuilder`.
    public var start: CGPoint
    public var end: CGPoint
    public var mode: MeasureMode
    public var strokeWidth: CGFloat
    public var colorHex: String
    /// Whether the numeric size readout is drawn. The label is part of the
    /// layer, toggleable like any other style.
    public var showLabel: Bool
    public var unit: MeasureUnit
    public var decimals: Int
    public var capStyle: MeasureCapStyle
    public var form: MeasureForm

    public init(start: CGPoint = .zero, end: CGPoint = .zero, mode: MeasureMode = .free,
                strokeWidth: CGFloat = 2, colorHex: String = "#FF3B30", showLabel: Bool = true,
                unit: MeasureUnit = .points, decimals: Int = 0, capStyle: MeasureCapStyle = .ticks,
                form: MeasureForm = .line) {
        self.start = start
        self.end = end
        self.mode = mode
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
        self.showLabel = showLabel
        self.unit = unit
        self.decimals = decimals
        self.capStyle = capStyle
        self.form = form
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        mode = try c.decode(MeasureMode.self, forKey: .mode)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        colorHex = try c.decode(String.self, forKey: .colorHex)
        showLabel = try c.decode(Bool.self, forKey: .showLabel)
        unit = try c.decode(MeasureUnit.self, forKey: .unit)
        decimals = try c.decode(Int.self, forKey: .decimals)
        capStyle = try c.decode(MeasureCapStyle.self, forKey: .capStyle)
        // `form` postdates the type; older payloads default to the straight line.
        form = try c.decodeIfPresent(MeasureForm.self, forKey: .form) ?? .line
    }
}

extension MeasureContent {
    /// The measured span in raw document pixels: euclidean for `free`, the
    /// absolute dx/dy for the locked modes.
    public var rawDistance: CGFloat {
        switch mode {
        case .free: hypot(end.x - start.x, end.y - start.y)
        case .horizontal: abs(end.x - start.x)
        case .vertical: abs(end.y - start.y)
        }
    }

    /// The span in the configured unit. Points divide the raw pixel distance by
    /// `pixelScale` (≤0 is treated as 1× so a missing scale never divides away
    /// the value); pixels return the raw distance unchanged.
    public func displayDistance(pixelScale: CGFloat) -> CGFloat {
        switch unit {
        case .pixels: rawDistance
        case .points: rawDistance / (pixelScale > 0 ? pixelScale : 1)
        }
    }

    /// The formatted readout, e.g. "120 pt" or "240.0 px".
    public func label(pixelScale: CGFloat) -> String {
        let value = displayDistance(pixelScale: pixelScale)
        return String(format: "%.\(max(0, decimals))f %@", value, unit.suffix)
    }

    /// Drawable geometry for this measure's own reference points.
    public func geometry() -> MeasureGeometry {
        Self.geometry(mode: mode, start: start, end: end)
    }

    /// Pure geometry from two reference points: where the dimension line and any
    /// witness lines fall, and where the label centers. The locked modes level
    /// the dimension line onto the *end* point's axis and drop a witness line
    /// from the start point when it sits off that axis.
    public static func geometry(mode: MeasureMode, start s: CGPoint, end e: CGPoint) -> MeasureGeometry {
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        switch mode {
        case .free:
            return MeasureGeometry(dimension: MeasureSegment(s, e), extensions: [], labelAnchor: mid(s, e))
        case .horizontal:
            let y = e.y
            let dim = MeasureSegment(CGPoint(x: s.x, y: y), CGPoint(x: e.x, y: y))
            var extensions: [MeasureSegment] = []
            if s.y != y { extensions.append(MeasureSegment(s, CGPoint(x: s.x, y: y))) }
            return MeasureGeometry(dimension: dim, extensions: extensions, labelAnchor: mid(dim.a, dim.b))
        case .vertical:
            let x = e.x
            let dim = MeasureSegment(CGPoint(x: x, y: s.y), CGPoint(x: x, y: e.y))
            var extensions: [MeasureSegment] = []
            if s.x != x { extensions.append(MeasureSegment(s, CGPoint(x: x, y: s.y))) }
            return MeasureGeometry(dimension: dim, extensions: extensions, labelAnchor: mid(dim.a, dim.b))
        }
    }

    /// The dominant axis between two opposite corners — the measured gap for a
    /// bracket. Vertical when the box is at least as tall as it is wide.
    public static func bracketAxis(start s: CGPoint, end e: CGPoint) -> MeasureMode {
        abs(e.y - s.y) >= abs(e.x - s.x) ? .vertical : .horizontal
    }

    /// The squared-U bracket between `start` and `end` (opposite corners): the
    /// four-point open path (leg → connector → leg), the connector midpoint where
    /// the label anchors, and the outward unit pointing away from the opening (the
    /// side the label sits on). Mode selects which axis the connector spans.
    public func bracketGeometry() -> (path: [CGPoint], connectorMid: CGPoint, outward: CGVector) {
        let x0 = start.x, y0 = start.y, x1 = end.x, y1 = end.y
        if mode == .horizontal {
            // Legs vertical (at x0 and x1), connector horizontal at y1 (far from y0).
            let path = [CGPoint(x: x0, y: y0), CGPoint(x: x0, y: y1),
                        CGPoint(x: x1, y: y1), CGPoint(x: x1, y: y0)]
            return (path, CGPoint(x: (x0 + x1) / 2, y: y1), CGVector(dx: 0, dy: y1 >= y0 ? 1 : -1))
        } else {
            // Legs horizontal (at y0 and y1), connector vertical at x1 (far from x0).
            let path = [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0),
                        CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
            return (path, CGPoint(x: x1, y: (y0 + y1) / 2), CGVector(dx: x1 >= x0 ? 1 : -1, dy: 0))
        }
    }

    /// Where the label plate centers, given its size. Line: on the dimension line.
    /// Bracket: outside the connector, offset by the plate half-extent + a gap.
    public func labelCenter(labelSize: CGSize) -> CGPoint {
        switch form {
        case .line:
            return geometry().labelAnchor
        case .bracket:
            let b = bracketGeometry()
            let reach = (abs(b.outward.dx) > 0 ? labelSize.width : labelSize.height) / 2 + Self.labelOutwardGap
            return CGPoint(x: b.connectorMid.x + b.outward.dx * reach,
                           y: b.connectorMid.y + b.outward.dy * reach)
        }
    }

    /// Gap between a bracket's connector and its outside label plate.
    public static let labelOutwardGap: CGFloat = 6

    /// Label text plate point size. Fixed (independent of the document's
    /// `pixelScale`) so a measure's frame never shifts when the unit toggles.
    public static let labelFontSize: CGFloat = 24
    /// Padding inside the label plate, each side.
    public static let labelPadding: CGFloat = 7

    /// Perpendicular reach of the end caps (ticks/arrowheads) past the line.
    public var capExtent: CGFloat { (strokeWidth * 1.5 + 4).rounded(.up) }

    /// How far drawing can extend past the reference-point bounding box: half the
    /// stroke or the cap reach, whichever is larger.
    public var renderPadding: CGFloat {
        max(strokeWidth / 2, capExtent).rounded(.up)
    }

    /// A generous estimate of the label plate's footprint, used by the builder to
    /// reserve frame space. Sized from the raw-pixel magnitude (an upper bound on
    /// digit count across units), so it stays stable when the unit/scale changes.
    /// The rasterizer measures the real text and centers within this reservation.
    public var estimatedLabelSize: CGSize {
        let digits = max(1, String(Int(rawDistance.rounded())).count)
        let chars = CGFloat(digits + 4) // space + up-to-2-char unit + slack
        let w = chars * Self.labelFontSize * 0.62 + 2 * Self.labelPadding
        let h = Self.labelFontSize * 1.3 + 2 * Self.labelPadding
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }
}

/// Builds and edits measure layers, mirroring `AnnotationBuilder`: the frame is
/// the reference-point bounding box padded for cap overhang, and start/end are
/// re-expressed layer-local so the drawn shape scales with the frame.
public enum MeasureBuilder {

    /// The layer a placement from `start` to `end` (document coordinates)
    /// creates. Frame = padded bbox; endpoints become layer-local.
    public static func layer(content: MeasureContent, from start: CGPoint, to end: CGPoint) -> Layer {
        var content = content
        // Adopt the real span up front so `rawDistance`-derived metrics
        // (renderPadding, estimatedLabelSize) reflect THIS measure, not the
        // input content's stale endpoints. Endpoints are re-localized below.
        content.start = start
        content.end = end
        let pad = content.renderPadding
        var box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
            .insetBy(dx: -pad, dy: -pad)
        // Reserve room for the label plate (on the line, or outside a bracket's
        // connector) so the number isn't clipped at the frame edge.
        if content.showLabel {
            let size = content.estimatedLabelSize
            let center = content.labelCenter(labelSize: size)
            box = box.union(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                   width: size.width, height: size.height))
        }
        box.size.width = max(box.size.width, 1)
        box.size.height = max(box.size.height, 1)
        content.start = CGPoint(x: start.x - box.minX, y: start.y - box.minY)
        content.end = CGPoint(x: end.x - box.minX, y: end.y - box.minY)
        return Layer(name: "Measure", content: .measure(content), frame: box)
    }

    /// Redraw a measure between document-space `start` and `end`: identity,
    /// name, and style survive; the frame is rebuilt with fresh padding.
    public static func updating(_ layer: Layer, start: CGPoint, end: CGPoint) -> Layer {
        guard let m = layer.measure else { return layer }
        let rebuilt = self.layer(content: m, from: start, to: end)
        var updated = layer
        updated.frame = rebuilt.frame
        updated.content = rebuilt.content
        return updated
    }

    /// Handle-resize remap: reference points scale proportionally into the
    /// proposed frame, then the layer is rebuilt so caps keep full padding.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        guard let m = layer.measure,
              layer.frame.width > 0, layer.frame.height > 0 else { return layer }
        func remap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x / layer.frame.width * frame.width,
                    y: frame.minY + p.y / layer.frame.height * frame.height)
        }
        return updating(layer, start: remap(m.start), end: remap(m.end))
    }

    /// Style/readout edit on an existing measure: reference points stay anchored
    /// in document space while the frame re-pads for any new stroke width.
    public static func restyled(_ layer: Layer, colorHex: String? = nil, strokeWidth: CGFloat? = nil,
                                showLabel: Bool? = nil, unit: MeasureUnit? = nil, decimals: Int? = nil,
                                mode: MeasureMode? = nil, capStyle: MeasureCapStyle? = nil,
                                form: MeasureForm? = nil) -> Layer {
        guard var m = layer.measure,
              let start = layer.measureEndpoint(.start),
              let end = layer.measureEndpoint(.end) else { return layer }
        if let colorHex { m.colorHex = colorHex }
        if let strokeWidth { m.strokeWidth = strokeWidth }
        if let showLabel { m.showLabel = showLabel }
        if let unit { m.unit = unit }
        if let decimals { m.decimals = decimals }
        if let mode { m.mode = mode }
        if let capStyle { m.capStyle = capStyle }
        if let form { m.form = form }
        var updated = layer
        updated.content = .measure(m)
        return updating(updated, start: start, end: end)
    }
}
