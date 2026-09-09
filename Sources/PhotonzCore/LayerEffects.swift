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
    /// A soft coloured halo outside the layer, or a lit edge inside it.
    ///
    /// Underneath it is a shadow with nowhere to fall (`GlowEffect.asShadow`),
    /// and that is exactly why it is its own kind rather than advice about how
    /// to set a shadow up: nobody finds "shadow, coloured, offset nought", and
    /// a glow has no Distance and no Direction to answer for.
    case glow

    /// What the row is called on screen.
    public var title: String {
        switch self {
        case .blur: return "Blur"
        case .shadow: return "Shadow"
        case .border: return "Border"
        case .glow: return "Glow"
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
        // outside it, so a border is countable too. A glow likewise: a tight
        // bright core and a wide soft bloom are two of them.
        case .shadow, .border, .glow: return true
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
        case .shadow, .border, .glow: return false
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
        case .glow: return .glow
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
    /// What the ring is drawn in. Flat by default; it holds a gradient once one
    /// is chosen, exactly as a shape's outline always could — which matters
    /// because a shape's outline BECAME one of these
    /// (`OutlineRetirement.swift`), and a gradient edge somebody drew must not
    /// flatten just because the app moved where it lives.
    public var paint: Paint
    /// The one flat colour the ring stands for. Everything that can only draw
    /// one reads it: a swatch, a contrast reading, a letter's outline. Setting
    /// it makes the ring flat, which is what painting a border a colour means.
    public var colorHex: String {
        get { paint.hex }
        set { paint.hex = newValue; paint.kind = .solid }
    }
    /// Which side of the layer's edge it sits on. This is the whole of what
    /// makes an inner border and an outer border two different things.
    public var position: BorderPosition
    /// How far the ring stands AWAY from the edge it sits against, in document
    /// points. Nought puts it right on that edge, which is where every border
    /// drawn before this one sits.
    ///
    /// This is what makes two rings on one shape worth having: a tight one on
    /// the edge and a second standing ten points off it. Inside, ten moves the
    /// ring ten points further in from the inside edge; outside, ten points
    /// further out. Centred straddles the edge and has no side to measure
    /// from, so the number is kept but not applied and no control is offered
    /// for it (`BorderPosition.appliesOffset`).
    public var offset: CGFloat = 0
    /// What the ring goes round on a LABEL: its letters, or the box the words
    /// sit in (`BorderFollows.swift`). Nothing but a label has letters, so on
    /// every other layer the ring follows the box whatever this says.
    public var follows: BorderFollows
    /// Whether it paints at all. Off keeps every number on it, exactly as a
    /// shadow's tick does.
    public var isOn: Bool

    /// What a border looks like the moment it is added: thick enough to see at
    /// a glance without swamping a small shape.
    public static let startingWidth: CGFloat = 2
    /// How far the Width slider goes, matching the outline's own range so one
    /// ring cannot reach somewhere the other cannot.
    public static let widthRange: ClosedRange<CGFloat> = 0...40
    /// How far the Offset slider goes. The same range the width carries, so a
    /// ring can stand as far off the edge as it can be thick and the two rows
    /// read as one pair rather than as two unrelated scales.
    public static let offsetRange: ClosedRange<CGFloat> = 0...40

    public init(width: CGFloat = BorderEffect.startingWidth,
                colorHex: String = "#000000",
                position: BorderPosition = .outside,
                offset: CGFloat = 0,
                follows: BorderFollows = .letters,
                isOn: Bool = true) {
        self.width = width
        self.paint = Paint(hex: colorHex)
        self.position = position
        self.offset = offset
        self.follows = follows
        self.isOn = isOn
    }

    private enum CodingKeys: String, CodingKey {
        case width, colorHex, paint, position, offset, follows, isOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decode(CGFloat.self, forKey: .width)
        position = try c.decodeIfPresent(BorderPosition.self, forKey: .position) ?? .outside
        // A file written before the offset existed says nothing, and every ring
        // in it sat right on its edge, so that is what it opens as.
        offset = try c.decodeIfPresent(CGFloat.self, forKey: .offset) ?? 0
        // A file written before the choice existed says nothing, and every
        // border it holds on a label was drawn round the letters, so that is
        // what it opens as (`BorderFollows.swift`).
        follows = try c.decodeIfPresent(BorderFollows.self, forKey: .follows) ?? .letters
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? true
        // The flat colour is where it has always been; the ramp goes in beside
        // it, and only when there is one.
        if let ramp = try c.decodeIfPresent(Paint.self, forKey: .paint) {
            paint = ramp
        } else {
            paint = Paint(hex: try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#000000")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        // Always the plain string, so a border written today still draws in a
        // build that has never heard of a gradient one.
        try c.encode(colorHex, forKey: .colorHex)
        if paint.isGradient { try c.encode(paint, forKey: .paint) }
        try c.encode(position, forKey: .position)
        // Only when it stands off the edge, so a border written today opens in
        // an older build drawing exactly where it has always drawn.
        if offset != 0 { try c.encode(offset, forKey: .offset) }
        // Only the answer that is not the ordinary one, so a label bordered
        // today opens in an older build drawing exactly what it drew before.
        if follows != .letters { try c.encode(follows, forKey: .follows) }
        try c.encode(isOn, forKey: .isOn)
    }

    /// Whether this entry puts anything on the canvas.
    public var paints: Bool { isOn && width > 0 }

    /// Where this ring's outer edge sits relative to the layer's edge, signed.
    /// What DRAWS it: the renderer grows the box by it, corners and all.
    public var ringOutset: CGFloat { position.ringOutset(width: width, offset: offset) }

    /// How far it reaches PAST the layer's edge. Zero for an inside ring
    /// however far it is offset, which is why an inner border never makes a
    /// layer take up more room.
    public var outset: CGFloat { max(0, ringOutset) }

    /// Whether the offset means anything where this ring sits. Centred has no
    /// side of the edge to stand off from, so it does not.
    public var appliesOffset: Bool { position.appliesOffset }
}

/// Which way a glow is thrown: out past the layer's edge, or in from it.
///
/// The same effect in two places rather than two effects, exactly as a shadow's
/// Kind is. Splitting a kind across two entries on the plus is the thing the
/// user reported on 2026-09-07: it reads as if inner and outer were unrelated
/// ideas when one control turns either into the other in place.
public enum GlowKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// A halo round the outside of the layer, painted behind it.
    case outer
    /// A lit band inside the layer's edge, clipped to its silhouette.
    case inner

    /// What the Kind popup calls it.
    public var title: String {
        switch self {
        case .outer: return "Outer"
        case .inner: return "Inner"
        }
    }
}

/// A coloured halo somebody ADDED: a soft glow outside the layer's edge, or a
/// lit edge inside it.
///
/// Four things and no more — a colour, how far it reaches, how soft it is, and
/// how strong. There is no Distance and no Direction, because a glow does not
/// fall anywhere: that is the whole difference between it and a shadow, and it
/// is why a glow's settings are shorter than a shadow's rather than the same
/// six controls with two of them set to nought.
public struct GlowEffect: Hashable, Codable, Sendable {
    public var colorHex: String
    /// Softness — gaussian sigma of the halo's falloff, in document points.
    public var radius: CGFloat
    /// Size — how far the halo's SHAPE grows from the layer's edge before it is
    /// blurred. Distinct from softness: size decides how far the light reaches,
    /// softness decides how gently it stops.
    public var size: CGFloat
    public var opacity: Double
    /// Outside the edge, or inside it.
    public var kind: GlowKind
    /// Whether it paints at all. Off keeps every number on it, exactly as a
    /// shadow's tick does.
    public var isOn: Bool

    /// What a glow looks like the moment it is added.
    ///
    /// A clear blue rather than a tasteful near-nothing, because the failure a
    /// first-time user actually hits is adding a Glow and seeing no difference.
    /// It has to be obvious on a white canvas and on a dark one, and it must
    /// never be black: a black halo is a shadow, and the point of this effect
    /// is that it does not only darken.
    ///
    /// The size and the softness were raised on 2026-09-08 after watching it on
    /// the probe: a big softness over a small size spreads what little alpha
    /// there is over thirty-odd points, and the halo came out so pale on a
    /// white canvas that it read as nothing happening. A band with a solid core
    /// and a soft edge is the thing a person recognises as a glow.
    public static let startingColorHex = "#4DA3FF"
    public static let startingRadius: CGFloat = 10
    public static let startingSize: CGFloat = 6
    public static let startingOpacity: Double = 0.9
    /// How far the Softness slider goes, matching the shadow's own softness so
    /// one halo cannot be softer than the other can ever be.
    public static let softnessRange: ClosedRange<CGFloat> = 0...40
    /// How far the Size slider goes.
    public static let sizeRange: ClosedRange<CGFloat> = 0...40

    public init(colorHex: String = GlowEffect.startingColorHex,
                radius: CGFloat = GlowEffect.startingRadius,
                size: CGFloat = GlowEffect.startingSize,
                opacity: Double = GlowEffect.startingOpacity,
                kind: GlowKind = .outer,
                isOn: Bool = true) {
        self.colorHex = colorHex
        self.radius = radius
        self.size = size
        self.opacity = opacity
        self.kind = kind
        self.isOn = isOn
    }

    /// Whether this entry puts anything on the canvas. A glow with no softness
    /// and no size has nowhere to be: it would land exactly under the layer.
    public var paints: Bool { isOn && opacity > 0 && (radius > 0 || size > 0) }

    /// How far it reaches PAST the layer's edge. Nought for an inner glow,
    /// which is why one never makes a layer take up more room. 3σ covers a
    /// gaussian's visible tail, the same reckoning a shadow's reach uses.
    public var outset: CGFloat {
        guard paints, kind == .outer else { return 0 }
        return radius * 3 + max(size, 0)
    }

    /// The same halo said in the language the renderer already speaks: a
    /// shadow with nowhere to fall.
    ///
    /// A glow IS an unoffset shadow, so it is drawn down the tested path that
    /// casts one behind a layer or into it rather than through a second halo
    /// engine that would have to be kept in step with the first.
    public var asShadow: ShadowStyle {
        ShadowStyle(radius: radius, offset: .zero, spread: size, colorHex: colorHex,
                    opacity: opacity, kind: kind == .inner ? .inner : .drop, isOn: isOn)
    }
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
    case glow(GlowEffect)

    public var kind: EffectKind {
        switch self {
        case .blur: return .blur
        case .shadow: return .shadow
        case .border: return .border
        case .glow: return .glow
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
            case .glow(let glow): return glow.isOn
            }
        }
        set {
            switch self {
            case .blur(var blur): blur.isOn = newValue; self = .blur(blur)
            case .shadow(var shadow): shadow.isOn = newValue; self = .shadow(shadow)
            case .border(var border): border.isOn = newValue; self = .border(border)
            case .glow(var glow): glow.isOn = newValue; self = .glow(glow)
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
            case .glow(let glow): return glow.colorHex
            }
        }
        set {
            guard let newValue else { return }
            switch self {
            case .blur: return
            case .shadow(var shadow): shadow.colorHex = newValue; self = .shadow(shadow)
            case .border(var border): border.colorHex = newValue; self = .border(border)
            case .glow(var glow): glow.colorHex = newValue; self = .glow(glow)
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

    /// The glow this entry holds, or nil when it is not a glow.
    public var glow: GlowEffect? {
        get { if case .glow(let glow) = self { return glow } else { return nil } }
        set { if let newValue, case .glow = self { self = .glow(newValue) } }
    }

    // Written by hand rather than synthesized, so the saved file reads
    // `{"kind":"shadow","shadow":{…}}` instead of Swift's `{"shadow":{"_0":…}}`.
    // A file is a thing people open, and a new kind should be legible in it.
    private enum CodingKeys: String, CodingKey { case kind, blur, shadow, border, glow }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(EffectKind.self, forKey: .kind)
        switch kind {
        case .blur: self = .blur(try c.decode(BlurEffect.self, forKey: .blur))
        case .shadow: self = .shadow(try c.decode(ShadowStyle.self, forKey: .shadow))
        case .border: self = .border(try c.decode(BorderEffect.self, forKey: .border))
        case .glow: self = .glow(try c.decode(GlowEffect.self, forKey: .glow))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .blur(let blur): try c.encode(blur, forKey: .blur)
        case .shadow(let shadow): try c.encode(shadow, forKey: .shadow)
        case .border(let border): try c.encode(border, forKey: .border)
        case .glow(let glow): try c.encode(glow, forKey: .glow)
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
    /// Beside the shadow rather than at the end, because they are the two
    /// halos: one darkens and one lights, and somebody reaching for a glow is
    /// looking where the shadow is.
    case glow
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
        case .glow: return .glow
        case .border: return .border
        case .blur: return .blur
        }
    }

    /// One line saying what this does, for the menu item's own help.
    public var summary: String {
        switch self {
        case .shadow: return "Thrown behind the layer, or cast into it"
        case .glow: return "A coloured halo outside the layer, or a lit edge inside it"
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
        // Outer, because the layer's own edge is where a person is looking:
        // an inner glow on a shape that is already bright reads as nothing
        // happening, and the Kind on the row turns it inside in one press.
        case .glow: return .glow(GlowEffect())
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

    /// Every glow somebody added, in the order the list holds them: the first
    /// is nearest the eye, so it paints over the ones below it.
    public var glowEffects: [GlowEffect] { effects.compactMap(\.glow) }

    /// The glows that actually paint: switched on, visible, and with somewhere
    /// to be.
    public var paintedGlows: [GlowEffect] { glowEffects.filter(\.paints) }

    /// How far the furthest glow reaches past the layer's edge.
    ///
    /// The furthest one decides rather than the sum of them: two halos round
    /// the same box overlap, they do not stack end to end.
    public var glowOutset: CGFloat { paintedGlows.map(\.outset).max() ?? 0 }

    /// The glow at a place in the LIST — not a place among the glows — because
    /// that is the number a row in the panel already knows.
    public func glowEffect(at index: Int) -> GlowEffect? { effect(at: index)?.glow }

    /// Changes one glow in place, and does nothing at all when the entry there
    /// is not a glow.
    public mutating func updateGlowEffect(at index: Int,
                                          _ mutate: (inout GlowEffect) -> Void) {
        guard var glow = glowEffect(at: index) else { return }
        mutate(&glow)
        effects[index] = .glow(glow)
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

    /// What the tick says OUT LOUD: its state, and, while the row speaks for
    /// fewer layers than are picked, which of them it is speaking for.
    ///
    /// The count was already written under the row, but only as a line of grey
    /// text: a screen reader announcing the switch, and a scripted walk reading
    /// the panel, both heard a flat "on" over two shapes where only one had the
    /// effect (found 2026-09-08). The two are different questions and they keep
    /// different words. Mixed means the layers that HAVE it disagree about
    /// whether it draws, and carries no count, because the line under the row
    /// already spells that one out. A count means the row cannot reach
    /// everything picked, whatever the ones it does reach are doing.
    public var switchReading: String {
        let state = isMixed ? "mixed" : (isOn ? "on" : "off")
        guard !isMixed, !switchIDs.isEmpty, switchIDs.count < selectionCount else { return state }
        return "\(state) for \(switchIDs.count) of \(selectionCount)"
    }

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
    /// Over several picked layers the rows line up by POSITION in the list and
    /// then by KIND within a position. Adding an effect adds it to every picked
    /// layer, so the lists stay the same length as each other from then on; a
    /// layer that is behind says so in the row's own sentence rather than the
    /// row vanishing. Where the picked layers hold DIFFERENT things in one
    /// place — a shadow on one, a border on the other — that place brings a row
    /// each, because an effect a picked layer really has may never be missing
    /// from the list.
    public func layerEffectRows(layerIDs: [UUID]) -> [LayerEffectRow] {
        let picked = layerIDs.compactMap { layer(id: $0) }.filter { !$0.isLocked }
        guard !picked.isEmpty else { return [] }
        let depth = picked.map { $0.style.effects.count }.max() ?? 0
        // One row per KIND at each place, not one row per place. Taking only
        // the first kind found at a place meant a shape whose border sat where
        // another shape's shadow sat had NO ROW AT ALL: nothing to switch,
        // nothing to remove, and nothing on screen saying its effect was there
        // (found on the probe, 2026-09-08). A row may speak for some of the
        // picked layers and say so; it may never leave one of them out in
        // silence.
        var places: [(index: Int, kind: EffectKind)] = []
        var totals: [EffectKind: Int] = [:]
        for index in 0..<depth {
            var here: [EffectKind] = []
            for layer in picked {
                guard let kind = layer.style.effect(at: index)?.kind,
                      !here.contains(kind) else { continue }
                here.append(kind)
            }
            for kind in here {
                places.append((index, kind))
                totals[kind, default: 0] += 1
            }
        }
        var rows: [LayerEffectRow] = []
        var seen: [EffectKind: Int] = [:]
        for (index, kind) in places {
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

    /// One glow's settings, on every picked layer whose list holds a glow at
    /// that place. A layer with a shadow there is left alone rather than
    /// having its shadow quietly turned into a halo.
    @discardableResult
    public mutating func updateGlowEffect(layerIDs: [UUID], at index: Int,
                                          _ mutate: (inout GlowEffect) -> Void) -> Int {
        var changed = 0
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  layer.style.glowEffect(at: index) != nil else { continue }
            updateLayer(id: id) { $0.style.updateGlowEffect(at: index, mutate) }
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
