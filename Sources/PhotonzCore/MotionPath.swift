import CoreGraphics
import Foundation

// A moving layer draws its path on the canvas, and dragging the path bends it
// into an arc (task `a-moving-layer-draws-its-path-on-the-canvas-and`,
// `docs/design/mocks/pages/video-move-wt.html` steps 5, 7 and 8).
//
// **Easing is how fast it travels; the path is where it travels.** The two are
// separate on purpose (the mock's own note): a straight move can still ease,
// and an arc can still run at a flat rate. So the ease of a stretch decides how
// far ALONG the stretch the value is at a moment, and the path decides where
// that distance lands. Nothing about the keys changes when a path bends: the
// two keys are the same two keys, and each stretch between them carries one
// more number, its bend.
//
// A bend is the offset of a quadratic Bezier's control point from the middle of
// the straight line between the two keys, in the same points the keys are in.
// Stated that way rather than as a place, so a key dragged somewhere else
// carries the arc with it instead of leaving a control point stranded where the
// key used to be. The handle on the canvas is NOT the control point: it is the
// middle of the curve itself, which is where a hand expects to take hold of a
// line, and it sits exactly half way to the control point (`middle`).

/// One stretch of a motion path: from one key's place to the next one's.
public struct MotionPathSegment: Hashable, Sendable {
    public let start: CGPoint
    public let end: CGPoint
    /// The control point's offset from the middle of the chord. Zero is a
    /// straight run.
    public let bend: CGPoint

    public init(start: CGPoint, end: CGPoint, bend: CGPoint = .zero) {
        self.start = start
        self.end = end
        self.bend = bend
    }

    /// Anything under a hundredth of a point is a line: nobody can see it and
    /// the panel must not say Curved about it.
    public var isCurved: Bool { hypot(bend.x, bend.y) >= 0.01 }

    /// The middle of the straight line between the two keys.
    public var chordMiddle: CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// The quadratic's control point.
    public var control: CGPoint {
        CGPoint(x: chordMiddle.x + bend.x, y: chordMiddle.y + bend.y)
    }

    /// The point ON the path half way through its parameter, which is where
    /// the handle sits. For a quadratic that is the chord's middle plus half
    /// the bend.
    public var middle: CGPoint {
        CGPoint(x: chordMiddle.x + bend.x / 2, y: chordMiddle.y + bend.y / 2)
    }

    /// The bend that makes a stretch from `start` to `end` pass through
    /// `point` at its middle: what dragging the handle to `point` writes.
    public static func bend(from start: CGPoint, to end: CGPoint, throughMiddle point: CGPoint) -> CGPoint {
        let chord = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        return CGPoint(x: (point.x - chord.x) * 2, y: (point.y - chord.y) * 2)
    }

    /// Where the curve is at parameter `t` (0 at `start`, 1 at `end`).
    public func point(atParameter t: Double) -> CGPoint {
        let c = control
        let u = 1 - t
        let a = u * u
        let b = 2 * u * t
        let d = t * t
        return CGPoint(x: a * Double(start.x) + b * Double(c.x) + d * Double(end.x),
                       y: a * Double(start.y) + b * Double(c.y) + d * Double(end.y))
    }

    /// How many straight pieces the arc is measured in. Thirty-two keeps the
    /// rate within a percent or so on the most lopsided bend a handle can
    /// make, and costs nothing next to drawing a frame.
    static let measuringPieces = 32

    /// The parameter at a fraction of the way along the path's LENGTH, so a
    /// linear stretch covers equal distances in equal times on an arc as it
    /// does on a line.
    public func parameter(atFraction fraction: Double) -> Double {
        let f = min(max(fraction, 0), 1)
        guard isCurved else { return f }
        let pieces = Self.measuringPieces
        var lengths = [0.0]
        var last = start
        for step in 1...pieces {
            let next = point(atParameter: Double(step) / Double(pieces))
            lengths.append((lengths.last ?? 0) + Double(hypot(next.x - last.x, next.y - last.y)))
            last = next
        }
        let total = lengths.last ?? 0
        guard total > 0 else { return f }
        let wanted = f * total
        for step in 1...pieces where lengths[step] >= wanted {
            let before = lengths[step - 1]
            let piece = lengths[step] - before
            let within = piece > 0 ? (wanted - before) / piece : 0
            return (Double(step - 1) + within) / Double(pieces)
        }
        return 1
    }

    /// Where the path is a fraction of the way along its length.
    public func point(atFraction fraction: Double) -> CGPoint {
        point(atParameter: parameter(atFraction: fraction))
    }

    /// The parameter of the point on the curve nearest `target`, found by
    /// looking along it. Close enough to judge a drawing by, which is all it
    /// is for.
    public func parameter(nearest target: CGPoint) -> Double {
        var best = 0.0
        var bestDistance = Double.infinity
        for step in 0...200 {
            let t = Double(step) / 200
            let p = point(atParameter: t)
            let distance = Double(hypot(p.x - target.x, p.y - target.y))
            if distance < bestDistance {
                bestDistance = distance
                best = t
            }
        }
        return best
    }

    /// The two halves of this stretch cut at parameter `t`, as the bends each
    /// half needs to trace the same curve (de Casteljau), measured against
    /// `middle`, the place the new key actually holds.
    func split(atParameter t: Double, at middle: CGPoint) -> (CGPoint, CGPoint) {
        let c = control
        let leftControl = CGPoint(x: start.x + (c.x - start.x) * t, y: start.y + (c.y - start.y) * t)
        let rightControl = CGPoint(x: c.x + (end.x - c.x) * t, y: c.y + (end.y - c.y) * t)
        let leftChord = CGPoint(x: (start.x + middle.x) / 2, y: (start.y + middle.y) / 2)
        let rightChord = CGPoint(x: (middle.x + end.x) / 2, y: (middle.y + end.y) / 2)
        return (CGPoint(x: leftControl.x - leftChord.x, y: leftControl.y - leftChord.y),
                CGPoint(x: rightControl.x - rightChord.x, y: rightControl.y - rightChord.y))
    }
}

/// What the Path control in Properties says: a line between every pair of
/// keys, or at least one arc.
public enum MotionPathShape: String, Hashable, Sendable, CaseIterable {
    case straight
    case curved

    public var title: String {
        switch self {
        case .straight: "Straight"
        case .curved: "Curved"
        }
    }
}

// MARK: - A motion's path

extension LayerMotion {

    /// The stretches between this motion's keys, first to last, in the value's
    /// own points. Empty unless this is a move with two keys or more: nothing
    /// else has a path to draw.
    public var pathSegments: [MotionPathSegment] {
        guard property == .position else { return [] }
        let list = keyframes
        guard list.count >= 2 else { return [] }
        var segments: [MotionPathSegment] = []
        for index in 0..<(list.count - 1) {
            guard case let .point(start) = list[index].value,
                  case let .point(end) = list[index + 1].value else { return [] }
            segments.append(MotionPathSegment(start: start, end: end, bend: list[index].bend ?? .zero))
        }
        return segments
    }

    /// Straight until any stretch bends.
    public var pathShape: MotionPathShape {
        pathSegments.contains(where: \.isCurved) ? .curved : .straight
    }

    /// This motion with stretch `index` bent so its middle passes through
    /// `point`: the handle let go there. A handle let go back on the line
    /// leaves the stretch straight and writes nothing.
    public func bending(segment index: Int, throughMiddle point: CGPoint) -> LayerMotion {
        let segments = pathSegments
        guard segments.indices.contains(index) else { return self }
        let run = segments[index]
        let bend = MotionPathSegment.bend(from: run.start, to: run.end, throughMiddle: point)
        return settingBend(bend, segment: index)
    }

    /// Stretch `index` put back on the straight line: a double-click on its
    /// handle.
    public func straightening(segment index: Int) -> LayerMotion {
        settingBend(.zero, segment: index)
    }

    /// The Path control's two answers. Straight puts every stretch back on its
    /// line; Curved leaves a path that already curves alone and otherwise
    /// arcs every stretch up and over, as far as a quarter of its length,
    /// which is the mock's own arc and a place to drag from.
    public func shapingPath(_ shape: MotionPathShape) -> LayerMotion {
        let segments = pathSegments
        guard !segments.isEmpty, shape != pathShape else { return self }
        var shaped = self
        for (index, run) in segments.enumerated() {
            switch shape {
            case .straight:
                shaped = shaped.settingBend(.zero, segment: index)
            case .curved:
                shaped = shaped.settingBend(Self.upwardArc(for: run), segment: index)
            }
        }
        return shaped
    }

    /// Half the chord's length, square to it, on whichever side is up the
    /// screen: the control point of an arc whose top stands a quarter of the
    /// chord above the line.
    static func upwardArc(for run: MotionPathSegment) -> CGPoint {
        let dx = run.end.x - run.start.x
        let dy = run.end.y - run.start.y
        // Square to the chord, the same length as half of it.
        var across = CGPoint(x: dy / 2, y: -dx / 2)
        // Up is smaller y. A chord that runs straight up and down has no up
        // side, and bows to the left, which reads the same way round every
        // time.
        if across.y > 0 || (across.y == 0 && across.x > 0) {
            across = CGPoint(x: -across.x, y: -across.y)
        }
        return across
    }

    /// This motion with the bend of stretch `index` set, nil where it is
    /// straight so a straight path encodes exactly what it did before paths
    /// could bend.
    func settingBend(_ bend: CGPoint, segment index: Int) -> LayerMotion {
        var list = keyframes
        guard list.indices.contains(index), index < list.count - 1 else { return self }
        list[index].bend = MotionPathSegment(start: .zero, end: .zero, bend: bend).isCurved ? bend : nil
        return rebuilt(from: list)
    }

    /// Where the value is `progress` of the way (already eased) from `left`
    /// to `right`: along the bend when the stretch has one, and by the plain
    /// blend otherwise.
    func travelled(from left: MotionStop, to right: MotionStop, progress: Double) -> MotionValue? {
        if let bend = left.bend, case let .point(start) = left.value, case let .point(end) = right.value {
            let run = MotionPathSegment(start: start, end: end, bend: bend)
            if run.isCurved {
                // Overshoot (a back or an elastic curve) runs on past the key
                // along the arc's own parameter rather than stopping dead.
                if progress < 0 || progress > 1 { return .point(run.point(atParameter: progress)) }
                return .point(run.point(atFraction: progress))
            }
        }
        return left.value.blended(to: right.value, progress: progress)
    }

    /// The bends the two halves of a curved stretch need when a key lands
    /// part way along it at `ms` holding `value`, so the arc survives the new
    /// key. Nil when that stretch is straight or the moment is not inside one.
    func bendsSplitting(atMS ms: Int, value: MotionValue) -> (index: Int, left: CGPoint, right: CGPoint)? {
        guard property == .position, case let .point(middle) = value else { return nil }
        let list = keyframes
        guard list.count >= 2 else { return nil }
        for index in 0..<(list.count - 1) {
            let left = list[index]
            let right = list[index + 1]
            guard ms > left.atMS, ms < right.atMS else { continue }
            guard let bend = left.bend, case let .point(start) = left.value,
                  case let .point(end) = right.value else { return nil }
            let run = MotionPathSegment(start: start, end: end, bend: bend)
            guard run.isCurved else { return nil }
            let local = Double(ms - left.atMS) / Double(right.atMS - left.atMS)
            let eased = segmentCurve(leaving: left, arriving: right).value(at: local)
            let t = run.parameter(atFraction: eased)
            let (leftBend, rightBend) = run.split(atParameter: t, at: middle)
            return (index, leftBend, rightBend)
        }
        return nil
    }
}

// MARK: - The path on the canvas

/// A moving layer's path as the canvas draws it: through the middle of the
/// layer, in canvas points.
public struct MotionPathOnCanvas: Hashable, Sendable {
    public let layerID: UUID
    public let motionID: UUID
    public let segments: [MotionPathSegment]
    /// Where each key sits, first to last.
    public var keyPoints: [CGPoint] {
        guard let first = segments.first else { return [] }
        return [first.start] + segments.map(\.end)
    }
}

extension PhotonzDocument {

    /// How far a layer's value (its top-left corner, in whatever contains it)
    /// is from the point the canvas draws its path through: half its size,
    /// plus wherever its container puts it.
    private func motionPathOffset(of layer: Layer) -> CGPoint {
        let placed = canvasLayer(id: layer.id)?.frame.origin ?? layer.frame.origin
        let box = layer.frame.standardized
        return CGPoint(x: placed.x - layer.frame.origin.x + box.width / 2,
                       y: placed.y - layer.frame.origin.y + box.height / 2)
    }

    /// The path a moving layer travels, or nil where it does not move from one
    /// place to another.
    public func motionPath(layerID: UUID) -> MotionPathOnCanvas? {
        guard let layer = layer(id: layerID), let motion = layer.keyedMotion(.position),
              motion.isOn else { return nil }
        let segments = motion.pathSegments
        guard !segments.isEmpty else { return nil }
        let offset = motionPathOffset(of: layer)
        func shifted(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.x, y: p.y + offset.y) }
        return MotionPathOnCanvas(
            layerID: layerID, motionID: motion.id,
            segments: segments.map {
                MotionPathSegment(start: shifted($0.start), end: shifted($0.end), bend: $0.bend)
            })
    }

    /// Stretch `segment` of a layer's path bent so its middle passes through
    /// `point`, in canvas points: the handle let go there.
    public mutating func bendMotionPath(layerID: UUID, segment: Int, throughCanvasPoint point: CGPoint) {
        guard let layer = layer(id: layerID) else { return }
        let offset = motionPathOffset(of: layer)
        let local = CGPoint(x: point.x - offset.x, y: point.y - offset.y)
        updateMotionPath(layerID: layerID) { $0.bending(segment: segment, throughMiddle: local) }
    }

    /// A layer's path set Straight or Curved outright.
    public mutating func shapeMotionPath(layerID: UUID, _ shape: MotionPathShape) {
        updateMotionPath(layerID: layerID) { $0.shapingPath(shape) }
    }

    /// Stretch `segment` of a layer's path put back on its line.
    public mutating func straightenMotionPath(layerID: UUID, segment: Int) {
        updateMotionPath(layerID: layerID) { $0.straightening(segment: segment) }
    }

    private mutating func updateMotionPath(layerID: UUID, _ change: (LayerMotion) -> LayerMotion) {
        updateLayer(id: layerID) { layer in
            layer.motions = layer.motions?.map { $0.property == .position ? change($0) : $0 }
        }
    }
}
