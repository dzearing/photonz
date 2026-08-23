import CoreGraphics
import Foundation

/// One measurement role's remembered ink (§5, `next-measure-roles`): the four
/// color fields a caliper draws with. `MeasureStyles` keeps one of these per
/// `MeasureRole`, so switching a measurement's role applies that role's set and
/// style edits absorb into the edited role's memory only.
public struct MeasureRoleColors: Equatable, Codable, Sendable {
    /// Caliper ink: legs, head line, and the chip's border.
    public var strokeColorHex: String
    /// The label chip's fill.
    public var chipColorHex: String
    /// The chip fill's alpha, 0…1 (clamped on assignment).
    public var chipOpacity: CGFloat {
        didSet { chipOpacity = MeasureContent.clampedOpacity(chipOpacity) }
    }
    /// The numeric readout's color.
    public var textColorHex: String

    public init(strokeColorHex: String, chipColorHex: String,
                chipOpacity: CGFloat = 1, textColorHex: String = "#FFFFFF") {
        self.strokeColorHex = strokeColorHex
        self.chipColorHex = chipColorHex
        self.chipOpacity = MeasureContent.clampedOpacity(chipOpacity)
        self.textColorHex = textColorHex
    }

    /// The shipped redliner set — what Size measurements (and every pre-roles
    /// caliper) default to: red ink, solid darker-red chip, white numbers.
    public static let sizeDefault = MeasureRoleColors(strokeColorHex: "#FF3B30",
                                                      chipColorHex: "#8C201A")
    /// The mock's Spacing set: blue ink, solid darker-blue chip, white numbers.
    public static let spacingDefault = MeasureRoleColors(strokeColorHex: "#0A84FF",
                                                         chipColorHex: "#1B3A66")

    /// Tolerant like `MeasureStyles`: a blob from a build that predates a field
    /// fills that field in (from the red set) rather than dropping the memory.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeasureRoleColors.sizeDefault
        self.init(
            strokeColorHex: try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
                ?? d.strokeColorHex,
            chipColorHex: try c.decodeIfPresent(String.self, forKey: .chipColorHex) ?? d.chipColorHex,
            chipOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity) ?? d.chipOpacity,
            textColorHex: try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? d.textColorHex)
    }
}

/// The persisted style new calipers start with — the measure tool's own memory,
/// exactly like `AnnotationStyles` is the per-shape memory and `TextStyles` the
/// text tool's. Every measure control the inspector exposes lives here, so the
/// next caliper you draw (this session or after a relaunch) looks like the last
/// one you tuned.
///
/// Colors are remembered **per role** (§5, `next-measure-roles`): Size keeps
/// the shipped red set, Spacing defaults to the mock's blue set, and `role` is
/// the last-used role — together they are what a NEW caliper takes. Width,
/// label size, unit, and decimals stay shared across roles. (The defaults are
/// NOT `MeasureContent`'s own defaults — those stay pinned to the
/// pre-color-split look so existing documents keep decoding to what they
/// always drew.)
public struct MeasureStyles: Equatable, Codable, Sendable {
    /// The role a NEW caliper takes — the last-used one (creation or a Role
    /// switch absorbs it, like every other default).
    public var role: MeasureRole
    /// Size's remembered ink (the shipped red set until tuned).
    public var sizeColors: MeasureRoleColors
    /// Spacing's remembered ink (the mock's blue set until tuned).
    public var spacingColors: MeasureRoleColors
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

    public init(role: MeasureRole = .size,
                sizeColors: MeasureRoleColors = .sizeDefault,
                spacingColors: MeasureRoleColors = .spacingDefault,
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
        self.role = role
        self.sizeColors = sizeColors
        self.spacingColors = spacingColors
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

    // MARK: Per-role colors

    public func colors(for role: MeasureRole) -> MeasureRoleColors {
        switch role {
        case .size: sizeColors
        case .spacing: spacingColors
        }
    }

    public mutating func updateColors(for role: MeasureRole,
                                      _ mutate: (inout MeasureRoleColors) -> Void) {
        switch role {
        case .size: mutate(&sizeColors)
        case .spacing: mutate(&spacingColors)
        }
    }

    /// The ACTIVE (last-used) role's ink — what the next caliper draws with.
    /// Setters write into that role's memory only.
    public var strokeColorHex: String {
        get { colors(for: role).strokeColorHex }
        set { updateColors(for: role) { $0.strokeColorHex = newValue } }
    }
    public var chipColorHex: String {
        get { colors(for: role).chipColorHex }
        set { updateColors(for: role) { $0.chipColorHex = newValue } }
    }
    public var chipOpacity: CGFloat {
        get { colors(for: role).chipOpacity }
        set { updateColors(for: role) { $0.chipOpacity = newValue } }
    }
    public var textColorHex: String {
        get { colors(for: role).textColorHex }
        set { updateColors(for: role) { $0.textColorHex = newValue } }
    }

    // MARK: Persistence

    enum CodingKeys: String, CodingKey {
        case role, sizeColors, spacingColors
        case strokeWidth, labelSizePx, unit, decimals, layerStyle, snapsToCenters
        // Pre-roles flat color keys: decoded to seed the Size memory (the only
        // set that existed), and mirrored on encode so an older build reading
        // this blob still sees the active colors.
        case strokeColorHex, chipColorHex, chipOpacity, textColorHex
    }

    /// Every field is optional on decode: a prefs blob written by a build that
    /// predates a field must fill that field in, not fail and drop the whole
    /// remembered style. Flat pre-roles color keys seed the Size memory.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeasureStyles()
        var size = try c.decodeIfPresent(MeasureRoleColors.self, forKey: .sizeColors)
        if size == nil {
            // Colors tuned before roles existed were tuned on the only (red)
            // set — they become Size's memory.
            let flat = MeasureRoleColors.sizeDefault
            size = MeasureRoleColors(
                strokeColorHex: try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
                    ?? flat.strokeColorHex,
                chipColorHex: try c.decodeIfPresent(String.self, forKey: .chipColorHex)
                    ?? flat.chipColorHex,
                chipOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity)
                    ?? flat.chipOpacity,
                textColorHex: try c.decodeIfPresent(String.self, forKey: .textColorHex)
                    ?? flat.textColorHex)
        }
        self.init(
            role: try c.decodeIfPresent(MeasureRole.self, forKey: .role) ?? d.role,
            sizeColors: size ?? .sizeDefault,
            spacingColors: try c.decodeIfPresent(MeasureRoleColors.self, forKey: .spacingColors)
                ?? d.spacingColors,
            strokeWidth: try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? d.strokeWidth,
            labelSizePx: try c.decodeIfPresent(CGFloat.self, forKey: .labelSizePx) ?? d.labelSizePx,
            unit: try c.decodeIfPresent(MeasureUnit.self, forKey: .unit) ?? d.unit,
            decimals: try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals,
            layerStyle: try c.decodeIfPresent(LayerStyle.self, forKey: .layerStyle) ?? d.layerStyle,
            snapsToCenters: try c.decodeIfPresent(Bool.self, forKey: .snapsToCenters)
                ?? d.snapsToCenters)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(sizeColors, forKey: .sizeColors)
        try c.encode(spacingColors, forKey: .spacingColors)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(labelSizePx, forKey: .labelSizePx)
        try c.encode(unit, forKey: .unit)
        try c.encode(decimals, forKey: .decimals)
        try c.encode(layerStyle, forKey: .layerStyle)
        try c.encode(snapsToCenters, forKey: .snapsToCenters)
        // Write-only mirror of the active role's colors under the flat pre-roles
        // keys, so a build from before the split still reads a sensible set.
        try c.encode(strokeColorHex, forKey: .strokeColorHex)
        try c.encode(chipColorHex, forKey: .chipColorHex)
        try c.encode(chipOpacity, forKey: .chipOpacity)
        try c.encode(textColorHex, forKey: .textColorHex)
    }

    /// The label scale (`MeasureContent.labelScale`) this pixel size means.
    public var labelScale: CGFloat { labelSizePx / MeasureContent.labelFontSize }

    /// The template a new caliper starts from: the last-used role, drawn in that
    /// role's remembered ink. Axis, feet, and head offset are set per placement,
    /// so the geometry here is placeholder.
    public var content: MeasureContent {
        let ink = colors(for: role)
        return MeasureContent(mode: .horizontal, strokeWidth: strokeWidth,
                              strokeColorHex: ink.strokeColorHex, chipColorHex: ink.chipColorHex,
                              chipOpacity: ink.chipOpacity, textColorHex: ink.textColorHex,
                              showLabel: true, unit: unit, decimals: decimals,
                              labelScale: labelScale, role: role)
    }

    /// Remember an edited caliper's styling as the new default — how a tweak in
    /// the inspector becomes what the NEXT caliper starts with. Colors file
    /// under the content's role; the role itself becomes the last-used one.
    public mutating func absorb(_ content: MeasureContent) {
        role = content.role
        updateColors(for: content.role) {
            $0.strokeColorHex = content.strokeColorHex
            $0.chipColorHex = content.chipColorHex
            $0.chipOpacity = content.chipOpacity
            $0.textColorHex = content.textColorHex
        }
        strokeWidth = content.strokeWidth
        labelSizePx = content.labelPointSize
        unit = content.unit
        decimals = content.decimals
    }
}
