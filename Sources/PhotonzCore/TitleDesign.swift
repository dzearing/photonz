import CoreGraphics
import Foundation

// Titles move in parts, not as one block (task
// `titles-move-in-parts-not-as-one-block`, `docs/design/video-titles-polish.md`).
//
// Today's presets read as slides because the whole group arrives as one slab.
// A polished title does the opposite: its background, its lines of words and
// its accents each come in on their own beat with their own movement, keep
// something gently moving while they hold, and leave quicker than they came.
//
// **A design compiles into ordinary keys** on the layers inside the title's
// group, never a runtime object of its own, so a preset stays layers you own
// (`docs/design/video-titles.md`): every part's keys are draggable, easable and
// deletable like any key somebody made by hand.
//
// **Locked builds, stretchy hold.** An out is written against the title's END
// and kept within its last half second, where the refit that follows a trim
// finds it (`TitleTime.refitFade`), and an in is written against its start. So
// dragging the bar longer or shorter stretches the hold and leaves every in and
// out exactly as long as it was, the way Motion's build markers do in Final Cut.

/// What a part of a title is for, so a later theme or font pair can restyle any
/// preset by role.
public enum TitlePartRole: String, CaseIterable, Hashable, Codable, Sendable {
    case background, headline, subtitle, kicker, accent
}

/// Which way something moves, or which way a wipe's edge travels.
public enum TitleDirection: String, CaseIterable, Hashable, Codable, Sendable {
    case up, down, left, right

    var vector: CGPoint {
        switch self {
        case .up: CGPoint(x: 0, y: -1)
        case .down: CGPoint(x: 0, y: 1)
        case .left: CGPoint(x: -1, y: 0)
        case .right: CGPoint(x: 1, y: 0)
        }
    }
}

/// How a part comes in, or goes off.
public enum TitleBuildKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// Opacity only.
    case fade
    /// Fades while it travels a short way into place, in `direction`.
    case rise
    /// Fades while it sharpens from a blur.
    case blurIn
    /// Fades while it settles from `amount` percent of its size.
    case scaleFrom
    /// Revealed from one edge with the far edge still: a crop on a picture or
    /// a shape, and on words their own reveal (`TextReveal.swift`), which
    /// uncovers the letters where they stand.
    case wipe
    /// Grows from `amount` percent past its own size and settles back: a
    /// spring. On the way out it drops its bounce.
    case springPop
    /// A line draws itself on from its start, and off from its start again
    /// (`StrokeTrim.swift`): an underline or a rule. Anything with no line of
    /// its own wipes on in `direction` instead.
    case drawOn
    /// Glass over the recording frosting over: what is behind it blurs and
    /// dims in, and on the way out sharpens and brightens back to the real
    /// footage (`BlurEffect`, background). Anything that is not glass fades.
    case frost
    /// Words slide up from behind their own baseline, cut off by their own
    /// box: the premium headline entrance. A shape wipes up instead.
    case maskReveal
    /// Letters start spread wide and close up as they fade in. Anything that
    /// is not words fades.
    case trackIn
    /// Letters appear one after another, as typed. Anything that is not
    /// words fades.
    case typewriter

    public var title: String {
        switch self {
        case .fade: "Fade"
        case .rise: "Rise"
        case .blurIn: "Blur In"
        case .scaleFrom: "Scale From"
        case .wipe: "Wipe"
        case .springPop: "Spring Pop"
        case .drawOn: "Draw On"
        case .frost: "Frost"
        case .maskReveal: "Mask Reveal"
        case .trackIn: "Track In"
        case .typewriter: "Typewriter"
        }
    }

    /// The amount a build of this kind takes when nobody says: points of a
    /// 1080 line frame for a rise and a blur, a percentage for a scale, and
    /// for a track in how wide the letters start, as a percent of the type.
    public var defaultAmount: Double {
        switch self {
        case .fade, .wipe, .drawOn, .frost, .maskReveal, .typewriter: 0
        case .rise: 24
        case .blurIn: 12
        case .scaleFrom: 110
        case .springPop: 85
        case .trackIn: 25
        }
    }

    /// What words split into when a build of this kind says nothing: a mask
    /// reveal goes by line, a track in and a typewriter by letter, and
    /// everything else moves the words whole.
    public var defaultUnit: TextRevealUnit {
        switch self {
        case .maskReveal: .line
        case .trackIn, .typewriter: .letter
        default: .whole
        }
    }
}

/// One in or one out of one part.
public struct TitleBuild: Hashable, Codable, Sendable {
    public var kind: TitleBuildKind
    /// For an in, how long after the title arrives this part starts. For an
    /// out, how long before the title goes this part has finished leaving, so
    /// the last in is naturally the first out.
    public var delayMS: Int
    public var lengthMS: Int
    /// How far, how soft or how big, as `TitleBuildKind.defaultAmount` says.
    public var amount: Double
    public var direction: TitleDirection
    /// The curve the move runs on (the shared `EasingCurve` list).
    public var curve: EasingCurve
    /// On words, what they come in a piece at a time by (line, word or
    /// letter), each piece `lengthMS` long. Nil moves them as the kind
    /// suits (`TitleBuildKind.defaultUnit`). Ignored on anything else.
    public var unit: TextRevealUnit?
    /// How long after one piece starts the next one does; nil for the
    /// unit's own (`TextRevealUnit.defaultStaggerMS`).
    public var staggerMS: Int?

    public init(_ kind: TitleBuildKind, delayMS: Int, lengthMS: Int, amount: Double? = nil,
                direction: TitleDirection = .up, curve: EasingCurve = .easeOutExpo,
                by unit: TextRevealUnit? = nil, staggerMS: Int? = nil) {
        self.kind = kind
        self.delayMS = max(0, delayMS)
        self.lengthMS = max(1, lengthMS)
        self.amount = amount ?? kind.defaultAmount
        self.direction = direction
        self.curve = curve
        self.unit = unit
        self.staggerMS = staggerMS.map { max(0, $0) }
    }

    /// The usual way off: shorter than the way in, eased in.
    public static func off(_ kind: TitleBuildKind, delayMS: Int, lengthMS: Int = 250, amount: Double? = nil,
                    direction: TitleDirection = .up) -> TitleBuild {
        TitleBuild(kind, delayMS: delayMS, lengthMS: lengthMS, amount: amount, direction: direction,
                   curve: .easeIn)
    }
}

/// What a part does while it is up.
public enum TitleHoldKind: String, CaseIterable, Hashable, Codable, Sendable {
    /// Nothing: it simply stays.
    case none
    /// Travels `amount` points slowly in `direction`.
    case drift
    /// Grows by `amount` percent, slowly: the Ken Burns push. On glass over a
    /// recording it is the footage behind that grows (`BlurEffect.zoom`), so
    /// a negative amount is the backdrop slowly settling back to its size.
    case push
    /// On and off on a steady beat, the way a text cursor waits.
    case blink
}

public struct TitleHold: Hashable, Codable, Sendable {
    public var kind: TitleHoldKind
    public var amount: Double
    public var direction: TitleDirection

    public init(_ kind: TitleHoldKind, amount: Double = 0, direction: TitleDirection = .up) {
        self.kind = kind
        self.amount = amount
        self.direction = direction
    }

    public static let still = TitleHold(.none)

    /// Half a blink: how long a cursor stays on, and then off.
    public static let blinkMS = 530
}

/// One part of a title: a piece of its group named by `path` (names from the
/// group down, joined with `/`), with its in, its hold and its out.
public struct TitlePart: Hashable, Codable, Sendable {
    public var path: String
    public var role: TitlePartRole
    public var `in`: TitleBuild?
    public var hold: TitleHold
    public var out: TitleBuild?

    public init(path: String, role: TitlePartRole, in entrance: TitleBuild? = nil,
                hold: TitleHold = .still, out: TitleBuild? = nil) {
        self.path = path
        self.role = role
        self.in = entrance
        self.hold = hold
        self.out = out
    }
}

/// A title as parts that each come in on their own beat.
public struct TitleDesign: Hashable, Codable, Sendable {
    public var parts: [TitlePart]

    public init(parts: [TitlePart]) {
        self.parts = parts
    }

    /// How long after the title arrives its last part has finished arriving.
    public var inLengthMS: Int {
        parts.compactMap { $0.in.map { $0.delayMS + $0.lengthMS } }.max() ?? 0
    }

    /// How long before the title goes its first part starts leaving.
    public var outLengthMS: Int {
        parts.compactMap { $0.out.map { $0.delayMS + $0.lengthMS } }.max() ?? 0
    }

    /// The piece `path` names inside `layer`: each name found among the
    /// pieces below the one before it, nearest first.
    public static func find(_ path: String, in layer: Layer) -> Layer? {
        var here = layer
        for name in path.split(separator: "/").map(String.init) {
            guard let found = first(named: name, below: here) else { return nil }
            here = found
        }
        return here.id == layer.id ? nil : here
    }

    private static func first(named name: String, below layer: Layer) -> Layer? {
        for child in layer.children where child.name == name { return child }
        for child in layer.children {
            if let found = first(named: name, below: child) { return found }
        }
        return nil
    }
}

// MARK: - Compiling a design into keys

extension PhotonzDocument {

    /// Write a design onto the pieces of a title's group as ordinary keys:
    /// each part's in from the title's start, its out against the title's end,
    /// its hold between. Whatever a piece had keyed for the properties a part
    /// moves is replaced, because the design is the whole of how it moves.
    /// False for anything not placed in time, or where no part found its piece.
    @discardableResult
    public mutating func applyTitleDesign(_ design: TitleDesign, layerID: UUID) -> Bool {
        guard let group = layer(id: layerID), group.group != nil, group.isPlacedInTime,
              let time = group.time else { return false }
        let unit = max(min(canvasSize.width / 1920, canvasSize.height / 1080), 0.01)
        var wrote = false
        for part in design.parts {
            guard let current = layer(id: layerID), let piece = TitleDesign.find(part.path, in: current)
            else { continue }
            let compiler = TitleCompiler(piece: piece, lengthMS: time.lengthMS, clock: time.sourceInMS,
                                         unit: unit)
            let made = compiler.motions(for: part)
            // Words wiped in are uncovered by their own reveal, which is the
            // whole of how they arrive: no fade keyed on top of it.
            let reveal = compiler.wordReveal(for: part)
            guard !made.isEmpty || reveal != nil else { continue }
            var moved = Set(made.map(\.property))
            if reveal != nil { moved.insert(.opacity) }
            updateLayer(id: piece.id) { edited in
                var motions = (edited.motions ?? []).filter { !moved.contains($0.property) }
                motions += made
                edited.motions = motions.isEmpty ? nil : motions
                if let reveal, case .text(var text) = edited.content {
                    text.reveal = reveal
                    edited.content = .text(text)
                }
            }
            wrote = true
        }
        return wrote
    }

    /// Take a design's keys off the pieces of a title's group: every property
    /// any of its parts moves, and the reveal a wipe gave words. Keys on other
    /// properties stay. What a restyle does before it compiles a design again
    /// (`TitleRestyle.swift`), so a part that stops moving a property does not
    /// keep the keys an earlier design wrote on it.
    mutating func clearTitleDesign(_ design: TitleDesign, layerID: UUID) {
        guard let group = layer(id: layerID), group.group != nil, let time = group.time else { return }
        for part in design.parts {
            guard let current = layer(id: layerID), let piece = TitleDesign.find(part.path, in: current)
            else { continue }
            // As long as it takes for every in, hold and out to be written, so
            // no property a part moves is missed on a short title.
            let compiler = TitleCompiler(piece: piece, lengthMS: max(time.lengthMS, 600_000),
                                         clock: time.sourceInMS, unit: 1)
            var moved = Set(compiler.motions(for: part).map(\.property))
            let revealed = compiler.wordReveal(for: part) != nil
            if revealed { moved.insert(.opacity) }
            guard !moved.isEmpty else { continue }
            updateLayer(id: piece.id) { edited in
                let motions = (edited.motions ?? []).filter { !moved.contains($0.property) }
                edited.motions = motions.isEmpty ? nil : motions
                if revealed, case .text(var text) = edited.content {
                    text.reveal = nil
                    edited.content = .text(text)
                }
            }
        }
    }

    /// How long after it arrives a placed layer has finished arriving: its bar
    /// fade in, or the last key anything inside it reaches in the front half of
    /// its stretch. Where the playhead goes after an insert, and the moment a
    /// Library tile is pictured at.
    public func titleArrivalMS(layerID: UUID) -> Int {
        guard let layer = layer(id: layerID), let time = layer.time else { return 0 }
        var last = layer.pictureFadeMS(.in)
        for piece in layer.selfAndDescendants where piece.id == layer.id || piece.time == nil {
            // Words coming in a piece at a time have arrived when the last
            // piece has (`TextReveal.swift`).
            if let text = piece.text, let reveal = text.reveal {
                let count = TextReveal.spans(in: text.string, unit: reveal.unit)?.count
                    ?? max(1, text.string.split(whereSeparator: \.isNewline).count)
                let ends = reveal.startMS - time.sourceInMS + reveal.lengthMS(count: count)
                if ends < time.lengthMS { last = max(last, ends) }
            }
            for motion in piece.motions ?? [] where motion.repeats == .once && motion.isOn {
                for key in motion.keyframes {
                    let at = key.atMS - time.sourceInMS
                    if at < time.lengthMS / 2 { last = max(last, at) }
                }
            }
        }
        return min(last, time.lengthMS)
    }
}

/// One part's keys, for one piece of one title.
struct TitleCompiler {
    let piece: Layer
    let lengthMS: Int
    /// Where the title's own clock starts (`LayerTime.sourceInMS`).
    let clock: Int
    /// One point of a 1080 line frame, on this one.
    let unit: CGFloat

    /// One stretch of one property: from a value to another over a span of
    /// the title, on a curve.
    struct Run {
        var start: Int
        var end: Int
        var from: MotionValue
        var to: MotionValue
        var curve: EasingCurve
    }

    /// What a build actually does on this piece: a draw on with no line to
    /// draw is a wipe, and a frost with no glass to frost is a fade.
    private func kind(of build: TitleBuild) -> TitleBuildKind {
        switch build.kind {
        case .drawOn: draws ? .drawOn : .wipe
        case .frost: isGlass ? .frost : .fade
        // Words do these themselves (`revealStyle`); a shape does the
        // nearest thing it can.
        case .maskReveal: piece.text != nil ? .maskReveal : .wipe
        case .trackIn, .typewriter: piece.text != nil ? build.kind : .fade
        default: build.kind
        }
    }

    /// Whether this piece is a line that can be drawn on.
    private var draws: Bool { piece.drawsItsOwnOutline && piece.strokeTrimForMotion != nil }

    /// Whether this piece is glass: something with a background blur.
    private var isGlass: Bool { piece.style.effects.contains { $0.blur?.kind == .background } }

    /// How a piece's words come in by their own reveal, or nil where its in
    /// is keys: a wipe, a mask reveal, a track in and a typewriter always,
    /// and a fade, a rise or a blur in once it says a piece to come in by.
    private func revealStyle(_ build: TitleBuild?) -> TextRevealStyle? {
        guard let build, piece.text != nil else { return nil }
        switch kind(of: build) {
        case .wipe: return .wipe
        case .maskReveal: return .maskReveal
        case .trackIn: return .trackIn
        case .typewriter: return .typewriter
        case .fade, .rise: return build.unit == nil ? nil : .riseAndFade
        case .blurIn: return build.unit == nil ? nil : .blurIn
        case .scaleFrom, .springPop, .drawOn, .frost: return nil
        }
    }

    /// Whether this piece's in is its words' own reveal rather than keys.
    private func revealsWords(_ build: TitleBuild?) -> Bool { revealStyle(build) != nil }

    /// The reveal a piece's words come in by, where its in is one. A rise's
    /// and a blur's points of a 1080 line frame become a share of the type,
    /// which is how a reveal measures; a track in's amount already is one.
    func wordReveal(for part: TitlePart) -> TextReveal? {
        guard let build = part.in, let style = revealStyle(build), let text = piece.text else { return nil }
        let half = lengthMS / 2
        let start = min(build.delayMS, half)
        let length = max(1, min(build.delayMS + build.lengthMS, half) - start)
        let unitOfWords = build.unit ?? build.kind.defaultUnit
        let amount: Double? = switch style {
        case .riseAndFade:
            build.kind == .fade ? 0 : build.amount * Double(unit) / Double(max(1, text.fontSize)) * 100
        case .blurIn: build.amount * Double(unit) / Double(max(1, text.fontSize)) * 100
        case .trackIn: build.amount
        case .maskReveal, .typewriter, .wipe: nil
        }
        return TextReveal(style: style, unit: unitOfWords, staggerMS: build.staggerMS, lengthMS: length,
                          startMS: clock + start, amount: amount, direction: build.direction,
                          curve: build.curve)
    }

    func motions(for part: TitlePart) -> [LayerMotion] {
        var runs: [MotionProperty: [Run]] = [:]
        let half = lengthMS / 2
        // The in, from the title's start, inside its front half.
        var inEnd = 0
        if let build = part.in, revealsWords(build) {
            inEnd = min(build.delayMS + build.lengthMS, half)
        } else if let build = part.in {
            let start = min(build.delayMS, half)
            let end = min(build.delayMS + build.lengthMS, half)
            inEnd = end
            if end > start {
                for (property, off, curve) in offs(build, arriving: true) {
                    runs[property, default: []].append(Run(start: start, end: end, from: off,
                                                           to: rest(property), curve: curve))
                }
                // A crop always leaves a point of the shape, so a wipe also
                // fades up over its first moments rather than showing a
                // sliver before it starts.
                if kind(of: build) == .wipe, wipes {
                    runs[.opacity, default: []].append(Run(start: start, end: start + sliver(end - start),
                                                           from: .number(0), to: rest(.opacity),
                                                           curve: .linear))
                }
            }
        }
        // The out, against the title's end, inside its back half.
        var outStart = lengthMS
        var outRuns: [(MotionProperty, MotionValue, EasingCurve)] = []
        var outEnd = lengthMS
        if let build = part.out {
            outEnd = max(lengthMS - build.delayMS, half)
            outStart = max(lengthMS - build.delayMS - build.lengthMS, half)
            if outEnd > outStart { outRuns = offs(build, arriving: false) }
        }
        // The hold, between them.
        var held: [MotionProperty: MotionValue] = [:]
        if part.hold.kind == .blink, outStart > inEnd {
            // Off half a beat, on half a beat, jumping rather than fading, as
            // the Mac's own text cursor does; it ends on, so the out leaves
            // from where it rests.
            let on = rest(.opacity)
            var at = inEnd, lit = true
            while at + TitleHold.blinkMS < outStart {
                let next = at + TitleHold.blinkMS
                runs[.opacity, default: []].append(Run(start: at, end: next, from: lit ? on : .number(0),
                                                       to: lit ? .number(0) : on, curve: .steps(1)))
                at = next
                lit.toggle()
            }
            if !lit {
                runs[.opacity, default: []].append(Run(start: at, end: outStart, from: .number(0), to: on,
                                                       curve: .steps(1)))
            }
        } else if part.hold.kind != .none, outStart > inEnd {
            for (property, value) in holdEnds(part.hold) {
                held[property] = value
                runs[property, default: []].append(Run(start: inEnd, end: outStart, from: rest(property),
                                                       to: value, curve: .linear))
            }
        }
        for (property, off, curve) in outRuns {
            runs[property, default: []].append(Run(start: outStart, end: outEnd,
                                                   from: held[property] ?? rest(property),
                                                   to: off, curve: curve))
        }
        if let build = part.out, kind(of: build) == .wipe, wipes, outEnd > outStart {
            runs[.opacity, default: []].append(Run(start: outEnd - sliver(outEnd - outStart), end: outEnd,
                                                   from: rest(.opacity), to: .number(0), curve: .linear))
        }
        return runs.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { property in
            motion(property, runs[property] ?? [])
        }
    }

    /// The keys for one property's runs, in order: a key where each run
    /// starts carrying its curve, and one where it ends.
    private func motion(_ property: MotionProperty, _ runs: [Run]) -> LayerMotion? {
        var stops: [MotionStop] = []
        for run in runs.sorted(by: { $0.start < $1.start }) {
            if let last = stops.last, last.atMS == clock + run.start {
                stops[stops.count - 1].value = run.from
                stops[stops.count - 1].curve = run.curve
            } else {
                stops.append(MotionStop(atMS: clock + run.start, value: run.from, curve: run.curve))
            }
            stops.append(MotionStop(atMS: clock + run.end, value: run.to))
        }
        guard let first = stops.first else { return nil }
        return LayerMotion.keyed(property, atMS: first.atMS, value: first.value).rebuilt(from: stops)
    }

    /// How long a wipe takes to fade its last point of shape up or away.
    private func sliver(_ length: Int) -> Int { min(length, max(30, length / 6)) }

    /// What a property holds at rest: what the piece was drawn with.
    private func rest(_ property: MotionProperty) -> MotionValue {
        if property.isCrop { return .number(0) }
        return piece.keyStill(property) ?? .number(property == .scale ? 100 : 0)
    }

    private var origin: CGPoint { piece.frame.origin }

    private func moved(_ direction: TitleDirection, by points: Double) -> MotionValue {
        let distance = CGFloat(points) * unit
        return .point(CGPoint(x: origin.x + direction.vector.x * distance,
                              y: origin.y + direction.vector.y * distance))
    }

    /// Whether a crop can cut this piece: a picture, or a shape, which a crop
    /// shrinks from that edge (`Layer.croppedByKey`).
    private var wipes: Bool { piece.supportsContentCrop || piece.annotation != nil }

    /// Each property a build moves, the value it has while the part is off,
    /// and the curve it runs on.
    private func offs(_ build: TitleBuild, arriving: Bool) -> [(MotionProperty, MotionValue, EasingCurve)] {
        let curve = build.curve
        let gone: (MotionProperty, MotionValue, EasingCurve) = (.opacity, .number(0), curve)
        switch kind(of: build) {
        case .fade:
            return [gone]
        case .rise:
            // In: it starts behind where it is going. Out: it carries on.
            let direction = arriving ? opposite(build.direction) : build.direction
            return [gone, (.position, moved(direction, by: build.amount), curve)]
        case .blurIn:
            return [gone, (.blur, .number(build.amount * Double(unit)), curve)]
        case .scaleFrom:
            return [gone, (.scale, .number(build.amount), curve)]
        case .springPop:
            // The bounce is the spring's own curve on the way in, and the
            // fade arrives without one; leaving, it simply shrinks away.
            return arriving
                ? [(.opacity, .number(0), .easeOutQuint), (.scale, .number(build.amount), .easeOutBack)]
                : [gone, (.scale, .number(build.amount), curve)]
        case .wipe:
            guard wipes else { return [gone] }
            return [(cropEdge(build.direction, arriving: arriving), .number(100), curve)]
        case .drawOn:
            // In: the end runs out from the start. Out: the start runs after
            // it, so the line leaves the way it was drawn.
            return arriving ? [(.trimEnd, .number(0), curve)] : [(.trimStart, .number(100), curve)]
        case .frost:
            // Clear and undimmed while it is off: the footage itself.
            return [gone, (.backgroundBlur, .number(0), curve)]
        case .maskReveal:
            // Words leaving by a mask: they drop back behind their baseline,
            // which keys can only say as a short fall and a fade.
            return [gone, (.position, moved(opposite(build.direction), by: 12), curve)]
        case .trackIn, .typewriter:
            return [gone]
        }
    }

    /// The edge a wipe cuts. Coming in, the edge it travels toward starts
    /// fully cut and opens; going off, the edge behind it closes.
    private func cropEdge(_ direction: TitleDirection, arriving: Bool) -> MotionProperty {
        switch (direction, arriving) {
        case (.right, true), (.left, false): .cropRight
        case (.left, true), (.right, false): .cropLeft
        case (.down, true), (.up, false): .cropBottom
        case (.up, true), (.down, false): .cropTop
        }
    }

    private func opposite(_ direction: TitleDirection) -> TitleDirection {
        switch direction {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }

    private func holdEnds(_ hold: TitleHold) -> [(MotionProperty, MotionValue)] {
        switch hold.kind {
        case .none, .blink: []
        case .drift: [(.position, moved(hold.direction, by: hold.amount))]
        case .push:
            if isGlass, case let .number(zoom) = rest(.backgroundZoom) {
                [(.backgroundZoom, .number(zoom + hold.amount))]
            } else {
                [(.scale, .number(100 + hold.amount))]
            }
        }
    }
}
