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

    /// What the inspector calls this slot in a sentence about it.
    public var title: String {
        switch self {
        case .fill: return "Fill"
        case .stroke: return "Color"
        case .text: return "Color"
        }
    }

    /// The kind of paint this slot takes, which is what decides whether a
    /// saved color is offered here. An outline and a letter are both ink; a
    /// box's inside and a frame's surface are both surface.
    public var styleRole: ColorStyleRole {
        switch self {
        case .fill: return .surface
        case .stroke, .text: return .ink
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
public struct ColorStyle: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String
    /// The parts of a layer this color is offered for. Nil means nobody has
    /// said yet — a style saved before this existed — and the document works
    /// out a sensible answer rather than hiding it from every row.
    public var roles: [ColorStyleRole]?

    public init(id: UUID = UUID(), name: String, colorHex: String,
                roles: [ColorStyleRole]? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.roles = ColorStyle.normalizedRoles(roles)
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

/// One of a layer's slots, pointed at a style. Stored as a small list rather
/// than a dictionary so it writes to disk as plain JSON and reads as plain
/// English.
public struct ColorStyleBinding: Hashable, Codable, Sendable {
    public var slot: ColorSlot
    public var styleID: UUID

    public init(slot: ColorSlot, styleID: UUID) {
        self.slot = slot
        self.styleID = styleID
    }
}

extension Layer {

    /// The color slots this layer has, in the order the inspector shows them.
    /// A layer with none of them (an image, a group that is not a frame) can
    /// never wear a style.
    public var colorSlots: [ColorSlot] {
        switch content {
        case .annotation(let annotation):
            switch annotation.shape {
            case .rectangle, .ellipse: return [.fill, .stroke]
            case .line, .arrow, .highlight: return [.stroke]
            }
        case .text: return [.text]
        case .group(let group): return group.isFrame ? [.fill] : []
        default: return []
        }
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
            return annotation.colorHex
        case (.text, .text(let text)):
            return text.colorHex
        default:
            return nil
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
        default:
            return
        }
    }

    /// The style painting a slot, or nil when the color there is the layer's own.
    public func colorStyleID(for slot: ColorSlot) -> UUID? {
        colorStyleBindings?.first { $0.slot == slot }?.styleID
    }

    /// Whether any of this layer's colors comes from a style.
    public var wearsColorStyle: Bool { !(colorStyleBindings ?? []).isEmpty }

    /// Points a slot at a style. The color itself is written by the document,
    /// which is the only thing that knows what the style is painted.
    mutating func bindColorStyle(_ styleID: UUID, for slot: ColorSlot) {
        var bindings = (colorStyleBindings ?? []).filter { $0.slot != slot }
        bindings.append(ColorStyleBinding(slot: slot, styleID: styleID))
        colorStyleBindings = bindings.sorted { $0.slot.rawValue < $1.slot.rawValue }
    }

    /// Lets go of a slot's style, keeping the color it is wearing.
    mutating func unbindColorStyle(for slot: ColorSlot) {
        let remaining = (colorStyleBindings ?? []).filter { $0.slot != slot }
        // Back to nothing rather than an empty list, so a layer that never
        // wore a style writes exactly what it always wrote.
        colorStyleBindings = remaining.isEmpty ? nil : remaining
    }
}

// MARK: - The document's styles

extension PhotonzDocument {

    /// The name a style takes when nobody has named it yet.
    public static let colorStyleNameBase = "Color"

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
        let style = ColorStyle(name: ComponentNaming.normalized(name) ?? freshColorStyleName(),
                               colorHex: colorHex, roles: roles)
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
    public func colorStyles(for slot: ColorSlot) -> [ColorStyle] {
        colorStyles.filter { effectiveColorStyleRoles(id: $0.id).contains(slot.styleRole) }
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
            $0.setColorHex(style.colorHex, for: slot)
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
        guard let index = colorStyles.firstIndex(where: { $0.id == styleID }) else { return 0 }
        colorStyles[index].colorHex = hex
        var repainted = 0
        mapLayers { layer in
            for binding in layer.colorStyleBindings ?? [] where binding.styleID == styleID {
                layer.setColorHex(hex, for: binding.slot)
                repainted += 1
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
                layer.unbindColorStyle(for: binding.slot)
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
        let styles = Dictionary(colorStyles.map { ($0.id, $0.colorHex) },
                                uniquingKeysWith: { first, _ in first })
        var broken = 0
        mapLayers { layer in
            guard let bindings = layer.colorStyleBindings else { return }
            for binding in bindings where styles[binding.styleID] != layer.colorHex(for: binding.slot) {
                layer.unbindColorStyle(for: binding.slot)
                broken += 1
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
