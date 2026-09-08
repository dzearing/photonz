import CoreGraphics
import Foundation

/// The Effects list: what a layer has because somebody ADDED it.
///
/// The split the whole panel turns on, settled by the user on 2026-09-07
/// (`docs/design/shape-parts.md`, "Appearance and Effects"):
///
/// > **Appearance** is what a shape simply HAS — its opacity, its fill, its
/// > outline, and a corner radius where there are corners. Always there,
/// > always in the same order, never added and never removed.
/// >
/// > **Effects** is a list you ADD to. It starts empty. A shadow, a blur, and
/// > later a glow or a filter arrive from one plus, can arrive more than once,
/// > and can be taken out again.
///
/// One sentence tells you which panel a thing is in, and that is the point: the
/// old panel carried an opacity in one and a shadow's opacity in the other, so
/// a shadow's blur read as a second copy of the layer's blur.
public enum EffectKind: String, CaseIterable, Hashable, Sendable {
    /// The layer's own softness, laid over everything it is made of.
    case blur
    /// What the layer throws behind it, or has cast into it.
    case shadow
    /// A ring round the layer, sitting inside its edge, on it, or outside it.
    /// A shape already HAS one line — its Outline, in Appearance — so every
    /// border in this list is an EXTRA one, which is why there can be several.
    case border

    /// What the row is called on screen.
    public var title: String {
        switch self {
        case .blur: return "Blur"
        case .shadow: return "Shadow"
        case .border: return "Border"
        }
    }

    /// Whether a layer can wear more than one of these.
    ///
    /// A card wants a tight dark contact shadow AND a wide soft lift, so a
    /// shadow is countable. A layer has one softness, so a blur is not: adding
    /// a second one would be two answers to one question.
    public var isCountable: Bool {
        switch self {
        case .blur: return false
        // A card wants a dark hairline tight to its edge AND a pale halo
        // outside it, so a border is countable too.
        case .shadow, .border: return true
        }
    }

    /// Whether this kind holds one fixed place in the list.
    ///
    /// The order of the list is the order things paint, top nearest the eye. A
    /// blur is laid over the whole layer and the shadows are thrown behind it,
    /// so a blur is always at the top and does not drag: there is nowhere else
    /// for it to be that would look any different, and a grip that changes
    /// nothing is a grip that lies.
    public var isPinned: Bool {
        switch self {
        case .blur: return true
        case .shadow, .border: return false
        }
    }

    /// Whether the row carries a colour well of its own.
    public var paintsAColor: Bool { colorSlot != nil }

    /// Which kind of colour this effect paints, so that its colour can be
    /// named, offered and saved through the same machinery every other colour
    /// in the app uses (`ColorStyles.swift`). Nil for an effect with no colour
    /// at all, which brings no colour row rather than a blank one.
    public var colorSlot: ColorSlot? {
        switch self {
        case .blur: return nil
        case .shadow: return .shadow
        case .border: return .border
        }
    }
}

/// The layer's own softness. One number and a switch, so it behaves like every
/// other entry in the list rather than being a slider that is secretly always
/// there.
public struct BlurEffect: Hashable, Codable, Sendable {
    /// Gaussian sigma, in document points.
    public var radius: CGFloat
    /// Whether it paints at all. Off keeps the number, exactly as a shadow's
    /// tick does.
    public var isOn: Bool

    /// What a blur looks like the moment it is added: enough to read as blurred
    /// without hiding what is under it, so the next thing you do is tune it
    /// rather than discover that nothing happened.
    public static let startingRadius: CGFloat = 8

    public init(radius: CGFloat = BlurEffect.startingRadius, isOn: Bool = true) {
        self.radius = radius
        self.isOn = isOn
    }
}

/// A ring round the layer, added rather than simply there.
///
/// The Outline in Appearance is the ONE line a shape has, drawn on its own
/// boundary. A border is an EXTRA one, which is why you can add several: an
/// inner hairline and an outer halo are two entries, told apart by nothing more
/// than where each sits (`BorderPosition`).
public struct BorderEffect: Hashable, Codable, Sendable {
    /// How thick the line is, in document points.
    public var width: CGFloat
    public var colorHex: String
    /// Which side of the layer's edge it sits on. This is the whole of what
    /// makes an inner border and an outer border two different things.
    public var position: BorderPosition
    /// Whether it paints at all. Off keeps every number on it, exactly as a
    /// shadow's tick does.
    public var isOn: Bool

    /// What a border looks like the moment it is added: thick enough to see at
    /// a glance without swamping a small shape.
    public static let startingWidth: CGFloat = 2
    /// How far the Width slider goes, matching the outline's own range so one
    /// ring cannot reach somewhere the other cannot.
    public static let widthRange: ClosedRange<CGFloat> = 0...40

    public init(width: CGFloat = BorderEffect.startingWidth,
                colorHex: String = "#000000",
                position: BorderPosition = .outside,
                isOn: Bool = true) {
        self.width = width
        self.colorHex = colorHex
        self.position = position
        self.isOn = isOn
    }

    /// Whether this entry puts anything on the canvas.
    public var paints: Bool { isOn && width > 0 }

    /// How far it reaches PAST the layer's edge. Zero for an inside ring, which
    /// is why an inner border never makes a layer take up more room.
    public var outset: CGFloat { position.outset(width: width) }
}

/// One entry in the Effects list.
///
/// This is the extension point the panel is built on: **a new effect is a new
/// case here plus the settings it carries, and nothing else changes.** The
/// plus, the tick, the cross, the grip, the reach sentence over a multiple
/// selection and the saved file all read the list rather than the kind.
public enum LayerEffect: Hashable, Codable, Sendable {
    case blur(BlurEffect)
    case shadow(ShadowStyle)
    case border(BorderEffect)

    public var kind: EffectKind {
        switch self {
        case .blur: return .blur
        case .shadow: return .shadow
        case .border: return .border
        }
    }

    /// Whether this entry paints. Off keeps every number on it, which is the
    /// difference between the tick and the cross.
    public var isOn: Bool {
        get {
            switch self {
            case .blur(let blur): return blur.isOn
            case .shadow(let shadow): return shadow.isOn
            case .border(let border): return border.isOn
            }
        }
        set {
            switch self {
            case .blur(var blur): blur.isOn = newValue; self = .blur(blur)
            case .shadow(var shadow): shadow.isOn = newValue; self = .shadow(shadow)
            case .border(var border): border.isOn = newValue; self = .border(border)
            }
        }
    }

    /// Which kind of colour this entry paints, or nil when it paints none.
    public var colorSlot: ColorSlot? { kind.colorSlot }

    /// What this entry is painted, or nil when it paints no colour at all.
    ///
    /// One question for every kind, so the colour row under an effect is one
    /// row rather than one per kind: a new effect that carries a colour answers
    /// here and gets the row, the saved colours and the naming for free.
    public var colorHex: String? {
        get {
            switch self {
            case .blur: return nil
            case .shadow(let shadow): return shadow.colorHex
            case .border(let border): return border.colorHex
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            case .blur: return
            case .shadow(var shadow): shadow.colorHex = newValue; self = .shadow(shadow)
            case .border(var border): border.colorHex = newValue; self = .border(border)
            }
        }
    }

    /// The shadow this entry holds, or nil when it is not a shadow.
    public var shadow: ShadowStyle? {
        get { if case .shadow(let shadow) = self { return shadow } else { return nil } }
        set { if let newValue, case .shadow = self { self = .shadow(newValue) } }
    }

    /// The blur this entry holds, or nil when it is not a blur.
    public var blur: BlurEffect? {
        get { if case .blur(let blur) = self { return blur } else { return nil } }
        set { if let newValue, case .blur = self { self = .blur(newValue) } }
    }

    /// The border this entry holds, or nil when it is not a border.
    public var border: BorderEffect? {
        get { if case .border(let border) = self { return border } else { return nil } }
        set { if let newValue, case .border = self { self = .border(newValue) } }
    }

    // Written by hand rather than synthesized, so the saved file reads
    // `{"kind":"shadow","shadow":{…}}` instead of Swift's `{"shadow":{"_0":…}}`.
    // A file is a thing people open, and a new kind should be legible in it.
    private enum CodingKeys: String, CodingKey { case kind, blur, shadow, border }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(EffectKind.self, forKey: .kind)
        switch kind {
        case .blur: self = .blur(try c.decode(BlurEffect.self, forKey: .blur))
        case .shadow: self = .shadow(try c.decode(ShadowStyle.self, forKey: .shadow))
        case .border: self = .border(try c.decode(BorderEffect.self, forKey: .border))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .blur(let blur): try c.encode(blur, forKey: .blur)
        case .shadow(let shadow): try c.encode(shadow, forKey: .shadow)
        case .border(let border): try c.encode(border, forKey: .border)
        }
    }
}

extension EffectKind: Codable {}

/// What the plus on the Effects header offers.
///
/// One entry per KIND, and never one entry per setting. Inner and outer are a
/// setting on one effect rather than two effects, so the menu says Shadow once
/// and the row it becomes carries the Kind that turns it into an inner one; the
/// same is true of a border, whose Position is what makes an inner one and an
/// outer one two of them. Splitting a kind across two menu items was the thing
/// the user reported on 2026-09-07: it made the list read as if inner and outer
/// were unrelated ideas, and it still left no way to add a border at all.
public enum AddableEffect: String, CaseIterable, Hashable, Sendable, Identifiable {
    case shadow
    case border
    case blur

    public var id: String { rawValue }

    /// What the plus menu calls it: the same word the row will wear, so what
    /// you asked for and what arrives are named the same thing.
    public var title: String { kind.title }

    /// The row it becomes once added.
    public var kind: EffectKind {
        switch self {
        case .shadow: return .shadow
        case .border: return .border
        case .blur: return .blur
        }
    }

    /// One line saying what this does, for the menu item's own help.
    public var summary: String {
        switch self {
        case .shadow: return "Thrown behind the layer, or cast into it"
        case .border: return "An extra ring, inside the layer's edge or outside it"
        case .blur: return "Softens the whole layer"
        }
    }

    /// The entry it adds, born with settings that already look like something.
    public var newEffect: LayerEffect {
        switch self {
        case .shadow: return .shadow(ShadowStyle(kind: .drop))
        // Outside, because the one line a shape already HAS is drawn inside its
        // edge: a border landing in the same place would look like nothing
        // happened.
        case .border: return .border(BorderEffect())
        case .blur: return .blur(BlurEffect())
        }
    }
}

extension LayerStyle {

    /// The entry at a place in the list, or nil when the list is shorter than
    /// that. Every row that speaks for one entry reads through here, so a row
    /// left over from a longer selection cannot crash on a shorter layer.
    public func effect(at index: Int) -> LayerEffect? {
        effects.indices.contains(index) ? effects[index] : nil
    }

    /// Changes one entry in place, and does nothing at all when there is no
    /// such entry.
    public mutating func updateEffect(at index: Int, _ mutate: (inout LayerEffect) -> Void) {
        guard effects.indices.contains(index) else { return }
        mutate(&effects[index])
    }

    /// Which shadow the entry at this place in the list is, counting only
    /// shadows.
    ///
    /// The list holds every kind, and the shadow's own settings rows count
    /// shadows: `shadow(at:)`, the colour well, the renderer. This is the one
    /// place the two numberings meet, so nothing else has to know that a blur
    /// sitting above two shadows makes the second shadow entry number three.
    public func shadowIndex(ofEffect index: Int) -> Int? {
        guard effects.indices.contains(index), effects[index].kind == .shadow else { return nil }
        return effects[..<index].filter { $0.kind == .shadow }.count
    }

    /// Where in the list a new entry of this kind belongs.
    ///
    /// A pinned kind keeps its one place at the top; everything else lands at
    /// the FOOT, furthest from the eye, so the rows already in the list hold
    /// still: adding a second shadow must never move the one somebody has just
    /// tuned.
    func insertionIndex(for kind: EffectKind) -> Int {
        kind.isPinned ? pinnedCount : effects.count
    }

    /// How many entries at the top of the list hold a fixed place.
    public var pinnedCount: Int { effects.prefix { $0.kind.isPinned }.count }

    /// Every ring somebody added, in the order the list holds them: the first
    /// is nearest the eye, so it paints over the ones below it.
    public var borderEffects: [BorderEffect] { effects.compactMap(\.border) }

    /// The rings that actually paint: switched on, and not zero wide.
    public var paintedBorders: [BorderEffect] { borderEffects.filter(\.paints) }

    /// How far the furthest added ring reaches past the layer's edge.
    ///
    /// The furthest one decides rather than the sum of them: two rings round
    /// the same box overlap, they do not stack end to end.
    public var borderEffectOutset: CGFloat { paintedBorders.map(\.outset).max() ?? 0 }

    /// The border at a place in the LIST — not a place among the borders —
    /// because that is the number a row in the panel already knows.
    public func borderEffect(at index: Int) -> BorderEffect? { effect(at: index)?.border }

    /// Changes one border in place, and does nothing at all when the entry
    /// there is not a border.
    public mutating func updateBorderEffect(at index: Int,
                                            _ mutate: (inout BorderEffect) -> Void) {
        guard var border = borderEffect(at: index) else { return }
        mutate(&border)
        effects[index] = .border(border)
    }
}

/// One row of the Effects list, and exactly which of the picked layers it
/// speaks for.
///
/// Computed here rather than in the panel so that what a row SAYS and what it
/// DOES can never drift apart: the tick, the cross, the grip and the settings
/// under it all read their reach off the same value.
public struct LayerEffectRow: Hashable, Sendable, Identifiable {
    public let kind: EffectKind
    /// Where this entry sits in the layer's Effects list, top nearest the eye.
    public let index: Int
    /// Which shadow this is, counting only shadows, for the settings rows that
    /// are addressed that way. Nil on anything that is not a shadow.
    public let shadowIndex: Int?
    /// Which of it this is, among the entries of the same kind, counting from
    /// one. The second shadow says "Shadow 2" rather than being told from the
    /// first by counting down the panel.
    public let ordinal: Int
    /// How many entries of this kind the whole list holds, so a lone shadow is
    /// simply "Shadow".
    public let countOfKind: Int
    /// The picked layers this row reaches.
    public let switchIDs: [UUID]
    /// How many of those have it switched on.
    public let onCount: Int
    /// How many layers are picked altogether, so a row can say what it leaves
    /// out.
    public let selectionCount: Int

    public init(kind: EffectKind, index: Int, shadowIndex: Int?, ordinal: Int,
                countOfKind: Int, switchIDs: [UUID], onCount: Int, selectionCount: Int) {
        self.kind = kind
        self.index = index
        self.shadowIndex = shadowIndex
        self.ordinal = ordinal
        self.countOfKind = countOfKind
        self.switchIDs = switchIDs
        self.onCount = onCount
        self.selectionCount = selectionCount
    }

    public var id: String { "\(kind.rawValue).\(index)" }

    /// What the row is called on screen, told from its own twin when it has
    /// one.
    public var title: String {
        countOfKind > 1 ? "\(kind.title) \(ordinal)" : kind.title
    }

    /// On only when every layer this row reaches has it switched on, so two
    /// boxes where one shadow is off read as off and one click switches both
    /// on rather than switching the other off.
    public var isOn: Bool { !switchIDs.isEmpty && onCount == switchIDs.count }

    /// True while some of the layers this row reaches have it on and the rest
    /// do not. A Mac switch has no third position, so the row says so in words
    /// and the switch is drawn one step quieter (`UX-PATTERNS.md` section 4).
    public var isMixed: Bool { onCount > 0 && onCount < switchIDs.count }

    /// Everything in this list was added, so everything in it can be taken out
    /// again. That is what makes it a list rather than a set of rows that are
    /// off nearly all the time.
    public var canRemove: Bool { true }

    /// Whether the grip is there. A pinned kind has one place in the order and
    /// no grip, because a grip that changes nothing is a grip that lies.
    public var canReorder: Bool { !kind.isPinned }

    /// What the row says out loud when it reaches fewer layers than are picked,
    /// or when the ones it reaches disagree. Nil when it speaks for all of them
    /// and they agree, because a sentence saying "this does what it looks like
    /// it does" is a sentence in the way.
    public var reachNote: String? {
        let reach = switchIDs.count
        var lines: [String] = []
        if reach > 0, reach < selectionCount {
            lines.append("Applies to \(reach) of the \(selectionCount) selected layers.")
        }
        if isMixed {
            let verb = onCount == 1 ? "has" : "have"
            let of = reach < selectionCount ? "\(onCount) of those"
                : "\(onCount) of the \(selectionCount) selected layers"
            lines.append("\(of) \(verb) it switched on. "
                + "Switching this on turns the rest on too.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }
}

extension PhotonzDocument {

    /// The Effects list for a set of picked layers.
    ///
    /// Empty on a shape nobody has added anything to, which is the whole point:
    /// Effects starts with nothing in it and gains a row only when you press
    /// the plus.
    ///
    /// Over several picked layers the rows line up by POSITION in the list, not
    /// by kind, the same rule the Appearance rows follow. Adding an effect adds
    /// it to every picked layer, so the lists stay the same length as each
    /// other from then on; a layer that is behind says so in the row's own
    /// sentence rather than the row vanishing.
    public func layerEffectRows(layerIDs: [UUID]) -> [LayerEffectRow] {
        let picked = layerIDs.compactMap { layer(id: $0) }.filter { !$0.isLocked }
        guard !picked.isEmpty else { return [] }
        let depth = picked.map { $0.style.effects.count }.max() ?? 0
        // The kind at each place is whatever the first layer that HAS a row
        // there wears, so a shorter list never changes what the rows are called.
        var rows: [LayerEffectRow] = []
        var seen: [EffectKind: Int] = [:]
        var totals: [EffectKind: Int] = [:]
        var kinds: [EffectKind] = []
        for index in 0..<depth {
            guard let kind = picked.compactMap({ $0.style.effect(at: index)?.kind }).first
            else { continue }
            kinds.append(kind)
            totals[kind, default: 0] += 1
        }
        for (index, kind) in kinds.enumerated() {
            let holders = picked.filter { $0.style.effect(at: index)?.kind == kind }
            seen[kind, default: 0] += 1
            rows.append(LayerEffectRow(
                kind: kind,
                index: index,
                shadowIndex: holders.first?.style.shadowIndex(ofEffect: index),
                ordinal: seen[kind] ?? 1,
                countOfKind: totals[kind] ?? 1,
                switchIDs: holders.map(\.id),
                onCount: holders.filter { $0.style.effect(at: index)?.isOn == true }.count,
                selectionCount: layerIDs.count))
        }
        return rows
    }

    /// Adds one effect to every picked layer.
    ///
    /// A countable kind lands at the FOOT of the list, furthest from the eye, so
    /// the rows already there hold still: adding a second shadow must never move
    /// the one somebody has just tuned. A kind a layer can only have one of
    /// takes its fixed place, and a second press does nothing rather than
    /// putting two answers to one question in the list. Returns how many layers
    /// took it.
    @discardableResult
    public mutating func addEffect(_ addable: AddableEffect, layerIDs: [UUID]) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked else { continue }
            if !addable.kind.isCountable,
               layer.style.effects.contains(where: { $0.kind == addable.kind }) { continue }
            updateLayer(id: id) { target in
                // Through the layer, never through the list: a name worn by an
                // effect below the new one has to come down a place with it
                // (`ColorStyles.swift`, `insertEffect`).
                target.insertEffect(addable.newEffect,
                                    at: target.style.insertionIndex(for: addable.kind))
            }
            changed += 1
        }
        return changed
    }

    /// The cross on a row: takes that entry out of the list, on every picked
    /// layer that has one there. Different from the tick, which keeps every
    /// number on it and stops it drawing.
    @discardableResult
    public mutating func removeEffect(layerIDs: [UUID], at index: Int) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.effects.indices.contains(index) else { continue }
            updateLayer(id: id) { $0.removeEffect(at: index) }
            changed += 1
        }
        return changed
    }

    /// A row dragged somewhere else in the list, which is a change to what
    /// paints over what: the top of the list is nearest the eye.
    ///
    /// A pinned entry holds its place and nothing may be dropped above one.
    @discardableResult
    public mutating func moveEffect(layerIDs: [UUID], from: Int, to: Int) -> Int {
        guard from != to else { return 0 }
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.effects.indices.contains(from),
                  layer.style.effects.indices.contains(to) else { continue }
            let floor = layer.style.pinnedCount
            guard from >= floor, to >= floor else { continue }
            updateLayer(id: id) { $0.moveEffect(from: from, to: to) }
            changed += 1
        }
        return changed
    }

    /// Changes one entry in the list on every picked layer that has one there.
    /// Returns how many took the change.
    @discardableResult
    public mutating func updateEffect(layerIDs: [UUID], at index: Int,
                                      _ mutate: (inout LayerEffect) -> Void) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.effect(at: index) != nil else { continue }
            updateLayer(id: id) { $0.style.updateEffect(at: index, mutate) }
            changed += 1
        }
        return changed
    }

    /// One border's settings, on every picked layer whose list holds a border
    /// at that place. A layer with a shadow there is left alone rather than
    /// having its shadow quietly turned into a ring.
    @discardableResult
    public mutating func updateBorderEffect(layerIDs: [UUID], at index: Int,
                                            _ mutate: (inout BorderEffect) -> Void) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.borderEffect(at: index) != nil else { continue }
            updateLayer(id: id) { $0.style.updateBorderEffect(at: index, mutate) }
            changed += 1
        }
        return changed
    }

    /// The tick on one entry: stops it drawing, and keeps every number on it.
    @discardableResult
    public mutating func setEffectEnabled(layerIDs: [UUID], at index: Int, on: Bool) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let effect = layer.style.effect(at: index), effect.isOn != on else { continue }
            updateLayer(id: id) { $0.style.updateEffect(at: index) { $0.isOn = on } }
            changed += 1
        }
        return changed
    }
}
