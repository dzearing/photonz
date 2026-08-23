import CoreGraphics
import Foundation

/// Which axis a caliper measures. The measuring line (the two feet) is always
/// horizontal or vertical; the axis picks which. There is no free/diagonal mode
/// — the caliper is the one opinionated measure tool.
public enum MeasureMode: String, CaseIterable, Hashable, Codable, Sendable {
    case horizontal
    case vertical
}

/// The unit a measure's readout is shown in. Both read out as "px" — the
/// distinction is logical vs device pixels, matching how CSS treats `px` as a
/// logical unit. `points` divides the raw bitmap distance by the document's
/// `pixelScale`, so a 2× Retina capture reads in LOGICAL pixels (on-screen /
/// design size); `pixels` shows the raw DEVICE-pixel distance (2× larger on
/// Retina — an opt-in for when you truly want bitmap pixels).
public enum MeasureUnit: String, CaseIterable, Hashable, Codable, Sendable {
    case points
    case pixels

    /// Both units are pixels; the mode (Logical vs Actual) carries the
    /// distinction, so the readout stays a plain, familiar "px".
    public var suffix: String { "px" }
}

/// What a measurement is calling out — the mock legend's Size (red) vs Spacing
/// (blue) distinction (§5, `next-measure-roles`). Each role keeps its own
/// remembered color set in `MeasureStyles`. Alignment checks are a separate
/// payload (`AlignmentCheck` on the content), but this type is written to
/// absorb an `alignment` case should it ever become a role.
public enum MeasureRole: String, CaseIterable, Hashable, Codable, Sendable {
    case size
    case spacing
}

/// The drawable geometry of a caliper: the two **feet** on the measured space
/// (the measuring line), the two **head** corners (the closed, perpendicular
/// outer end offset from the feet), and the label anchor at the head midpoint.
/// All in the same coordinate space as the input points (layer-local or doc).
///
/// The squared-U outline is `footA → headA → headB → footB`: legs point from the
/// head down to the feet, and the chip sits centered on the head line.
public struct CaliperGeometry: Equatable, Sendable {
    public var footA: CGPoint
    public var footB: CGPoint
    public var headA: CGPoint
    public var headB: CGPoint
    /// Head-line midpoint — where the chip/label centers (the outer edge).
    public var labelAnchor: CGPoint
    public var axis: MeasureMode

    public init(footA: CGPoint, footB: CGPoint, headA: CGPoint, headB: CGPoint,
                labelAnchor: CGPoint, axis: MeasureMode) {
        self.footA = footA
        self.footB = footB
        self.headA = headA
        self.headB = headB
        self.labelAnchor = labelAnchor
        self.axis = axis
    }

    /// The open squared-U outline, corner order `footA → headA → headB → footB`.
    public var path: [CGPoint] { [footA, headA, headB, footB] }
}

/// A measurement annotation: the two feet of a measuring line plus a signed
/// perpendicular `headOffset` to the head/chip bar, and how the span is reported.
/// Mirrors the two-endpoint layer pattern (`start`/`end` = the feet, layer-local
/// once built) but carries its own readout model — mode, unit, decimals, and a
/// toggleable label.
public struct MeasureContent: Hashable, Codable, Sendable {
    /// The two feet of the measuring line, on the measured space; layer-local
    /// once placed. Kept level (shared cross-axis coordinate) so the line is
    /// exactly horizontal or vertical.
    public var start: CGPoint
    public var end: CGPoint
    /// Signed perpendicular distance from the feet line to the head/chip bar. Its
    /// sign is the caliper's direction (which side the head sits) — an invert
    /// control is redundant.
    public var headOffset: CGFloat
    public var mode: MeasureMode
    public var strokeWidth: CGFloat
    /// The caliper's ink: legs, head line, and the label chip's border.
    public var strokeColorHex: String
    /// The label chip's fill. Its alpha lives in `chipOpacity`, NOT in this hex —
    /// `RGBA.hexString` emits six digits and drops alpha, so a `#RRGGBBAA` stored
    /// here would lose its transparency on the first round-trip through a picker.
    public var chipColorHex: String
    /// The label chip fill's alpha, 0 (invisible chip) … 1 (solid). Clamped.
    public var chipOpacity: CGFloat
    /// The numeric readout's color.
    public var textColorHex: String
    /// Whether the numeric size readout is drawn. The label is always shown in the
    /// UI now (no toggle); the field stays for internal/legacy use.
    public var showLabel: Bool
    public var unit: MeasureUnit
    public var decimals: Int
    /// Multiplier on the base label font/pill size, driven by the inspector's
    /// "Label size" slider. 1 = default.
    public var labelScale: CGFloat
    /// Size vs Spacing (§5, `next-measure-roles`). Purely semantic — rendering
    /// reads the color fields, which the role's remembered set feeds at
    /// creation/switch time. Every document saved before roles decodes `.size`.
    public var role: MeasureRole
    /// Present when this measure is an **alignment check** (§9): the feet are
    /// the two ends of a dashed guide line, `headOffset` is 0, and the label
    /// reads the check's verdict instead of a distance. Nil for plain calipers
    /// and for every document saved before this field existed.
    public var alignment: AlignmentCheck?
    /// Where the readout sits relative to the measurement (UX-PATTERNS D14).
    /// Chosen once, when the measurement lands, by `MeasureLabelPlanner`; only
    /// the readout ever moves, never the geometry. Every document saved before
    /// this field existed decodes `.onLine`, exactly how it used to draw.
    public var labelPlacement: MeasureLabelPlacement
    /// A small extra shift along the measuring line, used to keep two nearby
    /// readouts from stacking. Zero for almost every measurement.
    public var labelNudge: CGFloat

    public init(start: CGPoint = .zero, end: CGPoint = .zero,
                headOffset: CGFloat = MeasureContent.defaultHeadOffset,
                mode: MeasureMode = .horizontal, strokeWidth: CGFloat = 1,
                strokeColorHex: String = MeasureContent.defaultStrokeColorHex,
                chipColorHex: String = MeasureContent.defaultChipColorHex,
                chipOpacity: CGFloat = MeasureContent.defaultChipOpacity,
                textColorHex: String = MeasureContent.defaultStrokeColorHex,
                showLabel: Bool = true,
                unit: MeasureUnit = .pixels, decimals: Int = 0, labelScale: CGFloat = 1,
                role: MeasureRole = .size,
                alignment: AlignmentCheck? = nil,
                labelPlacement: MeasureLabelPlacement = .onLine,
                labelNudge: CGFloat = 0) {
        self.start = start
        self.end = end
        self.headOffset = headOffset
        self.mode = mode
        self.strokeWidth = strokeWidth
        self.strokeColorHex = strokeColorHex
        self.chipColorHex = chipColorHex
        self.chipOpacity = MeasureContent.clampedOpacity(chipOpacity)
        self.textColorHex = textColorHex
        self.showLabel = showLabel
        self.unit = unit
        self.decimals = decimals
        self.labelScale = labelScale
        self.role = role
        self.alignment = alignment
        self.labelPlacement = labelPlacement
        self.labelNudge = labelNudge
    }

    /// Default caliper ink — the original single measure color.
    public static let defaultStrokeColorHex = "#FF3B30"
    /// Default chip fill: the neutral white the rasterizer used to hardcode…
    public static let defaultChipColorHex = "#FFFFFF"
    /// …at the alpha it used to hardcode with it.
    public static let defaultChipOpacity: CGFloat = 0.92

    /// Alpha clamped into 0…1 (a picker or a hand-edited document can overshoot).
    static func clampedOpacity(_ value: CGFloat) -> CGFloat { min(max(value, 0), 1) }

    enum CodingKeys: String, CodingKey {
        case start, end, headOffset, mode, strokeWidth, showLabel, unit, decimals, labelScale
        case role
        case alignment
        case labelPlacement, labelNudge
        case strokeColorHex, chipColorHex, chipOpacity, textColorHex
        // Legacy keys from the pre-caliper measure model (decode-only) and the
        // pre-split single color (decode + a write-only mirror, see `encode`).
        case form, capStyle, colorHex
    }

    /// Explicit so the legacy-only `CodingKeys` cases don't block synthesis; only
    /// the current caliper keys are written (plus the legacy color mirror).
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(headOffset, forKey: .headOffset)
        try c.encode(mode, forKey: .mode)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(strokeColorHex, forKey: .strokeColorHex)
        try c.encode(chipColorHex, forKey: .chipColorHex)
        try c.encode(chipOpacity, forKey: .chipOpacity)
        try c.encode(textColorHex, forKey: .textColorHex)
        // Write-only mirror of the pre-split key: a build from before the color
        // split REQUIRES `colorHex`, so keeping it here means an older Photonz can
        // still open documents this one saves (it just sees one color). Never read
        // back when `strokeColorHex` is present.
        try c.encode(strokeColorHex, forKey: .colorHex)
        try c.encode(showLabel, forKey: .showLabel)
        try c.encode(unit, forKey: .unit)
        try c.encode(decimals, forKey: .decimals)
        try c.encode(labelScale, forKey: .labelScale)
        try c.encode(role, forKey: .role)
        try c.encodeIfPresent(alignment, forKey: .alignment)
        try c.encode(labelPlacement, forKey: .labelPlacement)
        try c.encode(labelNudge, forKey: .labelNudge)
    }

    /// Decodes new caliper payloads directly and **migrates** legacy measures
    /// (the old box-corner `line`/`bracket`/`free` model) to the nearest H/V
    /// caliper. New payloads carry `headOffset`; legacy ones don't.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let s = try c.decode(CGPoint.self, forKey: .start)
        let e = try c.decode(CGPoint.self, forKey: .end)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        // Pre-split documents carry one `colorHex`; it seeded both the ink and the
        // readout, and the chip was always white at 92%. Migrating that way makes
        // an existing caliper look byte-identical to how it looked before.
        let legacyColor = try c.decodeIfPresent(String.self, forKey: .colorHex)
        strokeColorHex = try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
            ?? legacyColor ?? Self.defaultStrokeColorHex
        textColorHex = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? strokeColorHex
        chipColorHex = try c.decodeIfPresent(String.self, forKey: .chipColorHex)
            ?? Self.defaultChipColorHex
        chipOpacity = Self.clampedOpacity(
            try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity) ?? Self.defaultChipOpacity)
        showLabel = try c.decode(Bool.self, forKey: .showLabel)
        unit = try c.decode(MeasureUnit.self, forKey: .unit)
        decimals = try c.decode(Int.self, forKey: .decimals)
        labelScale = try c.decodeIfPresent(CGFloat.self, forKey: .labelScale) ?? 1
        role = try c.decodeIfPresent(MeasureRole.self, forKey: .role) ?? .size
        alignment = try c.decodeIfPresent(AlignmentCheck.self, forKey: .alignment)
        labelPlacement = try c.decodeIfPresent(MeasureLabelPlacement.self,
                                               forKey: .labelPlacement) ?? .onLine
        labelNudge = try c.decodeIfPresent(CGFloat.self, forKey: .labelNudge) ?? 0

        // Legacy `mode` may be "free" (no longer a case) — decode as a raw string.
        let modeString = try c.decodeIfPresent(String.self, forKey: .mode)

        if let offset = try c.decodeIfPresent(CGFloat.self, forKey: .headOffset) {
            // New caliper payload.
            start = s
            end = e
            headOffset = offset
            mode = MeasureMode(rawValue: modeString ?? "") ?? Self.dominantAxis(from: s, to: e)
            return
        }

        // Legacy payload → migrate to a caliper.
        let form = try c.decodeIfPresent(String.self, forKey: .form) ?? "line"
        let legacyMode = MeasureMode(rawValue: modeString ?? "")
        let axis = legacyMode ?? Self.dominantAxis(from: s, to: e)
        mode = axis
        if form == "bracket" {
            // Old bracket: `start` was a head-side corner, `end` the opposite
            // foot-side corner. Feet lie on the end side; the head sat on the
            // start side. Re-express as (feet line + signed offset to the head).
            switch axis {
            case .horizontal:
                start = CGPoint(x: s.x, y: e.y)
                end = CGPoint(x: e.x, y: e.y)
                headOffset = s.y - e.y
            case .vertical:
                start = CGPoint(x: e.x, y: s.y)
                end = CGPoint(x: e.x, y: e.y)
                headOffset = s.x - e.x
            }
        } else {
            // Old line/free: keep the two points as the feet (leveled by
            // geometry) and give the head a default reach.
            start = s
            end = e
            headOffset = Self.defaultHeadOffset
        }
    }

    /// The axis whose span dominates the drag from `s` to `e`.
    public static func dominantAxis(from s: CGPoint, to e: CGPoint) -> MeasureMode {
        abs(e.x - s.x) >= abs(e.y - s.y) ? .horizontal : .vertical
    }
}

extension MeasureContent {
    /// Default perpendicular reach of the legs (feet → head), in layer-local
    /// units, used when a caliper is first created.
    public static let defaultHeadOffset: CGFloat = 28

    /// The measured span in raw document pixels: the feet line's axis extent.
    public var rawDistance: CGFloat {
        switch mode {
        case .horizontal: abs(end.x - start.x)
        case .vertical: abs(end.y - start.y)
        }
    }

    /// A raw pixel value in the configured unit. Points divide by `pixelScale`
    /// (≤0 is treated as 1× so a missing scale never divides away the value);
    /// pixels return it unchanged.
    public func displayValue(_ raw: CGFloat, pixelScale: CGFloat) -> CGFloat {
        switch unit {
        case .pixels: raw
        case .points: raw / (pixelScale > 0 ? pixelScale : 1)
        }
    }

    /// The span in the configured unit.
    public func displayDistance(pixelScale: CGFloat) -> CGFloat {
        displayValue(rawDistance, pixelScale: pixelScale)
    }

    /// The formatted readout: a caliper's distance ("120 px"), or an alignment
    /// check's verdict ("aligned" / "off 4 px" / "no edges").
    public func label(pixelScale: CGFloat) -> String {
        if let alignment {
            guard let verdict = alignment.verdict else { return "no edges" }
            guard !verdict.isAligned else { return "aligned" }
            let delta = displayValue(verdict.maxDelta, pixelScale: pixelScale)
            return String(format: "off %.\(max(0, decimals))f %@", delta, unit.suffix)
        }
        let value = displayDistance(pixelScale: pixelScale)
        return String(format: "%.\(max(0, decimals))f %@", value, unit.suffix)
    }

    /// Drawable geometry for this measure's own points (feet + head + anchor).
    public func caliperGeometry() -> CaliperGeometry {
        Self.caliperGeometry(mode: mode, start: start, end: end, headOffset: headOffset)
    }

    /// Pure geometry from the two feet + a signed head offset. The feet are
    /// leveled onto a single cross-axis value (start's) so the measuring line is
    /// exactly horizontal/vertical; the head is that line shifted perpendicular
    /// by `headOffset`; the label anchors at the head midpoint.
    public static func caliperGeometry(mode: MeasureMode, start s: CGPoint, end e: CGPoint,
                                       headOffset: CGFloat) -> CaliperGeometry {
        switch mode {
        case .horizontal:
            let footY = s.y
            let headY = footY + headOffset
            return CaliperGeometry(
                footA: CGPoint(x: s.x, y: footY), footB: CGPoint(x: e.x, y: footY),
                headA: CGPoint(x: s.x, y: headY), headB: CGPoint(x: e.x, y: headY),
                labelAnchor: CGPoint(x: (s.x + e.x) / 2, y: headY), axis: .horizontal)
        case .vertical:
            let footX = s.x
            let headX = footX + headOffset
            return CaliperGeometry(
                footA: CGPoint(x: footX, y: s.y), footB: CGPoint(x: footX, y: e.y),
                headA: CGPoint(x: headX, y: s.y), headB: CGPoint(x: headX, y: e.y),
                labelAnchor: CGPoint(x: headX, y: (s.y + e.y) / 2), axis: .vertical)
        }
    }

    /// Where the chip/label centers: the head-line midpoint (the outer edge).
    public var labelAnchor: CGPoint { caliperGeometry().labelAnchor }

    /// The head handle's position (document/layer space): the head midpoint,
    /// dragged perpendicular to change the offset (distance) and side.
    public var headHandle: CGPoint { labelAnchor }

    /// The along-axis half-length of the chip's footprint, given its size — the
    /// extent the (translucent) pill blocks on the head line. Horizontal chips
    /// block their width; vertical head lines are blocked by the chip height.
    public func chipAxisHalfExtent(chipSize: CGSize) -> CGFloat {
        (mode == .horizontal ? chipSize.width : chipSize.height) / 2
    }

    /// Base label text point size (in image pixels) — the default label size, at
    /// `labelScale` 1. Multiplied by `labelScale` (the inspector slider) for the
    /// effective size. Shared by the baked pill and the live glass overlay so the
    /// head-line gap always matches the pill.
    public static let labelFontSize: CGFloat = 18
    /// Base padding inside the label pill, each side (image pixels).
    public static let labelPadding: CGFloat = 8

    /// The effective label font size = base × `labelScale`.
    public var labelPointSize: CGFloat { Self.labelFontSize * labelScale }
    /// The effective pill padding = base × `labelScale` (so proportions hold).
    public var labelPadding: CGFloat { Self.labelPadding * labelScale }
    /// Allowed range for the label-size slider.
    public static let labelScaleRange: ClosedRange<CGFloat> = 0.5...5
    /// The label-size slider's range in effective PIXELS (what the inspector shows).
    public static let labelSizeRangePx: ClosedRange<CGFloat> = 8...64
    /// Extra clearance between the head line's cut ends and the chip, so a
    /// translucent pill never reveals a stroke behind it.
    public static let chipLineGap: CGFloat = 5
    /// Nominal rounded-corner radius at the two head↔leg joins (clamped to the
    /// caliper's size at draw time).
    public static let cornerRadius: CGFloat = 5

    /// A generous estimate of the chip's footprint, used by the builder to
    /// reserve frame space. Sized from the raw-pixel magnitude (an upper bound on
    /// digit count across units), so it stays stable when the unit/scale changes.
    /// The rasterizer measures the real text and centers within this reservation.
    public var estimatedLabelSize: CGSize {
        // Alignment verdicts are words, not distances: "off 120 px" is the
        // longest realistic form, and a fixed reservation keeps the frame
        // stable when the verdict text changes.
        let chars: CGFloat
        if alignment != nil {
            chars = 10
        } else {
            let digits = max(1, String(Int(rawDistance.rounded())).count)
            chars = CGFloat(digits + 4) // space + up-to-2-char unit + slack
        }
        let w = chars * labelPointSize * 0.62 + 2 * labelPadding
        let h = labelPointSize * 1.3 + 2 * labelPadding
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }

    /// How far drawing can extend past the caliper's point bounding box: half the
    /// stroke plus the corner radius, so rounded joins never clip.
    public var renderPadding: CGFloat {
        (strokeWidth / 2 + Self.cornerRadius + 2).rounded(.up)
    }
}

/// Builds and edits caliper layers, mirroring `AnnotationBuilder`: the frame is
/// the caliper's bounding box (feet + head + reserved chip) padded for stroke
/// overhang, and the feet are re-expressed layer-local so the shape scales with
/// the frame. `headOffset` is a delta, so it's translation-invariant.
public enum MeasureBuilder {

    /// Perpendicular half-length of the small tick drawn where an aligned
    /// element crosses an alignment guide. Big enough to read as a deliberate
    /// mark at 1:1 on a Retina capture — at 5 it was a hairline you had to look
    /// for, and a guide that cannot show what it checked is not showing its
    /// work.
    public static let alignmentTickHalf: CGFloat = 8

    /// The stock layer names a fresh caliper / alignment guide is born with.
    /// `MeasureSpecList.displayName` treats these as "never renamed" and shows
    /// the derived name instead, so they double as that sentinel.
    public static let defaultName = "Measure"
    public static let defaultAlignmentName = "Alignment"

    /// The perpendicular reach a caliper needs so its readout sits CLEAR of the
    /// thing it measures, rather than on top of it. The chip centers on the head
    /// line, so the head has to stand off by at least half the chip's cross-axis
    /// extent, plus the gap the head line already leaves and a little margin.
    ///
    /// Modes that measure something they can see (the size of an element, the
    /// space between two of them) place their own calipers, so they use this
    /// instead of the bare default reach — a 12 px gap with a 90 px readout
    /// parked on it tells you nothing about which gap you measured.
    /// Pass `canvas` and the head also picks its SIDE: outward (down for a width
    /// caliper, right for a height one) unless the readout would fall off the
    /// image there, in which case it flips to the other side. A measurement
    /// half off the canvas is not a measurement.
    public static func clearingHeadOffset(content: MeasureContent,
                                          from start: CGPoint, to end: CGPoint,
                                          canvas: CGSize? = nil) -> CGFloat {
        var probe = content
        probe.start = start
        probe.end = end
        let chip = probe.estimatedLabelSize
        let half = (content.mode == .horizontal ? chip.height : chip.width) / 2
        let reach = max(MeasureContent.defaultHeadOffset,
                        half + MeasureContent.chipLineGap + 6)
        guard let canvas else { return reach }
        let feet = content.mode == .horizontal ? start.y : start.x
        let limit = content.mode == .horizontal ? canvas.height : canvas.width
        if feet + reach + half <= limit { return reach }
        return feet - reach - half >= 0 ? -reach : reach
    }

    /// The layer a placement whose feet run from `start` to `end` (document
    /// coordinates) creates. Frame = padded bbox (+ chip reservation); feet
    /// become layer-local. An alignment payload's items must arrive in DOCUMENT
    /// space (like `start`/`end`); they are re-expressed layer-local too.
    public static func layer(content: MeasureContent, from start: CGPoint, to end: CGPoint) -> Layer {
        var content = content
        content.start = start
        content.end = end
        let g = content.caliperGeometry()
        let pad = content.renderPadding
        var box = boundingBox(of: [g.footA, g.footB, g.headA, g.headB]).insetBy(dx: -pad, dy: -pad)
        // Reserve room for the chip WHERE IT ACTUALLY LANDS — which, when the
        // readout has moved out of the way of its subject (D14), is not on the
        // head line at all.
        if content.showLabel {
            box = box.union(content.labelRect(chipSize: content.estimatedLabelSize))
        }
        // An alignment check also draws each item's tick (and an outlier's
        // actual edge, which can sit well off the guide) — reserve that too.
        if let check = content.alignment {
            for item in check.items {
                let reach = alignmentTickHalf + pad
                switch content.mode {
                case .vertical:
                    box = box.union(CGRect(x: item.edge - reach, y: item.spanStart - pad,
                                           width: reach * 2,
                                           height: max(item.spanEnd - item.spanStart, 1) + pad * 2))
                case .horizontal:
                    box = box.union(CGRect(x: item.spanStart - pad, y: item.edge - reach,
                                           width: max(item.spanEnd - item.spanStart, 1) + pad * 2,
                                           height: reach * 2))
                }
            }
        }
        box.size.width = max(box.size.width, 1)
        box.size.height = max(box.size.height, 1)
        content.start = CGPoint(x: start.x - box.minX, y: start.y - box.minY)
        content.end = CGPoint(x: end.x - box.minX, y: end.y - box.minY)
        if var check = content.alignment {
            check.items = check.items.map { item in
                var item = item
                switch content.mode {
                case .vertical:
                    item.edge -= box.minX
                    item.spanStart -= box.minY
                    item.spanEnd -= box.minY
                case .horizontal:
                    item.edge -= box.minY
                    item.spanStart -= box.minX
                    item.spanEnd -= box.minX
                }
                return item
            }
            content.alignment = check
        }
        let name = content.alignment == nil ? defaultName : defaultAlignmentName
        return Layer(name: name, content: .measure(content), frame: box)
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Redraw a caliper whose feet run between document-space `start` and `end`:
    /// identity, name, style, and `headOffset` survive; the frame is rebuilt.
    public static func updating(_ layer: Layer, start: CGPoint, end: CGPoint) -> Layer {
        guard var m = layer.measure else { return layer }
        // `layer(content:from:to:)` expects alignment items in document space;
        // the stored ones are layer-local to the CURRENT frame.
        if var check = m.alignment {
            check.items = check.items.map { item in
                var item = item
                switch m.mode {
                case .vertical:
                    item.edge += layer.frame.minX
                    item.spanStart += layer.frame.minY
                    item.spanEnd += layer.frame.minY
                case .horizontal:
                    item.edge += layer.frame.minY
                    item.spanStart += layer.frame.minX
                    item.spanEnd += layer.frame.minX
                }
                return item
            }
            m.alignment = check
        }
        return rebuilding(layer, content: m, start: start, end: end)
    }

    /// Rebuild from content whose alignment items (if any) are ALREADY in
    /// document space — the shared tail of `updating` and `resized`.
    private static func rebuilding(_ layer: Layer, content: MeasureContent,
                                   start: CGPoint, end: CGPoint) -> Layer {
        let rebuilt = self.layer(content: content, from: start, to: end)
        var updated = layer
        updated.frame = rebuilt.frame
        updated.content = rebuilt.content
        return updated
    }

    /// Redraw a caliper with a new signed `headOffset` (the head-handle drag),
    /// keeping the feet anchored in document space.
    public static func updating(_ layer: Layer, start: CGPoint, end: CGPoint,
                                headOffset: CGFloat) -> Layer {
        guard var m = layer.measure else { return layer }
        m.headOffset = headOffset
        var updated = layer
        updated.content = .measure(m)
        return updating(updated, start: start, end: end)
    }

    /// Handle-resize remap: feet scale proportionally into the proposed frame and
    /// `headOffset` scales with the perpendicular dimension, then the layer is
    /// rebuilt so strokes keep full padding. (Measures don't expose frame handles,
    /// so this is only hit by whole-document resize.)
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        guard var m = layer.measure,
              layer.frame.width > 0, layer.frame.height > 0 else { return layer }
        func remap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x / layer.frame.width * frame.width,
                    y: frame.minY + p.y / layer.frame.height * frame.height)
        }
        let ratio = m.mode == .horizontal ? frame.height / layer.frame.height
                                          : frame.width / layer.frame.width
        m.headOffset *= ratio
        // Alignment items scale into the new frame's document space alongside
        // the feet (remap() maps a layer-local point there directly, so the
        // shared `rebuilding` tail must not convert them again).
        if var check = m.alignment {
            check.items = check.items.map { item in
                switch m.mode {
                case .vertical:
                    let a = remap(CGPoint(x: item.edge, y: item.spanStart))
                    let b = remap(CGPoint(x: item.edge, y: item.spanEnd))
                    return AlignmentItem(edge: a.x, spanStart: a.y, spanEnd: b.y)
                case .horizontal:
                    let a = remap(CGPoint(x: item.spanStart, y: item.edge))
                    let b = remap(CGPoint(x: item.spanEnd, y: item.edge))
                    return AlignmentItem(edge: a.y, spanStart: a.x, spanEnd: b.x)
                }
            }
            m.alignment = check
        }
        // remap() maps a layer-local point into the new frame's document space.
        let startDoc = remap(m.start), endDoc = remap(m.end)
        return rebuilding(layer, content: m, start: startDoc, end: endDoc)
    }

    /// Where an existing measurement's readout actually sits, in DOCUMENT
    /// space — what the next measurement's readout has to stay off (D14 rule 4).
    public static func readoutRect(of layer: Layer) -> CGRect? {
        guard let m = layer.measure, m.showLabel else { return nil }
        return m.labelRect(chipSize: m.estimatedLabelSize)
            .offsetBy(dx: layer.frame.minX, dy: layer.frame.minY)
    }

    /// The layer's measure with its feet and alignment items re-expressed in
    /// DOCUMENT space (they are stored layer-local once placed).
    public static func documentSpaceContent(of layer: Layer) -> MeasureContent? {
        guard var m = layer.measure else { return nil }
        let origin = layer.frame.origin
        m.start = CGPoint(x: m.start.x + origin.x, y: m.start.y + origin.y)
        m.end = CGPoint(x: m.end.x + origin.x, y: m.end.y + origin.y)
        if var check = m.alignment {
            check.items = check.items.map { item in
                var item = item
                switch m.mode {
                case .vertical:
                    item.edge += origin.x
                    item.spanStart += origin.y
                    item.spanEnd += origin.y
                case .horizontal:
                    item.edge += origin.y
                    item.spanStart += origin.x
                    item.spanEnd += origin.x
                }
                return item
            }
            m.alignment = check
        }
        return m
    }

    /// Re-picks where the readout sits after something moved, and rebuilds the
    /// frame around it. The measurement itself never moves: the feet, the head,
    /// the ticks and the connector stay exactly where they were (D14 rule 5).
    public static func replanningLabel(_ layer: Layer, canvas: CGSize?,
                                       avoiding others: [CGRect] = []) -> Layer {
        guard var m = layer.measure, let probe = documentSpaceContent(of: layer) else { return layer }
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: canvas, avoiding: others)
        guard plan.placement != m.labelPlacement || plan.nudge != m.labelNudge else { return layer }
        m.labelPlacement = plan.placement
        m.labelNudge = plan.nudge
        var updated = layer
        updated.content = .measure(m)
        return updating(updated, start: probe.start, end: probe.end)
    }

    /// Style/readout edit on an existing measure: feet stay anchored in document
    /// space while the frame re-pads for any new stroke width.
    public static func restyled(_ layer: Layer, strokeColorHex: String? = nil,
                                chipColorHex: String? = nil, chipOpacity: CGFloat? = nil,
                                textColorHex: String? = nil, strokeWidth: CGFloat? = nil,
                                showLabel: Bool? = nil, unit: MeasureUnit? = nil, decimals: Int? = nil,
                                mode: MeasureMode? = nil, labelScale: CGFloat? = nil,
                                role: MeasureRole? = nil) -> Layer {
        guard var m = layer.measure,
              let start = layer.measureEndpoint(.start),
              let end = layer.measureEndpoint(.end) else { return layer }
        if let strokeColorHex { m.strokeColorHex = strokeColorHex }
        if let chipColorHex { m.chipColorHex = chipColorHex }
        if let chipOpacity { m.chipOpacity = MeasureContent.clampedOpacity(chipOpacity) }
        if let textColorHex { m.textColorHex = textColorHex }
        if let strokeWidth { m.strokeWidth = strokeWidth }
        if let showLabel { m.showLabel = showLabel }
        if let unit { m.unit = unit }
        if let decimals { m.decimals = decimals }
        if let mode { m.mode = mode }
        if let labelScale { m.labelScale = labelScale }
        if let role { m.role = role }
        var updated = layer
        updated.content = .measure(m)
        return updating(updated, start: start, end: end)
    }
}
