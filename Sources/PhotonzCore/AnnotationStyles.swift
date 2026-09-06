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

    /// What the saved colours these tools are holding were CALLED when they
    /// were picked up, keyed by id.
    ///
    /// A layer needs no such thing: it lives in the document that owns the
    /// name, so it can always ask. What a tool holds outlives the document,
    /// which is exactly the case where the app has something to say — "there is
    /// no Accent here" — and no document to ask. So the name rides along.
    private var heldStyleNames: [String: String] = [:]

    public init() {
        var shapes: [String: ShapeDefaults] = [:]
        for shape in AnnotationShape.allCases {
            shapes[shape.rawValue] = ShapeDefaults.standard(for: shape)
        }
        self.shapes = shapes
    }

    private enum CodingKeys: String, CodingKey {
        case shapes
        case heldColorStyleNames
        // Legacy single-bucket keys (pre per-shape); migrated on decode.
        case strokeColorHex, highlightColorHex, strokeWidth, arrowheadScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Prefs written before names rode along hold ids and nothing else. The
        // sentences fall back to saying "the saved color it was holding".
        heldStyleNames = try c.decodeIfPresent([String: String].self,
                                               forKey: .heldColorStyleNames) ?? [:]
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
        // Nothing at all when no tool is holding a name, so prefs that have
        // never met a saved colour write exactly what they always wrote.
        if !heldStyleNames.isEmpty {
            try c.encode(heldStyleNames, forKey: .heldColorStyleNames)
        }
    }

    // MARK: - Per-shape accessors

    private func defaults(forShape shape: AnnotationShape) -> ShapeDefaults {
        shapes[shape.rawValue] ?? ShapeDefaults.standard(for: shape)
    }

    public func colorHex(forShape shape: AnnotationShape) -> String { defaults(forShape: shape).colorHex }

    /// What the next shape of this kind is drawn IN, gradient and all.
    public func paint(forShape shape: AnnotationShape) -> Paint { defaults(forShape: shape).paint }

    public func strokeWidth(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).strokeWidth }

    public func arrowheadScale(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).arrowheadScale }

    /// Interior fill new rectangles/ellipses start with; nil = no fill.
    public func fillColorHex(forShape shape: AnnotationShape) -> String? { defaults(forShape: shape).fillColorHex }

    /// The interior new boxes of this kind start with, gradient and all;
    /// nil = no fill.
    public func fillPaint(forShape shape: AnnotationShape) -> Paint? { defaults(forShape: shape).fill }

    /// Corner radius new rectangles start with.
    public func cornerRadius(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).cornerRadius }

    /// Caption text size (image pixels) new arrows start with.
    public func captionFontSize(forShape shape: AnnotationShape) -> CGFloat { defaults(forShape: shape).captionFontSize }

    /// The non-destructive effects (shadow, opacity, blur, …) a NEW annotation
    /// of this shape starts with — captured from the last one the user styled,
    /// so e.g. adding a drop shadow to one arrow carries to the next.
    public func layerStyle(forShape shape: AnnotationShape) -> LayerStyle { defaults(forShape: shape).layerStyle }

    public mutating func setColorHex(_ hex: String, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].colorHex = hex
        setColorStyleID(nil, slot: .stroke, forShape: shape)
    }

    /// Arms this shape's outline with a paint. A gradient here is what makes a
    /// whole run of shapes come out gradient without painting each one.
    ///
    /// Any saved colour the tool was holding is let go of here, because a plain
    /// colour is a plain colour: this is the one way an outline gets painted
    /// without a name, so it is the one place the name has to come off.
    public mutating func setPaint(_ paint: Paint, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].paint = paint
        setColorStyleID(nil, slot: .stroke, forShape: shape)
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

    public mutating func setFillColorHex(_ hex: String?, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].fillColorHex = hex
        setColorStyleID(nil, slot: .fill, forShape: shape)
    }

    /// Arms this shape's interior with a paint; nil = no fill. Any saved colour
    /// the interior was holding comes off, for the same reason it does on the
    /// outline.
    public mutating func setFillPaint(_ paint: Paint?, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].fill = paint
        setColorStyleID(nil, slot: .fill, forShape: shape)
    }

    // MARK: - The saved colour a tool is holding

    /// The saved colour this shape's tool draws a slot in, or nil when the
    /// colour there is just a colour.
    ///
    /// It is only ever an id. What the colour actually IS lives in the open
    /// document, and the document is asked every time a shape is drawn — this
    /// preference outlives any one document, so an id from a document that is
    /// closed means nothing and has to fall back to the flat paint beside it.
    /// `PhotonzDocument.wearingArmedColorStyles` is where that happens.
    public func colorStyleID(forShape shape: AnnotationShape, slot: ColorSlot) -> UUID? {
        defaults(forShape: shape).colorStyleID(for: slot)
    }

    /// Points this shape's tool at a saved colour, or lets go of the one it was
    /// holding. Painting the slot any other way lets go by itself.
    ///
    /// `name` is what that colour is called right now, kept beside the id so
    /// the app can still say it in a document that has never heard of it. It
    /// is optional because letting go needs no name, and because the two
    /// callers that only move an id around have nothing new to teach.
    public mutating func setColorStyleID(_ id: UUID?, slot: ColorSlot,
                                         forShape shape: AnnotationShape,
                                         name: String? = nil) {
        shapes[shape.rawValue, default: .standard(for: shape)].setColorStyleID(id, for: slot)
        if let id, let name, !name.isEmpty { heldStyleNames[id.uuidString] = name }
        forgetUnheldStyleNames()
    }

    /// What the saved colour with this id was called when a tool picked it up,
    /// or nil when no tool ever learned its name.
    public func heldColorStyleName(_ id: UUID) -> String? { heldStyleNames[id.uuidString] }

    /// Drops the name of any saved colour no tool is holding any more, so the
    /// preference does not grow a list of colours nobody is drawing in.
    private mutating func forgetUnheldStyleNames() {
        guard !heldStyleNames.isEmpty else { return }
        var held: Set<String> = []
        for defaults in shapes.values {
            for binding in defaults.colorStyles ?? [] { held.insert(binding.styleID.uuidString) }
        }
        heldStyleNames = heldStyleNames.filter { held.contains($0.key) }
    }

    /// The saved colour the tool in your hand is holding for a slot; nil for a
    /// tool that draws no shape.
    public func colorStyleID(for tool: Tool, slot: ColorSlot) -> UUID? {
        guard let shape = tool.annotationShape else { return nil }
        return colorStyleID(forShape: shape, slot: slot)
    }

    public mutating func setCornerRadius(_ radius: CGFloat, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].cornerRadius = radius
    }

    public mutating func setCaptionFontSize(_ size: CGFloat, forShape shape: AnnotationShape) {
        shapes[shape.rawValue, default: .standard(for: shape)].captionFontSize = size
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

    /// What the tool in your hand is armed with, gradient and all; nil for a
    /// tool that draws no shape.
    public func paint(for tool: Tool) -> Paint? {
        guard let shape = tool.annotationShape else { return nil }
        return paint(forShape: shape)
    }

    /// Arms the tool in your hand. Ignored by a tool that draws no shape.
    public mutating func setPaint(_ paint: Paint, for tool: Tool) {
        guard let shape = tool.annotationShape else { return }
        setPaint(paint, forShape: shape)
    }

    /// The interior fill `tool` draws with (rectangle/ellipse); nil = no fill,
    /// and nil for tools that have no interior.
    public func fillColorHex(for tool: Tool) -> String? {
        guard let shape = tool.annotationShape else { return nil }
        return fillColorHex(forShape: shape)
    }

    public mutating func setFillColorHex(_ hex: String?, for tool: Tool) {
        guard let shape = tool.annotationShape else { return }
        setFillColorHex(hex, forShape: shape)
    }

    /// The interior the tool in your hand is armed with, gradient and all.
    public func fillPaint(for tool: Tool) -> Paint? {
        guard let shape = tool.annotationShape else { return nil }
        return fillPaint(forShape: shape)
    }

    public mutating func setFillPaint(_ paint: Paint?, for tool: Tool) {
        guard let shape = tool.annotationShape else { return }
        setFillPaint(paint, forShape: shape)
    }

    /// Styled content for a new annotation, nil for non-annotation tools.
    public func content(for tool: Tool) -> AnnotationContent? {
        guard let shape = tool.annotationShape else { return nil }
        let d = defaults(forShape: shape)
        // Highlight is a filled box; the stroke width slider doesn't touch it.
        let width = tool.usesStrokeWidth ? d.strokeWidth : AnnotationContent.defaultStrokeWidth
        var content = AnnotationContent(shape: shape, strokeWidth: width, colorHex: d.colorHex,
                                        arrowheadScale: d.arrowheadScale,
                                        cornerRadius: d.cornerRadius, fillColorHex: d.fillColorHex,
                                        captionFontSize: d.captionFontSize)
        // The whole paint, not just the flat color it stands for: an armed
        // tool's gradient reaches the new shape here, which is the one place
        // both the live drag preview and the committed shape are built from.
        content.paint = d.paint
        content.fill = d.fill
        return content
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
    /// What the next shape of this kind is drawn IN. A paint rather than one
    /// flat color, so the tool in your hand can be armed with a gradient and a
    /// whole run of shapes comes out gradient without painting each one.
    public var paint: Paint
    /// The one flat color this default stands for. Everything that can only
    /// hold one reads it, and setting it puts the tool back to flat, which is
    /// what picking a plain color off a swatch row means.
    public var colorHex: String {
        get { paint.hex }
        set { paint.hex = newValue; paint.kind = .solid }
    }
    public var strokeWidth: CGFloat
    public var arrowheadScale: CGFloat
    /// Interior fill for box shapes; nil = outline only. A paint for the same
    /// reason the outline is one.
    public var fill: Paint?
    /// The fill's one flat color; setting it puts the fill back to flat.
    public var fillColorHex: String? {
        get { fill?.hex }
        set { fill = newValue.map { Paint(hex: $0) } }
    }
    /// Corner radius for rectangles; 0 = sharp.
    public var cornerRadius: CGFloat
    /// Non-destructive effects (shadow/opacity/blur/border/corner) new objects
    /// of this shape inherit.
    public var layerStyle: LayerStyle
    /// Caption text size for arrows (image pixels).
    public var captionFontSize: CGFloat
    /// The saved colours this shape's tool is HOLDING, slot by slot. Same list
    /// a layer keeps, for the same reason: a name and the colour it currently
    /// paints, so the next shape can wear the name rather than a copy of it.
    /// Nil, not an empty list, when the tool holds no names, so a preference
    /// that has never seen one writes exactly what it always wrote.
    public var colorStyles: [ColorStyleBinding]?

    /// The saved colour a slot is holding, if any.
    public func colorStyleID(for slot: ColorSlot) -> UUID? {
        colorStyles?.first { $0.slot == slot }?.styleID
    }

    /// Points a slot at a saved colour, or lets go of the one it holds.
    public mutating func setColorStyleID(_ id: UUID?, for slot: ColorSlot) {
        var kept = (colorStyles ?? []).filter { $0.slot != slot }
        if let id { kept.append(ColorStyleBinding(slot: slot, styleID: id)) }
        colorStyles = kept.isEmpty ? nil : kept.sorted { $0.slot.rawValue < $1.slot.rawValue }
    }

    public init(paint: Paint, strokeWidth: CGFloat, arrowheadScale: CGFloat,
                fill: Paint? = nil, cornerRadius: CGFloat = 0,
                layerStyle: LayerStyle = LayerStyle(),
                captionFontSize: CGFloat = AnnotationContent.captionFontSizeDefault) {
        self.paint = paint
        self.strokeWidth = strokeWidth
        self.arrowheadScale = arrowheadScale
        self.fill = fill
        self.cornerRadius = cornerRadius
        self.layerStyle = layerStyle
        self.captionFontSize = captionFontSize
    }

    /// The flat way in, which is every default the app had before gradients.
    public init(colorHex: String, strokeWidth: CGFloat, arrowheadScale: CGFloat,
                fillColorHex: String? = nil, cornerRadius: CGFloat = 0,
                layerStyle: LayerStyle = LayerStyle(),
                captionFontSize: CGFloat = AnnotationContent.captionFontSizeDefault) {
        self.init(paint: Paint(hex: colorHex), strokeWidth: strokeWidth,
                  arrowheadScale: arrowheadScale,
                  fill: fillColorHex.map { Paint(hex: $0) }, cornerRadius: cornerRadius,
                  layerStyle: layerStyle, captionFontSize: captionFontSize)
    }

    /// `paint` and `fill` keep the key names their flat ancestors wrote —
    /// `colorHex`, `fillColorHex` — because a flat paint still writes a bare
    /// hex string there. Prefs that have never held a gradient are byte for
    /// byte what they always were, and prefs written before gradients existed
    /// decode untouched.
    private enum CodingKeys: String, CodingKey {
        case paint = "colorHex"
        case strokeWidth, arrowheadScale
        case fill = "fillColorHex"
        case cornerRadius, layerStyle, captionFontSize, colorStyles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paint = try c.decode(Paint.self, forKey: .paint)
        strokeWidth = try c.decode(CGFloat.self, forKey: .strokeWidth)
        // `arrowheadScale` may be absent in early per-shape prefs.
        arrowheadScale = try c.decodeIfPresent(CGFloat.self, forKey: .arrowheadScale)
            ?? AnnotationStyles.defaultArrowheadScale
        // `fillColorHex` postdates per-shape prefs; absent = no fill.
        fill = try c.decodeIfPresent(Paint.self, forKey: .fill)
        // `cornerRadius` postdates per-shape prefs; absent = sharp.
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 0
        // `layerStyle` postdates per-shape prefs.
        layerStyle = try c.decodeIfPresent(LayerStyle.self, forKey: .layerStyle) ?? LayerStyle()
        // `captionFontSize` postdates captions themselves.
        captionFontSize = try c.decodeIfPresent(CGFloat.self, forKey: .captionFontSize)
            ?? AnnotationContent.captionFontSizeDefault
        // `colorStyles` postdates a tool being able to hold a saved colour at
        // all; absent = holding none, which is what every older pref means.
        colorStyles = try c.decodeIfPresent([ColorStyleBinding].self, forKey: .colorStyles)
    }

    /// The smart default for a shape: red strokes, yellow highlight (system
    /// palette), 4pt stroke, ×1.0 arrowhead, no effects.
    static func standard(for shape: AnnotationShape) -> ShapeDefaults {
        let color = shape == .highlight ? "#FFD60A" : "#FF3B30"
        // Rectangle/ellipse draw SOLID by default (fill = the shape color) — you
        // reach for a box to fill an area; outline-only is a fill-color choice
        // away. Nil fill (arrow/line/highlight) means no interior fill.
        let fill: String? = (shape == .rectangle || shape == .ellipse) ? color : nil
        return ShapeDefaults(colorHex: color,
                             strokeWidth: AnnotationContent.defaultStrokeWidth,
                             arrowheadScale: AnnotationStyles.defaultArrowheadScale,
                             fillColorHex: fill)
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
