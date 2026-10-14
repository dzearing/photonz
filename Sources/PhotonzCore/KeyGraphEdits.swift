import CoreGraphics
import Foundation

// The value graph takes points you add and segments you pick (task
// `the-value-graph-lets-you-add-points-pick-the-seg`,
// `docs/design/mocks/pages/video-animate.html`, THE GRAPH).
//
// A segment is the stretch between two keys, named by the key it starts at
// (`KeyRef`), so a pick survives keys being added elsewhere. Its curve is the
// stretch's own (`StretchCurve.swift`): the same answer the panel's Curve row
// gives for the stretch under the playhead.

extension PhotonzDocument {

    // MARK: - A point added on the line

    /// A key added on a keyed value's curve at a moment of the document,
    /// holding the value the curve has there. Part way along a stretch, the
    /// stretch's curve is cut in two at that moment (`EasingCurve.split`), so
    /// the line keeps its shape. Nil where a key already sits there or the
    /// value is not keyed on this layer.
    @discardableResult
    public mutating func addKeyOnCurve(layerID: UUID, motionID: UUID, atDocumentMS ms: Int) -> KeyRef? {
        guard let layer = layer(id: layerID),
              let motion = keyedMotions(of: layer).first(where: { $0.id == motionID }) else { return nil }
        let clock = max(0, clipKeyClock(layer, atDocumentMS: ms))
        let list = motion.keyframes
        guard motion.keyIndex(near: clock) == nil, let first = list.first, let last = list.last else { return nil }
        let value: MotionValue
        var cut: (index: Int, at: Double, curve: EasingCurve)?
        if clock <= first.atMS {
            value = first.value
        } else if clock >= last.atMS {
            value = last.value
        } else {
            let progress = Double(clock - motion.timing.startMS) / Double(max(1, motion.timing.durationMS))
            value = motion.value(atProgress: progress)
            if let index = motion.stretch(atMS: clock), let curve = motion.stretchCurve(index) {
                let span = Double(max(1, list[index + 1].atMS - list[index].atMS))
                cut = (index, Double(clock - list[index].atMS) / span, curve)
            }
        }
        var made = motion.settingKey(atMS: clock, value: value)
        if let cut {
            let (left, right) = cut.curve.split(at: cut.at)
            made = made.curvingStretch(cut.index, left).curvingStretch(cut.index + 1, right)
        }
        replaceMotions(layerID: layerID, [motion.id: made])
        return KeyRef(motionID: motion.id, clockMS: clock)
    }

    // MARK: - Picked segments

    /// The stretches these segments name on each motion of a layer: the
    /// indices of the keys they start at. The last key starts none.
    private func stretchStarts(_ segments: Set<KeyRef>, on layer: Layer) -> [(LayerMotion, [Int])] {
        keyedMotions(of: layer).compactMap { motion in
            let list = motion.keyframes
            let starts = list.indices.dropLast().filter {
                segments.contains(KeyRef(motionID: motion.id, clockMS: list[$0].atMS))
            }
            return starts.isEmpty ? nil : (motion, starts)
        }
    }

    /// Every picked segment runs on `curve`, and every other stretch as it
    /// was. One change. False where none of them is a segment.
    @discardableResult
    public mutating func curveStretches(layerID: UUID, _ segments: Set<KeyRef>, _ curve: EasingCurve) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        let hits = stretchStarts(segments, on: layer)
        guard !hits.isEmpty else { return false }
        var made: [UUID: LayerMotion?] = [:]
        for (motion, starts) in hits {
            made[motion.id] = starts.reduce(motion) { $0.curvingStretch($1, curve) }
        }
        replaceMotions(layerID: layerID, made)
        return true
    }

    /// What a curve chosen for points and segments picked together acts on:
    /// every picked segment, and for every picked point the segment it
    /// starts, the way the mock's key carries the curve leaving it
    /// (`video-animate.html`, Pick: the timeline bar's Easing "sets it for
    /// everything picked"). The last key starts none, so it counts as the
    /// segment arriving at it, and a choice never passes a point by; a value
    /// keyed only once has no segment at all.
    public func segmentsInHand(layerID: UUID, points: Set<KeyRef>, segments: Set<KeyRef>) -> Set<KeyRef> {
        guard let layer = layer(id: layerID) else { return segments }
        var inHand = segments
        for (motion, indices) in picked(points, on: layer) {
            let list = motion.keyframes
            guard list.count > 1 else { continue }
            for index in indices {
                let start = index + 1 < list.count ? index : index - 1
                inHand.insert(KeyRef(motionID: motion.id, clockMS: list[start].atMS))
            }
        }
        return inHand
    }

    /// The curve every picked segment runs on, where they agree; nil where
    /// they differ or none is a segment, so a menu ticks only what is true of
    /// every one.
    public func stretchesCurve(layerID: UUID, _ segments: Set<KeyRef>) -> EasingCurve? {
        guard let layer = layer(id: layerID) else { return nil }
        let curves = stretchStarts(segments, on: layer).flatMap { motion, starts in
            starts.map { motion.stretchCurve($0) }
        }
        guard let first = curves.first, let shared = first, curves.allSatisfy({ $0 == shared }) else { return nil }
        return shared
    }

    // MARK: - A point dragged

    /// One key carried `byMS` along the timeline and, for a value with a
    /// number, set to `value`: a point dragged on the graph, as one change. A
    /// move plots the distance travelled, so its point moves in time only.
    /// Returns where the key landed, nil where it could not move.
    @discardableResult
    public mutating func moveKeyOnGraph(layerID: UUID, _ ref: KeyRef, byMS delta: Int,
                                        toValue value: Double?) -> KeyRef? {
        var landed = ref
        if delta != 0 {
            let moved = moveKeys(layerID: layerID, [ref], byMS: delta, copying: false)
            guard moved.count == 1, let only = moved.first else { return nil }
            landed = only
        }
        guard let value, let layer = layer(id: layerID),
              let motion = keyedMotions(of: layer).first(where: { $0.id == ref.motionID }),
              let index = motion.keyframes.firstIndex(where: { $0.atMS == landed.clockMS }),
              case .number = motion.keyframes[index].value else { return landed }
        var list = motion.keyframes
        list[index].value = .number(motion.property.graphBounded(value))
        replaceMotions(layerID: layerID, [motion.id: motion.rebuilt(from: list)])
        return landed
    }
}

extension MotionProperty {
    /// A value dragged on the graph, kept to what the property can be: a
    /// percentage of opacity between nought and a hundred, a size or a
    /// distance never below nought, an angle anywhere.
    func graphBounded(_ value: Double) -> Double {
        switch self {
        case .opacity, .shadowOpacity, .glowOpacity:
            return min(max(value, 0), 100)
        case .rotation, .rotationX, .rotationY, .shadowDirection, .depth, .pivotDepth,
             .cameraX, .cameraY, .cameraDepth:
            return value
        default:
            return max(value, 0)
        }
    }
}
