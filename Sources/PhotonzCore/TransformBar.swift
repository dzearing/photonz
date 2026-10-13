import CoreGraphics

/// The small glass bar of transform values that rides beside a layer while it
/// is in hand (`pages/video-animate.html`, "Animate with the overlay"; the
/// placement contract's "Named exception: the value overlay").
///
/// Move, resize, turn or tilt a layer and the bar comes up beside it with the
/// numbers to type into and a Reset. What is here is the part that is not a
/// view: which values it shows, which of them the hand is changing, which side
/// of the object it sits on, and exactly where, so a bar can never cover the
/// handle being dragged or the tool bar under the canvas.
public enum TransformBar {

    /// One value on the bar.
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case x, y, width, height, angle, tiltX, tiltY, depth, pivotDepth

        /// The short label in front of the number. The angle's is the mock's
        /// angle mark, drawn by the view; its word is here for anything that
        /// reads the bar out.
        public var label: String {
            switch self {
            case .x: "X"
            case .y: "Y"
            case .width: "W"
            case .height: "H"
            case .angle: "Angle"
            case .tiltX: "Tilt X"
            case .tiltY: "Tilt Y"
            case .depth: "Depth"
            case .pivotDepth: "Pivot"
            }
        }

        /// The unit after the number, for the values that are angles.
        public var unit: String? {
            switch self {
            case .angle, .tiltX, .tiltY: "°"
            default: nil
            }
        }

        /// The property the timeline lists this value under, so the bar's key
        /// diamond and a key made from the bar agree with the track.
        public var property: MotionProperty {
            switch self {
            case .x, .y: .position
            case .width, .height: .scale
            case .angle: .rotation
            case .tiltX: .rotationX
            case .tiltY: .rotationY
            case .depth: .depth
            case .pivotDepth: .pivotDepth
            }
        }

        /// The four values the layer's box holds, as opposed to its turn.
        public var isBox: Bool { self == .x || self == .y || self == .width || self == .height }

        /// The values that place the layer in space.
        public var isSpace: Bool {
            self == .tiltX || self == .tiltY || self == .depth || self == .pivotDepth
        }
    }

    /// What brought the bar up.
    public enum Gesture: Equatable, Sendable {
        /// The layer's body dragged to a new place.
        case move
        /// One of the eight squares round its frame.
        case resize(ResizeHandle)
        /// The turn knob above it.
        case rotate
        /// A corner pulled with Option, which slants rather than sizes.
        case skew
        /// One of the knob's 3D arcs, or the depth arrow.
        case tilt(SpaceHandle)
        /// An arrow key.
        case nudge
        /// Layer, Show Transform Values: asked for, with nothing in hand.
        case command

        /// Whether this gesture turned the layer in space, which brings the
        /// space values onto the bar even while every one of them reads 0.
        public var usesSpace: Bool {
            if case .tilt = self { return true }
            return false
        }
    }

    /// Which side of the object the bar sits on.
    public enum Side: Equatable, Sendable {
        case below, above
    }

    /// The gap between the object's frame and the bar.
    public static let gap: CGFloat = 12
    /// How far inside the canvas the bar always stays.
    public static let margin: CGFloat = 12
    /// Room kept above the object's frame for the turn knob, so a bar above
    /// the object sits clear of the knob rather than on it.
    public static let knobClearance: CGFloat = 24

    /// The values the bar shows: the box and the angle always, and the space
    /// values once the layer is in space. Pivot only does something to a layer
    /// that is turned, so it waits for that, as the panel's row did.
    public static func fields(inSpace: Bool, turned: Bool) -> [Field] {
        var fields: [Field] = [.x, .y, .width, .height, .angle]
        if inSpace { fields += [.tiltX, .tiltY, .depth] }
        if inSpace, turned { fields.append(.pivotDepth) }
        return fields
    }

    /// The side the bar takes when a gesture starts. A bottom handle in hand
    /// would have the bar under the pointer, so the bar goes above; it keeps
    /// that side until the hand lets go, so it never jumps mid drag.
    public static func side(for gesture: Gesture) -> Side {
        if case .resize(let handle) = gesture, handle.movesMaxY { return .above }
        return .below
    }

    /// The fields a gesture is changing, which the bar outlines while it runs.
    public static func liveFields(for gesture: Gesture) -> Set<Field> {
        switch gesture {
        case .move, .nudge: [.x, .y]
        case .resize(let handle):
            Set<Field>()
                .union(handle.movesMinX || handle.movesMaxX ? [.width] : [])
                .union(handle.movesMinY || handle.movesMaxY ? [.height] : [])
        case .rotate, .skew: [.angle]
        case .tilt(.swing): [.tiltY]
        case .tilt(.tip): [.tiltX]
        case .tilt(.depth): [.depth]
        case .command: []
        }
    }

    /// Where the bar goes, in the canvas view's own points (y down).
    ///
    /// One rule, applied in order: on the side asked for, 12 points off the
    /// object's frame (above it, clear of the knob); on the other side when
    /// that side has no room; slid sideways to stay 12 points inside the
    /// canvas; and never down over the tool bar, whose top is `floor`.
    public static func frame(around box: CGRect, bar: CGSize, canvas: CGSize,
                             floor: CGFloat, side: Side) -> CGRect {
        let below = box.maxY + gap
        let above = box.minY - knobClearance - gap - bar.height
        let lowest = max(margin, floor - bar.height)
        let top: CGFloat
        switch side {
        case .above:
            top = above >= margin ? above : below
        case .below:
            top = below + bar.height <= floor ? below : above
        }
        let left = min(max(box.midX - bar.width / 2, margin),
                       max(margin, canvas.width - margin - bar.width))
        return CGRect(x: left, y: min(max(top, margin), lowest),
                      width: bar.width, height: bar.height)
    }

    /// Reset's size: the layer's own size, around the middle it has now, so an
    /// animated size comes back without the layer moving.
    public static func resetFrame(shown: CGRect, own: CGSize) -> CGRect {
        CGRect(x: shown.midX - own.width / 2, y: shown.midY - own.height / 2,
               width: own.width, height: own.height)
    }
}

/// A number typed into a value field, or a sum to work one out.
///
/// The bar takes sums the way every design tool's fields do: `+40` moves a
/// thing 40 on from where it is, `*2` doubles it, `/4` quarters it, and a
/// whole sum like `1920/2` or `(100-20)*2` is worked out. A leading minus on
/// its own is a negative number, not a step back, because `-5` typed into an
/// angle means minus five degrees.
public enum TypedSum {

    /// The value the text stands for, worked from `current` where it starts
    /// with an operator; nil for anything that is not a number or a sum.
    public static func value(_ text: String, from current: CGFloat?) -> CGFloat? {
        var cleaned = text.lowercased().filter { !$0.isWhitespace }
        cleaned = cleaned.replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{00D7}", with: "*")
            .replacingOccurrences(of: "\u{00F7}", with: "/")
        for unit in ["degrees", "deg", "px", "pt", "°", "%"] where cleaned.hasSuffix(unit) {
            cleaned = String(cleaned.dropLast(unit.count))
            break
        }
        guard let first = cleaned.first else { return nil }
        if "+*/".contains(first) {
            guard let current else { return nil }
            cleaned = "(\(Self.spell(current)))" + cleaned
        }
        var parser = Parser(Array(cleaned))
        guard let value = parser.sum(), parser.atEnd, value.isFinite else { return nil }
        return CGFloat(value)
    }

    private static func spell(_ value: CGFloat) -> String {
        String(Double(value))
    }

    /// Plus and minus over times and divide over numbers and brackets.
    private struct Parser {
        let characters: [Character]
        var index = 0

        init(_ characters: [Character]) { self.characters = characters }

        var atEnd: Bool { index == characters.count }

        private var next: Character? { index < characters.count ? characters[index] : nil }

        mutating func sum() -> Double? {
            guard var total = product() else { return nil }
            while let op = next, op == "+" || op == "-" {
                index += 1
                guard let term = product() else { return nil }
                total = op == "+" ? total + term : total - term
            }
            return total
        }

        mutating func product() -> Double? {
            guard var total = factor() else { return nil }
            while let op = next, op == "*" || op == "/" {
                index += 1
                guard let term = factor() else { return nil }
                if op == "/" {
                    guard term != 0 else { return nil }
                    total /= term
                } else {
                    total *= term
                }
            }
            return total
        }

        mutating func factor() -> Double? {
            guard let c = next else { return nil }
            if c == "-" {
                index += 1
                return factor().map { -$0 }
            }
            if c == "(" {
                index += 1
                guard let inner = sum(), next == ")" else { return nil }
                index += 1
                return inner
            }
            return number()
        }

        mutating func number() -> Double? {
            let start = index
            var dots = 0
            while let c = next, c.isASCII, c.isNumber || c == "." {
                if c == "." { dots += 1 }
                index += 1
            }
            guard index > start, dots <= 1 else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}
