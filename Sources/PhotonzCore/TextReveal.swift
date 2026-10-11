import CoreGraphics
import Foundation

// Title text comes in by line, word or letter (task
// `title-text-comes-in-by-line-word-or-letter`,
// `docs/design/video-titles-polish.md`).
//
// Polished titles bring their words in a piece at a time: each line rising
// from behind its own baseline, each word fading up a few frames after the one
// before, letters closing up from wide tracking, or typed one at a time.
//
// **One reveal per text, stored once.** What the words split into, how far
// apart each piece starts, in what order and how each one arrives are four
// answers on the text itself. They are never turned into a layer per word: the
// words stay one piece of text you edit and restyle like any other, and the
// pieces only exist at the moment drawn. The document hands the renderer how
// far into its reveal a text is (`TextContent.revealElapsedMS`, set on the
// frame drawn at a moment the way a caption's lit word is), and the renderer
// draws each piece where this file says it is.
//
// **On the layer's own clock.** A reveal starts at a moment of the clock its
// keys are read on (`startMS`), so it moves with the bar the way a key does,
// and a piece of a title reads it on the title's clock.

/// What a text's words are split into for its reveal.
public enum TextRevealUnit: String, CaseIterable, Hashable, Codable, Sendable {
    case whole, line, word, letter

    public var title: String {
        switch self {
        case .whole: "Whole"
        case .line: "Line"
        case .word: "Word"
        case .letter: "Letter"
        }
    }

    /// How far apart the pieces start when nobody says: the offsets polished
    /// intros use (20 to 40 ms a letter, 40 to 100 a word or a line).
    public var defaultStaggerMS: Int {
        switch self {
        case .whole: 0
        case .line: 100
        case .word: 70
        case .letter: 30
        }
    }
}

/// Which piece goes first.
public enum TextRevealOrder: String, CaseIterable, Hashable, Codable, Sendable {
    /// In reading order.
    case forward
    case reverse
    /// The middle piece first, then outwards both ways together.
    case centerOut
    /// A shuffle, the same one every time for the same seed.
    case random

    public var title: String {
        switch self {
        case .forward: "Forward"
        case .reverse: "Reverse"
        case .centerOut: "Center Out"
        case .random: "Random"
        }
    }
}

/// How each piece arrives.
public enum TextRevealStyle: String, CaseIterable, Hashable, Codable, Sendable {
    /// Fades in while it travels up into place.
    case riseAndFade
    /// Slides up from behind its own baseline, cut off by its own box: the
    /// standard premium headline entrance.
    case maskReveal
    /// Fades in while it sharpens from a blur.
    case blurIn
    /// Starts spread wide about its line's middle and closes up as it fades in.
    case trackIn
    /// Appears whole at its moment, one after another.
    case typewriter
    /// Stays still while an edge travels across and uncovers it.
    case wipe

    public var title: String {
        switch self {
        case .riseAndFade: "Rise and Fade"
        case .maskReveal: "Mask Reveal"
        case .blurIn: "Blur In"
        case .trackIn: "Track In"
        case .typewriter: "Typewriter"
        case .wipe: "Wipe"
        }
    }

    /// How far, how soft or how wide, in percent of the type size, when
    /// nobody says.
    public var defaultAmount: Double {
        switch self {
        case .riseAndFade: 35
        case .blurIn: 12
        case .trackIn: 40
        case .maskReveal, .typewriter, .wipe: 0
        }
    }

    /// Whether the pieces travel or blur, rather than only appearing.
    public var hasAmount: Bool { defaultAmount > 0 }

    /// Whether each piece takes time to arrive. A typewriter's letters do not.
    public var hasLength: Bool { self != .typewriter }
}

/// A stretch of the words, in UTF-16 units the way text layout counts them.
public struct TextRevealSpan: Hashable, Codable, Sendable {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

/// Where a piece sits along its line, counted left to right as drawn: what
/// Track In spreads the pieces about.
public struct TextRevealPlace: Hashable, Sendable {
    public var index: Int
    public var count: Int
    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }
}

/// One piece at one moment: everything the renderer needs to draw it.
public struct TextRevealPose: Hashable, Sendable {
    public var opacity: Double = 1
    /// How far from home it is, in multiples of the type size, y downwards.
    public var offsetEm: CGPoint = .zero
    /// How soft, in multiples of the type size.
    public var blurEm: Double = 0
    /// How far it has slid out of its own box, against `direction`, as a
    /// fraction of the box: 1 is wholly hidden behind its edge, 0 home.
    public var slide: Double = 0
    /// How much of it an edge travelling in `direction` has uncovered.
    public var shown: Double = 1
    public var direction: TitleDirection = .up

    public var isAtRest: Bool {
        opacity >= 1 && offsetEm == .zero && blurEm <= 0 && slide <= 0 && shown >= 1
    }
}

/// How a text's words come in.
public struct TextReveal: Hashable, Codable, Sendable {
    public var style: TextRevealStyle
    public var unit: TextRevealUnit
    /// How long after one piece starts the next one does.
    public var staggerMS: Int
    /// How long each piece takes to arrive.
    public var lengthMS: Int
    public var order: TextRevealOrder
    /// The shuffle `random` uses.
    public var seed: UInt32
    /// When the first piece starts, on the clock the layer's keys are read on.
    public var startMS: Int
    /// How far, how soft or how wide, in percent of the type size
    /// (`TextRevealStyle.defaultAmount`).
    public var amount: Double
    /// Which way a piece travels into place, or the way a wipe's edge moves.
    public var direction: TitleDirection
    /// The curve each piece arrives on.
    public var curve: EasingCurve

    public init(style: TextRevealStyle, unit: TextRevealUnit, staggerMS: Int? = nil,
                lengthMS: Int? = nil, order: TextRevealOrder = .forward, seed: UInt32 = 1,
                startMS: Int = 0, amount: Double? = nil, direction: TitleDirection? = nil,
                curve: EasingCurve = .easeOutExpo) {
        self.style = style
        self.unit = unit
        self.staggerMS = max(0, staggerMS ?? (style == .typewriter ? 50 : unit.defaultStaggerMS))
        self.lengthMS = max(1, lengthMS ?? (unit == .letter ? 400 : 600))
        self.order = order
        self.seed = seed
        self.startMS = startMS
        self.amount = amount ?? style.defaultAmount
        self.direction = direction ?? (style == .wipe ? .right : .up)
        self.curve = curve
    }

    // MARK: Pieces

    /// The pieces of `string` for `unit`, in reading order: each letter as a
    /// reader counts one (an emoji with its modifiers is one), each run of
    /// non-space characters, or the whole. Nil for lines, which only the
    /// layout knows.
    public static func spans(in string: String, unit: TextRevealUnit) -> [TextRevealSpan]? {
        switch unit {
        case .line:
            return nil
        case .whole:
            let length = (string as NSString).length
            return length > 0 ? [TextRevealSpan(location: 0, length: length)] : []
        case .word:
            return CaptionActiveWord.tokenSpans(in: string).map {
                TextRevealSpan(location: $0.location, length: $0.length)
            }
        case .letter:
            var spans: [TextRevealSpan] = []
            var offset = 0
            for character in string {
                let width = character.utf16.count
                if !character.isWhitespace { spans.append(TextRevealSpan(location: offset, length: width)) }
                offset += width
            }
            return spans
        }
    }

    // MARK: Order and timing

    /// Which beat each of `count` pieces goes on, in reading order: pieces
    /// on the same beat go together.
    public func ranks(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        switch order {
        case .forward:
            return Array(0..<count)
        case .reverse:
            return (0..<count).map { count - 1 - $0 }
        case .centerOut:
            let middle = Double(count - 1) / 2
            return (0..<count).map { Int((abs(Double($0) - middle)).rounded(.down)) }
        case .random:
            var order = Array(0..<count)
            var generator = SeededShuffle(seed: seed)
            for index in stride(from: count - 1, to: 0, by: -1) {
                let other = Int(generator.next() % UInt64(index + 1))
                order.swapAt(index, other)
            }
            var ranks = [Int](repeating: 0, count: count)
            for (beat, piece) in order.enumerated() { ranks[piece] = beat }
            return ranks
        }
    }

    /// How long the whole reveal takes for `count` pieces, from its start.
    public func lengthMS(count: Int) -> Int {
        let last = ranks(count: count).max() ?? 0
        return last * staggerMS + (style.hasLength ? lengthMS : 1)
    }

    /// Whether every one of `count` pieces is home `elapsed` ms in.
    public func hasSettled(atElapsedMS elapsed: Int, count: Int) -> Bool {
        elapsed >= lengthMS(count: count)
    }

    // MARK: One piece at one moment

    /// The piece that goes on beat `rank`, `elapsed` ms into the reveal.
    public func pose(rank: Int, atElapsedMS elapsed: Int,
                     place: TextRevealPlace = TextRevealPlace(index: 0, count: 1)) -> TextRevealPose {
        pose(rank: rank, atElapsed: Double(elapsed), place: place)
    }

    /// The same, at a moment between two whole milliseconds: where a piece is
    /// while a shutter is open across it (`MotionSmear.swift`).
    public func pose(rank: Int, atElapsed elapsed: Double,
                     place: TextRevealPlace = TextRevealPlace(index: 0, count: 1)) -> TextRevealPose {
        let begins = Double(rank * staggerMS)
        var pose = TextRevealPose(direction: direction)
        if style == .typewriter {
            pose.opacity = elapsed >= begins ? 1 : 0
            return pose
        }
        let t = min(max((elapsed - begins) / Double(max(1, lengthMS)), 0), 1)
        let p = curve.value(at: t)
        let left = 1 - p
        let size = amount / 100
        switch style {
        case .riseAndFade:
            pose.opacity = min(max(p, 0), 1)
            let travel = left * size
            pose.offsetEm = CGPoint(x: -direction.vector.x * travel, y: -direction.vector.y * travel)
        case .maskReveal:
            // Wholly behind its edge until its beat, so nothing shows early.
            pose.slide = t <= 0 ? 1 : max(0, left)
        case .blurIn:
            pose.opacity = min(max(p, 0), 1)
            pose.blurEm = max(0, left * size)
        case .trackIn:
            pose.opacity = min(max(p, 0), 1)
            let middle = Double(place.count - 1) / 2
            pose.offsetEm = CGPoint(x: (Double(place.index) - middle) * left * size, y: 0)
        case .wipe:
            pose.shown = t <= 0 ? 0 : min(max(p, 0), 1)
        case .typewriter:
            break
        }
        return pose
    }
}

/// A small, fixed shuffle (SplitMix64), so a random order is the same on the
/// canvas, in playback and in an export, on every machine.
private struct SeededShuffle {
    var state: UInt64
    init(seed: UInt32) { state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - On the layer

extension Layer {

    /// This text as drawn at `ms` of its own motion clock: how far into its
    /// reveal it is, for the renderer. Everything else comes back as it was.
    func withTextRevealShown(atMotionMS ms: Int) -> Layer {
        guard case .text(var text) = content, let reveal = text.reveal else { return self }
        text.revealElapsedMS = ms - reveal.startMS
        var shown = self
        shown.content = .text(text)
        return shown
    }
}

extension PhotonzDocument {

    /// Where the clock `layerID`'s keys are read on starts: its own stretch's,
    /// or the nearest stretch holding it, or the document's.
    public func motionClockStartMS(layerID: UUID) -> Int {
        var here: UUID? = layerID
        while let id = here, let layer = layer(id: id) {
            if let time = layer.time { return time.sourceInMS }
            here = parentID(of: id)
        }
        return 0
    }

    /// Give a text its reveal, or take it off with nil. A reveal given here
    /// starts where the text's own clock does, so its words begin arriving the
    /// moment it comes on. False for anything that is not text.
    @discardableResult
    public mutating func setTextReveal(_ reveal: TextReveal?, layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID), case .text(var text) = layer.content else { return false }
        var reveal = reveal
        if reveal != nil, text.reveal == nil { reveal?.startMS = motionClockStartMS(layerID: layerID) }
        text.reveal = reveal
        updateLayer(id: layerID) { $0.content = .text(text) }
        return true
    }
}
