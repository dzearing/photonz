import CoreGraphics
import Foundation

// MARK: - The reworked selection: one set of grips, a knob, a mode chip, a tag
//
// The user's prototype (`docs/design/mocks/pages/selection-transform.html`,
// approved 2026-11-01, building on `lang-selection.html` section 03b):
//
// - The grips look the SAME in every mode: white square corners, one white
//   pill per edge sitting just outside it, and a white knob with a clockwise
//   arrow hanging on a dotted stem off the top edge. A mode only ADDS
//   controls; 3D adds a depth grip below the card.
// - A chip beside the knob picks the mode, in the order the operations
//   apply: Size, (Skew & distort,) 3D. It shows which mode is on.
// - A tag below the frame says the size (or in 3D the tip, swing and depth),
//   and while the pointer rests on a grip, what that grip does.
// - Everything is drawn FLAT at the card's projected corners, so a grip is
//   one size on screen however the card is turned or pushed back.
// - Hit areas are generous (edge 48 by 24, corner 14, knob 15) and where two
//   overlap on a small object the grip whose drawing is nearer wins, so
//   every grip keeps its own target and hovering lights only one.
//
// All of it is in the canvas VIEW's points, y down, from the four corners the
// canvas already works out for the outline.

/// The ways a picked layer's grips work, picked on the chip by the knob.
public enum TransformMode: String, Hashable, Sendable, CaseIterable, Codable {
    /// Corners resize keeping proportions, edges stretch one way, the knob turns.
    case size
    /// Skew and distort reshape the picture itself (not built yet:
    /// `TransformMode.offered` leaves it out until it is).
    case reshape
    /// Edge pills tip and swing, the depth grip pushes back or pulls forward;
    /// corners still resize and the knob still turns.
    case space

    /// The modes the chip offers today, in the order they apply.
    public static let offered: [TransformMode] = [.size, .space]

    /// The mode's name, as the chip's tip and the tag say it.
    public var title: String {
        switch self {
        case .size: "Size"
        case .reshape: "Skew & distort"
        case .space: "3D"
        }
    }
}

/// One thing on a picked layer's selection a press can take.
public enum SelectionGrip: Hashable, Sendable {
    case corner(ResizeHandle)
    case edge(ResizeHandle)
    case knob
    case depth
    case chip(TransformMode)

    /// How a walk names it.
    public var name: String {
        switch self {
        case .corner(let handle), .edge(let handle): handle.rawValue
        case .knob: "knob"
        case .depth: "depth"
        case .chip(let mode): "chip-" + mode.rawValue
        }
    }

    /// The grip a walk names, or nil.
    public init?(name: String) {
        if name == "knob" { self = .knob; return }
        if name == "depth" { self = .depth; return }
        if name.hasPrefix("chip-"), let mode = TransformMode(rawValue: String(name.dropFirst(5))) {
            self = .chip(mode); return
        }
        guard let handle = ResizeHandle(rawValue: name) else { return nil }
        self = handle.isCorner ? .corner(handle) : .edge(handle)
    }
}

/// Where a picked layer's grips sit on screen, and which one a point is on.
public struct SelectionGrips: Hashable, Sendable {

    // MARK: Sizes, in view points (the prototype's own numbers)

    public static let cornerSide: CGFloat = 10
    public static let cornerRadius: CGFloat = 2
    public static let cornerReach: CGFloat = 14
    public static let pillLength: CGFloat = 20
    public static let pillThickness: CGFloat = 7
    /// How far an edge pill's middle sits outside its edge: half its
    /// thickness and a point and a half, so it touches the outside.
    public static let pillOffset: CGFloat = pillThickness / 2 + 1.5
    public static let edgeHit = CGSize(width: 48, height: 24)
    /// An edge shorter than this has no room for a pill between its corners:
    /// the pill and half of each corner square, with a point clear each side.
    public static let shortestPillEdge: CGFloat = pillLength + cornerSide + 4
    /// A side shorter than this pushes its corners out, so four squares
    /// never cover a small layer.
    public static let crampedSide: CGFloat = 24
    public static let crampedOutset: CGFloat = 6
    public static let knobDistance: CGFloat = 30
    public static let knobRadius: CGFloat = 9.5
    public static let knobReach: CGFloat = 15
    /// Where the dotted stems start, out from their edge: just past the pill.
    public static let stemStart: CGFloat = 9
    public static let lineWidth: CGFloat = 1.5
    public static let depthDistance: CGFloat = 30
    public static let depthSize = CGSize(width: 18, height: 24)
    public static let depthHit = CGSize(width: 36, height: 40)
    public static let chipButton = CGSize(width: 22, height: 20)
    public static let chipPadding: CGFloat = 2
    public static let chipGap: CGFloat = 1
    /// From the knob's middle to the chip's left side.
    public static let chipOffset: CGFloat = 16
    /// How far above the card's highest point the chip row stays.
    public static let chipRise: CGFloat = 22
    /// From the frame's lowest point to the tag, and in 3D past the depth grip.
    public static let tagGap: CGFloat = 12
    public static let tagGapInSpace: CGFloat = 50
    public static let tagAboveGap: CGFloat = 6

    // MARK: What is drawn

    public struct Corner: Hashable, Sendable {
        public let handle: ResizeHandle
        public let center: CGPoint
    }

    public struct Edge: Hashable, Sendable {
        public let handle: ResizeHandle
        public let center: CGPoint
        /// The edge's direction, in radians, y down.
        public let angle: CGFloat
    }

    public struct ChipButton: Hashable, Sendable {
        public let mode: TransformMode
        public let frame: CGRect
    }

    public struct Segment: Hashable, Sendable {
        public let from: CGPoint
        public let to: CGPoint
    }

    /// The four corners as drawn, top left, top right, bottom right, bottom left.
    public let quad: [CGPoint]
    public let mode: TransformMode
    public let corners: [Corner]
    public let edges: [Edge]
    public let knob: CGPoint?
    public let stem: Segment?
    public let depth: CGPoint?
    public let depthStem: Segment?
    public let chip: [ChipButton]
    /// Out from the card's middle through its top edge, unit length.
    public let up: CGPoint

    public init(quad: [CGPoint], mode: TransformMode, rotates: Bool, resizes: Bool,
                modes: [TransformMode] = TransformMode.offered) {
        let q = quad.count == 4 ? quad : [CGPoint](repeating: quad.first ?? .zero, count: 4)
        self.quad = q
        self.mode = mode
        let centre = CGPoint(x: q.reduce(0) { $0 + $1.x } / 4, y: q.reduce(0) { $0 + $1.y } / 4)
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        func length(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }
        /// The unit normal of edge a→b pointing away from the middle.
        func outward(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            let l = length(a, b)
            guard l > 1e-9 else {
                let m = mid(a, b), d = length(centre, m)
                return d > 1e-9 ? CGPoint(x: (m.x - centre.x) / d, y: (m.y - centre.y) / d) : CGPoint(x: 0, y: -1)
            }
            var n = CGPoint(x: -(b.y - a.y) / l, y: (b.x - a.x) / l)
            let m = mid(a, b)
            if n.x * (m.x - centre.x) + n.y * (m.y - centre.y) < 0 { n = CGPoint(x: -n.x, y: -n.y) }
            return n
        }
        let top = mid(q[0], q[1]), bottom = mid(q[2], q[3])
        let up = outward(q[0], q[1])
        self.up = up

        if resizes {
            // A cramped side pushes the corners on it outward, along the
            // card's own sides, so the squares stand clear of the layer.
            let across = length(q[0], q[1]) < Self.crampedSide || length(q[3], q[2]) < Self.crampedSide
            let down = length(q[0], q[3]) < Self.crampedSide || length(q[1], q[2]) < Self.crampedSide
            let handles: [ResizeHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
            let left = outward(q[3], q[0]), right = outward(q[1], q[2]), downward = outward(q[2], q[3])
            corners = handles.enumerated().map { i, handle in
                var p = q[i]
                if across {
                    let side = handle.movesMinX ? left : right
                    p = CGPoint(x: p.x + side.x * Self.crampedOutset, y: p.y + side.y * Self.crampedOutset)
                }
                if down {
                    let side = handle.movesMinY ? up : downward
                    p = CGPoint(x: p.x + side.x * Self.crampedOutset, y: p.y + side.y * Self.crampedOutset)
                }
                return Corner(handle: handle, center: p)
            }
            let sides: [(ResizeHandle, Int, Int)] = [(.top, 0, 1), (.right, 1, 2), (.bottom, 2, 3), (.left, 3, 0)]
            func pill(_ handle: ResizeHandle, _ a: Int, _ b: Int) -> Edge {
                let n = outward(q[a], q[b]), m = mid(q[a], q[b])
                return Edge(handle: handle,
                            center: CGPoint(x: m.x + n.x * Self.pillOffset, y: m.y + n.y * Self.pillOffset),
                            angle: atan2(q[b].y - q[a].y, q[b].x - q[a].x))
            }
            var roomy = sides.filter { length(q[$0.1], q[$0.2]) >= Self.shortestPillEdge }
            // In 3D any edge pill tips and swings, so even a layer too small
            // for pills keeps one, on its longest edge, out past its corners.
            if mode == .space, roomy.isEmpty,
               let longest = sides.max(by: { length(q[$0.1], q[$0.2]) < length(q[$1.1], q[$1.2]) }) {
                roomy = [longest]
            }
            edges = roomy.map { pill($0.0, $0.1, $0.2) }
        } else {
            corners = []
            edges = []
        }

        if rotates {
            let k = CGPoint(x: top.x + up.x * Self.knobDistance, y: top.y + up.y * Self.knobDistance)
            knob = k
            stem = Segment(from: CGPoint(x: top.x + up.x * Self.stemStart, y: top.y + up.y * Self.stemStart),
                           to: CGPoint(x: k.x - up.x * Self.knobRadius, y: k.y - up.y * Self.knobRadius))
            // The chip row never sits on the card: above its highest point
            // when the knob would put it there.
            let highest = q.map(\.y).min() ?? k.y
            let rowY = min(k.y, highest - Self.chipRise)
            var x = k.x + Self.chipOffset + Self.chipPadding
            // One mode is no choice, so no chip.
            chip = modes.count < 2 ? [] : modes.map { mode in
                defer { x += Self.chipButton.width + Self.chipGap }
                return ChipButton(mode: mode, frame: CGRect(x: x, y: rowY - Self.chipButton.height / 2,
                                                            width: Self.chipButton.width,
                                                            height: Self.chipButton.height))
            }
        } else {
            knob = nil
            stem = nil
            chip = []
        }

        if mode == .space {
            let d = CGPoint(x: bottom.x - up.x * Self.depthDistance, y: bottom.y - up.y * Self.depthDistance)
            depth = d
            depthStem = Segment(
                from: CGPoint(x: bottom.x - up.x * Self.stemStart, y: bottom.y - up.y * Self.stemStart),
                to: CGPoint(x: d.x + up.x * Self.depthSize.height / 2, y: d.y + up.y * Self.depthSize.height / 2))
        } else {
            depth = nil
            depthStem = nil
        }
    }

    /// The white plate the chip's buttons sit on.
    public var chipPlate: CGRect? {
        guard let first = chip.first, let last = chip.last else { return nil }
        return first.frame.union(last.frame).insetBy(dx: -Self.chipPadding, dy: -Self.chipPadding)
    }

    // MARK: What a press takes

    /// The grip a press at `p` takes, or nil (the card itself, or nothing).
    ///
    /// The chip's buttons first, exactly where they are drawn. Then every grip
    /// whose hit area holds the point, and of those the one whose DRAWING is
    /// nearest (inside it is nearest of all), then the nearer middle: on a
    /// small object the generous areas overlap, and this keeps each grip its
    /// own target round its own drawing.
    public func hit(_ p: CGPoint) -> SelectionGrip? {
        if let plate = chipPlate, plate.contains(p) {
            return chip.min { distance(p, toRect: $0.frame) < distance(p, toRect: $1.frame) }.map { .chip($0.mode) }
        }
        var best: (grip: SelectionGrip, drawn: CGFloat, middle: CGFloat)?
        func consider(_ grip: SelectionGrip, _ centre: CGPoint, inside: Bool, drawn: CGFloat) {
            guard inside else { return }
            let middle = hypot(p.x - centre.x, p.y - centre.y)
            if let b = best, (b.drawn, b.middle) <= (drawn, middle) { return }
            best = (grip, drawn, middle)
        }
        for corner in corners {
            let c = corner.center
            let r = hypot(p.x - c.x, p.y - c.y)
            let half = Self.cornerSide / 2
            consider(.corner(corner.handle), c, inside: r <= Self.cornerReach,
                     drawn: distance(p, toRect: CGRect(x: c.x - half, y: c.y - half,
                                                       width: Self.cornerSide, height: Self.cornerSide)))
        }
        for edge in edges {
            let local = Self.local(p, about: edge.center, angle: edge.angle)
            let inside = abs(local.x) <= Self.edgeHit.width / 2 && abs(local.y) <= Self.edgeHit.height / 2
            consider(.edge(edge.handle), edge.center, inside: inside,
                     drawn: Self.distance(local, toBoxOf: CGSize(width: Self.pillLength, height: Self.pillThickness)))
        }
        if let knob {
            let r = hypot(p.x - knob.x, p.y - knob.y)
            consider(.knob, knob, inside: r <= Self.knobReach, drawn: max(0, r - Self.knobRadius))
        }
        if let depth {
            let angle = atan2(up.x, -up.y)
            let local = Self.local(p, about: depth, angle: angle)
            let inside = abs(local.x) <= Self.depthHit.width / 2 && abs(local.y) <= Self.depthHit.height / 2
            consider(.depth, depth, inside: inside, drawn: Self.distance(local, toBoxOf: Self.depthSize))
        }
        return best?.grip
    }

    /// How many square view points answer to `grip`: what a walk and the audit
    /// measure for a small object's targets.
    public func hitArea(of grip: SelectionGrip, step: CGFloat = 0.5) -> CGFloat {
        let centre: CGPoint
        switch grip {
        case .corner(let handle): guard let c = corners.first(where: { $0.handle == handle }) else { return 0 }
            centre = c.center
        case .edge(let handle): guard let e = edges.first(where: { $0.handle == handle }) else { return 0 }
            centre = e.center
        case .knob: guard let knob else { return 0 }
            centre = knob
        case .depth: guard let depth else { return 0 }
            centre = depth
        case .chip(let mode): guard let b = chip.first(where: { $0.mode == mode }) else { return 0 }
            centre = CGPoint(x: b.frame.midX, y: b.frame.midY)
        }
        let reach: CGFloat = 30
        var count = 0
        var y = centre.y - reach
        while y <= centre.y + reach {
            var x = centre.x - reach
            while x <= centre.x + reach {
                if hit(CGPoint(x: x, y: y)) == grip { count += 1 }
                x += step
            }
            y += step
        }
        return CGFloat(count) * step * step
    }

    // MARK: The tag

    /// Where a tag of `size` goes: centred under the frame (past the depth
    /// grip in 3D), or, when that runs out of `bounds`, above the frame's top
    /// left corner, where neither the knob nor the chip is.
    public func tagFrame(size: CGSize, in bounds: CGRect) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        let lowest = ys.max() ?? 0, highest = ys.min() ?? 0
        let bottom = CGPoint(x: (quad[2].x + quad[3].x) / 2, y: (quad[2].y + quad[3].y) / 2)
        let gap = mode == .space ? Self.tagGapInSpace : Self.tagGap
        let below = lowest + gap
        func clampedX(_ x: CGFloat) -> CGFloat {
            min(max(x, bounds.minX), max(bounds.minX, bounds.maxX - size.width))
        }
        if below + size.height <= bounds.maxY {
            return CGRect(x: clampedX(bottom.x - size.width / 2), y: below, width: size.width, height: size.height)
        }
        let left = xs.min() ?? 0
        var y = highest - Self.tagAboveGap - size.height
        // Above the chip row too, if the chip has risen over the card.
        if let plate = chipPlate, plate.minX < left + size.width, plate.maxY > y {
            y = min(y, plate.minY - Self.tagAboveGap - size.height)
        }
        return CGRect(x: clampedX(left), y: max(bounds.minY, y), width: size.width, height: size.height)
    }

    // MARK: Geometry

    /// `p` in a frame centred on `centre` and turned by `angle`.
    static func local(_ p: CGPoint, about centre: CGPoint, angle: CGFloat) -> CGPoint {
        let dx = p.x - centre.x, dy = p.y - centre.y
        let c = cos(angle), s = sin(angle)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    /// How far a point in a box's own frame is from a box of `size` about the origin.
    static func distance(_ local: CGPoint, toBoxOf size: CGSize) -> CGFloat {
        let dx = max(0, abs(local.x) - size.width / 2), dy = max(0, abs(local.y) - size.height / 2)
        return hypot(dx, dy)
    }

    private func distance(_ p: CGPoint, toRect r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }
}

// MARK: - What the tag says

public enum SelectionTag {
    /// The tag at rest: the size and any turn in Size; the tip, swing and
    /// depth in 3D.
    public static func resting(mode: TransformMode, size: CGSize, rotation: Double,
                               turn: LayerTurn3D?) -> String {
        switch mode {
        case .space:
            let t = turn ?? LayerTurn3D()
            var words = "Tip \(whole(t.rotationX))° · Swing \(whole(t.rotationY))°"
            let depth = t.depth.rounded()
            if depth != 0 { words += depth > 0 ? " · forward \(whole(depth))" : " · back \(whole(-depth))" }
            return words
        case .size, .reshape:
            var words = "\(whole(size.width)) × \(whole(size.height))"
            let turned = rotation.rounded()
            if turned != 0, turned.truncatingRemainder(dividingBy: 360) != 0 { words += " · \(whole(turned))°" }
            return words
        }
    }

    /// What resting on `grip` says it does, in `mode`.
    public static func does(_ grip: SelectionGrip, mode: TransformMode) -> String {
        switch grip {
        case .corner: "Resize · ⇧ stretch"
        case .edge: mode == .space ? "Tip and swing" : "Stretch"
        case .knob: mode == .space ? "Turn" : "Turn · double-click for 0°"
        case .depth: "Push back or pull forward"
        case .chip(let picked): picked.title
        }
    }

    /// While a drag on a grip is under way.
    public static func dragging(_ grip: SelectionGrip, turn: LayerTurn3D) -> String {
        switch grip {
        case .depth:
            let d = turn.depth.rounded()
            return d >= 0 ? "Forward \(whole(d))" : "Back \(whole(-d))"
        default:
            return "Tip \(whole(turn.rotationX))° · Swing \(whole(turn.rotationY))°"
        }
    }

    static func whole(_ value: Double) -> String {
        let r = value.rounded()
        return r == 0 ? "0" : String(Int(r))
    }

    static func whole(_ value: CGFloat) -> String { whole(Double(value)) }
}

// MARK: - What a drag on a grip does

public enum SelectionDrag {
    /// An edge pill in 3D: across tips, along swings, at the arcs' own rate
    /// (`SpaceDrag.degreesPerPoint`), whichever edge is held. Shift steps both
    /// in 15 degree steps.
    public static func tilted(_ start: LayerTurn3D, by delta: CGPoint, snapped: Bool) -> LayerTurn3D {
        let swung = SpaceDrag.turned(start, by: .swing, delta: delta, zoom: 1, snapped: snapped)
        return SpaceDrag.turned(swung, by: .tip, delta: delta, zoom: 1, snapped: snapped)
    }

    /// The depth grip: up pulls the layer forward, toward the viewer, down
    /// pushes it back, at the arrow's own rate. `nearest` is how far forward
    /// it may come before it would pass the camera.
    public static func pushed(_ start: LayerTurn3D, by delta: CGPoint, zoom: CGFloat,
                              nearest: Double?) -> LayerTurn3D {
        var turned = start
        let scale = zoom > 0 ? Double(zoom) : 1
        let moved = start.depth - Double(delta.y) * SpaceDrag.depthPerPoint / scale
        turned.depth = min(max(moved, SpaceDrag.furthest), nearest ?? .infinity).rounded()
        return turned
    }

    /// Whether a resize keeps the layer's proportions. The user, 2026-11-01:
    /// "I consistently want the aspect ratio preserved, and almost never want
    /// to stretch something." A corner keeps them for every layer, picture or
    /// shape, and Shift stretches freely; an edge stretches one way, and
    /// Shift keeps them there as it always has.
    public static func keepsProportions(_ handle: ResizeHandle, shift: Bool) -> Bool {
        handle.isCorner ? !shift : shift
    }

    /// Option: the resize grows from the middle, so the side opposite the one
    /// held moves by as much the other way.
    public static func fromCentre(start: CGRect, proposed: CGRect, handle: ResizeHandle,
                                  minSize: CGFloat = 1) -> CGRect {
        var width = start.width, height = start.height
        if handle.movesMinX || handle.movesMaxX {
            width = max(minSize, start.width + 2 * (proposed.width - start.width))
        }
        if handle.movesMinY || handle.movesMaxY {
            height = max(minSize, start.height + 2 * (proposed.height - start.height))
        }
        return CGRect(x: start.midX - width / 2, y: start.midY - height / 2, width: width, height: height)
    }
}
