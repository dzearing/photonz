import CoreGraphics
import Foundation

/// The persisted style new calipers start with — the measure tool's own memory,
/// exactly like `AnnotationStyles` is the per-shape memory and `TextStyles` the
/// text tool's. Every measure control the inspector exposes lives here, so the
/// next caliper you draw (this session or after a relaunch) looks like the last
/// one you tuned.
///
/// Defaults are the redlining look the user asked for: a red caliper, a solid
/// darker-red chip, white numbers, a 2px line and a 20px label. (They are NOT
/// `MeasureContent`'s own defaults — those stay pinned to the pre-color-split
/// look so existing documents keep decoding to what they always drew.)
public struct MeasureStyles: Equatable, Codable, Sendable {
    /// Caliper ink: legs, head line, and the chip's border.
    public var strokeColorHex: String
    /// The label chip's fill.
    public var chipColorHex: String
    /// The chip fill's alpha, 0…1 (clamped on assignment).
    public var chipOpacity: CGFloat {
        didSet { chipOpacity = min(max(chipOpacity, 0), 1) }
    }
    /// The numeric readout's color.
    public var textColorHex: String
    public var strokeWidth: CGFloat
    /// The label's size in image pixels — what the inspector's slider shows —
    /// clamped to `MeasureContent.labelSizeRangePx`. Stored in pixels rather than
    /// as a scale so the remembered value means the same thing the UI displayed.
    public var labelSizePx: CGFloat {
        didSet { labelSizePx = Self.clampedLabelSize(labelSizePx) }
    }
    public var unit: MeasureUnit
    public var decimals: Int
    /// Non-destructive effects (shadow, opacity, blur, border, corner radius,
    /// blend) a NEW caliper inherits — captured from the last one you styled, so
    /// a drop shadow you add in Effects carries to the next measure. Same deal
    /// `AnnotationStyles` gives each shape.
    public var layerStyle: LayerStyle
    /// The Snap tool option (`next-measure-center-snap`): true = "Edges and
    /// centers" (measure points also magnetize to element/gap centers), false =
    /// "Edges". Rides with the styles so it stays how you left it.
    public var snapsToCenters: Bool

    public init(strokeColorHex: String = "#FF3B30",
                chipColorHex: String = "#8C201A",
                chipOpacity: CGFloat = 1,
                textColorHex: String = "#FFFFFF",
                strokeWidth: CGFloat = 2,
                labelSizePx: CGFloat = 20,
                // Logical points, not raw bitmap pixels: redlining a UI expects
                // on-screen (design) sizes, and a 2× Retina screenshot's raw
                // pixels read double that.
                unit: MeasureUnit = .points,
                decimals: Int = 0,
                layerStyle: LayerStyle = LayerStyle(),
                // The mock's default: `Snap: Edges and centers`.
                snapsToCenters: Bool = true) {
        self.strokeColorHex = strokeColorHex
        self.chipColorHex = chipColorHex
        self.chipOpacity = min(max(chipOpacity, 0), 1)
        self.textColorHex = textColorHex
        self.strokeWidth = strokeWidth
        self.labelSizePx = Self.clampedLabelSize(labelSizePx)
        self.unit = unit
        self.decimals = decimals
        self.layerStyle = layerStyle
        self.snapsToCenters = snapsToCenters
    }

    private static func clampedLabelSize(_ value: CGFloat) -> CGFloat {
        min(max(value, MeasureContent.labelSizeRangePx.lowerBound),
            MeasureContent.labelSizeRangePx.upperBound)
    }

    /// Every field is optional on decode: a prefs blob written by a build that
    /// predates a field must fill that field in, not fail and drop the whole
    /// remembered style.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeasureStyles()
        self.init(
            strokeColorHex: try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
                ?? d.strokeColorHex,
            chipColorHex: try c.decodeIfPresent(String.self, forKey: .chipColorHex) ?? d.chipColorHex,
            chipOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity) ?? d.chipOpacity,
            textColorHex: try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? d.textColorHex,
            strokeWidth: try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? d.strokeWidth,
            labelSizePx: try c.decodeIfPresent(CGFloat.self, forKey: .labelSizePx) ?? d.labelSizePx,
            unit: try c.decodeIfPresent(MeasureUnit.self, forKey: .unit) ?? d.unit,
            decimals: try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals,
            layerStyle: try c.decodeIfPresent(LayerStyle.self, forKey: .layerStyle) ?? d.layerStyle,
            snapsToCenters: try c.decodeIfPresent(Bool.self, forKey: .snapsToCenters)
                ?? d.snapsToCenters)
    }

    /// The label scale (`MeasureContent.labelScale`) this pixel size means.
    public var labelScale: CGFloat { labelSizePx / MeasureContent.labelFontSize }

    /// The template a new caliper starts from. Axis, feet, and head offset are
    /// set per placement, so the geometry here is placeholder.
    public var content: MeasureContent {
        MeasureContent(mode: .horizontal, strokeWidth: strokeWidth,
                       strokeColorHex: strokeColorHex, chipColorHex: chipColorHex,
                       chipOpacity: chipOpacity, textColorHex: textColorHex,
                       showLabel: true, unit: unit, decimals: decimals,
                       labelScale: labelScale)
    }

    /// Remember an edited caliper's styling as the new default — how a tweak in
    /// the inspector becomes what the NEXT caliper starts with.
    public mutating func absorb(_ content: MeasureContent) {
        strokeColorHex = content.strokeColorHex
        chipColorHex = content.chipColorHex
        chipOpacity = content.chipOpacity
        textColorHex = content.textColorHex
        strokeWidth = content.strokeWidth
        labelSizePx = content.labelPointSize
        unit = content.unit
        decimals = content.decimals
    }
}
