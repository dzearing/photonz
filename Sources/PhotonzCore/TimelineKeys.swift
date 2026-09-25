import Foundation

// Premiere's keys on the timeline.
//
// A Premiere editor reaches for J/K/L, I and O, the arrows and ⌘K without
// looking. Most of those letters already mean a Photoshop tool here (K the
// Lens, L the Line, I Measure, O the Ellipse, A the Arrow, M the marquee), so a
// press means the timeline's thing only while the timeline has the keyboard,
// which is Premiere's own rule: a key acts on the panel that has focus. The
// keys no tool wants (Space, Home, End, ⌘K, ⌥I, ⌥O) work wherever the keyboard
// is, because there is nothing for them to be mistaken for. ⌘T is Final Cut's
// Add Cross Dissolve rather than Premiere's ⌘D, which is Photoshop's Deselect.
//
// Everything here is the decision; the app turns an `NSEvent` into a
// `TimelineKeyPress` and a `TimelineKeyCommand` into the edit.

/// A key, as the timeline reads it.
public enum TimelineKey: Hashable, Sendable {
    /// A printable key, lowercased: "j", "=", "\\".
    case letter(Character)
    case space, left, right, up, down, home, end, delete, forwardDelete
}

/// The modifiers a timeline key cares about.
public struct TimelineKeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let command = TimelineKeyModifiers(rawValue: 1 << 0)
    public static let option = TimelineKeyModifiers(rawValue: 1 << 1)
    public static let shift = TimelineKeyModifiers(rawValue: 1 << 2)
    public static let control = TimelineKeyModifiers(rawValue: 1 << 3)
}

/// One press of a key.
public struct TimelineKeyPress: Hashable, Sendable {
    public var key: TimelineKey
    public var modifiers: TimelineKeyModifiers
    /// The key is being held and this press is the system repeating it.
    public var isRepeat: Bool

    public init(key: TimelineKey, modifiers: TimelineKeyModifiers = [], isRepeat: Bool = false) {
        self.key = key
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    /// Read off what the keyboard sent. The named keys come from their key
    /// codes, because the characters they send are private-use code points;
    /// everything else is its character, lowercased so ⇧L reads as L with
    /// Shift held. Nil for a press that carries nothing to read.
    public init?(characters: String, keyCode: UInt16, modifiers: TimelineKeyModifiers, isRepeat: Bool) {
        let named: TimelineKey? = switch keyCode {
        case 49: .space
        case 123: .left
        case 124: .right
        case 125: .down
        case 126: .up
        case 115: .home
        case 119: .end
        case 51: .delete
        case 117: .forwardDelete
        default: nil
        }
        if let named {
            self.init(key: named, modifiers: modifiers, isRepeat: isRepeat)
            return
        }
        guard characters.count == 1, let character = characters.lowercased().first else { return nil }
        self.init(key: .letter(character), modifiers: modifiers, isRepeat: isRepeat)
    }
}

/// Which way a J, K or L press asks the playhead to go.
public enum ShuttleKey: Hashable, Sendable {
    case reverse, stop, forward
}

/// What a timeline key does.
public enum TimelineKeyCommand: Hashable, Sendable {
    case playPause
    case shuttle(ShuttleKey)
    case stepFrames(Int)
    case editPoint(forward: Bool)
    case goToStart, goToEnd
    case markIn, markOut, clearIn, clearOut
    case addMarker
    case splitAtPlayhead
    /// Premiere's Delete: what is picked goes and nothing else moves.
    case lift
    case rippleDelete
    /// Premiere's Extract (') and Lift (;): what the In and the Out enclose
    /// comes out of every track, closing the gap or leaving it.
    case extractMarked, liftMarked
    /// Premiere's Q and W: the piece under the playhead loses everything from
    /// its start up to the playhead, or from the playhead to its end, and the
    /// gap closes on every track (`RippleTrim.swift`).
    case rippleTrimToPlayhead(RippleTrimEnd)
    /// Final Cut's ⌘T, Premiere's ⌘D: the default transition on the cut at
    /// the playhead (`DefaultTransition.swift`).
    case applyDefaultTransition
    /// Premiere's and Final Cut's S: clips stop, or start again, catching on
    /// the playhead, the cuts and each other while they are dragged.
    case toggleSnapping
    case selectTool, bladeTool, trackSelectForwardTool
    case zoomIn, zoomOut, zoomToFit
}

public enum TimelineKeys {

    /// How many frames ⇧← and ⇧→ travel: Premiere's five.
    public static let shiftStepFrames = 5

    /// What a press does, or nil where the timeline leaves it to whatever
    /// would have had it anyway.
    ///
    /// - Parameters:
    ///   - timelineFocused: the timeline has the keyboard. Only then does a key
    ///     that is also a tool, a nudge or a delete on the canvas mean the
    ///     timeline's thing.
    ///   - kHeld: K is down, which turns J and L into a frame at a time.
    public static func command(for press: TimelineKeyPress, timelineFocused: Bool,
                               kHeld: Bool = false) -> TimelineKeyCommand? {
        let mods = press.modifiers
        // The keys nothing else in a document with time wants.
        switch (press.key, mods) {
        case (.space, []): return .playPause
        case (.home, []): return .goToStart
        case (.end, []): return .goToEnd
        case (.letter("k"), [.command]): return .splitAtPlayhead
        // Final Cut's key, since Premiere's ⌘D is Photoshop's Deselect here.
        case (.letter("t"), [.command]): return .applyDefaultTransition
        case (.letter("i"), [.option]): return .clearIn
        case (.letter("o"), [.option]): return .clearOut
        default: break
        }
        guard timelineFocused else { return nil }
        switch (press.key, mods) {
        case (.left, []): return .stepFrames(-1)
        case (.right, []): return .stepFrames(1)
        case (.left, [.shift]): return .stepFrames(-shiftStepFrames)
        case (.right, [.shift]): return .stepFrames(shiftStepFrames)
        case (.up, []): return .editPoint(forward: false)
        case (.down, []): return .editPoint(forward: true)
        case (.delete, []), (.forwardDelete, []): return .lift
        case (.delete, [.shift]), (.forwardDelete, [.shift]): return .rippleDelete
        default: break
        }
        guard mods.isEmpty, case .letter(let character) = press.key else { return nil }
        // K held: J and L creep a frame a press, and a held key repeats
        // itself into Premiere's slow crawl.
        if kHeld, character == "j" || character == "l" {
            return .stepFrames(character == "l" ? 1 : -1)
        }
        // Every other letter acts once per press. A held L speeding the
        // shuttle up thirty times a second would be a key nobody could use.
        guard !press.isRepeat else { return nil }
        switch character {
        case "j": return .shuttle(.reverse)
        case "k": return .shuttle(.stop)
        case "l": return .shuttle(.forward)
        case "i": return .markIn
        case "o": return .markOut
        case "m": return .addMarker
        case "'": return .extractMarked
        case ";": return .liftMarked
        case "q": return .rippleTrimToPlayhead(.start)
        case "w": return .rippleTrimToPlayhead(.end)
        case "s": return .toggleSnapping
        case "v": return .selectTool
        case "b": return .bladeTool
        case "a": return .trackSelectForwardTool
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        case "\\": return .zoomToFit
        default: return nil
        }
    }
}

/// J, K and L: how fast, and which way.
///
/// Each press of the key for the way it is already going climbs a ladder of
/// speeds; the other key starts again at normal speed the other way; K stops.
public struct TimelineShuttle: Hashable, Sendable {

    /// Premiere's ladder, doubling.
    public static let ladder: [Double] = [1, 2, 4, 8]

    /// The rate it is running at: negative is backwards, nought is stopped.
    public private(set) var rate: Double = 0

    public init() {}

    /// A press of J, K or L. Returns the rate to play at, nought to stop.
    public mutating func press(_ key: ShuttleKey) -> Double {
        switch key {
        case .stop:
            rate = 0
        case .forward, .reverse:
            let sign: Double = key == .forward ? 1 : -1
            if rate * sign > 0 {
                let current = abs(rate)
                let next = Self.ladder.first { $0 > current } ?? Self.ladder[Self.ladder.count - 1]
                rate = next * sign
            } else {
                rate = sign
            }
        }
        return rate
    }

    /// Something else stopped the playhead (a pause, a scrub, the end).
    public mutating func stopped() { rate = 0 }

    /// Something else started it (Space, the Play button).
    public mutating func playing(at rate: Double) { self.rate = rate }
}

extension PhotonzDocument {

    /// Every moment ↑ and ↓ can land on: where anything with time comes in and
    /// goes out, and every cut inside a clip. Sorted, each once.
    public func editPointMoments() -> [Int] {
        var moments = Set<Int>()
        forEachLayer { layer in
            guard let time = layer.time else { return }
            moments.insert(time.inMS)
            moments.insert(time.outMS)
            if let pieces = layer.clipPieces, pieces.count > 1 {
                for index in 1..<pieces.count {
                    moments.insert(time.inMS + pieces.startMS(ofPiece: index))
                }
            }
        }
        return moments.sorted()
    }

    /// The edit point after a moment, or before it. Nil past the last one or
    /// before the first.
    public func neighbourEditPoint(from ms: Int, forward: Bool) -> Int? {
        let moments = editPointMoments()
        return forward ? moments.first { $0 > ms } : moments.last { $0 < ms }
    }
}
