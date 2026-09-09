import CoreGraphics
import Foundation

/// Named colors that layers point at (`docs/design/ui-building.md`, step D8).
///
/// A **style** is a color with a name. A layer either holds a raw color, the
/// way it always has, or points one of its color slots at a style; editing the
/// style repaints everything pointing at it, in one step.
///
/// The color is kept ON the layer as well as in the style. Nothing downstream —
/// the renderer, export, thumbnails, the package writer — has to learn what a
/// style is, because a layer wearing one draws exactly like a layer that was
/// painted that color by hand. The binding is the extra fact: it says where the
/// color came from, so an edit to the style can find its way back.
///
/// Tokens, where one name resolves differently in light and dark, are the layer
/// underneath this one and are deliberately not here yet.

// MARK: - The colors a layer has

/// One of a layer's paintable colors. A layer offers the slots its content
/// actually has: a box has an interior and an ink, a line has only ink, a text
/// block has its ink, a frame has its surface.
public enum ColorSlot: String, CaseIterable, Hashable, Codable, Sendable {
    /// A box's interior, or a frame's surface.
    case fill
    /// A shape's outline, and the whole of a line, arrow or highlight.
    case stroke
    /// A text block's ink.
    case text
    /// The ring a layer's own styling draws around it — the Border in the
    /// Effects section. Last, because it sits over whatever the layer is
    /// rather than saying what the layer is.
    case border
    /// What a shadow is painted.
    ///
    /// The odd one out, and deliberately so: NO layer lists this among its own
    /// slots, because a shadow is not part of what a layer is — it is an entry
    /// in the Effects list, and the colour belongs to that entry. It is here so
    /// that an effect's colour can be named, offered and saved through exactly
    /// the machinery every other colour uses (`LayerEffects.swift`).
    case shadow
    /// What a glow is painted.
    ///
    /// The odd one out for the same reason the shadow is: no layer lists it
    /// among its own slots, because a glow is an entry in the Effects list and
    /// the colour belongs to that entry (`LayerEffects.swift`).
    case glow

    /// What the inspector calls this slot in a sentence about it.
    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Color"
        case .text: return "Color"
        case .border: return "Border"
        case .shadow: return "Shadow"
        case .glow: return "Glow"
        }
    }

    /// Whether this slot can hold a gradient, or only a flat color.
    ///
    /// A shape's inside, a frame's surface and a shape's outline are areas and
    /// runs the shape rasterizer draws itself, so a ramp fits them. A text
    /// block's ink is laid down glyph by glyph and the Border is a ring drawn
    /// over the finished layer; both take one color today. Nothing that cannot
    /// hold a ramp is ever offered the choice, because a row of gradient tiles
    /// that quietly does nothing is worse than no row.
    public var acceptsGradient: Bool {
        switch self {
        // A border takes one because a shape's outline always could, and a
        // shape's outline IS a border now (`OutlineRetirement.swift`). A shadow
        // and a glow are light rather than paint, and a letter's ink has no box
        // for a ramp to run across.
        case .fill, .stroke, .border: return true
        case .text, .shadow, .glow: return false
        }
    }

    /// The kind of paint this slot takes, which is what decides whether a
    /// saved color is offered here. An outline and a letter are both ink; a
    /// box's inside and a frame's surface are both surface.
    public var styleRole: ColorStyleRole {
        switch self {
        case .fill: return .surface
        // A shadow is drawn OVER the design rather than filling an area of it,
        // the same as a line and a letter, so it takes the ink shelf: the
        // near-black somebody keeps for hairlines is the one they reach for.
        case .stroke, .text, .border, .shadow, .glow: return .ink
        }
    }
}

/// What a saved color is FOR.
///
/// A color row used to offer every saved color in the document, so the inside
/// of a box could be painted with a color somebody made for hairlines. There
/// are only two answers worth keeping apart, and they are the two a person
/// already thinks in: the color things are drawn IN, and the color areas are
/// filled WITH.
public enum ColorStyleRole: String, CaseIterable, Hashable, Codable, Sendable {
    /// What a line, an outline or letters are drawn in.
    case ink
    /// What an area is filled with: a box's inside, a frame's surface.
    case surface

    /// How the Library offers this as something to tick. Plain words, because
    /// "ink" and "surface" are our words and not everybody's.
    public var title: String {
        switch self {
        case .ink: return "Outlines and text"
        case .surface: return "Fills and backgrounds"
        }
    }
}

/// A color saved under a name. `id` is what layers point at, so renaming one
/// never loosens anything.
///
/// What it holds is a whole `Paint`, so the thing worth keeping most — a
/// gradient somebody spent time aiming — can be kept at all. A flat style is a
/// solid paint, which writes the same bare hex string on disk it always wrote,
/// so a document saved before ramps existed opens unchanged.
public struct ColorStyle: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// What this style paints: one flat color, or a ramp.
    public var paint: Paint
    /// The parts of a layer this color is offered for. Nil means nobody has
    /// said yet — a style saved before this existed — and the document works
    /// out a sensible answer rather than hiding it from every row.
    public var roles: [ColorStyleRole]?

    /// The one flat color this style stands for: what a solid style paints,
    /// and what a ramp falls back to anywhere only one color can be drawn.
    public var colorHex: String {
        get { paint.hex }
        set { paint.hex = newValue }
    }

    /// Whether this style is a ramp rather than one flat color.
    public var isGradient: Bool { paint.isGradient }

    public init(id: UUID = UUID(), name: String, paint: Paint,
                roles: [ColorStyleRole]? = nil) {
        self.id = id
        self.name = name
        self.paint = paint
        self.roles = ColorStyle.normalizedRoles(roles)
    }

    public init(id: UUID = UUID(), name: String, colorHex: String,
                roles: [ColorStyleRole]? = nil) {
        self.init(id: id, name: name, paint: Paint(hex: colorHex), roles: roles)
    }

    /// The wire keeps saying `colorHex`, because that is what every document
    /// already on disk says and a solid paint writes exactly the string that
    /// key has always held.
    private enum CodingKeys: String, CodingKey {
        case id, name, paint = "colorHex", roles
    }

    /// What this style paints IN a slot: the whole ramp where one fits, and
    /// its flat color where one does not.
    ///
    /// So a gradient that also names an ink color still paints text something,
    /// rather than the text quietly losing the name the moment somebody turns
    /// the style into a ramp.
    public func paint(for slot: ColorSlot) -> Paint {
        slot.acceptsGradient ? paint : Paint(hex: paint.hex)
    }

    /// In one fixed order, without repeats, so the same two answers always
    /// write the same JSON and two styles for the same parts compare equal. An
    /// empty list becomes nil: a color that is for nothing at all would vanish
    /// from every row with no way back.
    static func normalizedRoles(_ roles: [ColorStyleRole]?) -> [ColorStyleRole]? {
        guard let roles else { return nil }
        let kept = ColorStyleRole.allCases.filter { roles.contains($0) }
        return kept.isEmpty ? nil : kept
    }

    /// Whether this color is offered for a slot, going only on what the style
    /// itself says. A style that has said nothing is offered everywhere; the
    /// document's `colorStyles(for:)` is the one that guesses better.
    public func suits(_ slot: ColorSlot) -> Bool {
        guard let roles else { return true }
        return roles.contains(slot.styleRole)
    }
}

/// One of a layer's colours, pointed at a style. Stored as a small list rather
/// than a dictionary so it writes to disk as plain JSON and reads as plain
/// English.
///
/// Nearly every binding names one of the layer's own slots. A binding with an
/// `effectIndex` names the colour of ONE ENTRY in the Effects list instead —
/// the second shadow's colour, this border's colour — which is how an effect's
/// colour gets to wear a saved name like every other colour in the app. The
/// slot still rides along, because it is what says which saved colours are
/// offered there.
public struct ColorStyleBinding: Hashable, Codable, Sendable {
    public var slot: ColorSlot
    /// Where in the layer's Effects list this colour lives, when it is an
    /// effect's rather than one of the layer's own. Nil is every binding that
    /// existed before effects could wear a name, and it is left out of the file
    /// entirely, so a document that has never met one reads exactly as it did.
    ///
    /// It is a PLACE, so the list moving has to move it: `Layer.insertEffect`,
    /// `removeEffect` and `moveEffect` are the only ways the list may change
    /// for exactly that reason.
    public var effectIndex: Int?
    public var styleID: UUID

    public init(slot: ColorSlot, effectIndex: Int? = nil, styleID: UUID) {
        self.slot = slot
        self.effectIndex = effectIndex
        self.styleID = styleID
    }
}

extension Layer {

    /// The color slots this layer has, in the order the inspector shows them.
    /// A layer with none of them (an image, a group that is not a frame) can
    /// never wear a style.
    public var colorSlots: [ColorSlot] {
        var slots: [ColorSlot]
        switch content {
        case .annotation(let annotation):
            switch annotation.shape {
            // A box and an oval have no stroke of their own since the Outline
            // row left Appearance: their edge is a Border in the Effects list,
            // so its colour is the border's (`OutlineRetirement.swift`).
            case .rectangle, .ellipse: slots = [.fill]
            case .line, .arrow, .highlight: slots = [.stroke]
            }
        case .text: slots = [.text]
        case .group(let group): slots = group.isFrame ? [.fill] : []
        default: slots = []
        }
        if hasBorderColor { slots.append(.border) }
        return slots
    }

    /// Whether this layer has a border color to talk about.
    ///
    /// A border is not part of what a layer IS — it is styling laid over
    /// whatever the layer happens to be — so any kind of layer can have one,
    /// including a picture and a plain group. It counts as a color only once
    /// there is a border to paint: a Border row over a layer with no border
    /// would be a color nobody can see, and the way to a border is its width
    /// in the Effects section rather than a checkbox on the row.
    ///
    /// A border pointed at a saved color keeps its slot at zero width, so
    /// taking the border off for a moment does not quietly lose the name.
    ///
    /// The ring in question is the one nearest the eye in the Effects list,
    /// since a layer has no ring of its own any more (`OutlineRetirement.swift`).
    var hasBorderColor: Bool {
        guard let index = style.borderEffectIndex else { return false }
        return style.borderWidth > 0 || colorStyleID(forEffectAt: index) != nil
    }

    /// The color in a slot right now, or nil when the slot is empty (a box with
    /// no fill, a frame you see through) or the layer has no such slot.
    public func colorHex(for slot: ColorSlot) -> String? {
        switch (slot, content) {
        case (.fill, .annotation(let annotation)):
            guard annotation.shape == .rectangle || annotation.shape == .ellipse else { return nil }
            return annotation.fillColorHex
        case (.fill, .group(let group)):
            return group.isFrame ? group.backgroundHex : nil
        case (.stroke, .annotation(let annotation)):
            // A box and an oval have no stroke to report: their edge is a
            // Border in the Effects list (`OutlineRetirement.swift`).
            guard !annotation.drawsARingRatherThanBeingOne else { return nil }
            return annotation.colorHex
        case (.text, .text(let text)):
            return text.colorHex
        case (.border, _):
            return hasBorderColor ? style.borderColorHex : nil
        default:
            return nil
        }
    }

    /// What is painting a slot right now — flat color or gradient — or nil
    /// when the slot is empty or this layer has no such slot. The gradient
    /// counterpart of `colorHex(for:)`, which stays the way to ask for the one
    /// flat color a slot stands for.
    public func paint(for slot: ColorSlot) -> Paint? {
        switch (slot, content) {
        case (.fill, .annotation(let annotation)):
            guard annotation.shape == .rectangle || annotation.shape == .ellipse else { return nil }
            return annotation.fill
        case (.fill, .group(let group)):
            return group.isFrame ? group.background : nil
        case (.stroke, .annotation(let annotation)):
            guard !annotation.drawsARingRatherThanBeingOne else { return nil }
            return annotation.paint
        case (.border, _):
            return hasBorderColor ? style.borderEffects.first?.paint : nil
        default:
            return colorHex(for: slot).map { Paint(hex: $0) }
        }
    }

    /// Paints a slot with a whole paint. A slot that cannot hold a gradient
    /// takes the flat color out of it rather than refusing, so a paint arriving
    /// from anywhere always lands as something.
    public mutating func setPaint(_ paint: Paint, for slot: ColorSlot) {
        guard colorSlots.contains(slot) else { return }
        guard slot.acceptsGradient else {
            setColorHex(paint.hex, for: slot)
            return
        }
        switch (slot, content) {
        case (.fill, .annotation(var annotation)):
            annotation.fill = paint
            content = .annotation(annotation)
        case (.fill, .group(var group)):
            group.background = paint
            content = .group(group)
        case (.stroke, .annotation(var annotation)):
            annotation.paint = paint
            content = .annotation(annotation)
        case (.border, _):
            // The ring nearest the eye, ramp and all.
            guard let index = style.borderEffectIndex else { return }
            style.updateBorderEffect(at: index) { $0.paint = paint }
        default:
            setColorHex(paint.hex, for: slot)
        }
    }

    /// What a slot is given when it is switched ON from nothing.
    ///
    /// A box takes its own outline color, which is what toggling a single box's
    /// fill has always done: the fill starts where the shape's own color is and
    /// the well beside the switch refines it. A frame takes the surface a new
    /// frame starts with. Nil for a slot that cannot be switched, and for a
    /// layer that does not have it.
    public func startingColorHex(for slot: ColorSlot) -> String? {
        guard colorSlots.contains(slot) else { return nil }
        switch (slot, content) {
        case (.fill, .annotation(let annotation)): return annotation.colorHex
        case (.fill, .group): return Layer.defaultFrameBackgroundHex
        default: return colorHex(for: slot)
        }
    }

    /// Paints a slot. Only the slots this layer has answer; an empty color is
    /// only meaningful where the model already allows one (a box's fill, a
    /// frame's surface).
    mutating func setColorHex(_ hex: String?, for slot: ColorSlot) {
        guard colorSlots.contains(slot) else { return }
        switch (slot, content) {
        case (.fill, .annotation(var annotation)):
            annotation.fillColorHex = hex
            content = .annotation(annotation)
        case (.fill, .group(var group)):
            group.backgroundHex = hex
            content = .group(group)
        case (.stroke, .annotation(var annotation)):
            guard let hex else { return }
            annotation.colorHex = hex
            content = .annotation(annotation)
        case (.text, .text):
            // Through the text builder, so repainting text keeps the contrast
            // halo that every other way of coloring text maintains.
            guard let hex else { return }
            self = TextBuilder.restyled(layer: self, colorHex: hex)
        case (.border, _):
            // A border is always painted something; there is no empty border
            // color, only a border with no width.
            guard let hex else { return }
            style.borderColorHex = hex
        default:
            return
        }
    }

    /// The style painting a slot, or nil when the color there is the layer's own.
    ///
    /// `.border` means the ring nearest the eye, and that ring is an entry in
    /// the Effects list, so the name lives on the entry
    /// (`OutlineRetirement.swift`). Everything that speaks of a layer's border
    /// colour reads and writes the same one name that way.
    public func colorStyleID(for slot: ColorSlot) -> UUID? {
        if slot == .border, let index = style.borderEffectIndex {
            return colorStyleID(forEffectAt: index)
        }
        return colorStyleBindings?.first { $0.slot == slot && $0.effectIndex == nil }?.styleID
    }

    /// Whether any of this layer's colors comes from a style.
    public var wearsColorStyle: Bool { !(colorStyleBindings ?? []).isEmpty }

    /// Points a slot at a style. The color itself is written by the document,
    /// which is the only thing that knows what the style is painted.
    mutating func bindColorStyle(_ styleID: UUID, for slot: ColorSlot) {
        if slot == .border, let index = style.borderEffectIndex {
            bindColorStyle(styleID, forEffectAt: index)
            return
        }
        var bindings = (colorStyleBindings ?? [])
            .filter { !($0.slot == slot && $0.effectIndex == nil) }
        bindings.append(ColorStyleBinding(slot: slot, styleID: styleID))
        colorStyleBindings = Layer.sortedBindings(bindings)
    }

    /// Lets go of a slot's style, keeping the color it is wearing.
    mutating func unbindColorStyle(for slot: ColorSlot) {
        if slot == .border, let index = style.borderEffectIndex {
            unbindColorStyle(forEffectAt: index)
            return
        }
        let remaining = (colorStyleBindings ?? [])
            .filter { !($0.slot == slot && $0.effectIndex == nil) }
        // Back to nothing rather than an empty list, so a layer that never
        // wore a style writes exactly what it always wrote.
        colorStyleBindings = remaining.isEmpty ? nil : remaining
    }

    /// One fixed order, so the same set of bindings always writes the same
    /// JSON: the layer's own colours first in slot order, then the effects in
    /// the order the list holds them.
    static func sortedBindings(_ bindings: [ColorStyleBinding]) -> [ColorStyleBinding] {
        bindings.sorted { a, b in
            switch (a.effectIndex, b.effectIndex) {
            case (nil, nil): return a.slot.rawValue < b.slot.rawValue
            case (nil, _): return true
            case (_, nil): return false
            case (let x?, let y?): return x < y
            }
        }
    }
}

// MARK: - An effect's colour

/// An effect's colour is a colour like any other, and this is what makes that
/// true: it is read, painted, named and let go of through the same calls, the
/// only difference being that it is addressed by its PLACE in the Effects list
/// rather than by one of the layer's own slots.
///
/// Reported by the user on 2026-09-07: a border's colour sat in the row header
/// while its width and position sat in the settings, and it was the one colour
/// in the app that could not take a saved name.
extension Layer {

    /// What the effect at this place in the list is painted, or nil when there
    /// is no effect there or it paints no colour at all (a blur).
    public func colorHex(forEffectAt index: Int) -> String? {
        style.effect(at: index)?.colorHex
    }

    /// The whole paint an effect's colour stands for. A border can hold a ramp,
    /// because a shape's outline always could and a shape's outline IS a border
    /// now (`OutlineRetirement.swift`); a shadow and a glow are light rather
    /// than paint, so theirs is the one flat colour dressed as a paint.
    public func paint(forEffectAt index: Int) -> Paint? {
        if let border = style.effect(at: index)?.border { return border.paint }
        return colorHex(forEffectAt: index).map { Paint(hex: $0) }
    }

    /// Paints the effect at a place in the list. An entry with no colour is
    /// left alone rather than gaining one.
    public mutating func setColorHex(_ hex: String, forEffectAt index: Int) {
        setPaint(Paint(hex: hex), forEffectAt: index)
    }

    /// The same, with the whole paint. A ramp handed to an effect that cannot
    /// draw one keeps its flat colour rather than being refused, exactly as
    /// every other slot that cannot take a gradient does.
    public mutating func setPaint(_ paint: Paint, forEffectAt index: Int) {
        guard let slot = style.effect(at: index)?.colorSlot else { return }
        if slot.acceptsGradient, style.effect(at: index)?.border != nil {
            style.updateBorderEffect(at: index) { $0.paint = paint }
        } else {
            style.updateEffect(at: index) { $0.colorHex = paint.hex }
        }
    }

    /// The style painting an effect's colour, or nil when the colour is its own.
    public func colorStyleID(forEffectAt index: Int) -> UUID? {
        colorStyleBindings?.first { $0.effectIndex == index }?.styleID
    }

    /// Points an effect's colour at a style. The colour itself is written by
    /// the document, which is the only thing that knows what the style paints.
    mutating func bindColorStyle(_ styleID: UUID, forEffectAt index: Int) {
        guard let slot = style.effect(at: index)?.colorSlot else { return }
        var bindings = (colorStyleBindings ?? []).filter { $0.effectIndex != index }
        bindings.append(ColorStyleBinding(slot: slot, effectIndex: index, styleID: styleID))
        colorStyleBindings = Layer.sortedBindings(bindings)
    }

    /// Lets go of an effect's style, keeping the colour it is wearing.
    mutating func unbindColorStyle(forEffectAt index: Int) {
        let remaining = (colorStyleBindings ?? []).filter { $0.effectIndex != index }
        colorStyleBindings = remaining.isEmpty ? nil : remaining
    }

    /// Puts an effect in the list, carrying every name below it down a place.
    ///
    /// The ONLY way an effect may be added, and the same for `removeEffect` and
    /// `moveEffect` below. A binding names a place in the list, so a list that
    /// changes behind their back leaves a shadow wearing the border's name.
    mutating func insertEffect(_ effect: LayerEffect, at index: Int) {
        let at = min(max(0, index), style.effects.count)
        style.effects.insert(effect, at: at)
        remapEffectPlaces { $0 >= at ? $0 + 1 : $0 }
    }

    /// Takes an effect out of the list. Its name goes with it, and everything
    /// below it comes up a place.
    mutating func removeEffect(at index: Int) {
        guard style.effects.indices.contains(index) else { return }
        style.effects.remove(at: index)
        remapEffectPlaces { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
    }

    /// Drags an effect somewhere else in the list, names and all.
    mutating func moveEffect(from: Int, to: Int) {
        guard style.effects.indices.contains(from),
              style.effects.indices.contains(to), from != to else { return }
        let moved = style.effects.remove(at: from)
        style.effects.insert(moved, at: to)
        remapEffectPlaces { place in
            if place == from { return to }
            if from < to { return place > from && place <= to ? place - 1 : place }
            return place >= to && place < from ? place + 1 : place
        }
    }

    /// Rewrites every name a place in the Effects list carries — the colour
    /// bindings here and the effect-style bindings in `EffectStyles.swift` —
    /// dropping the ones the change answered with nothing.
    private mutating func remapEffectPlaces(_ move: (Int) -> Int?) {
        remapEffectStyleBindings(move)
        remapEffectColorBindings(move)
    }

    /// Rewrites every effect COLOUR binding's place, dropping the ones the
    /// change answered with nothing.
    private mutating func remapEffectColorBindings(_ move: (Int) -> Int?) {
        guard let bindings = colorStyleBindings,
              bindings.contains(where: { $0.effectIndex != nil }) else { return }
        var rebuilt: [ColorStyleBinding] = []
        for binding in bindings {
            guard let place = binding.effectIndex else { rebuilt.append(binding); continue }
            guard let moved = move(place) else { continue }
            var carried = binding
            carried.effectIndex = moved
            rebuilt.append(carried)
        }
        colorStyleBindings = rebuilt.isEmpty ? nil : Layer.sortedBindings(rebuilt)
    }
}

// MARK: - The document's styles

extension PhotonzDocument {

    /// The name a style takes when nobody has named it yet.
    public static let colorStyleNameBase = "Color"

    /// ...and the one a saved ramp takes, because a shelf of tiles called
    /// Color 2 and Color 3 where half of them are gradients is a shelf nobody
    /// reads.
    public static let gradientStyleNameBase = "Gradient"

    /// What a style of this paint is called before anybody names it.
    public static func colorStyleNameBase(for paint: Paint) -> String {
        paint.isGradient ? gradientStyleNameBase : colorStyleNameBase
    }

    /// The style behind an id.
    public func colorStyle(id: UUID) -> ColorStyle? {
        colorStyles.first { $0.id == id }
    }

    /// A style name nobody is using yet: "Color", then "Color 2", "Color 3"…
    public func freshColorStyleName(base: String = PhotonzDocument.colorStyleNameBase) -> String {
        let taken = Set(colorStyles.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Adds a style with a color, and returns its id. A blank name becomes the
    /// made-up one rather than a nameless tile on the shelf.
    @discardableResult
    public mutating func addColorStyle(name: String? = nil, colorHex: String,
                                       roles: [ColorStyleRole]? = nil) -> UUID {
        addColorStyle(name: name, paint: Paint(hex: colorHex), roles: roles)
    }

    /// The same, with a whole paint: this is how a gradient gets a name.
    @discardableResult
    public mutating func addColorStyle(name: String? = nil, paint: Paint,
                                       roles: [ColorStyleRole]? = nil) -> UUID {
        let base = PhotonzDocument.colorStyleNameBase(for: paint)
        let style = ColorStyle(name: ComponentNaming.normalized(name)
                                 ?? freshColorStyleName(base: base),
                               paint: paint, roles: roles)
        colorStyles.append(style)
        return style.id
    }

    /// The parts a saved color is offered for, including the answer worked out
    /// for one that has never said.
    ///
    /// Saving a color always records what it was saved from, so this only has
    /// to guess for styles that predate that. It guesses the way a person
    /// would: one of the app's own five is what the app made it for, and
    /// anything else is for the parts it is already painting. A color nothing
    /// uses and nobody named a part for stays offered everywhere, because a
    /// style that has quietly disappeared from every row is worse than one
    /// offered in a row you did not want it in.
    public func effectiveColorStyleRoles(id: UUID) -> [ColorStyleRole] {
        guard let style = colorStyle(id: id) else { return [] }
        if let roles = style.roles { return roles }
        if let starter = StarterStyle.allCases.first(where: { $0.styleID == id }) {
            return starter.roles
        }
        var found: Set<ColorStyleRole> = []
        for layer in allLayers {
            for binding in layer.colorStyleBindings ?? [] where binding.styleID == id {
                found.insert(binding.slot.styleRole)
            }
        }
        guard !found.isEmpty else { return ColorStyleRole.allCases }
        return ColorStyleRole.allCases.filter { found.contains($0) }
    }

    /// The saved colors one row offers: the ones meant for the part it paints,
    /// in the order the shelf lists them. This is what stops a color made for
    /// hairlines turning up as something to fill a box with.
    ///
    /// A saved ramp is offered only where a ramp can actually be drawn. One
    /// blue really is both the fill of a button and the color of a link, so an
    /// ink style turns up on the Text row — but a sunset listed there would
    /// paint one flat orange, and a name that quietly means something else in
    /// one row is worse than a shorter list.
    public func colorStyles(for slot: ColorSlot) -> [ColorStyle] {
        colorStyles.filter { style in
            guard !style.isGradient || slot.acceptsGradient else { return false }
            return effectiveColorStyleRoles(id: style.id).contains(slot.styleRole)
        }
    }

    /// Changes what a saved color is offered for. Ticking nothing is refused:
    /// it would take the style off every row with no way to put it back.
    /// Nothing is repainted — this is about what gets offered, not what is
    /// already painted.
    public mutating func setColorStyleRoles(id: UUID, roles: [ColorStyleRole]) {
        guard let index = colorStyles.firstIndex(where: { $0.id == id }),
              let kept = ColorStyle.normalizedRoles(roles) else { return }
        colorStyles[index].roles = kept
    }

    /// Saves what a layer is painted in one slot as a named style, and points
    /// that layer at it — the point of saving is to keep using it, so the layer
    /// you saved from is the style's first user. Nil when there is no color
    /// there to save.
    /// One layer is a selection of one, so this is the same call the row over
    /// a multi-selection makes and the two can never drift apart.
    @discardableResult
    public mutating func saveColorStyle(from layerID: UUID, slot: ColorSlot,
                                        name: String? = nil) -> UUID? {
        saveColorStyle(from: [layerID], slot: slot, name: name)
    }

    /// Points a layer's slot at a style and paints it. False when the layer has
    /// no such slot, or the style is not in this document.
    @discardableResult
    public mutating func bindColorStyle(layerID: UUID, slot: ColorSlot, styleID: UUID) -> Bool {
        guard let style = colorStyle(id: styleID),
              layer(id: layerID)?.colorSlots.contains(slot) == true else { return false }
        updateLayer(id: layerID) {
            $0.setPaint(style.paint(for: slot), for: slot)
            $0.bindColorStyle(styleID, for: slot)
        }
        return true
    }

    /// Lets a slot go back to being a color of its own. Nothing is repainted:
    /// the layer keeps exactly what it is wearing.
    public mutating func unbindColorStyle(layerID: UUID, slot: ColorSlot) {
        updateLayer(id: layerID) { $0.unbindColorStyle(for: slot) }
    }

    /// Repaints a style, and with it every slot pointing at it. Returns how
    /// many slots followed, which is what a notice can say out loud.
    ///
    /// One mutation, so `History.perform` records the style and everything it
    /// paints as a single undo step.
    @discardableResult
    public mutating func setColorStyleHex(styleID: UUID, hex: String) -> Int {
        setColorStylePaint(styleID: styleID, paint: Paint(hex: hex))
    }

    /// Repaints a style with a whole paint, and with it every slot pointing at
    /// it — which is how a saved gradient is edited in one place. A slot that
    /// cannot hold a ramp takes the paint's flat color, so nothing wearing the
    /// style is left behind when it becomes one.
    @discardableResult
    public mutating func setColorStylePaint(styleID: UUID, paint: Paint) -> Int {
        guard let index = colorStyles.firstIndex(where: { $0.id == styleID }) else { return 0 }
        colorStyles[index].paint = paint
        let style = colorStyles[index]
        // Worked out before the walk, because a copy's answer names a knob and
        // only the originals know which colour that knob paints.
        let knobs = componentColorKnobSlots
        var repainted = 0
        mapLayers { layer in
            for binding in layer.colorStyleBindings ?? [] where binding.styleID == styleID {
                if let place = binding.effectIndex {
                    // An effect takes one flat colour, so a saved ramp lands as
                    // the colour it starts on rather than the border quietly
                    // dropping the name the day somebody makes it a gradient.
                    layer.setPaint(style.paint(for: binding.slot), forEffectAt: place)
                } else {
                    layer.setPaint(style.paint(for: binding.slot), for: binding.slot)
                }
                repainted += 1
            }
            // A copy that answered a colour knob with this name follows it too.
            // The answer keeps the colour beside the name so it stays honest
            // the day the name is deleted.
            layer.updateColorAnswers { property, answer in
                guard answer.styleID == styleID, let slot = knobs[property] else { return nil }
                return ComponentColorAnswer(paint: style.paint(for: slot), styleID: styleID)
            }
        }
        return repainted
    }

    /// Renames a style. A blank name is refused rather than leaving a nameless
    /// tile on the shelf.
    public mutating func renameColorStyle(id: UUID, to name: String) {
        guard let index = colorStyles.firstIndex(where: { $0.id == id }),
              let chosen = ComponentNaming.normalized(name) else { return }
        colorStyles[index].name = chosen
    }

    /// Takes a style off the shelf. Every layer wearing it keeps the color it
    /// has and simply owns it again: deleting a name must never repaint work.
    public mutating func deleteColorStyle(id: UUID) {
        guard colorStyles.contains(where: { $0.id == id }) else { return }
        colorStyles.removeAll { $0.id == id }
        mapLayers { layer in
            for binding in layer.colorStyleBindings ?? [] where binding.styleID == id {
                if let place = binding.effectIndex {
                    layer.unbindColorStyle(forEffectAt: place)
                } else {
                    layer.unbindColorStyle(for: binding.slot)
                }
            }
            // A copy that answered a colour knob with this name keeps the
            // colour and simply owns it again, exactly as a layer does.
            layer.updateColorAnswers { _, answer in
                guard answer.styleID == id else { return nil }
                return ComponentColorAnswer(paint: answer.paint)
            }
        }
    }

    /// How many slots in the document wear this style. Two colors on one layer
    /// count twice, because that is two things an edit would repaint.
    public func colorStyleUsageCount(id: UUID) -> Int {
        allLayers.reduce(0) { total, layer in
            total + (layer.colorStyleBindings ?? []).count { $0.styleID == id }
        }
    }

    /// Every layer wearing this style, once each, so the app can select them.
    public func layersUsingColorStyle(id: UUID) -> [UUID] {
        allLayers.filter { layer in
            (layer.colorStyleBindings ?? []).contains { $0.styleID == id }
        }.map(\.id)
    }

    /// What the Library's Styles scope shows: one tile per style, with what it
    /// is painted and how much of the document leans on it.
    public var colorStyleLibraryEntries: [LibraryEntry] {
        colorStyles.map { style in
            LibraryEntry(id: style.id.uuidString, scope: .styles, name: style.name,
                         detail: ColorStyleNaming.detail(usageCount: colorStyleUsageCount(id: style.id)))
        }
    }

    /// The safety net, run after every edit (`History.perform`).
    ///
    /// A binding is a claim: "this color came from that style". Anything that
    /// paints a layer some other way — the paint bucket, a paste, a tool
    /// default — would leave the claim false, and an inspector row saying
    /// "Accent" over a color that is not Accent is worse than no styles at all.
    /// So a slot whose color has drifted from its style, or whose style is
    /// gone, quietly lets go and keeps what it is wearing. Returns how many
    /// bindings broke.
    ///
    /// The walk is the same one the component sync already makes, and a layer
    /// that has never worn a style is one nil check: a document that has never
    /// seen a style allocates nothing here.
    @discardableResult
    public mutating func reconcileColorStyles() -> Int {
        let styles = Dictionary(colorStyles.map { ($0.id, $0) },
                                uniquingKeysWith: { first, _ in first })
        var broken = 0
        mapLayers { layer in
            // A copy's answer naming a colour this document does not have is
            // the same false claim one level up, and lets go the same way: the
            // colour it is wearing stays, the name goes. `deleteColorStyle`
            // does this on the way out; this is the net under a file that
            // arrived with the claim already broken.
            layer.updateColorAnswers { _, answer in
                guard let styleID = answer.styleID, styles[styleID] == nil else { return nil }
                broken += 1
                return ComponentColorAnswer(paint: answer.paint)
            }
            guard let bindings = layer.colorStyleBindings else { return }
            for binding in bindings {
                // Paint-deep, and against what the style paints IN THAT SLOT:
                // moving one stop of a gradient leaves its flat color alone, so
                // a hex check would let the claim stand over a ramp nobody
                // saved.
                let wanted = styles[binding.styleID]?.paint(for: binding.slot)
                let worn = binding.effectIndex.map { layer.paint(forEffectAt: $0) }
                    ?? layer.paint(for: binding.slot)
                guard let wanted, let worn, wanted.draws(sameAs: worn) else {
                    if let place = binding.effectIndex {
                        layer.unbindColorStyle(forEffectAt: place)
                    } else {
                        layer.unbindColorStyle(for: binding.slot)
                    }
                    broken += 1
                    continue
                }
            }
        }
        return broken
    }

    /// Every layer in the tree, groups and their contents alike, run through a
    /// mutation in place.
    private mutating func mapLayers(_ body: (inout Layer) -> Void) {
        func walk(_ list: inout [Layer]) {
            for index in list.indices {
                body(&list[index])
                if list[index].isGroup {
                    var children = list[index].children
                    walk(&children)
                    list[index].children = children
                }
            }
        }
        walk(&layers)
    }
}

/// What a style's tile says under its swatch.
public enum ColorStyleNaming {
    /// What a style is, in the few words a hover tip has room for: the hex it
    /// is, or the kind of ramp it runs.
    public static func paintText(_ paint: Paint) -> String {
        guard paint.isGradient else { return paint.hex }
        return "\(paint.kind.title) gradient"
    }

    /// The word for what is being kept, so a button about a ramp does not call
    /// it a color.
    public static func subject(_ paint: Paint) -> String {
        paint.isGradient ? "gradient" : "color"
    }

    /// What the Style section calls the row holding it. A section that says
    /// Color over a ramp is a section arguing with the thing beside it.
    public static func rowTitle(_ paint: Paint) -> String {
        paint.isGradient ? "Gradient" : "Color"
    }

    /// The small print under "Use it for", said only about a ramp: text and
    /// borders take one flat color, so a gradient does not turn up there even
    /// when it is kept for outlines. Nil for a flat color, which goes
    /// everywhere it is ticked for.
    public static func gradientReachNote(_ paint: Paint) -> String? {
        guard paint.isGradient else { return nil }
        return "Text and borders take one flat color, so a gradient is not offered there."
    }

    /// The detail line: how much of the document an edit to this style would
    /// repaint, which is the question a shelf full of styles raises.
    public static func detail(usageCount: Int) -> String {
        switch usageCount {
        case 0: return "not used yet"
        case 1: return "1 use"
        default: return "\(usageCount) uses"
        }
    }
}
