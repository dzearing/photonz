import CoreGraphics
import Foundation

/// The measure tool's remembered ink: the five colour fields a caliper draws
/// with. `MeasureStyles` keeps ONE of these for every mode and role, so a Size
/// caliper recoloured is what the next Gap and Distance start with too (the
/// user, 2026-10-13: "gap vs size shouldn't be different").
public struct MeasureColors: Equatable, Codable, Sendable {
    /// Caliper ink: its legs and its head line.
    public var strokeColorHex: String
    /// The label chip's fill.
    public var chipColorHex: String
    /// The chip fill's alpha, 0…1 (clamped on assignment).
    public var chipOpacity: CGFloat {
        didSet { chipOpacity = MeasureContent.clampedOpacity(chipOpacity) }
    }
    /// The numeric readout's color.
    public var textColorHex: String
    /// The ring round the chip. Nil means the chip is remembered with no ring
    /// at all, which is what a chip whose edge was switched off absorbs.
    public var chipBorderColorHex: String?

    public init(strokeColorHex: String, chipColorHex: String,
                chipOpacity: CGFloat = 1, textColorHex: String = "#FFFFFF",
                chipBorderColorHex: String? = nil) {
        self.strokeColorHex = strokeColorHex
        self.chipColorHex = chipColorHex
        self.chipOpacity = MeasureContent.clampedOpacity(chipOpacity)
        self.textColorHex = textColorHex
        // A set with nothing said about the ring rings the chip in its own ink,
        // which is what every caliper drew before the ring was a part of its own.
        self.chipBorderColorHex = chipBorderColorHex ?? strokeColorHex
    }

    /// The shipped set every new measurement starts in until somebody tunes
    /// it: mid blue caliper and ring, a solid dark navy chip, white numbers.
    /// Sampled from the user's screenshot of 2026-10-13.
    public static let standard = MeasureColors(strokeColorHex: "#3774D5",
                                               chipColorHex: "#233963")

    /// What Size measurements used to start in before the sets were merged,
    /// kept only so a memory that never moved off it moves to `standard`.
    public static let formerSize = MeasureColors(strokeColorHex: "#FF3B30",
                                                 chipColorHex: "#8C201A")
    /// What Gap measurements used to start in, for the same reason.
    public static let formerSpacing = MeasureColors(strokeColorHex: "#0A84FF",
                                                    chipColorHex: "#1B3A66")

    /// A set somebody actually chose, rather than one a build shipped.
    var isTuned: Bool { self != .standard && self != .formerSize && self != .formerSpacing }

    /// Spelled out because both halves of the coding are written by hand now,
    /// so nothing is synthesised to hang them on.
    enum CodingKeys: String, CodingKey {
        case strokeColorHex, chipColorHex, chipOpacity, textColorHex, chipBorderColorHex
    }

    /// Tolerant like `MeasureStyles`: a blob from a build that predates a field
    /// fills that field in (from the shipped set) rather than dropping the memory.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeasureColors.standard
        self.init(
            strokeColorHex: try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
                ?? d.strokeColorHex,
            chipColorHex: try c.decodeIfPresent(String.self, forKey: .chipColorHex) ?? d.chipColorHex,
            chipOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity) ?? d.chipOpacity,
            textColorHex: try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? d.textColorHex,
            // A remembered set written before the chip had a ring of its own
            // rings it in that set's ink, which is what it drew.
            chipBorderColorHex: try c.decodeIfPresent(String.self, forKey: .chipBorderColorHex))
        // A ring written as switched off (the key there, holding null) stays
        // off. The init reads nil as "ring it in the ink", so it is said here.
        if c.contains(.chipBorderColorHex), try c.decodeNil(forKey: .chipBorderColorHex) {
            chipBorderColorHex = nil
        }
    }

    /// Written by hand so a ring switched OFF stays off: the synthesised
    /// encoder drops a nil, and an absent key means "ring it in the ink" here.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(strokeColorHex, forKey: .strokeColorHex)
        try c.encode(chipColorHex, forKey: .chipColorHex)
        try c.encode(chipOpacity, forKey: .chipOpacity)
        try c.encode(textColorHex, forKey: .textColorHex)
        if let chipBorderColorHex {
            try c.encode(chipBorderColorHex, forKey: .chipBorderColorHex)
        } else {
            try c.encodeNil(forKey: .chipBorderColorHex)
        }
    }
}

/// The persisted style new calipers start with — the measure tool's own memory,
/// exactly like `AnnotationStyles` is the per-shape memory and `TextStyles` the
/// text tool's. Every measure control the inspector exposes lives here, so the
/// next caliper you draw (this session or after a relaunch) looks like the last
/// one you tuned.
///
/// Colours are remembered ONCE for every mode and role (`colors`): recolouring
/// a Size caliper, a Gap or a Distance is what the next measurement of any
/// kind starts in. Until 2026-10-13 Size and Spacing each kept a set of their
/// own (red and blue), so a Size recoloured left the next Gap blue and the
/// user read that as the colour not being remembered. `role` is still the
/// last-used role, which tags and names a new caliper and never colours it.
/// (The defaults are NOT `MeasureContent`'s own defaults — those stay pinned
/// to the pre-color-split look so existing documents keep decoding to what
/// they always drew.)
public struct MeasureStyles: Equatable, Codable, Sendable {
    /// The role a NEW caliper takes — the last-used one (creation or a Role
    /// switch absorbs it, like every other default). It never decides colour.
    public var role: MeasureRole
    /// The one remembered ink every new measurement starts in.
    public var colors: MeasureColors
    public var strokeWidth: CGFloat
    /// How thick the readout chip's ring is, shared across roles the way the
    /// caliper's own thickness is. Zero means the next caliper's chip has no
    /// ring at all.
    public var chipBorderWidth: CGFloat
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
    /// The colour a Size measurement's box is tinted, when somebody has picked
    /// one for it. Nil follows the calipers' ink, so the box is blue while
    /// they are blue and turns with them.
    public var sizeBoxColorPick: String?
    /// How faint a Size measurement's box starts (its Opacity), 0…1.
    public var sizeBoxOpacity: CGFloat {
        didSet { sizeBoxOpacity = min(max(sizeBoxOpacity, 0), 1) }
    }

    /// The colour the next Size measurement's box is tinted. Setting it is a
    /// pick of its own, which stops it following Size's ink.
    public var sizeBoxColorHex: String {
        get { sizeBoxColorPick ?? colors.strokeColorHex }
        set { sizeBoxColorPick = newValue }
    }

    public init(role: MeasureRole = .size,
                colors: MeasureColors = .standard,
                strokeWidth: CGFloat = 2,
                chipBorderWidth: CGFloat? = nil,
                labelSizePx: CGFloat = 20,
                // Logical points, not raw bitmap pixels: redlining a UI expects
                // on-screen (design) sizes, and a 2× Retina screenshot's raw
                // pixels read double that.
                unit: MeasureUnit = .points,
                decimals: Int = 0,
                layerStyle: LayerStyle = LayerStyle(),
                // The mock's default: `Snap: Edges and centers`.
                snapsToCenters: Bool = true,
                sizeBoxColorPick: String? = nil,
                sizeBoxOpacity: CGFloat = MeasureSizeGroup.defaultBoxOpacity) {
        self.role = role
        self.colors = colors
        self.strokeWidth = strokeWidth
        self.chipBorderWidth = max(chipBorderWidth ?? strokeWidth, 0)
        self.labelSizePx = Self.clampedLabelSize(labelSizePx)
        self.unit = unit
        self.decimals = decimals
        self.layerStyle = layerStyle
        self.snapsToCenters = snapsToCenters
        self.sizeBoxColorPick = sizeBoxColorPick
        self.sizeBoxOpacity = min(max(sizeBoxOpacity, 0), 1)
    }

    private static func clampedLabelSize(_ value: CGFloat) -> CGFloat {
        min(max(value, MeasureContent.labelSizeRangePx.lowerBound),
            MeasureContent.labelSizeRangePx.upperBound)
    }

    // MARK: The shared colours, field by field

    /// The remembered ink, read and written one field at a time.
    public var strokeColorHex: String {
        get { colors.strokeColorHex }
        set { colors.strokeColorHex = newValue }
    }
    public var chipColorHex: String {
        get { colors.chipColorHex }
        set { colors.chipColorHex = newValue }
    }
    public var chipOpacity: CGFloat {
        get { colors.chipOpacity }
        set { colors.chipOpacity = newValue }
    }
    public var textColorHex: String {
        get { colors.textColorHex }
        set { colors.textColorHex = newValue }
    }

    // MARK: Persistence

    enum CodingKeys: String, CodingKey {
        case role, colors
        // The per-role sets from before the colours were shared: read once,
        // to move whatever somebody tuned into `colors`, and never written.
        case sizeColors, spacingColors
        case strokeWidth, chipBorderWidth
        case labelSizePx, unit, decimals, layerStyle, snapsToCenters
        case sizeBoxColor, sizeBoxOpacity
        // Pre-roles flat color keys: decoded to seed the Size memory (the only
        // set that existed), and mirrored on encode so an older build reading
        // this blob still sees the active colors.
        case strokeColorHex, chipColorHex, chipOpacity, textColorHex
    }

    /// Every field is optional on decode: a prefs blob written by a build that
    /// predates a field must fill that field in, not fail and drop the whole
    /// remembered style. A blob from before the colours were shared moves the
    /// set somebody actually tuned into the shared one (`movedColors`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MeasureStyles()
        let role = try c.decodeIfPresent(MeasureRole.self, forKey: .role) ?? d.role
        let shared = try c.decodeIfPresent(MeasureColors.self, forKey: .colors)
        var boxPick = try c.decodeIfPresent(String.self, forKey: .sizeBoxColor)
        if shared == nil, boxPick?.uppercased() == MeasureColors.formerSize.strokeColorHex {
            // A box left on the old red was the old red because Size was: it
            // follows the new ink rather than staying the one red thing left.
            boxPick = nil
        }
        self.init(
            role: role,
            colors: try shared ?? Self.movedColors(from: c, role: role),
            strokeWidth: try c.decodeIfPresent(CGFloat.self, forKey: .strokeWidth) ?? d.strokeWidth,
            chipBorderWidth: try c.decodeIfPresent(CGFloat.self, forKey: .chipBorderWidth),
            labelSizePx: try c.decodeIfPresent(CGFloat.self, forKey: .labelSizePx) ?? d.labelSizePx,
            unit: try c.decodeIfPresent(MeasureUnit.self, forKey: .unit) ?? d.unit,
            decimals: try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals,
            layerStyle: try c.decodeIfPresent(LayerStyle.self, forKey: .layerStyle) ?? d.layerStyle,
            snapsToCenters: try c.decodeIfPresent(Bool.self, forKey: .snapsToCenters)
                ?? d.snapsToCenters,
            sizeBoxColorPick: boxPick,
            sizeBoxOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .sizeBoxOpacity)
                ?? d.sizeBoxOpacity)
    }

    /// The shared set a memory from an older build moves to: the last-used
    /// role's set if somebody tuned it, else the other role's if THAT was
    /// tuned, else the shipped blue. A set still on what a build shipped (the
    /// old red or blue) was never chosen, so it is not carried over.
    private static func movedColors(from c: KeyedDecodingContainer<CodingKeys>,
                                    role: MeasureRole) throws -> MeasureColors {
        var size = try c.decodeIfPresent(MeasureColors.self, forKey: .sizeColors)
        let spacing = try c.decodeIfPresent(MeasureColors.self, forKey: .spacingColors)
        if size == nil, c.contains(.strokeColorHex) || c.contains(.chipColorHex) {
            // Colours tuned before roles existed were the only set there was.
            let d = MeasureColors.standard
            size = MeasureColors(
                strokeColorHex: try c.decodeIfPresent(String.self, forKey: .strokeColorHex)
                    ?? d.strokeColorHex,
                chipColorHex: try c.decodeIfPresent(String.self, forKey: .chipColorHex)
                    ?? d.chipColorHex,
                chipOpacity: try c.decodeIfPresent(CGFloat.self, forKey: .chipOpacity)
                    ?? d.chipOpacity,
                textColorHex: try c.decodeIfPresent(String.self, forKey: .textColorHex)
                    ?? d.textColorHex)
        }
        let order = role == .spacing ? [spacing, size] : [size, spacing]
        return order.compactMap { $0 }.first(where: \.isTuned) ?? .standard
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(colors, forKey: .colors)
        try c.encode(strokeWidth, forKey: .strokeWidth)
        try c.encode(chipBorderWidth, forKey: .chipBorderWidth)
        try c.encode(labelSizePx, forKey: .labelSizePx)
        try c.encode(unit, forKey: .unit)
        try c.encode(decimals, forKey: .decimals)
        try c.encode(layerStyle, forKey: .layerStyle)
        try c.encode(snapsToCenters, forKey: .snapsToCenters)
        try c.encodeIfPresent(sizeBoxColorPick, forKey: .sizeBoxColor)
        try c.encode(sizeBoxOpacity, forKey: .sizeBoxOpacity)
        // Write-only mirror of the shared colours under the flat pre-roles
        // keys, so a build from before the split still reads a sensible set.
        try c.encode(strokeColorHex, forKey: .strokeColorHex)
        try c.encode(chipColorHex, forKey: .chipColorHex)
        try c.encode(chipOpacity, forKey: .chipOpacity)
        try c.encode(textColorHex, forKey: .textColorHex)
    }

    /// The label scale (`MeasureContent.labelScale`) this pixel size means.
    public var labelScale: CGFloat { labelSizePx / MeasureContent.labelFontSize }

    /// The template a new caliper starts from: the last-used role, drawn in the
    /// remembered ink. Axis, feet, and head offset are set per placement, so
    /// the geometry here is placeholder.
    public var content: MeasureContent { content(for: role) }

    /// The same template forced to a specific role — how Gap mode gets a
    /// Spacing callout without disturbing the remembered last-used role. The
    /// role tags it; the colours are the same shared set whatever the role.
    public func content(for role: MeasureRole) -> MeasureContent {
        let ink = colors
        return MeasureContent(mode: .horizontal, strokeWidth: strokeWidth,
                              strokeColorHex: ink.strokeColorHex, chipColorHex: ink.chipColorHex,
                              chipOpacity: ink.chipOpacity, textColorHex: ink.textColorHex,
                              chipBorderColorHex: ink.chipBorderColorHex ?? ink.strokeColorHex,
                              // A ring the memory has switched off comes out
                              // switched off, which is the whole point of
                              // remembering the last one you tuned.
                              chipBorderWidth: ink.chipBorderColorHex == nil ? 0 : chipBorderWidth,
                              showLabel: true, unit: unit, decimals: decimals,
                              labelScale: labelScale, role: role)
    }

    /// Remember an edited caliper's styling as the new default — how a tweak in
    /// the inspector becomes what the NEXT caliper starts with, in every mode.
    /// The role becomes the last-used one.
    public mutating func absorb(_ content: MeasureContent) {
        role = content.role
        colors.strokeColorHex = content.strokeColorHex
        colors.chipColorHex = content.chipColorHex
        colors.chipOpacity = content.chipOpacity
        colors.textColorHex = content.textColorHex
        colors.chipBorderColorHex = content.hasChipBorder ? content.chipBorderColorHex : nil
        strokeWidth = content.strokeWidth
        if content.hasChipBorder { chipBorderWidth = content.chipBorderWidth }
        labelSizePx = content.labelPointSize
        unit = content.unit
        decimals = content.decimals
    }
}
