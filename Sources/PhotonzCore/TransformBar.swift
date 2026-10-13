import CoreGraphics

/// The picked layer's transform values: the popover the tool bar's Info
/// button opens (the placement contract's "Named exception: the transform
/// values"). The user, 2026-10-12, of the bar that used to ride beside the
/// layer: "why is it covering up the most important aspect of the photo (the
/// transform grippers? ... Maybe it just becomes an 'i' icon that gets added to
/// the existing toolbar, and you can click to expand a popup".
///
/// What is here is the part that is not a view: which values it lists, which
/// of them the hand is changing, and exactly where the popover goes, so it can
/// never cover a handle, the knob or its 3D arcs.
public enum TransformBar {

    /// One value in the popover.
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case x, y, width, height, angle, tiltX, tiltY, depth, pivotDepth

        /// The row's name, in the popover's left column.
        public var label: String {
            switch self {
            case .x: "X"
            case .y: "Y"
            case .width: "W"
            case .height: "H"
            case .angle: "Rotation"
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

        /// The property the timeline lists this value under, so the popover's key
        /// diamond and a key made from it agree with the track.
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

    /// What the hand is doing to the layer while the popover is open.
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
        /// space values into the popover even while every one of them reads 0.
        public var usesSpace: Bool {
            if case .tilt = self { return true }
            return false
        }
    }

    /// How far inside the canvas the popover always stays.
    public static let margin: CGFloat = 12
    /// The gap between the popover and the tool bar under it, and between the
    /// popover and a handle it slid aside for.
    public static let popoverGap: CGFloat = 8
    /// How far round each handle point the popover keeps off: the 8 point
    /// squares with room for the pointer that is about to grab one.
    public static let handleReach: CGFloat = 10

    /// The values the popover lists: the box and the angle always, and the space
    /// values once the layer is in space. Pivot only does something to a layer
    /// that is turned, so it waits for that, as the panel's row did.
    public static func fields(inSpace: Bool, turned: Bool) -> [Field] {
        var fields: [Field] = [.x, .y, .width, .height, .angle]
        if inSpace { fields += [.tiltX, .tiltY, .depth] }
        if inSpace, turned { fields.append(.pivotDepth) }
        return fields
    }

    /// The fields a gesture is changing, which the popover outlines while it runs.
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

    /// Where the popover goes, in the canvas view's own points (y down).
    ///
    /// One rule, applied in order: centred on the Info button, its foot 8
    /// points over the tool bar (or the tool settings over it), whose top is
    /// `floor`; kept 12 points inside the canvas; and, where that would cover
    /// any of `keepOut`, slid sideways to the nearest place that covers none,
    /// 8 points off the handle it slid aside for. Where no sideways place is
    /// clear it stays over the button.
    public static func popoverFrame(anchorX: CGFloat, size: CGSize, canvas: CGSize,
                                    floor: CGFloat, keepOut: [CGRect]) -> CGRect {
        let top = max(margin, floor - popoverGap - size.height)
        let highest = max(margin, canvas.width - margin - size.width)
        func clamped(_ x: CGFloat) -> CGFloat { min(max(x, margin), highest) }
        func frame(_ x: CGFloat) -> CGRect {
            CGRect(x: x, y: top, width: size.width, height: size.height)
        }
        func isClear(_ rect: CGRect) -> Bool { !keepOut.contains { $0.intersects(rect) } }
        let natural = clamped(anchorX - size.width / 2)
        guard !isClear(frame(natural)) else { return frame(natural) }
        let band = frame(natural)
        let candidates = keepOut
            .filter { $0.maxY > band.minY && $0.minY < band.maxY }
            .flatMap { [$0.minX - popoverGap - size.width, $0.maxX + popoverGap] }
            .map(clamped)
            .filter { isClear(frame($0)) }
        guard let best = candidates.min(by: { abs($0 - natural) < abs($1 - natural) }) else {
            return frame(natural)
        }
        return frame(best)
    }

    /// The places a picked layer is handled by on screen, which the popover
    /// keeps off: its eight squares (the corners and edge middles of `quad`,
    /// the layer as drawn, in order round it), its turn knob, and with
    /// `space` the knob's two 3D arcs and the depth arrow. View points.
    public static func handleKeepOut(quad: [CGPoint], knob: CGPoint?,
                                     space: SpaceHandles?) -> [CGRect] {
        func around(_ p: CGPoint) -> CGRect {
            CGRect(x: p.x - handleReach, y: p.y - handleReach,
                   width: handleReach * 2, height: handleReach * 2)
        }
        func around(_ points: [CGPoint]) -> CGRect {
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
            else { return .null }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -handleReach, dy: -handleReach)
        }
        var boxes: [CGRect] = []
        for (index, corner) in quad.enumerated() {
            let next = quad[(index + 1) % quad.count]
            boxes.append(around(corner))
            boxes.append(around(CGPoint(x: (corner.x + next.x) / 2, y: (corner.y + next.y) / 2)))
        }
        if let space {
            boxes.append(around(space.knob))
            boxes.append(around(space.swingArc.points()))
            boxes.append(around(space.tipArc.points()))
            boxes.append(around([space.depthArrow.tail, space.depthArrow.head]))
        } else if let knob {
            boxes.append(around(knob))
        }
        return boxes
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
/// The transform values take sums the way every design tool's fields do: `+40` moves a
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
