import CoreGraphics
import Foundation

/// Effects saved under a name, that entries in a layer's Effects list point at
/// (`docs/design/ui-building.md`, "Styles are named values layers point at").
///
/// The third of the three kinds the spec asks for. A named paint is
/// `ColorStyles.swift`; a named text treatment is `TextStyleLibrary.swift`;
/// this is a named shadow, glow, border or blur. It is modelled on the text one
/// rather than the colour one, because an effect is several values kept
/// together rather than a single one: a drop shadow is a colour, a distance, a
/// direction, a softness, a size and an opacity, and the point of naming it is
/// keeping all six as one thing.
///
/// The effect is kept ON the layer as well as in the style, for exactly the
/// reason a colour and a treatment are: nothing downstream — the renderer,
/// export, thumbnails, the package writer — has to learn what an effect style
/// is, because a layer wearing one draws exactly like a layer somebody tuned by
/// hand. The pointer is the extra fact: it says where the effect came from, so
/// an edit to the style can find its way back.
///
/// ## Why the binding names a PLACE
///
/// An effect does not sit on a layer the way a colour or a font does — it sits
/// at an INDEX in a list that can be added to, taken from and dragged around.
/// The app already had to answer this once, for an effect's own colour
/// (`ColorStyleBinding.effectIndex`), and it answered it by naming the place
/// and making `Layer.insertEffect`, `removeEffect` and `moveEffect` the only
/// ways the list may change, so every binding is carried along by the same
/// move. A second, different way of addressing the same list would be a second
/// rule to keep in step with the first, so this one rides on it.

// MARK: - An effect saved under a name

/// An effect saved under a name. `id` is what layers point at, so renaming one
/// never loosens anything.
public struct EffectStyle: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    /// The whole entry, kind and settings together. A style's kind never
    /// changes: the section that edits it edits the settings of the kind it was
    /// saved as, so a row called Shadow can never quietly become a border.
    public var effect: LayerEffect

    public init(id: UUID = UUID(), name: String, effect: LayerEffect) {
        self.id = id
        self.name = name
        self.effect = effect
    }

    public var kind: EffectKind { effect.kind }
}

/// One entry in a layer's Effects list, pointed at a style.
///
/// Stored as a small list rather than a dictionary so it writes to disk as
/// plain JSON and reads as plain English, exactly as `ColorStyleBinding` does.
public struct EffectStyleBinding: Hashable, Codable, Sendable {
    /// Where in the layer's Effects list the named effect sits. A PLACE, so the
    /// list moving has to move it.
    public var effectIndex: Int
    public var styleID: UUID

    public init(effectIndex: Int, styleID: UUID) {
        self.effectIndex = effectIndex
        self.styleID = styleID
    }
}

// MARK: - The names a layer's effects wear

extension Layer {

    /// The style behind the effect at this place in the list, or nil when the
    /// effect there is the layer's own.
    public func effectStyleID(forEffectAt index: Int) -> UUID? {
        effectStyleBindings?.first { $0.effectIndex == index }?.styleID
    }

    /// Whether any entry in this layer's Effects list came from a name.
    public var wearsEffectStyle: Bool { !(effectStyleBindings ?? []).isEmpty }

    /// Points the effect at a place in the list at a style. The effect itself is
    /// written by the document, which is the only thing that knows what the
    /// style holds.
    mutating func bindEffectStyle(_ styleID: UUID, forEffectAt index: Int) {
        guard style.effects.indices.contains(index) else { return }
        var bindings = (effectStyleBindings ?? []).filter { $0.effectIndex != index }
        bindings.append(EffectStyleBinding(effectIndex: index, styleID: styleID))
        effectStyleBindings = Layer.sortedEffectStyleBindings(bindings)
    }

    /// Lets go of an entry's style, keeping the effect it is wearing.
    mutating func unbindEffectStyle(forEffectAt index: Int) {
        let remaining = (effectStyleBindings ?? []).filter { $0.effectIndex != index }
        // Back to nothing rather than an empty list, so a layer that never wore
        // a style writes exactly what it always wrote.
        effectStyleBindings = remaining.isEmpty ? nil : remaining
    }

    /// One fixed order, so the same set of bindings always writes the same JSON.
    static func sortedEffectStyleBindings(_ bindings: [EffectStyleBinding]) -> [EffectStyleBinding] {
        bindings.sorted { $0.effectIndex < $1.effectIndex }
    }

    /// Rewrites every effect-style binding's place, dropping the ones the change
    /// answered with nothing. Called from the same three list moves that carry
    /// the colour bindings (`ColorStyles.swift`).
    mutating func remapEffectStyleBindings(_ move: (Int) -> Int?) {
        guard let bindings = effectStyleBindings, !bindings.isEmpty else { return }
        var rebuilt: [EffectStyleBinding] = []
        for binding in bindings {
            guard let moved = move(binding.effectIndex) else { continue }
            rebuilt.append(EffectStyleBinding(effectIndex: moved, styleID: binding.styleID))
        }
        effectStyleBindings = rebuilt.isEmpty ? nil : Layer.sortedEffectStyleBindings(rebuilt)
    }
}

// MARK: - The document's effect styles

extension PhotonzDocument {

    /// What an effect style is called before anybody names it: the kind it is,
    /// so a shelf of them reads as Shadow, Glow, Border rather than as three
    /// squares called Effect.
    public static func effectStyleNameBase(for kind: EffectKind) -> String { kind.title }

    /// The style behind an id.
    public func effectStyle(id: UUID) -> EffectStyle? {
        effectStyles.first { $0.id == id }
    }

    /// A name nobody is using yet: "Shadow", then "Shadow 2", "Shadow 3"…
    public func freshEffectStyleName(base: String) -> String {
        let taken = Set(effectStyles.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Puts an effect on the shelf under a name, and returns its id. A blank
    /// name becomes the made-up one rather than a nameless tile.
    @discardableResult
    public mutating func addEffectStyle(name: String? = nil, effect: LayerEffect) -> UUID {
        let base = PhotonzDocument.effectStyleNameBase(for: effect.kind)
        let style = EffectStyle(name: ComponentNaming.normalized(name)
                                ?? freshEffectStyleName(base: base),
                                effect: effect)
        effectStyles.append(style)
        return style.id
    }

    /// The one effect every picked layer holds at this place in its list, or nil
    /// when they disagree or none of them has anything there.
    ///
    /// Nil when they disagree for the same reason the text one is: there is no
    /// one effect to keep, and a style quietly made out of whichever layer came
    /// first is a style that means nothing.
    public func sharedEffect(layerIDs: [UUID], at index: Int) -> LayerEffect? {
        var shared: LayerEffect?
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let effect = layer.style.effect(at: index) else { continue }
            if let shared, shared != effect { return nil }
            shared = effect
        }
        return shared
    }

    /// Saves the effect at a place in the list under a name, and points every
    /// picked layer holding that effect at it — the point of saving is to keep
    /// using it, so what you saved from is the style's first wearer.
    @discardableResult
    public mutating func saveEffectStyle(from layerIDs: [UUID], at index: Int,
                                         name: String? = nil) -> UUID? {
        guard let effect = sharedEffect(layerIDs: layerIDs, at: index) else { return nil }
        let styleID = addEffectStyle(name: name, effect: effect)
        _ = bindEffectStyle(layerIDs: layerIDs, at: index, styleID: styleID)
        return styleID
    }

    /// Dresses the entry at a place in the list in a style, on every picked
    /// layer that holds the SAME KIND there.
    ///
    /// A layer with a shadow where the style is a border is left alone rather
    /// than having its shadow turned into a ring: the row is titled after its
    /// kind, and a menu on it that could change the kind is a row that lies.
    /// Adding an effect of a different kind is what the plus is for
    /// (`useEffectStyle`).
    @discardableResult
    public mutating func bindEffectStyle(layerIDs: [UUID], at index: Int,
                                         styleID: UUID) -> Bool {
        guard let style = effectStyle(id: styleID) else { return false }
        var dressed = false
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.effect(at: index)?.kind == style.kind else { continue }
            updateLayer(id: id) { target in
                target.style.updateEffect(at: index) { $0 = style.effect }
                target.bindEffectStyle(styleID, forEffectAt: index)
                // The effect's colour now comes from the effect style, so a
                // colour style on the same entry would be a second name
                // claiming one colour. The effect style wins, exactly as a text
                // style wins over a colour style on the same words.
                target.unbindColorStyle(forEffectAt: index)
            }
            dressed = true
        }
        return dressed
    }

    /// Gives every picked layer the named effect, adding it to the list.
    ///
    /// This is what the plus on the Effects header does with a saved name, and
    /// it is the route by which a name reaches a layer that has nothing like it
    /// yet. A countable kind lands at the foot of the list, the way a fresh one
    /// does, so the rows already there hold still. A kind a layer can only have
    /// one of RE-SETS the one it already has rather than doing nothing: asking
    /// for Soft Blur has to end with the layer wearing Soft Blur.
    ///
    /// Returns how many layers took it.
    @discardableResult
    public mutating func useEffectStyle(layerIDs: [UUID], styleID: UUID) -> Int {
        guard let style = effectStyle(id: styleID) else { return 0 }
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            let existing = style.kind.isCountable ? nil
                : layer.style.effects.firstIndex { $0.kind == style.kind }
            updateLayer(id: id) { target in
                let place: Int
                if let existing {
                    target.style.updateEffect(at: existing) { $0 = style.effect }
                    place = existing
                } else {
                    place = target.style.insertionIndex(for: style.kind)
                    // Through the layer, never through the list: every name
                    // below the new one has to come down a place with it.
                    target.insertEffect(style.effect, at: place)
                }
                target.bindEffectStyle(styleID, forEffectAt: place)
                target.unbindColorStyle(forEffectAt: place)
            }
            changed += 1
        }
        return changed
    }

    /// Lets the entry at a place in the list go back to being the layer's own.
    /// Nothing is re-set: the layer keeps exactly the effect it is wearing.
    public mutating func unbindEffectStyle(layerIDs: [UUID], at index: Int) {
        for id in layerIDs {
            updateLayer(id: id) { $0.unbindEffectStyle(forEffectAt: index) }
        }
    }

    /// Re-sets a style, and with it every entry wearing it. Returns how many
    /// followed, which is what a notice can say out loud.
    ///
    /// One mutation, so `History.perform` records the style and everything it
    /// dresses as a single undo step.
    @discardableResult
    public mutating func setEffectStyle(styleID: UUID, effect: LayerEffect) -> Int {
        guard let index = effectStyles.firstIndex(where: { $0.id == styleID }),
              effectStyles[index].kind == effect.kind else { return 0 }
        effectStyles[index].effect = effect
        var dressed = 0
        mapEffectLayers { layer in
            for binding in layer.effectStyleBindings ?? [] where binding.styleID == styleID {
                guard layer.style.effect(at: binding.effectIndex)?.kind == effect.kind else { continue }
                layer.style.updateEffect(at: binding.effectIndex) { $0 = effect }
                dressed += 1
            }
        }
        return dressed
    }

    /// Renames a style. A blank name is refused rather than leaving a nameless
    /// tile on the shelf.
    public mutating func renameEffectStyle(id: UUID, to name: String) {
        guard let index = effectStyles.firstIndex(where: { $0.id == id }),
              let chosen = ComponentNaming.normalized(name) else { return }
        effectStyles[index].name = chosen
    }

    /// Takes a style off the shelf. Every layer wearing it keeps the effect it
    /// has and simply owns it again: deleting a name must never undo somebody's
    /// work.
    public mutating func deleteEffectStyle(id: UUID) {
        guard effectStyles.contains(where: { $0.id == id }) else { return }
        effectStyles.removeAll { $0.id == id }
        mapEffectLayers { layer in
            for binding in layer.effectStyleBindings ?? [] where binding.styleID == id {
                layer.unbindEffectStyle(forEffectAt: binding.effectIndex)
            }
        }
    }

    /// How many entries in the document wear this style. Two shadows on one
    /// layer count twice, because that is two things an edit would re-set.
    public func effectStyleUsageCount(id: UUID) -> Int {
        allLayers.reduce(0) { total, layer in
            total + (layer.effectStyleBindings ?? []).count { $0.styleID == id }
        }
    }

    /// Every layer wearing this style, once each, so the app can select them.
    public func layersUsingEffectStyle(id: UUID) -> [UUID] {
        allLayers.filter { layer in
            (layer.effectStyleBindings ?? []).contains { $0.styleID == id }
        }.map(\.id)
    }

    /// What the Library's Styles scope shows for effects: one tile per style,
    /// with how much of the document leans on it. They sit on the same shelf as
    /// the saved colours and text styles, because to a person they are the same
    /// kind of thing: a name you put on things.
    public var effectStyleLibraryEntries: [LibraryEntry] {
        effectStyles.map { style in
            LibraryEntry(id: style.id.uuidString, scope: .styles, name: style.name,
                         detail: EffectStyleNaming.detail(usageCount: effectStyleUsageCount(id: style.id)))
        }
    }

    /// The safety net, run after every edit (`History.perform`), and the exact
    /// counterpart of `reconcileColorStyles` and `reconcileTextStyles`.
    ///
    /// Pointing at a style is a claim: "this effect came from that name".
    /// Tuning the shadow by hand, switching it off, painting its colour some
    /// other way — every one of those would leave the claim false, and a row
    /// saying "Card lift" over a shadow that is nothing like Card lift is worse
    /// than no styles at all. So an entry that has drifted from its style, or
    /// whose style is gone, quietly lets go and keeps what it is wearing.
    /// Returns how many claims broke.
    ///
    /// The looking is read-only and the writing only happens when something
    /// actually drifted, so the overwhelmingly common edit — one that broke
    /// nothing — costs one optional check per layer and no copying at all.
    @discardableResult
    public mutating func reconcileEffectStyles() -> Int {
        let styles = Dictionary(effectStyles.map { ($0.id, $0.effect) },
                                uniquingKeysWith: { first, _ in first })
        var stale: [UUID: [Int]] = [:]
        for layer in allLayers {
            guard let bindings = layer.effectStyleBindings, !bindings.isEmpty else { continue }
            for binding in bindings {
                // A name this document no longer has is a claim that cannot be
                // true, which is the state a file can arrive in; an effect that
                // no longer matches the name is the quiet one an edit leaves
                // behind.
                if styles[binding.styleID] != layer.style.effect(at: binding.effectIndex) {
                    stale[layer.id, default: []].append(binding.effectIndex)
                }
            }
        }
        guard !stale.isEmpty else { return 0 }
        var broken = 0
        mapEffectLayers { layer in
            guard let places = stale[layer.id] else { return }
            for place in places {
                layer.unbindEffectStyle(forEffectAt: place)
                broken += 1
            }
        }
        return broken
    }

    /// Every layer in the tree run through a mutation in place. Named for what
    /// effect styles use it for; it walks everything, because an effect can be
    /// on any layer anywhere in the tree.
    private mutating func mapEffectLayers(_ body: (inout Layer) -> Void) {
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

// MARK: - What an effect style's tile and its section say

/// What an effect style's tile, its row and its section say about it.
public enum EffectStyleNaming {

    /// The detail line: how much of the document an edit to this style would
    /// re-set, which is the question a shelf full of styles raises.
    public static func detail(usageCount: Int) -> String {
        switch usageCount {
        case 0: return "not used yet"
        case 1: return "1 use"
        default: return "\(usageCount) uses"
        }
    }

    /// What the style's own section says about itself: how much of the document
    /// an edit here would re-set, which is the one fact somebody about to change
    /// it needs.
    public static func standing(usageCount: Int) -> String {
        switch usageCount {
        case 0: return "Nothing uses this yet. Add it from the plus on the Effects header to use it."
        case 1: return "1 effect uses this. Changing it re-sets that effect."
        case let count:
            return "\(count) effects use this. Changing it re-sets them all in one step."
        }
    }

    /// The few words a hover tip has room for: what the effect is, in the terms
    /// its own settings use.
    public static func effectText(_ effect: LayerEffect) -> String {
        switch effect {
        case .blur(let blur):
            return "Blur • \(points(blur.radius))"
        case .shadow(let shadow):
            return "\(shadow.kind.title) shadow • \(points(shadow.radius)) • \(percent(shadow.opacity))"
        case .border(let border):
            return "\(border.position.title) border • \(points(border.width)) • \(border.colorHex)"
        case .glow(let glow):
            return "\(glow.kind.title) glow • \(points(glow.radius)) • \(glow.colorHex)"
        }
    }

    private static func points(_ value: CGFloat) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? "\(Int(rounded)) pt" : String(format: "%.1f pt", Double(rounded))
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

// MARK: - What one effect row's Style control speaks for

/// What the Style row inside one effect has to show when it is speaking for
/// more than one layer.
///
/// Two cards whose shadow both wear "Card lift" have one thing to say. Two that
/// wear different things have none, and picking one of them to print would be a
/// row claiming a name the other is not wearing.
public enum EffectStyleReading: Hashable, Sendable {
    /// Nothing picked holds an effect at this place, so there is no row.
    case empty
    /// They all hold the same effect there, and none of them wears a name.
    case own(LayerEffect)
    /// Every one of them wears this style.
    case style(UUID)
    /// They differ: different settings, different names, or some named and some
    /// not.
    case mixed
}

/// The layers one effect's Style row speaks for, and what picking a name in it
/// does to all of them. One layer or twenty, the row means the same thing.
public struct EffectStyleSelection: Hashable, Sendable {

    /// One picked layer: what its effect at this place is, and the style behind
    /// it when there is one.
    public struct Member: Hashable, Sendable {
        public let id: UUID
        public let effect: LayerEffect
        public let styleID: UUID?

        public init(id: UUID, effect: LayerEffect, styleID: UUID? = nil) {
            self.id = id
            self.effect = effect
            self.styleID = styleID
        }
    }

    /// What the row shows in place of a name when they differ. The app's one
    /// word for it, so no two controls can spell it differently.
    public static let mixedText = MixedValue.text

    public let members: [Member]
    /// How many layers are picked altogether, including the ones with nothing at
    /// this place, so the row can say what it does and does not reach.
    public let selectionCount: Int

    public init(members: [Member], selectionCount: Int) {
        self.members = members
        self.selectionCount = selectionCount
    }

    public var count: Int { members.count }
    public var isEmpty: Bool { members.isEmpty }

    /// The layers a pick in this row re-sets, in the order they were given.
    public var layerIDs: [UUID] { members.map(\.id) }

    public var reading: EffectStyleReading {
        guard let first = members.first else { return .empty }
        if let styleID = first.styleID {
            for member in members.dropFirst() where member.styleID != styleID { return .mixed }
            return .style(styleID)
        }
        for member in members.dropFirst() where member.styleID != nil { return .mixed }
        for member in members.dropFirst() where member.effect != first.effect { return .mixed }
        return .own(first.effect)
    }

    /// The style every picked layer's effect already wears, when there is one.
    public var boundStyleID: UUID? {
        if case .style(let id) = reading { return id }
        return nil
    }

    /// Whether Unlink has anything to let go of: true as soon as one picked
    /// layer's effect comes from a style.
    public var wearsAnyStyle: Bool { members.contains { $0.styleID != nil } }

    /// What "Save as Style" would keep: the effect they all share, and only
    /// while none of them already wears a name. Nil means the button is not
    /// offered, because there is no one effect to give a name to.
    public var savableEffect: LayerEffect? {
        if case .own(let effect) = reading { return effect }
        return nil
    }

    /// What the row says before its settings are touched, when what they would
    /// change comes from a name: tuning the effect by hand takes it off the
    /// style. Said BEFORE the click, because a name that quietly stopped being
    /// worn is one nobody notices until an edit to it fails to reach a layer.
    public var unlinkNote: String? {
        let styled = members.count { $0.styleID != nil }
        guard styled > 0 else { return nil }
        if case .style = reading {
            return count > 1
                ? "Changing any setting below takes all \(count) of them off the style."
                : "Changing any setting below takes this off the style."
        }
        return "Changing any setting below takes \(styled) of them off their style."
    }
}

extension PhotonzDocument {

    /// What the Style row inside one effect shows for the picked layers. Locked
    /// layers sit out, the same way they sit out of the effect rows themselves.
    public func effectStyleSelection(layerIDs: [UUID], at index: Int,
                                     kind: EffectKind) -> EffectStyleSelection {
        var members: [EffectStyleSelection.Member] = []
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let effect = layer.style.effect(at: index), effect.kind == kind else { continue }
            members.append(EffectStyleSelection.Member(
                id: id, effect: effect, styleID: layer.effectStyleID(forEffectAt: index)))
        }
        return EffectStyleSelection(members: members, selectionCount: layerIDs.count)
    }
}
