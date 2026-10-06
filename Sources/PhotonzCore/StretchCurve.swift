import CoreGraphics
import Foundation

// Between the keys (task `a-moving-layer-shows-between-the-keys-in-propert`,
// `docs/design/mocks/pages/video-move-wt.html` step 6).
//
// Keys ease one key at a time, Premiere's way (`KeyEase`), so a stretch runs on
// what the key it leaves and the key it arrives at say. The Curve dropdown in
// Properties asks the same question the other way round, about the stretch the
// playhead is in, with the one list of eight curve names every page with timing
// uses (`EasingCurve.named`).
//
// **One answer, two ways to give it.** Linear, Ease in, Ease out and Ease in
// out are exactly what a pair of keys can say, so choosing one of them writes
// the two keys' eases, and the timeline's Easing and a key's right-click read
// the change without a second model to keep in step. The shaped four (sine,
// back, elastic, steps) are shapes no pair of keys makes, so they ride the
// stretch itself (`MotionStop.curve`), and a per-key ease chosen afterwards on
// either end takes the stretch back (`LayerMotion.easing(key:_:)`).

public enum StretchCurve {
    /// The four a pair of keys can say, and the halves each asks of them:
    /// a slow start is the key it leaves easing out, a slow end the key it
    /// arrives at easing in.
    static func halves(_ curve: EasingCurve) -> (leavingEases: Bool, arrivingEases: Bool)? {
        switch curve {
        case .linear: (false, false)
        case .easeIn: (true, false)
        case .easeOut: (false, true)
        case .easeInOut: (true, true)
        default: nil
        }
    }

    /// What the Curve dropdown calls a stretch: the curve's own name, Hold for
    /// a held key, and Custom for one drawn on the graph.
    public static func title(_ curve: EasingCurve) -> String {
        switch curve {
        case .steps(1): "Hold"
        case .custom: "Custom"
        default: curve.title
        }
    }
}

extension LayerMotion {

    /// The stretch (between `keyframes[i]` and `keyframes[i + 1]`) a moment of
    /// the layer's own clock is in. A key starts the stretch after it, the last
    /// key ends the last one, and a moment outside the keys takes the nearest.
    /// Nil with fewer than two keys, where there is nothing between.
    public func stretch(atMS ms: Int) -> Int? {
        let list = keyframes
        guard list.count > 1 else { return nil }
        let after = list.firstIndex { $0.atMS > ms } ?? list.count
        return min(max(after - 1, 0), list.count - 2)
    }

    /// The curve stretch `index` runs on, as the Curve dropdown names it. A
    /// pair of Bezier keys whose handles sit where one of the four puts them
    /// reads as that one, so turning a key Bezier renames nothing.
    public func stretchCurve(_ index: Int) -> EasingCurve? {
        let list = keyframes
        guard index >= 0, index + 1 < list.count else { return nil }
        let curve = segmentCurve(leaving: list[index], arriving: list[index + 1])
        guard case let .custom(x1, y1, x2, y2) = curve else { return curve }
        let named: [EasingCurve] = [.linear, .easeIn, .easeOut, .easeInOut]
        return named.first { candidate in
            guard let halves = StretchCurve.halves(candidate) else { return false }
            let a = KeyHandles.implied(by: KeyEase(easesIn: false, easesOut: halves.leavingEases)).leaving
            let b = KeyHandles.implied(by: KeyEase(easesIn: halves.arrivingEases, easesOut: false)).arriving
            return Self.close(x1, a.x) && Self.close(y1, a.y) && Self.close(x2, b.x) && Self.close(y2, b.y)
        } ?? curve
    }

    private static func close(_ a: Double, _ b: CGFloat) -> Bool { abs(a - Double(b)) < 0.001 }

    /// This motion with stretch `index` running on `curve`, and every other
    /// stretch exactly as it was.
    public func curvingStretch(_ index: Int, _ curve: EasingCurve) -> LayerMotion {
        var list = keyframes
        guard index >= 0, index + 1 < list.count else { return self }
        let before = list.indices.dropLast().map { stretchCurve($0) }
        var made: LayerMotion
        if case let .custom(x1, y1, x2, y2) = curve {
            // One drawn by hand is the two keys' own handles, so the graph
            // shows it and a key's right-click reads Bezier.
            made = settingHandle(key: index, .leaving, to: CGPoint(x: x1, y: y1))
                .settingHandle(key: index + 1, .arriving, to: CGPoint(x: x2, y: y2))
        } else if let halves = StretchCurve.halves(curve) {
            let fallback = KeyEase(following: self.curve)
            list[index].curve = nil
            list[index] = Self.leaving(list[index], eases: halves.leavingEases,
                                       isFirst: index == 0, fallback: fallback)
            list[index + 1] = Self.arriving(list[index + 1], eases: halves.arrivingEases,
                                            isLast: index + 1 == list.count - 1, fallback: fallback)
            made = rebuilt(from: list)
        } else {
            list[index].curve = curve
            made = rebuilt(from: list)
        }
        // What the keys cannot say (a held key it arrives at cannot ease in
        // without losing its hold, a handle is kept inside its stretch in
        // time), and any neighbour that was only following
        // the motion's curve because neither of its keys had been eased, are
        // pinned where they were meant to be.
        var pinned = made.keyframes
        var changed = false
        for stretch in pinned.indices.dropLast() {
            let wanted = stretch == index ? curve : before[stretch]
            if let wanted, made.stretchCurve(stretch) != wanted {
                pinned[stretch].curve = wanted
                changed = true
            }
        }
        if changed { made = made.rebuilt(from: pinned) }
        return made
    }

    /// A key given how the stretch LEAVING it should start. A Bezier key keeps
    /// its handles and moves that one; the first key has no stretch arriving,
    /// so its unseen half follows the one that shows.
    private static func leaving(_ key: MotionStop, eases: Bool, isFirst: Bool,
                                fallback: KeyEase) -> MotionStop {
        var key = key
        let now = key.ease ?? fallback
        if now == .bezier, var handles = key.handles {
            handles.leaving = KeyHandles.implied(by: KeyEase(easesIn: false, easesOut: eases)).leaving
            key.handles = handles
            return key
        }
        key.handles = nil
        key.ease = KeyEase(easesIn: isFirst ? eases : now.easesIn, easesOut: eases)
        return key
    }

    /// A key given how the stretch ARRIVING at it should end. A held key keeps
    /// its hold, which is about the stretch after it.
    private static func arriving(_ key: MotionStop, eases: Bool, isLast: Bool,
                                 fallback: KeyEase) -> MotionStop {
        var key = key
        let now = key.ease ?? fallback
        if now == .bezier, var handles = key.handles {
            handles.arriving = KeyHandles.implied(by: KeyEase(easesIn: eases, easesOut: false)).arriving
            key.handles = handles
            return key
        }
        if now == .hold, !isLast { return key }
        key.handles = nil
        key.ease = KeyEase(easesIn: eases, easesOut: isLast ? eases : now.easesOut)
        return key
    }
}

extension PhotonzDocument {

    /// The curve of the stretch the playhead is in, on one keyed value of a
    /// layer. Nil where that value has fewer than two keys.
    public func stretchCurve(layerID: UUID, _ property: MotionProperty, effect: Int = 0,
                             atDocumentTimeMS ms: Int) -> EasingCurve? {
        guard let layer = layer(id: layerID), let motion = layer.keyedMotion(property, effect: effect),
              let stretch = motion.stretch(atMS: layer.motionClockMS(atDocumentTimeMS: ms)) else { return nil }
        return motion.stretchCurve(stretch)
    }

    /// The Curve dropdown: the stretch the playhead is in runs on `curve`.
    public mutating func curveStretch(layerID: UUID, _ property: MotionProperty, effect: Int = 0,
                                      atDocumentTimeMS ms: Int, _ curve: EasingCurve) {
        guard let layer = layer(id: layerID), let motion = layer.keyedMotion(property, effect: effect),
              let stretch = motion.stretch(atMS: layer.motionClockMS(atDocumentTimeMS: ms)) else { return }
        let made = motion.curvingStretch(stretch, curve)
        updateLayer(id: layerID) { edited in
            edited.motions = edited.motions?.map { $0.id == made.id ? made : $0 }
        }
    }
}
