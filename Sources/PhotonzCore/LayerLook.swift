import CoreGraphics
import Foundation

/// The LOOK of one layer, lifted off it so another layer can wear it.
///
/// Asked for by the user on 2026-09-15: *"I wish there was some way to just
/// copy the format of one shape and best effort apply it to the properties of
/// another shape."* Matching two shapes meant reading every setting off one and
/// typing it into the other, part by part.
///
/// A look is exactly what `docs/design/shape-parts.md` says a layer is made of,
/// and nothing else:
///
/// - the colour of every PART the layer paints, and the saved colour each of
///   them wears,
/// - the one line round it, wherever that line lives,
/// - the three properties laid over the whole layer: how see-through it is, how
///   round its corners are, how it mixes,
/// - and the Effects list, everything somebody ADDED to it.
///
/// It carries NOTHING about where the layer is, how big it is, which way round
/// it is, or what it actually is. A line pasted from a circle is still a line.
///
/// **The edge is carried apart from the rest**, and that is the whole reason a
/// line can be made to match a circle's border in two moves. A circle wears its
/// edge as a Border in the Effects list; a line IS its edge. Those are the same
/// thing to a person and two different things underneath (`OutlineWidth.swift`
/// already draws the line between them), so the look holds "the edge" once and
/// each layer puts it where its own edge lives.
public struct LayerLook: Hashable, Codable, Sendable {

    /// One part the source painted, named by the slot it filled.
    public struct Part: Hashable, Codable, Sendable {
        public var slot: ColorSlot
        /// What it was painted, or nil when the part was switched OFF. Off is
        /// an opinion too: a box with no fill makes the box you paste it onto
        /// empty rather than leaving it as it was.
        public var paint: Paint?
        /// The saved colour it was wearing, so the copy arrives wearing the
        /// NAME rather than a loose copy of what that name paints today. This
        /// is the whole point of having saved a colour: the link must survive
        /// the moment it is most useful.
        public var styleID: UUID?

        public init(slot: ColorSlot, paint: Paint?, styleID: UUID? = nil) {
            self.slot = slot
            self.paint = paint
            self.styleID = styleID
        }
    }

    /// The one line round the source layer.
    public struct Edge: Hashable, Codable, Sendable {
        /// How thick it is on screen. Nought means there is no line: either the
        /// layer never had one or its ring is switched off.
        public var width: CGFloat
        public var paint: Paint
        public var styleID: UUID?
        /// The whole ring, when the source wore its edge as a Border in the
        /// Effects list. Kept entire so a ring pasted onto another box arrives
        /// on the same side of the edge, the same distance off it, switched on
        /// or off exactly as it was.
        public var ring: BorderEffect?
        /// Where that ring sat in the Effects list, so it goes back to the same
        /// place among whatever else was added.
        public var ringIndex: Int?

        public init(width: CGFloat, paint: Paint, styleID: UUID? = nil,
                    ring: BorderEffect? = nil, ringIndex: Int? = nil) {
            self.width = width
            self.paint = paint
            self.styleID = styleID
            self.ring = ring
            self.ringIndex = ringIndex
        }
    }

    /// A saved colour worn by one entry in `effects`, by its place in the list.
    public struct EffectName: Hashable, Codable, Sendable {
        public var index: Int
        public var styleID: UUID

        public init(index: Int, styleID: UUID) {
            self.index = index
            self.styleID = styleID
        }
    }

    /// What the layer it came off is called, so the app can say whose look it
    /// is holding.
    public var sourceName: String
    public var parts: [Part]
    public var edge: Edge
    public var opacity: Double
    public var cornerRadii: CornerRadii
    public var blendMode: BlendMode
    /// Everything ADDED, in the order it paints — minus the entry that IS the
    /// source's edge, which `edge` carries instead.
    public var effects: [LayerEffect]
    public var effectNames: [EffectName]

    public init(sourceName: String, parts: [Part], edge: Edge, opacity: Double,
                cornerRadii: CornerRadii, blendMode: BlendMode,
                effects: [LayerEffect], effectNames: [EffectName] = []) {
        self.sourceName = sourceName
        self.parts = parts
        self.edge = edge
        self.opacity = opacity
        self.cornerRadii = cornerRadii
        self.blendMode = blendMode
        self.effects = effects
        self.effectNames = effectNames
    }
}

// MARK: - Lifting a look off a layer

extension Layer {

    /// The look this layer is wearing.
    public var look: LayerLook {
        let edgeSlot = outlineSlot
        // Every colour the layer paints EXCEPT the one its edge is painted in:
        // the edge travels on its own so it can land wherever the target keeps
        // its own edge.
        let parts = colorSlots.filter { $0 != edgeSlot }.map { slot in
            LayerLook.Part(slot: slot, paint: paint(for: slot),
                           styleID: colorStyleID(for: slot))
        }

        // The edge, and — when it is a ring in the Effects list — the ring
        // itself and where it sat, so it can go back in the same place.
        let ringIndex = drawsItsOwnOutline ? nil : style.borderEffectIndex
        let edge = LayerLook.Edge(width: outlineWidth,
                                  paint: outlinePaint,
                                  styleID: colorStyleID(for: edgeSlot),
                                  ring: ringIndex.flatMap { style.effect(at: $0)?.border },
                                  ringIndex: ringIndex)

        // The Effects list with that ring taken out, and every saved colour on
        // the entries that are left moved up with them.
        var effects = style.effects
        var names: [LayerLook.EffectName] = []
        for index in effects.indices {
            guard let id = colorStyleID(forEffectAt: index) else { continue }
            names.append(LayerLook.EffectName(index: index, styleID: id))
        }
        if let ringIndex {
            effects.remove(at: ringIndex)
            names = names.compactMap { name in
                if name.index == ringIndex { return nil }
                return LayerLook.EffectName(index: name.index > ringIndex ? name.index - 1 : name.index,
                                            styleID: name.styleID)
            }
        }

        return LayerLook(sourceName: name, parts: parts, edge: edge,
                         opacity: style.opacity, cornerRadii: style.cornerRadii,
                         blendMode: style.blendMode, effects: effects,
                         effectNames: names)
    }
}

extension PhotonzDocument {

    /// The look one layer is wearing, or nil when there is no such layer.
    public func look(ofLayer id: UUID) -> LayerLook? { layer(id: id)?.look }
}

// MARK: - What happened when a look was put on

/// What putting a look on some layers actually did, in the words the notice
/// pill says out loud.
///
/// A look is best effort BY DESIGN: a target simply has the parts it has, and
/// one that does not fit is skipped rather than refusing the whole thing. The
/// cost of that is a result that is not quite a match and no way to tell why,
/// so what was skipped is counted and said.
public struct LookPaste: Hashable, Sendable {
    /// How many layers took it.
    public var layerCount: Int
    /// The parts that were left behind, said the way the panel says them
    /// ("Fill", "Head"), each named once however many layers skipped it.
    public var skipped: [String]
    /// How many picked layers were locked, and so left exactly as they were.
    public var lockedCount: Int

    public init(layerCount: Int, skipped: [String] = [], lockedCount: Int = 0) {
        self.layerCount = layerCount
        self.skipped = skipped
        self.lockedCount = lockedCount
    }

    /// The verdict at the head of the pill.
    public var title: String { layerCount == 0 ? "Nothing took it" : "Pasted" }

    /// One line saying how far it reached and what did not fit.
    public var detail: String {
        guard layerCount > 0 else {
            if lockedCount > 0 {
                return lockedCount == 1 ? "The layer is locked"
                                        : "All \(lockedCount) layers are locked"
            }
            return "Pick a shape to put it on"
        }
        var line = layerCount == 1 ? "1 layer took it" : "\(layerCount) layers took it"
        if !skipped.isEmpty {
            let named = LookPaste.list(skipped.map { "the \($0.lowercased())" })
            line += layerCount == 1 ? ". Skipped \(named), which it does not have"
                                    : ". Skipped \(named), which they do not have"
        }
        if lockedCount > 0 {
            line += lockedCount == 1 ? ". 1 locked layer was left alone"
                                     : ". \(lockedCount) locked layers were left alone"
        }
        return line
    }

    /// "fill", "fill and head", "fill, head and label fill".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
        }
    }
}

// MARK: - Putting a look on

extension PhotonzDocument {

    /// Puts a look on some layers, taking across everything each one can wear
    /// and quietly skipping what it cannot.
    ///
    /// The order matters and is the whole of the best-effort rule:
    ///
    /// 1. The three properties every layer has go on first.
    /// 2. The Effects list is REPLACED, because Effects is what was added and
    ///    matching one shape to another means it ends up wearing what that one
    ///    wears, not a merge of the two.
    /// 3. The edge goes on next, wherever this layer keeps its own edge: into
    ///    the Effects list for a box or a picture, onto the stroke for a line,
    ///    an arrow or a path.
    /// 4. The parts go on last, so a slot the source named exactly beats the
    ///    edge that happened to land in the same place.
    ///
    /// A locked layer is left exactly as it is. Nothing here fails: a part the
    /// target has no room for is counted and skipped.
    @discardableResult
    public mutating func applyLook(_ look: LayerLook, to layerIDs: [UUID]) -> LookPaste {
        var applied = 0
        var locked = 0
        var skipped: [String] = []
        func skip(_ title: String) {
            guard !skipped.contains(title) else { return }
            skipped.append(title)
        }

        for id in layerIDs {
            guard let target = layer(id: id) else { continue }
            guard !target.isLocked else { locked += 1; continue }

            // 1. What every layer has.
            updateLayer(id: id) {
                $0.style.opacity = look.opacity
                $0.style.cornerRadii = look.cornerRadii
                $0.style.blendMode = look.blendMode
            }

            // 2 and 3. The added list, with the edge put back into it when this
            // layer is the kind that wears its edge as a ring.
            applyEffectsAndEdge(look, to: id, skip: skip)

            // 4. The parts.
            for part in look.parts {
                guard let current = layer(id: id) else { break }
                guard current.colorSlots.contains(part.slot) else {
                    skip(part.slot.title)
                    continue
                }
                apply(part, to: id)
            }

            applied += 1
        }

        return LookPaste(layerCount: applied, skipped: skipped, lockedCount: locked)
    }

    /// Replaces the target's Effects list with the look's, and puts the look's
    /// edge where this layer's edge lives.
    private mutating func applyEffectsAndEdge(_ look: LayerLook, to id: UUID,
                                              skip: (String) -> Void) {
        guard let target = layer(id: id) else { return }
        let wearsARing = !target.drawsItsOwnOutline

        var effects = look.effects
        var names = look.effectNames

        if wearsARing, look.edge.width > 0 || look.edge.ring != nil {
            // The ring goes back where it sat among whatever else was added, so
            // a shadow that painted over it still paints over it.
            let at = min(max(0, look.edge.ringIndex ?? effects.count), effects.count)
            var ring = look.edge.ring
                ?? BorderEffect(width: look.edge.width, position: .inside)
            if look.edge.ring == nil { ring.paint = look.edge.paint }
            effects.insert(.border(ring), at: at)
            names = names.map {
                LayerLook.EffectName(index: $0.index >= at ? $0.index + 1 : $0.index,
                                     styleID: $0.styleID)
            }
            if let styleID = look.edge.styleID {
                names.append(LayerLook.EffectName(index: at, styleID: styleID))
            }
        }

        // Straight onto the layer, bindings and all: every name in the list
        // points at a PLACE in it, so the list and its names have to land in
        // one move or a shadow ends up wearing the border's name.
        updateLayer(id: id) { layer in
            layer.style.effects = effects
            layer.dropEffectColorStyles()
        }
        for name in names {
            guard colorStyle(id: name.styleID) != nil else { continue }
            _ = bindColorStyle(layerIDs: [id], effectAt: name.index, styleID: name.styleID)
        }

        guard !wearsARing else { return }

        // A line, an arrow or a path IS its edge. A look with no edge in it has
        // nothing to say about that line, and a line of no width is not a
        // setting, it is a delete — so the layer keeps the line it has and the
        // pill says the outline was skipped.
        guard look.edge.width > 0 else {
            if !target.outlineIsSwitchable { skip(LayerPart.outline.title) }
            else { _ = setPathOutline(layerIDs: [id], on: false) }
            return
        }
        updateLayer(id: id) { $0.setOutlineWidth(look.edge.width) }
        apply(LayerLook.Part(slot: .stroke, paint: look.edge.paint,
                             styleID: look.edge.styleID), to: id)
    }

    /// Paints one part on one layer: the saved colour when the document still
    /// has it, the loose colour when it does not, and nothing at all when the
    /// part was switched off, which switches this one off too.
    private mutating func apply(_ part: LayerLook.Part, to id: UUID) {
        guard let paint = part.paint else {
            _ = setColorEnabled(layerIDs: [id], slot: part.slot, on: false)
            return
        }
        // A part that is switched off has to come back before it can be
        // painted, exactly as letting a colour go on an off row does.
        if layer(id: id)?.colorHex(for: part.slot) == nil, part.slot.isSwitchable {
            _ = setColorEnabled(layerIDs: [id], slot: part.slot, on: true)
        }
        if let styleID = part.styleID, colorStyle(id: styleID) != nil {
            _ = bindColorStyle(layerIDs: [id], slot: part.slot, styleID: styleID)
            return
        }
        updateLayer(id: id) {
            $0.unbindColorStyle(for: part.slot)
            $0.setPaint(paint, for: part.slot)
        }
    }
}

extension Layer {

    /// Lets go of every saved colour worn by an entry in the Effects list,
    /// keeping the ones on the layer's own slots. Used when the whole list is
    /// replaced at once: a name points at a place in the list, and the list
    /// about to land is somebody else's.
    mutating func dropEffectColorStyles() {
        let remaining = (colorStyleBindings ?? []).filter { $0.effectIndex == nil }
        colorStyleBindings = remaining.isEmpty ? nil : remaining
    }
}
