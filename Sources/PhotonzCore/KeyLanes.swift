import CoreGraphics
import Foundation

// A layer's track opens into one lane per keyed value
// (task `a-layer-s-track-opens-into-one-lane-per-keyed-va`,
// `docs/design/mocks/pages/video-move-wt.html` `.kfl`/`.kfd`/`.kfseg`,
// `video.html` THE GRAPH).
//
// The clip carries one diamond per MOMENT (`ClipKeys.swift`); open its track
// and every keyed value gets a lane of its own, one diamond per key. Those are
// the keys a hand picks, drags, copies with Option, deletes and eases one at a
// time or many together, and a lane opens into the curve the value runs on,
// where a Bezier key's handles are dragged.
//
// A key is named by its motion and the moment on the layer's own clock
// (`KeyRef`), never by its place in a list: a drag re-sorts the list, and a
// selection that pointed at "the second key" would quietly change which key
// it means.

/// One key, as a selection holds it.
public struct KeyRef: Hashable, Sendable {
    public let motionID: UUID
    /// Where it sits on the layer's own clock (`MotionStop.atMS`).
    public let clockMS: Int

    public init(motionID: UUID, clockMS: Int) {
        self.motionID = motionID
        self.clockMS = clockMS
    }
}

/// One diamond on a lane.
public struct LaneKey: Hashable, Sendable {
    public let ref: KeyRef
    /// Where it is drawn, in the document's clock.
    public let documentMS: Int
    /// How the value moves through it: what somebody chose, or what its
    /// motion's curve does there where nobody has.
    public let ease: KeyEase
    /// The value, in the panel's words ("200%").
    public let reading: String
}

/// One keyed value of a layer: a row under its track.
public struct KeyLane: Identifiable, Hashable, Sendable {
    public let motionID: UUID
    public let property: MotionProperty
    public let keys: [LaneKey]

    public var id: UUID { motionID }
    public var title: String { property.title }
}

/// A lane opened into its curve: the value over time, on the timeline's own
/// clock, with every key and its handles where they sit on that curve.
public struct KeyGraph: Hashable, Sendable {
    public let motionID: UUID
    public let property: MotionProperty
    /// The curve, first to last: `x` is the document's clock, `y` the value.
    public let points: [CGPoint]
    public let keys: [KeyGraphKey]
    /// The lowest and highest the value goes, overshoot included.
    public let low: Double
    public let high: Double
}

/// One key on a curve, with its handles in the curve's own space.
public struct KeyGraphKey: Hashable, Sendable {
    public let ref: KeyRef
    public let documentMS: Int
    public let value: Double
    public let ease: KeyEase
    /// The handle shaping the stretch that arrives here, nil on the first key
    /// and after a held key.
    public let arriving: CGPoint?
    /// The handle shaping the stretch that leaves, nil on the last key and on
    /// a held one.
    public let leaving: CGPoint?
}

extension PhotonzDocument {

    /// The order the panel lists values in, which the lanes keep.
    private static let laneOrder: [MotionProperty] = [.position, .scale, .rotation, .opacity, .cornerRadius,
                                                      .strokeWidth, .color, .blur, .shadow, .textSize]

    static func laneRank(_ property: MotionProperty) -> Int {
        laneOrder.firstIndex(of: property) ?? laneOrder.count
    }

    /// The keyed values of a layer, in the panel's order.
    func laneMotions(of layer: Layer) -> [LayerMotion] {
        keyedMotions(of: layer).sorted { Self.laneRank($0.property) < Self.laneRank($1.property) }
    }

    /// Whether a layer has any value keyed, which is what earns its track the
    /// arrow that opens it.
    /// Whether any of these layers has a lane of keys: a track's arrow asks
    /// for every clip on it, and a Captions track has 170. One pass over the
    /// document rather than a search per clip.
    public func hasKeyLanes(anyOf ids: Set<UUID>) -> Bool {
        var found = false
        forEachLayer { layer in
            guard !found, ids.contains(layer.id) else { return }
            found = !keyedMotions(of: layer).isEmpty
        }
        return found
    }

    public func hasKeyLanes(layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        return !keyedMotions(of: layer).isEmpty
    }

    /// One lane per keyed value of a layer, each with every key on it that
    /// sits on the clip.
    public func keyLanes(layerID: UUID) -> [KeyLane] {
        guard let layer = layer(id: layerID) else { return [] }
        return laneMotions(of: layer).map { motion in
            let fallback = KeyEase(following: motion.curve)
            let keys = motion.keyframes.compactMap { key -> LaneKey? in
                guard let at = clipKeyDocumentMS(layer, clock: key.atMS) else { return nil }
                return LaneKey(ref: KeyRef(motionID: motion.id, clockMS: key.atMS), documentMS: at,
                               ease: key.ease ?? fallback, reading: motion.property.format(key.value))
            }
            return KeyLane(motionID: motion.id, property: motion.property, keys: keys)
        }
    }

    /// The indices of the picked keys on each motion of a layer.
    func picked(_ refs: Set<KeyRef>, on layer: Layer) -> [(LayerMotion, [Int])] {
        laneMotions(of: layer).compactMap { motion in
            let indices = motion.keyframes.indices.filter {
                refs.contains(KeyRef(motionID: motion.id, clockMS: motion.keyframes[$0].atMS))
            }
            return indices.isEmpty ? nil : (motion, indices)
        }
    }

    private mutating func replaceMotions(layerID: UUID, _ made: [UUID: LayerMotion?],
                                         stills: [(MotionProperty, MotionValue)] = []) {
        updateLayer(id: layerID) { edited in
            let kept = (edited.motions ?? []).compactMap { motion -> LayerMotion? in
                guard let replacement = made[motion.id] else { return motion }
                return replacement
            }
            edited.motions = kept.isEmpty ? nil : kept
            for (property, value) in stills { edited.setKeyStill(property, value) }
        }
    }

    // MARK: - Moving

    /// Carry the picked keys `byMS` along the timeline, all together, or leave
    /// them and carry copies (Option held). Returns the keys that moved, or
    /// the copies, which is what the selection holds afterwards.
    ///
    /// The picked keys keep their spacing and stay on the clip: a drag past
    /// either end stops with the outermost key on it. A key landing on one
    /// that stayed put takes its place, the way Premiere overwrites.
    @discardableResult
    public mutating func moveKeys(layerID: UUID, _ refs: Set<KeyRef>, byMS delta: Int,
                                  copying: Bool) -> Set<KeyRef> {
        guard let layer = layer(id: layerID) else { return refs }
        let hits = picked(refs, on: layer)
        guard !hits.isEmpty else { return refs }
        var low = Int.min
        var high = Int.max
        for (motion, indices) in hits {
            for index in indices {
                let clock = motion.keyframes[index].atMS
                guard let at = clipKeyDocumentMS(layer, clock: clock) else { continue }
                if let time = layer.time {
                    low = max(low, time.inMS - at)
                    high = min(high, time.outMS - at)
                } else {
                    low = max(low, -clock)
                }
            }
        }
        guard low <= high else { return refs }
        let shift = min(max(delta, low), high)
        guard abs(shift) > (copying ? PropertyKeys.nearMS : 0) else { return refs }

        var made: [UUID: LayerMotion?] = [:]
        var landed = Set<KeyRef>()
        for (motion, indices) in hits {
            var list = motion.keyframes
            let carried = indices.compactMap { index -> MotionStop? in
                var key = list[index]
                guard let at = clipKeyDocumentMS(layer, clock: key.atMS) else { return nil }
                key.atMS = clipKeyClock(layer, atDocumentMS: at + shift)
                return key
            }
            if !copying {
                for index in indices.sorted(by: >) { list.remove(at: index) }
            }
            list.removeAll { stayed in
                carried.contains { abs($0.atMS - stayed.atMS) <= PropertyKeys.nearMS }
            }
            list.append(contentsOf: carried)
            made[motion.id] = motion.rebuilt(from: list)
            for key in carried { landed.insert(KeyRef(motionID: motion.id, clockMS: key.atMS)) }
        }
        replaceMotions(layerID: layerID, made)
        return landed
    }

    // MARK: - Deleting and easing

    /// Delete the picked keys. A value losing its last key stops being keyed
    /// and keeps the value its first deleted key held.
    @discardableResult
    public mutating func removeKeys(layerID: UUID, _ refs: Set<KeyRef>) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        let hits = picked(refs, on: layer)
        guard !hits.isEmpty else { return false }
        var made: [UUID: LayerMotion?] = [:]
        var stills: [(MotionProperty, MotionValue)] = []
        for (motion, indices) in hits {
            var list = motion.keyframes
            let first = list[indices[0]].value
            for index in indices.sorted(by: >) { list.remove(at: index) }
            if list.isEmpty {
                made[motion.id] = .some(nil)
                stills.append((motion.property, first))
            } else {
                made[motion.id] = motion.rebuilt(from: list)
            }
        }
        replaceMotions(layerID: layerID, made, stills: stills)
        return true
    }

    /// Ease every picked key the same way: a right click on one of them.
    @discardableResult
    public mutating func easeKeys(layerID: UUID, _ refs: Set<KeyRef>, _ ease: KeyEase) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        let hits = picked(refs, on: layer)
        guard !hits.isEmpty else { return false }
        var made: [UUID: LayerMotion?] = [:]
        for (motion, indices) in hits {
            made[motion.id] = indices.reduce(motion) { $0.easing(key: $1, ease) }
        }
        replaceMotions(layerID: layerID, made)
        return true
    }

    /// How the picked keys move, where they all agree; nil where they differ,
    /// so a menu ticks only what is true of every one.
    public func keysEase(layerID: UUID, _ refs: Set<KeyRef>) -> KeyEase? {
        guard let layer = layer(id: layerID) else { return nil }
        let eases = picked(refs, on: layer).flatMap { motion, indices in
            indices.map { motion.keyframes[$0].ease ?? KeyEase(following: motion.curve) }
        }
        guard let first = eases.first, eases.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    // MARK: - The curve

    /// The height each key of a motion sits at on its curve: the number
    /// itself, or for a position the distance travelled along the path so
    /// far, so one curve still says how the move eases. Nil for a colour,
    /// which has no axis to plot on.
    private func graphHeights(_ motion: LayerMotion) -> [Double]? {
        var heights: [Double] = []
        var travelled = 0.0
        var last: CGPoint?
        for key in motion.keyframes {
            switch key.value {
            case let .number(number):
                heights.append(number)
            case let .point(point):
                if let last { travelled += Double(hypot(point.x - last.x, point.y - last.y)) }
                last = point
                heights.append(travelled)
            case .color:
                return nil
            }
        }
        return heights
    }

    /// How finely a stretch between two keys is sampled. Past the point the
    /// difference can be seen at a lane's height.
    static let graphSamples = 24

    /// A keyed value's curve on the timeline's clock, or nil where it has no
    /// numeric axis (a colour) or is not keyed on this layer.
    public func keyGraph(layerID: UUID, motionID: UUID) -> KeyGraph? {
        guard let layer = layer(id: layerID),
              let motion = keyedMotions(of: layer).first(where: { $0.id == motionID }),
              let heights = graphHeights(motion) else { return nil }
        let keys = motion.keyframes
        let times = keys.map { clipKeyDocumentMS(layer, clock: $0.atMS) }
        guard !keys.isEmpty, times.allSatisfy({ $0 != nil }) else { return nil }
        let at = times.map { $0 ?? 0 }
        let fallback = KeyEase(following: motion.curve)

        var points: [CGPoint] = []
        let start = layer.time?.inMS ?? min(0, at[0])
        let end = layer.time?.outMS ?? max(durationMS ?? 0, at[at.count - 1])
        if start < at[0] { points.append(CGPoint(x: Double(start), y: heights[0])) }
        points.append(CGPoint(x: Double(at[0]), y: heights[0]))
        var graphKeys: [KeyGraphKey] = []
        for index in keys.indices {
            let key = keys[index]
            let ease = key.ease ?? fallback
            var arriving: CGPoint?
            var leaving: CGPoint?
            if index > 0, (keys[index - 1].ease ?? fallback) != .hold {
                let handle = key.arrivingHandle(fallback)
                arriving = Self.graphPoint(handle, from: (at[index - 1], heights[index - 1]),
                                           to: (at[index], heights[index]))
            }
            if index < keys.count - 1 {
                let next = keys[index + 1]
                if ease != .hold {
                    let handle = key.leavingHandle(fallback)
                    leaving = Self.graphPoint(handle, from: (at[index], heights[index]),
                                              to: (at[index + 1], heights[index + 1]))
                    let curve = motion.segmentCurve(leaving: key, arriving: next)
                    for step in 1...Self.graphSamples {
                        let u = Double(step) / Double(Self.graphSamples)
                        let x = Double(at[index]) + u * Double(at[index + 1] - at[index])
                        let y = heights[index] + curve.value(at: u) * (heights[index + 1] - heights[index])
                        points.append(CGPoint(x: x, y: y))
                    }
                } else {
                    points.append(CGPoint(x: Double(at[index + 1]), y: heights[index]))
                    points.append(CGPoint(x: Double(at[index + 1]), y: heights[index + 1]))
                }
            }
            graphKeys.append(KeyGraphKey(ref: KeyRef(motionID: motion.id, clockMS: key.atMS),
                                         documentMS: at[index], value: heights[index], ease: ease,
                                         arriving: arriving, leaving: leaving))
        }
        if end > at[at.count - 1] {
            points.append(CGPoint(x: Double(end), y: heights[heights.count - 1]))
        }
        // The range is the keys' own, widened only where the curve really
        // overshoots them, so a plain move reads exactly its two values.
        var low = heights.min() ?? 0
        var high = heights.max() ?? 0
        for point in points {
            let y = Double(point.y)
            if y < low - 1e-6 { low = y }
            if y > high + 1e-6 { high = y }
        }
        return KeyGraph(motionID: motion.id, property: motion.property, points: points,
                        keys: graphKeys, low: low, high: high)
    }

    /// A handle, from its stretch's unit square into the curve's space.
    private static func graphPoint(_ handle: CGPoint, from a: (Int, Double), to b: (Int, Double)) -> CGPoint {
        CGPoint(x: Double(a.0) + Double(handle.x) * Double(b.0 - a.0),
                y: a.1 + Double(handle.y) * (b.1 - a.1))
    }

    /// Drag one of a key's handles to a point on its curve (the document's
    /// clock across, the value up). The key becomes a Bezier key. False where
    /// that key has no stretch on that side to shape.
    @discardableResult
    public mutating func setKeyHandle(layerID: UUID, _ ref: KeyRef, _ side: KeyHandleSide,
                                      toGraphPoint point: CGPoint) -> Bool {
        guard let layer = layer(id: layerID),
              let motion = keyedMotions(of: layer).first(where: { $0.id == ref.motionID }),
              let heights = graphHeights(motion) else { return false }
        let keys = motion.keyframes
        guard let index = keys.firstIndex(where: { $0.atMS == ref.clockMS }) else { return false }
        let other = side == .leaving ? index + 1 : index - 1
        guard keys.indices.contains(other),
              let here = clipKeyDocumentMS(layer, clock: keys[index].atMS),
              let there = clipKeyDocumentMS(layer, clock: keys[other].atMS) else { return false }
        let (a, b) = side == .leaving ? ((here, heights[index]), (there, heights[other]))
                                      : ((there, heights[other]), (here, heights[index]))
        guard b.0 != a.0 else { return false }
        let fallback = KeyEase(following: motion.curve)
        let now = side == .leaving ? keys[index].leavingHandle(fallback) : keys[index].arrivingHandle(fallback)
        let x = (Double(point.x) - Double(a.0)) / Double(b.0 - a.0)
        let rise = b.1 - a.1
        // A stretch that does not change has no height to drag the handle
        // along, so it keeps the one it had.
        let y = abs(rise) > 1e-9 ? (Double(point.y) - a.1) / rise : Double(now.y)
        let shaped = motion.settingHandle(key: index, side, to: CGPoint(x: x, y: y))
        replaceMotions(layerID: layerID, [motion.id: shaped])
        return true
    }
}
