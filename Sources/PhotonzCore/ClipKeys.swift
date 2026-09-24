import CoreGraphics
import Foundation

// Keys on a clip, and the title presets that write them
// (task `move-a-layer-from-a-to-b-grow-it-shrink-it-fade`,
// `docs/design/mocks/pages/video-move-wt.html`, `comp-video.html` `.kfm`).
//
// The panel's diamonds say WHAT is keyed (`PropertyKeys.swift`); the timeline
// says WHEN. A layer's clip carries one diamond for every moment something on
// it is keyed, whatever that something is, the way the mock draws its key
// marks. A hand drags that diamond in time, right-clicks it to ease it the way
// Premiere eases a key, and deletes it, and each acts on every key at that
// moment together, because that is what the one diamond stands for.
//
// A title preset is not a feature of its own: Animate In and Animate Out write
// ordinary keys at the clip's two ends, so what a preset made is draggable,
// easable and deletable exactly like a key made by hand.

/// One diamond on a clip: a moment of the document where something on the
/// layer is keyed.
public struct ClipKeyMark: Hashable, Sendable {
    /// Where it sits, in the document's clock.
    public let documentMS: Int
    /// What is keyed there, in the panel's order.
    public let properties: [MotionProperty]
}

// MARK: - The marks

extension PhotonzDocument {

    /// The keyed motions of a layer: every property somebody keyed, which in a
    /// document with time is every motion that plays once. A motion that loops
    /// is an icon's, and has no moments to draw.
    private func keyedMotions(of layer: Layer) -> [LayerMotion] {
        (layer.motions ?? []).filter { $0.repeats == .once && $0.isOn }
    }

    /// The moment of the document a key on a layer's own clock sits at, or nil
    /// where that part of the layer is not in the cut. Unlike the arrows'
    /// answer this keeps a key on the very last moment where it is, at the
    /// clip's right end, since that is where a fade out finishes.
    func clipKeyDocumentMS(_ layer: Layer, clock: Int) -> Int? {
        guard let time = layer.time else { return clock }
        if layer.cuts != nil { return layer.documentTimeMS(atMotionClockMS: clock) }
        let moment = time.inMS + clock - time.sourceInMS
        guard moment >= time.inMS - PropertyKeys.nearMS,
              moment <= time.outMS + PropertyKeys.nearMS else { return nil }
        return min(max(moment, time.inMS), time.outMS)
    }

    /// The layer's own clock at a moment of the document, the far end
    /// included (`motionClockMS` answers for the frames that play).
    func clipKeyClock(_ layer: Layer, atDocumentMS ms: Int) -> Int {
        guard let time = layer.time, layer.cuts == nil else {
            return layer.motionClockMS(atDocumentTimeMS: ms)
        }
        return max(0, ms - time.inMS + time.sourceInMS)
    }

    /// Every diamond on this layer's clip, first to last. Keys within
    /// `PropertyKeys.nearMS` of each other are one diamond.
    public func clipKeyMarks(layerID: UUID) -> [ClipKeyMark] {
        guard let layer = layer(id: layerID) else { return [] }
        var found: [(ms: Int, property: MotionProperty)] = []
        for motion in keyedMotions(of: layer) {
            for key in motion.keyframes {
                if let ms = clipKeyDocumentMS(layer, clock: key.atMS) { found.append((ms, motion.property)) }
            }
        }
        found.sort { $0.ms < $1.ms }
        let order = MotionProperty.allCases
        var marks: [ClipKeyMark] = []
        var group: [(ms: Int, property: MotionProperty)] = []
        func close() {
            guard let first = group.first else { return }
            let properties = Set(group.map(\.property)).sorted {
                (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0)
            }
            marks.append(ClipKeyMark(documentMS: first.ms, properties: properties))
            group = []
        }
        for item in found {
            if let first = group.first, item.ms - first.ms > PropertyKeys.nearMS { close() }
            group.append(item)
        }
        close()
        return marks
    }

    /// Which key of `motion` sits at a moment of the document, if one does.
    private func keyIndex(_ motion: LayerMotion, of layer: Layer, atDocumentMS ms: Int) -> Int? {
        let list = motion.keyframes
        let near = list.indices.filter { index in
            guard let at = clipKeyDocumentMS(layer, clock: list[index].atMS) else { return false }
            return abs(at - ms) <= PropertyKeys.nearMS
        }
        return near.first
    }

    /// Carry every key at `from` to `to`, keeping what each one says.
    ///
    /// The diamond stops short of the next key of anything it carries, either
    /// side, rather than jumping past it and turning one move into another,
    /// and it stays on the clip. False where nothing was keyed there.
    @discardableResult
    public mutating func moveClipKeys(layerID: UUID, fromMS from: Int, toMS to: Int) -> Bool {
        guard let layer = layer(id: layerID), let time = layer.time else { return false }
        let motions = keyedMotions(of: layer)
        var low = time.inMS
        var high = time.outMS
        var carried: [(UUID, Int)] = []
        for motion in motions {
            guard let index = keyIndex(motion, of: layer, atDocumentMS: from) else { continue }
            carried.append((motion.id, index))
            let list = motion.keyframes
            let gap = MotionStopDrag.shortestMS
            if index > 0, let before = clipKeyDocumentMS(layer, clock: list[index - 1].atMS) {
                low = max(low, before + gap)
            }
            if index < list.count - 1, let after = clipKeyDocumentMS(layer, clock: list[index + 1].atMS) {
                high = min(high, after - gap)
            }
        }
        guard !carried.isEmpty, low <= high else { return false }
        let landing = min(max(to, low), high)
        let clock = clipKeyClock(layer, atDocumentMS: landing)
        updateLayer(id: layerID) { edited in
            edited.motions = (edited.motions ?? []).map { motion in
                guard let hit = carried.first(where: { $0.0 == motion.id }) else { return motion }
                var list = motion.keyframes
                list[hit.1].atMS = clock
                return motion.rebuilt(from: list)
            }
        }
        return true
    }

    /// How the keys at a moment move, where they all agree; nil where they
    /// differ. A key nobody has eased reads as what its motion's curve does
    /// there, so the menu ticks what the picture is actually doing.
    public func clipKeyEase(layerID: UUID, atMS ms: Int) -> KeyEase? {
        guard let layer = layer(id: layerID) else { return nil }
        let eases = keyedMotions(of: layer).compactMap { motion -> KeyEase? in
            guard let index = keyIndex(motion, of: layer, atDocumentMS: ms) else { return nil }
            return motion.keyframes[index].ease ?? KeyEase(following: motion.curve)
        }
        guard let first = eases.first, eases.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Ease every key at a moment: a right click on the diamond.
    @discardableResult
    public mutating func easeClipKeys(layerID: UUID, atMS ms: Int, _ ease: KeyEase) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        var eased: [UUID: Int] = [:]
        for motion in keyedMotions(of: layer) {
            if let index = keyIndex(motion, of: layer, atDocumentMS: ms) { eased[motion.id] = index }
        }
        guard !eased.isEmpty else { return false }
        updateLayer(id: layerID) { edited in
            edited.motions = (edited.motions ?? []).map { motion in
                guard let index = eased[motion.id] else { return motion }
                return motion.easing(key: index, ease)
            }
        }
        return true
    }

    /// Delete every key at a moment. A value losing its last key stops being
    /// keyed and keeps the value it had there, as the panel's diamond does.
    @discardableResult
    public mutating func removeClipKeys(layerID: UUID, atMS ms: Int) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        let hits = keyedMotions(of: layer).compactMap { motion -> (LayerMotion, Int)? in
            keyIndex(motion, of: layer, atDocumentMS: ms).map { (motion, $0) }
        }
        guard !hits.isEmpty else { return false }
        for (motion, index) in hits {
            let list = motion.keyframes
            if list.count == 1 {
                // The value it held stays as the layer's own.
                let value = list[0].value
                updateLayer(id: layerID) { edited in
                    let kept = (edited.motions ?? []).filter { $0.id != motion.id }
                    edited.motions = kept.isEmpty ? nil : kept
                    edited.setKeyStill(motion.property, value)
                }
            } else {
                var rest = list
                rest.remove(at: index)
                let next = motion.rebuilt(from: rest)
                updateLayer(id: layerID) { edited in
                    edited.motions = (edited.motions ?? []).map { $0.id == motion.id ? next : $0 }
                }
            }
        }
        return true
    }
}

// MARK: - Title presets

/// How a title (or anything else placed in time) comes on, or goes off: the
/// four the right-click menu offers under Animate In and Animate Out.
public enum TitleAnimation: String, Hashable, Sendable, CaseIterable {
    case fade, slide, pop, scale

    public var title: String {
        switch self {
        case .fade: "Fade"
        case .slide: "Slide"
        case .pop: "Pop"
        case .scale: "Scale"
        }
    }

    /// How long one takes: half a second, or half the clip where the clip is
    /// shorter than a second, so an in and an out always both fit.
    public static let lengthMS = 500

    /// How small Pop and Scale start from, as a percentage. Not nought: a
    /// layer drawn at no size has no middle to grow about.
    static let smallestPercent: Double = 10
    /// How far Pop overshoots before it settles.
    static let overshootPercent: Double = 112
    /// How far past the frame's edge a slide starts or finishes, so not a
    /// sliver of it shows on the first or last frame.
    static let clearance: CGFloat = 40
}

extension PhotonzDocument {

    /// Animate In: keys at the start of a layer placed in time that bring it
    /// on. False for anything not placed in time.
    @discardableResult
    public mutating func animateIn(_ kind: TitleAnimation, layerID: UUID) -> Bool {
        writeTitleAnimation(kind, layerID: layerID, isIn: true)
    }

    /// Animate Out: keys at the end of a layer placed in time that take it off.
    @discardableResult
    public mutating func animateOut(_ kind: TitleAnimation, layerID: UUID) -> Bool {
        writeTitleAnimation(kind, layerID: layerID, isIn: false)
    }

    private mutating func writeTitleAnimation(_ kind: TitleAnimation, layerID: UUID, isIn: Bool) -> Bool {
        guard let layer = layer(id: layerID), layer.isPlacedInTime, let time = layer.time else { return false }
        let length = min(TitleAnimation.lengthMS, time.lengthMS / 2)
        guard length > 0 else { return false }
        // The layer's own end of the stretch (on screen) and the far end (off).
        let rest = isIn ? time.inMS + length : time.outMS - length
        let edge = isIn ? time.inMS : time.outMS
        let restClock = clipKeyClock(layer, atDocumentMS: rest)
        let edgeClock = clipKeyClock(layer, atDocumentMS: edge)
        // A rest key eases toward where it stays; the edge leaves quickly
        // (in) or arrives quickly (out), the way things fly on and off.
        let restEase: KeyEase = isIn ? .easeIn : .easeOut
        let edgeEase: KeyEase = .linear

        func key(_ property: MotionProperty, off: MotionValue,
                 through middle: (fraction: Double, value: MotionValue)? = nil) {
            guard let current = layer.keyStill(property) else { return }
            let resting = keyedValue(layerID: layerID, .motion(property), atDocumentTimeMS: rest) ?? current
            var list = layer.keyedMotion(property)?.keyframes ?? []
            // Nothing already keyed between the two ends survives: the preset
            // is the whole of how it comes on.
            let lowClock = min(restClock, edgeClock), highClock = max(restClock, edgeClock)
            list.removeAll { $0.atMS >= lowClock - PropertyKeys.nearMS && $0.atMS <= highClock + PropertyKeys.nearMS }
            list.append(MotionStop(atMS: restClock, value: resting, ease: restEase))
            list.append(MotionStop(atMS: edgeClock, value: off, ease: edgeEase))
            if let middle {
                let at = Double(edgeClock) + Double(restClock - edgeClock) * middle.fraction
                list.append(MotionStop(atMS: Int(at.rounded()), value: middle.value, ease: .easeInAndOut))
            }
            let base = layer.keyedMotion(property)
                ?? LayerMotion.keyed(property, atMS: restClock, value: resting)
            let made = base.rebuilt(from: list)
            updateLayer(id: layerID) { edited in
                var motions = (edited.motions ?? []).filter { $0.id != base.id }
                motions.append(made)
                edited.motions = motions
            }
        }

        let frame = layer.frame.standardized
        switch kind {
        case .fade:
            key(.opacity, off: .number(0))
        case .slide:
            let x = isIn ? -frame.width - TitleAnimation.clearance : canvasSize.width + TitleAnimation.clearance
            key(.position, off: .point(CGPoint(x: x, y: frame.origin.y)))
        case .pop:
            key(.scale, off: .number(TitleAnimation.smallestPercent),
                through: (0.65, .number(TitleAnimation.overshootPercent)))
            key(.opacity, off: .number(0))
        case .scale:
            key(.scale, off: .number(TitleAnimation.smallestPercent))
        }
        return true
    }
}
