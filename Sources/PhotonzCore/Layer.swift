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
    /// Where the words sit across their box, or nil for the left edge every
    /// piece of text was drawn at before this existed. Only visible when the
    /// box is wider than the words — which is exactly what stretching one does.
    /// See `TextAlign.swift`.
    public var alignment: TextAlign?
    /// And down it, or nil for the top edge.
    public var verticalAlignment: TextVerticalAlign?

    public init(string: String, fontName: String = "SF Pro", fontSize: CGFloat = 24,
                colorHex: String = "#FFFFFF", weight: TextWeight = .regular,
                alignment: TextAlign? = nil, verticalAlignment: TextVerticalAlign? = nil) {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.weight = weight
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        string = try container.decode(String.self, forKey: .string)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        // `weight` postdates TextContent; old payloads omit it.
        weight = try container.decodeIfPresent(TextWeight.self, forKey: .weight) ?? .regular
        // So do both alignments: text saved before them draws from the top
        // left, which is what a missing key means here.
        alignment = try container.decodeIfPresent(TextAlign.self, forKey: .alignment)
        verticalAlignment = try container.decodeIfPresent(TextVerticalAlign.self,
                                                          forKey: .verticalAlignment)
    }
}

public struct AnnotationContent: Hashable, Codable, Sendable {
    public var shape: AnnotationShape
    public var strokeWidth: CGFloat
    /// What the outline is drawn in — and the whole of a line, arrow or
    /// highlight. Flat by default; it holds a gradient once one is chosen.
    public var paint: Paint
    /// The flat color of the outline. Everything that can only draw one color
    /// reads this: the caption pill's tone, a swatch, a contrast reading.
    /// Setting it makes the outline flat, which is what painting a shape a
    /// color means.
    public var colorHex: String {
        get { paint.hex }
        set { paint.hex = newValue; paint.kind = .solid }
    }
    /// For arrows/lines: start and end in layer-local coordinates.
    public var start: CGPoint
    public var end: CGPoint
    /// Arrow-only: user-facing arrowhead size multiplier (1 = the bold default).
    public var arrowheadScale: CGFloat
    /// Rectangle-only: corner radius (layer-local units). 0 = sharp corners. The
    /// rasterizer draws a rounded-rect stroke, so the border follows the corners
    /// instead of being clipped away by a layer-level rounded mask.
    public var cornerRadius: CGFloat
    /// Rectangle/ellipse-only: what the inside is painted with. Nil = no fill
    /// (the classic outline-only redline). Highlight ignores it (its color IS
    /// the fill).
    public var fill: Paint?
    /// The fill's flat color, for everything that can only read one. Setting
    /// it makes the fill flat.
    public var fillColorHex: String? {
        get { fill?.hex }
        set { fill = newValue.map { Paint(hex: $0) } }
    }
    /// Arrow-only: label text rendered as a pill at the arrow's tail, matching
    /// the measure tool's readout treatment. Nil = plain arrow.
    public var caption: String?
    /// Arrow-only: the caption's text size in image pixels.
    public var captionFontSize: CGFloat
    /// Arrow-only: where the pill HANGS FROM, relative to the TAIL (`start`):
    /// the point on the pill's near side that stays put while the caption gets
    /// longer. Nil = the default, one `captionGap` past the tail along the
    /// shaft. Relative to the tail so an endpoint rebuild keeps it valid;
    /// `AnnotationBuilder.planningCaption` picks it against the canvas.
    public var captionOffset: CGSize?
    /// Arrow-only: which way the pill grows from that point, as a unit vector.
    /// Nil = along the shaft, away from the head. Picked once (when the caption
    /// field opens, or when the arrow changes) so a caption being typed grows
    /// away from the arrow instead of the whole bubble sliding off it.
    public var captionGrowth: CGSize?
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
        self.paint = Paint(hex: colorHex)
        self.start = start
        self.end = end
        self.arrowheadScale = arrowheadScale
        self.cornerRadius = cornerRadius
        self.fill = fillColorHex.map { Paint(hex: $0) }
        self.caption = caption
        self.captionFontSize = captionFontSize
        self.captionOffset = nil
        self.captionGrowth = nil
        self.captionPinned = false
    }

    /// `paint` and `fill` keep the key names their flat ancestors wrote —
    /// `colorHex`, `fillColorHex` — because a flat paint still writes a bare
    /// hex string there. Only a gradient writes an object, so a document with
    /// none in it is byte for byte what it always was.
    private enum CodingKeys: String, CodingKey {
        case shape, strokeWidth
        case paint = "colorHex"
        case start, end, arrowheadScale, cornerRadius
        case fill = "fillColorHex"
        case caption, captionFontSize, captionOffset, captionGrowth, captionPinned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shape = try c.decode(AnnotationShape.self, forKey: .shape)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        // A bare hex string is what this key has always held; a gradient
        // writes an object under the same key, so old documents are untouched.
        paint = try c.decode(Paint.self, forKey: .paint)
        start = try c.decode(CGPoint.self, forKey: .start)
        end = try c.decode(CGPoint.self, forKey: .end)
        // `arrowheadScale` postdates AnnotationContent; old payloads omit it.
        arrowheadScale = try c.decodeIfPresent(CGFloat.self, forKey: .arrowheadScale) ?? 1
        // `cornerRadius` postdates AnnotationContent too.
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        // `fillColorHex` postdates both; legacy shapes are outline-only.
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill)
        // Captions postdate everything above; legacy arrows are caption-free.
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        captionFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .captionFontSize)
            ?? Self.captionFontSizeDefault
        // Planned placement postdates captions; absent = the tail default.
        captionOffset = try c.decodeIfPresent(CGSize.self, forKey: .captionOffset)
        // Growth direction postdates the offset; absent = along the shaft.
        captionGrowth = try c.decodeIfPresent(CGSize.self, forKey: .captionGrowth)
        // Hand placement postdates planning; an old offset was the planner's.
        captionPinned = try c.decodeIfPresent(Bool.self, forKey: .captionPinned) ?? false
    }
}

extension AnnotationContent {
    /// Default caption text size (image pixels) — the measure label's default.
    public static let captionFontSizeDefault: CGFloat = 20
    /// The breathing space the caption planner keeps: how far the pill has to
    /// clear the arrowhead by, and how far past the tail the shaft has to run
    /// before the pill counts as sitting ON it. NOT a gap between the tail and
    /// the pill — the pill touches the tail (see `captionAttachment`).
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

    /// The narrowest a caption pill is ever drawn: a fifth wider than the pill
    /// is tall, so a one character caption (or an empty field) still reads as a
    /// badge lying on its side rather than a lozenge standing on end.
    ///
    /// Derived from the font size and padding alone, never from measured
    /// glyphs, because two places need the SAME number: the rasterizer, which
    /// knows the real text height, and `estimatedCaptionSize`, which reserves
    /// the frame from a character count and has no text measurement at all. A
    /// floor either of them could compute differently is a floor the drawn pill
    /// can spill out of. `captionFontSize * 1.4` is SF Pro's line height, which
    /// is what the measured text height comes back as.
    public var captionMinPillWidth: CGFloat {
        (captionFontSize * 1.4 + 2 * captionPadding) * 1.2
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

    /// The pill's fill opacity — as solid as the measure chip. It used to be
    /// 92%, which read as a softer, different control beside a caliper's
    /// readout; the two labels are one treatment.
    public static let captionChipOpacity = Double(MeasureRoleColors.sizeDefault.chipOpacity)

    /// The caption's text color — the measure readout's.
    public static let captionTextColorHex = MeasureRoleColors.sizeDefault.textColorHex

    /// The pill's border, in the arrow's own ink like the measure chip's border
    /// is in the caliper's: heavy enough to read on a thin arrow, still a
    /// hairline beside a thick shaft.
    public var captionBorderWidth: CGFloat { min(max(1.5, strokeWidth / 2), 3) }

    /// The pill around a laid-out line of caption text: padding on every side,
    /// and never narrower than `captionMinPillWidth`. The rasterizer and the
    /// on-canvas field both size themselves with this, so the bubble you type
    /// in is the bubble that lands.
    public func captionPillSize(forTextSize text: CGSize) -> CGSize {
        CGSize(width: max(text.width + 2 * captionPadding, captionMinPillWidth),
               height: text.height + 2 * captionPadding)
    }

    /// A capsule, whatever the pill's height — the measure chip's corner.
    public func captionCornerRadius(pillHeight: CGFloat) -> CGFloat { pillHeight / 2 }

    /// A generous estimate of the caption pill's footprint, used for frame
    /// reservation and hit-testing. The rasterizer measures the real text and
    /// hangs the (smaller) pill from the same attachment, so it always sits
    /// inside the box this estimate reserved — which is why the same width
    /// floor the rasterizer draws with is applied here too: without it a one
    /// character caption reserves less room than it draws.
    public var estimatedCaptionSize: CGSize {
        let chars = CGFloat(max(caption?.count ?? 0, 1) + 1)
        let w = max(chars * captionFontSize * 0.75 + 2 * captionPadding, captionMinPillWidth)
        let h = captionFontSize * 1.3 + 2 * captionPadding
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }

    /// The pill a caption's spot is picked against when the field opens: room
    /// for a real sentence (about 24 characters) at this caption's size, so the
    /// direction chosen on the first keystroke still holds the last one.
    public var captionRoomProbeSize: CGSize {
        var probe = self
        probe.caption = String(repeating: "n", count: 24)
        let room = probe.estimatedCaptionSize
        let now = estimatedCaptionSize
        return CGSize(width: max(room.width, now.width), height: max(room.height, now.height))
    }

    /// Which way the pill grows from its attachment: a unit vector. The picked
    /// direction when there is one, otherwise the way the shaft runs away from
    /// the head, squared off to that shaft's dominant axis. A zero-length arrow
    /// grows upward.
    ///
    /// Squared off because a caption is a wide, short capsule: let it grow on a
    /// diagonal and the corner nearest the arrow slides sideways with every
    /// character, which is the drift this whole anchoring exists to stop. On the
    /// axes — where most arrows are drawn — this is exactly the shaft direction.
    public func captionGrowthDirection() -> CGSize {
        if let captionGrowth {
            let length = hypot(captionGrowth.width, captionGrowth.height)
            if length > 0 {
                return CGSize(width: captionGrowth.width / length,
                              height: captionGrowth.height / length)
            }
        }
        let dx = start.x - end.x
        let dy = start.y - end.y
        if dx == 0, dy == 0 { return CGSize(width: 0, height: -1) }
        if abs(dx) >= abs(dy) { return CGSize(width: dx < 0 ? -1 : 1, height: 0) }
        return CGSize(width: 0, height: dy < 0 ? -1 : 1)
    }

    /// The point the pill hangs from (same coordinate space as `start`/`end`):
    /// the middle of its near side. By default that point IS the tail, so the
    /// shaft runs into the pill and the two read as one object; a planned or
    /// hand-placed spot overrides it. This point does NOT move when the caption
    /// gets longer, which is what makes a caption being typed grow away from
    /// the arrow instead of walking off it.
    ///
    /// It used to sit one `captionGap` past the tail. The pill then floated
    /// beside the arrow rather than being attached to it, which is what the
    /// user reported on 2026-09-05.
    public func captionAttachment() -> CGPoint {
        if let captionOffset {
            return CGPoint(x: start.x + captionOffset.width, y: start.y + captionOffset.height)
        }
        return start
    }

    /// Where a pill of `size` centers: the attachment plus half the pill's
    /// reach along the growth direction. Pass the measured pill (the rasterizer
    /// and the on-canvas field both do) and the near side lands exactly on the
    /// attachment; pass the estimate and you get `captionAnchor`.
    public func captionPillCenter(forPillSize size: CGSize) -> CGPoint {
        let d = captionGrowthDirection()
        let attachment = captionAttachment()
        let extent = (abs(d.width) * size.width + abs(d.height) * size.height) / 2
        return CGPoint(x: attachment.x + d.width * extent, y: attachment.y + d.height * extent)
    }

    /// Where the pill centers at its ESTIMATED size: what frame reservation and
    /// hit-testing use, so the generous box they draw around the label always
    /// starts at the same attachment the real pill does.
    public func captionAnchor() -> CGPoint {
        captionPillCenter(forPillSize: estimatedCaptionSize)
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

/// A layer whose content is other layers.
///
/// Children are held in the same bottom-up order as the document's top-level
/// stack (index 0 draws first). Each child's `frame` is measured from the
/// GROUP'S OWN ORIGIN, not from the canvas, which is what lets the same subtree
/// sit in two places at once without rewriting a number inside it. Groups only
/// translate — they never scale or rotate what they hold — so a layer's canvas
/// position is the sum of the origins from it up to the canvas, plain addition.
/// See `docs/design/ui-building.md`.
/// A **frame** is this same group with `isFrame` set: the one difference is
/// that its layer's stored `frame.size`, unused by an ordinary group, becomes
/// a real box the contents live in. That is what a screen is built on, and it
/// is why a document can hold several screens side by side without growing a
/// pages concept of its own.
public struct GroupContent: Hashable, Codable, Sendable {
    public var children: [Layer]
    /// Whether this group is a frame: a fixed box with a size of its own,
    /// rather than a box that follows whatever is inside it.
    public var isFrame: Bool
    /// What somebody has SAID about hiding whatever sticks out past this
    /// container's box, or nil while nobody has said anything. Kept apart from
    /// the answer below because the two kinds of container start from opposite
    /// places: a screen has always cut off what leaves it, and a group has
    /// always let it hang out, so a document saved before a group could be
    /// asked opens drawing exactly what it drew.
    var clipsContentsSetting: Bool?

    /// Whether this container hides what sticks out past its box. Meaningless
    /// for a container with no box of its own (`Layer.hasBoxOfItsOwn`), which
    /// has nothing hanging out of it in the first place.
    public var clipsContents: Bool {
        get { clipsContentsSetting ?? isFrame }
        set { clipsContentsSetting = newValue }
    }
    /// The surface a frame paints behind its contents ("#FFFFFF" for a white
    /// screen), or nil for a frame you can see straight through. Ordinary
    /// groups never paint one. Flat by default; it holds a gradient once one
    /// is chosen.
    public var background: Paint?
    /// The surface's flat color, for everything that can only read one.
    /// Setting it makes the surface flat.
    public var backgroundHex: String? {
        get { background?.hex }
        set { background = newValue.map { Paint(hex: $0) } }
    }
    /// Set on a **main component**: the identity every future instance points
    /// at, and what the Library lists (`docs/design/ui-building.md`, step C4).
    /// It is not the layer's own id, because a copy of a main is its own
    /// component and needs an identity that did not exist before.
    public var componentID: UUID?
    /// Set on a **main component** that is one of several versions of itself:
    /// which version this drawing is (`ComponentVersion`). Nil on a component
    /// that has only ever had one, which is every component saved before
    /// versions existed.
    public var versionID: UUID?
    /// Set on a **main component**: what this version is called in the menu on
    /// a copy — "Default", "Disabled". Nil while the component has one version,
    /// because there is nothing to tell it apart from.
    public var versionName: String?
    /// Set on an **instance**: the component this copy follows
    /// (`docs/design/ui-building.md`, step C5). Its children are not its own —
    /// the document keeps them equal to the main's, so editing the main is the
    /// only way anything inside a copy changes.
    public var instanceOf: UUID?
    /// Set on an **instance**: which version of its component this copy shows.
    /// Nil is a copy showing the component's first version, which is every copy
    /// of a component that has only one.
    public var instanceVersion: UUID?
    /// Set on a **main component**: the knobs it exposes, which are the only
    /// things a copy of it may set (`docs/design/ui-building.md`, step C6).
    /// Each one reaches one layer inside this group.
    public var properties: [ComponentProperty]
    /// Set on an **instance**: this copy's answers to the knobs its original
    /// exposes. They are the only things a copy owns; everything else inside it
    /// is refilled from the original after every edit.
    public var overrides: [ComponentOverride]
    /// Set on an **instance**: the original's look as of the last time this
    /// copy was put in step with it. Anything the copy's own look differs from
    /// this by is a part somebody set on the copy, and that part stops
    /// following (`docs/design/ui-building.md`, "A copy follows the original's
    /// look"). Nil means this copy has never met its original — a document
    /// saved before the look followed — and the next sync adopts the
    /// original's look as the memory without changing one pixel.
    public var followedStyle: LayerStyle?
    /// Set on an **instance**: the width and height this copy has been given
    /// for itself, where it has been given them (`InstanceSize`). Nil, or a nil
    /// side, is a copy that is the size of its original on that side — which is
    /// every copy until somebody drags its handle or types a number. It is
    /// written OVER the original's layout after every edit rather than refilled
    /// from it, which is what makes the same nav bar 1200 wide on a desktop
    /// screen and 375 on a phone without either one leaving the family.
    public var instanceSize: InstanceSize?
    /// How everything inside this group lines up when the group is resized —
    /// the container's default, which any one child may override with its own
    /// `Layer.placement` (`docs/design/ui-building.md`, "Resizing places the
    /// pieces"). Nil, or a nil axis, means the proportional multiply this app
    /// did before placement existed, so a group made before it decodes and
    /// resizes exactly as it always has.
    public var contentPlacement: LayerPlacement?
    /// Set when this group arranges its own contents: a stack along one axis,
    /// or a grid of rows (`GroupLayout`). Nil is a group that holds whatever
    /// you dragged into it wherever you dragged it, which is every group this
    /// app has ever made and every group in every document saved before this.
    public var layout: GroupLayout?

    public init(children: [Layer] = [], isFrame: Bool = false,
                clipsContents: Bool? = nil, backgroundHex: String? = nil,
                componentID: UUID? = nil, instanceOf: UUID? = nil,
                properties: [ComponentProperty] = [], overrides: [ComponentOverride] = [],
                followedStyle: LayerStyle? = nil, contentPlacement: LayerPlacement? = nil) {
        self.children = children
        self.isFrame = isFrame
        // A screen is born with the answer it has always given, so it saves and
        // opens byte for byte as it did. A group is born with none.
        self.clipsContentsSetting = clipsContents ?? (isFrame ? true : nil)
        self.background = backgroundHex.map { Paint(hex: $0) }
        self.componentID = componentID
        self.instanceOf = instanceOf
        self.properties = properties
        self.overrides = overrides
        self.followedStyle = followedStyle
        self.contentPlacement = contentPlacement
    }

    private enum CodingKeys: String, CodingKey {
        case children, isFrame, clipsContents, backgroundHex, componentID, instanceOf
        case properties, overrides, followedStyle, instanceSize, contentPlacement, layout
        case versionID, versionName, instanceVersion
    }

    /// Only a frame writes the frame keys and only a main writes the component
    /// key, so an ordinary group encodes exactly as it did before either
    /// existed and a document saved then decodes unchanged.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(children, forKey: .children)
        try c.encodeIfPresent(componentID, forKey: .componentID)
        try c.encodeIfPresent(instanceOf, forKey: .instanceOf)
        // Only a component somebody gave a second version to writes these, so
        // one saved before versions existed is byte for byte what it was.
        if componentID != nil {
            try c.encodeIfPresent(versionID, forKey: .versionID)
            try c.encodeIfPresent(versionName, forKey: .versionName)
        }
        if instanceOf != nil { try c.encodeIfPresent(instanceVersion, forKey: .instanceVersion) }
        // A group that exposes nothing and answers nothing writes neither key,
        // so a document saved before knobs existed is byte for byte what it was.
        if !properties.isEmpty { try c.encode(properties, forKey: .properties) }
        if !overrides.isEmpty { try c.encode(overrides, forKey: .overrides) }
        // Only a copy remembers a look, so a group that is not one encodes
        // exactly as it did before the look followed.
        if instanceOf != nil { try c.encodeIfPresent(followedStyle, forKey: .followedStyle) }
        // ...and only a copy somebody has resized writes a size of its own, so
        // a copy that follows its original is byte for byte what it always was.
        if instanceOf != nil, instanceSize?.isFollowing == false {
            try c.encode(instanceSize, forKey: .instanceSize)
        }
        // A group that never had a placement set writes no key, so a document
        // saved before placement existed is byte for byte what it was.
        try c.encodeIfPresent(contentPlacement?.normalized, forKey: .contentPlacement)
        // Only a group somebody asked to arrange itself writes this key, so a
        // document saved before stacks and grids existed is byte for byte what
        // it was.
        try c.encodeIfPresent(layout, forKey: .layout)
        // A group nobody has asked about cutting off its overflow writes no
        // key, so a document saved before it could be asked is byte for byte
        // what it was.
        if !isFrame { try c.encodeIfPresent(clipsContentsSetting, forKey: .clipsContents) }
        guard isFrame else { return }
        try c.encode(true, forKey: .isFrame)
        try c.encode(clipsContents, forKey: .clipsContents)
        try c.encodeIfPresent(background, forKey: .backgroundHex)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        children = try c.decode([Layer].self, forKey: .children)
        isFrame = try c.decodeIfPresent(Bool.self, forKey: .isFrame) ?? false
        clipsContentsSetting = try c.decodeIfPresent(Bool.self, forKey: .clipsContents)
        // A bare hex string is what this key has always held; a gradient
        // writes an object under the same key.
        background = try c.decodeIfPresent(Paint.self, forKey: .backgroundHex)
        componentID = try c.decodeIfPresent(UUID.self, forKey: .componentID)
        instanceOf = try c.decodeIfPresent(UUID.self, forKey: .instanceOf)
        versionID = try c.decodeIfPresent(UUID.self, forKey: .versionID)
        versionName = try c.decodeIfPresent(String.self, forKey: .versionName)
        instanceVersion = try c.decodeIfPresent(UUID.self, forKey: .instanceVersion)
        properties = try c.decodeIfPresent([ComponentProperty].self, forKey: .properties) ?? []
        overrides = try c.decodeIfPresent([ComponentOverride].self, forKey: .overrides) ?? []
        followedStyle = try c.decodeIfPresent(LayerStyle.self, forKey: .followedStyle)
        instanceSize = try c.decodeIfPresent(InstanceSize.self, forKey: .instanceSize)
        contentPlacement = try c.decodeIfPresent(LayerPlacement.self, forKey: .contentPlacement)
        layout = try c.decodeIfPresent(GroupLayout.self, forKey: .layout)
    }
}

public enum LayerContent: Hashable, Codable, Sendable {
    case image(ImageRef)
    case text(TextContent)
    case annotation(AnnotationContent)
    case zoomCallout(ZoomCalloutContent)
    case measure(MeasureContent)
    case collage(CollageContent)
    case group(GroupContent)

    /// True when this content's rendered appearance scales uniformly with the
    /// frame. Photos and collages do — every pixel is frame-relative. Annotation
    /// strokes, text glyphs, zoom-callout chrome, and measure ticks are all sized
    /// in fixed points, so scaling a start-frame sprite stretches them; a resize
    /// of that content must re-render rather than scale a sprite.
    var scalesUniformlyOnResize: Bool {
        switch self {
        case .image, .collage: true
        // A group holds strokes, glyphs and ticks whose sizes are fixed in
        // points, so scaling a sprite of it stretches them.
        case .annotation, .text, .zoomCallout, .measure, .group: false
        }
    }

    /// The same content with a fresh identity everywhere inside it. Leaves have
    /// no identity of their own so they come back unchanged; a group's children
    /// are copied all the way down, so duplicating a group never leaves two
    /// layers in the document sharing one id.
    func reidentified(map: inout [UUID: UUID]) -> LayerContent {
        guard case .group(var group) = self else { return self }
        group.children = group.children.map { $0.reidentified(map: &map) }
        // A copy of a main is a component of its own, not a second layer
        // claiming to be the same one: editing either must never move the
        // other, and the shelf must be able to tell them apart.
        if group.componentID != nil {
            group.componentID = UUID()
            // ...and it is a component of ONE version again: the versions of
            // the component it was copied from are not its.
            group.versionID = nil
            group.versionName = nil
        }
        // `instanceOf` is deliberately kept: a copy of a copy is another copy
        // of the same component, which is what ⌘J on an instance has to mean,
        // and its answers come with it or a configured copy would silently
        // reset when duplicated.
        return .group(group)
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

    /// True when this style draws nothing of its own: no fade, no blur, no
    /// rounded corners, no border, no shadow, plain blending. A group styled
    /// like this is a container rather than an object, so its children can draw
    /// straight onto the canvas and grouping changes no pixels.
    public var isPlain: Bool {
        opacity >= 1 && blurRadius <= 0 && cornerRadius <= 0 && borderWidth <= 0
            && (shadow?.opacity ?? 0) <= 0 && blendMode == .normal
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
    /// Position and size in the coordinate space of whatever contains this
    /// layer: the canvas for a top-level layer, the enclosing group's origin
    /// for a child. For a GROUP the origin is the anchor its children are
    /// measured from and the size is unused — a group's box follows its
    /// contents and is read from `localBounds`, never stored, so drawing a
    /// child that sticks out never silently rewrites its siblings' numbers.
    public var frame: CGRect
    /// Optional crop applied to the layer's own content, in layer-local coordinates.
    public var crop: CGRect?
    /// Geometric transform (rotation/skew/flip) applied at render time, around the frame's center.
    public var transform: LayerTransform
    public var style: LayerStyle
    public var isVisible: Bool
    public var isLocked: Bool
    /// Which of this layer's colors come from a named style rather than being
    /// its own (`docs/design/ui-building.md`, step D8). Nil until somebody
    /// saves a color as a style and points this layer at it, so a layer that
    /// has never met one writes exactly what it always wrote.
    public var colorStyleBindings: [ColorStyleBinding]?
    /// What this layer does when the group holding it is resized, overriding
    /// that group's default one axis at a time (`docs/design/ui-building.md`,
    /// "Resizing places the pieces"). Nil, or a nil axis, means follow the
    /// container, so a layer that has never been given one behaves exactly as
    /// it always did.
    public var placement: LayerPlacement?
    /// Set where this piece has been told to take the room the stack holding
    /// it has left over along the way that stack runs, instead of keeping the
    /// size it was drawn at (`docs/design/ui-building.md`, "A piece can take
    /// the room a row has left over"). Nil is every piece that has never been
    /// told to, which is every piece in every document written before this.
    public var flowFill: FlowFill?

    public init(id: UUID = UUID(), name: String, content: LayerContent, frame: CGRect,
                crop: CGRect? = nil, transform: LayerTransform = .identity,
                style: LayerStyle = LayerStyle(), isVisible: Bool = true, isLocked: Bool = false,
                colorStyleBindings: [ColorStyleBinding]? = nil,
                placement: LayerPlacement? = nil,
                flowFill: FlowFill? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.frame = frame
        self.crop = crop
        self.transform = transform
        self.style = style
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.colorStyleBindings = colorStyleBindings
        self.placement = placement
        self.flowFill = flowFill
    }

    /// A copy with a fresh identity, for duplicate/paste. The frame offset
    /// keeps the copy from landing invisibly on top of the original.
    public func duplicated(offsetBy offset: CGPoint = .zero) -> Layer {
        var map: [UUID: UUID] = [:]
        var copy = Layer(name: name + " copy", content: content.reidentified(map: &map),
                         frame: frame.offsetBy(dx: offset.x, dy: offset.y),
                         crop: crop, transform: transform, style: style,
                         isVisible: isVisible, isLocked: false,
                         colorStyleBindings: colorStyleBindings, placement: placement,
                         flowFill: flowFill)
        copy.repointComponentProperties(map)
        return copy
    }

    /// A copy of this layer and everything inside it with fresh ids, keeping
    /// the names, geometry and styling exactly as they are. This is what makes
    /// the same subtree able to sit in two places: the insides are identical
    /// and, because children are stored against their parent, not one number
    /// inside them has to change.
    public func reidentified() -> Layer {
        var map: [UUID: UUID] = [:]
        var copy = reidentified(map: &map)
        copy.repointComponentProperties(map)
        return copy
    }

    /// The same layer with fresh ids, recording what became what so anything
    /// that pointed at an old id can be pointed at the new one.
    func reidentified(map: inout [UUID: UUID]) -> Layer {
        let copy = Layer(name: name, content: content.reidentified(map: &map), frame: frame,
                         crop: crop, transform: transform, style: style,
                         isVisible: isVisible, isLocked: isLocked,
                         colorStyleBindings: colorStyleBindings, placement: placement,
                         flowFill: flowFill)
        map[id] = copy.id
        return copy
    }

    /// Points a duplicated original's knobs at its OWN layers.
    ///
    /// Duplicating a main mints a second component, and every knob on it names
    /// a layer inside by id. Without this the second component's knobs would
    /// still reach into the first one, so setting a copy of the new component
    /// would quietly edit the old one's insides. A copy's ANSWERS are left
    /// alone on purpose: they name knobs and shapes belonging to the original
    /// it follows, which is not being duplicated here.
    mutating func repointComponentProperties(_ map: [UUID: UUID]) {
        guard var group else { return }
        if !group.properties.isEmpty {
            for index in group.properties.indices {
                if let moved = map[group.properties[index].target] {
                    group.properties[index].target = moved
                }
            }
        }
        for index in group.children.indices {
            group.children[index].repointComponentProperties(map)
        }
        content = .group(group)
    }

    /// This layer's own content, if it is a group.
    public var group: GroupContent? {
        if case .group(let g) = content { return g }
        return nil
    }

    /// Whether this layer holds other layers.
    public var isGroup: Bool { group != nil }

    /// Whether this layer is a frame: a group with a size of its own, which is
    /// what a screen gets built on.
    public var isFrame: Bool { group?.isFrame == true }

    /// Whether this layer has a box of its own that its contents can hang out
    /// of: a screen, or a group somebody gave a width, a height or a largest
    /// size. A group that closes around its contents has nothing sticking out
    /// of it, so there is nothing there to cut off and no switch to offer.
    public var hasBoxOfItsOwn: Bool {
        guard let group else { return false }
        return group.isFrame || group.layout?.hasSizeOfItsOwn == true
    }

    /// Whether this layer hides what sticks out past its box. False for
    /// everything with no box of its own, however it is set.
    public var clipsToBounds: Bool { hasBoxOfItsOwn && group?.clipsContents == true }

    /// The canvas region this layer magnifies, for a zoom callout; nil for
    /// everything else.
    public var magnifiedSource: CGRect? {
        if case .zoomCallout(let callout) = content { return callout.sourceRect.standardized }
        return nil
    }

    /// The layers this one contains, empty for everything that is not a group.
    public var children: [Layer] {
        get { group?.children ?? [] }
        set {
            guard case .group(var g) = content else { return }
            g.children = newValue
            content = .group(g)
        }
    }

    /// This layer and every layer inside it, outermost first.
    public var selfAndDescendants: [Layer] {
        [self] + children.flatMap(\.selfAndDescendants)
    }

    /// The box this layer occupies in its PARENT'S coordinate space. A leaf is
    /// just its frame. A group is the union of its children's boxes shifted by
    /// the group's origin, so the box is always derived and never stored; an
    /// empty group is a zero-size box sitting on its own anchor.
    public var localBounds: CGRect {
        guard let group else { return frame }
        // A frame is the exception that makes screens possible: its box is the
        // size it was given and holds still, so drawing something that hangs
        // off the edge never resizes the screen you are building.
        if group.isFrame { return frame.standardized }
        // A group that arranges itself flows from its own corner, so its box
        // starts there: as wide and as tall as it was told to be, and where it
        // was told nothing, as big as what is inside it plus the space it keeps
        // clear at the edges.
        if let layout = group.layout { return arrangedBounds(group, layout) }
        var union: CGRect?
        for child in group.children {
            let box = child.localBounds
            union = union.map { $0.union(box) } ?? box
        }
        guard let union else { return CGRect(origin: frame.origin, size: .zero) }
        return union.offsetBy(dx: frame.origin.x, dy: frame.origin.y)
    }

    /// The box a group with a layout occupies: the size it was given on each
    /// axis, and on an axis it was given none, its contents plus the room it
    /// keeps on both of that axis' edges. Measured from the corner it flows
    /// from, never from the leftmost thing in it, so hiding the first row
    /// cannot slide the box.
    ///
    /// The sum itself lives in `GroupFlow.size`, with the flow that puts the
    /// contents there, so the box and the arrangement can never disagree about
    /// what counts (`docs/design/ui-building.md`, "A container closes around
    /// its contents").
    private func arrangedBounds(_ group: GroupContent, _ layout: GroupLayout) -> CGRect {
        CGRect(origin: frame.origin,
               size: GroupFlow.size(of: group.children, layout: layout,
                                    contentPlacement: group.contentPlacement,
                                    bounds: GroupFlow.Bounds.of(self, group, layout),
                                    onAScreen: group.isFrame))
    }

    /// The box this layer's DRAWING can touch in its parent's space, which is
    /// bigger than `localBounds` wherever a shadow or a blur reaches past the
    /// box. A group renders into a buffer this size, so nothing inside it is
    /// clipped: its own reach unioned with the reach of everything it holds.
    public var renderBounds: CGRect {
        let box = localBounds
        guard let group else { return box.insetBy(dx: -style.previewPadding, dy: -style.previewPadding) }
        // Nothing inside a clipping container can draw past its edge, so its
        // reach is its box plus whatever its own shadow adds.
        if clipsToBounds {
            return box.insetBy(dx: -style.previewPadding, dy: -style.previewPadding)
        }
        var reach = box
        for child in group.children {
            reach = reach.union(child.renderBounds.offsetBy(dx: frame.origin.x, dy: frame.origin.y))
        }
        return reach.insetBy(dx: -style.previewPadding, dy: -style.previewPadding)
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
        if let group {
            // A group has no shape of its own: the point lands on it only when
            // it lands on something it actually holds, so the empty space
            // between two children never swallows a click. Children are stored
            // against the group's origin, so the point moves into their space.
            let local = CGPoint(x: p.x - frame.origin.x, y: p.y - frame.origin.y)
            if group.isFrame {
                // A frame IS a surface — a screen you build on — so its whole
                // box takes a click even where it is empty, and a child that
                // hangs outside a clipping frame is not on screen to be hit.
                if localBounds.contains(p) { return true }
                guard !group.clipsContents else { return false }
            } else if clipsToBounds, !localBounds.contains(p) {
                // A group that cuts off what leaves it is not a surface: it
                // takes no click of its own, but what it cut away is not on
                // screen to be hit either.
                return false
            }
            return group.children.contains { $0.contains(canvasPoint: local, zoom: zoom) }
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
