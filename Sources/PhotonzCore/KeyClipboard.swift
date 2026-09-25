import CoreGraphics
import Foundation

// Keys copy between layers and the playhead lands on them
// (task `keys-copy-between-layers-and-the-playhead-lands`).
//
// Premiere's keyframe clipboard: pick keys on a layer's lanes, copy them, put
// the playhead somewhere (on this layer or another), paste. The earliest key
// lands at the playhead, the rest keep their spacing, and each lands on the
// value of the same name, so a title's fade and grow copy onto a second title
// in two keystrokes. A value the layer has not got (a text size on a box) is
// left out rather than refused, the way Premiere pastes what fits.
//
// The playhead's side of it: every key on the timeline is a moment the
// playhead is pulled onto when dragged near, and one it steps to from the
// keyboard.

/// Keys on the clipboard: what each one keys, how long after the earliest it
/// sits, what it holds and how it eases.
public struct CopiedKeys: Hashable, Codable, Sendable {
    public struct Key: Hashable, Codable, Sendable {
        public var property: MotionProperty
        /// How long after the earliest copied key this one sits, in the
        /// document's clock, so the spacing survives a paste anywhere.
        public var offsetMS: Int
        public var value: MotionValue
        /// How it eases: the ease somebody chose, or what its motion's curve
        /// did there, so a pasted key moves the way the copied one did.
        public var ease: KeyEase
        /// A Bezier key's handles.
        public var handles: KeyHandles?
        /// How the path bends on its way to the next COPIED key of the same
        /// move (`MotionStop.bend`). Nil on the last one: its next key is
        /// whatever the paste lands before, which the arc was never drawn to.
        public var bend: CGPoint?

        public init(property: MotionProperty, offsetMS: Int, value: MotionValue,
                    ease: KeyEase, handles: KeyHandles? = nil, bend: CGPoint? = nil) {
            self.property = property
            self.offsetMS = offsetMS
            self.value = value
            self.ease = ease
            self.handles = handles
            self.bend = bend
        }
    }

    public var keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    /// The pasteboard type the app writes these under, so copying anything
    /// else in any app replaces them the way a clipboard should.
    public static let pasteboardType = "com.dzearing.photonz.keys"

    /// The values these keys key, in the panel's order.
    public var properties: [MotionProperty] {
        var seen: [MotionProperty] = []
        for key in keys where !seen.contains(key.property) { seen.append(key.property) }
        return seen.sorted { PhotonzDocument.laneRank($0) < PhotonzDocument.laneRank($1) }
    }
}

/// Where a dragged playhead lands: on a key, where it is dragged near enough.
public enum KeySnap {
    /// `ms` pulled onto the nearest of `moments` within `reach`, or left alone.
    public static func snapped(_ ms: Int, to moments: [Int], withinMS reach: Int) -> Int {
        var best: (distance: Int, moment: Int)?
        for moment in moments {
            let distance = abs(moment - ms)
            guard distance <= reach, distance < (best?.distance ?? Int.max) else { continue }
            best = (distance, moment)
        }
        return best?.moment ?? ms
    }
}

extension PhotonzDocument {

    // MARK: - Copying

    /// The picked keys of a layer, ready for the clipboard. Nil where none of
    /// them is on the clip.
    public func copyKeys(layerID: UUID, _ refs: Set<KeyRef>) -> CopiedKeys? {
        guard let layer = layer(id: layerID) else { return nil }
        var found: [(property: MotionProperty, ms: Int, stop: MotionStop, ease: KeyEase)] = []
        for (motion, indices) in picked(refs, on: layer) {
            let fallback = KeyEase(following: motion.curve)
            for index in indices {
                let stop = motion.keyframes[index]
                guard let at = clipKeyDocumentMS(layer, clock: stop.atMS) else { continue }
                found.append((motion.property, at, stop, stop.ease ?? fallback))
            }
        }
        guard let earliest = found.map(\.ms).min() else { return nil }
        let lastOfEach = Dictionary(found.map { ($0.property, $0.ms) }, uniquingKeysWith: max)
        let keys = found.map { item in
            CopiedKeys.Key(property: item.property, offsetMS: item.ms - earliest, value: item.stop.value,
                           ease: item.ease, handles: item.ease == .bezier ? item.stop.handles : nil,
                           bend: lastOfEach[item.property] == item.ms ? nil : item.stop.bend)
        }
        .sorted {
            ($0.property == $1.property) ? $0.offsetMS < $1.offsetMS
                : Self.laneRank($0.property) < Self.laneRank($1.property)
        }
        return CopiedKeys(keys: keys)
    }

    // MARK: - Pasting

    /// The values of the copied keys this layer has, in the panel's order.
    private func pastableProperties(_ copied: CopiedKeys, on layer: Layer) -> [MotionProperty] {
        copied.properties.filter { layer.keyableProperties.contains(.motion($0)) }
    }

    /// Whether any of the copied keys would land on this layer.
    public func canPasteKeys(_ copied: CopiedKeys, layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID) else { return false }
        return !pastableProperties(copied, on: layer).isEmpty
    }

    /// Paste keys with the earliest at `ms`, each on the value of the same
    /// name. A pasted key landing on one already there takes its place, the
    /// way Premiere overwrites. Returns the keys that landed, which is what
    /// the lanes pick afterwards.
    @discardableResult
    public mutating func pasteKeys(_ copied: CopiedKeys, layerID: UUID, atDocumentMS ms: Int) -> Set<KeyRef> {
        guard let layer = layer(id: layerID) else { return [] }
        var landed = Set<KeyRef>()
        var made: [LayerMotion] = []
        for property in pastableProperties(copied, on: layer) {
            let incoming = copied.keys.filter { $0.property == property }
            guard let first = incoming.first else { continue }
            let existing = keyedMotions(of: layer).first { $0.property == property }
            let firstClock = clipKeyClock(layer, atDocumentMS: ms + first.offsetMS)
            let base = existing ?? .keyed(property, atMS: firstClock, value: first.value)
            var list = existing?.keyframes ?? []
            for key in incoming {
                let clock = clipKeyClock(layer, atDocumentMS: ms + key.offsetMS)
                list.removeAll { abs($0.atMS - clock) <= PropertyKeys.nearMS }
                list.append(MotionStop(atMS: clock, value: key.value, ease: key.ease, handles: key.handles,
                                       bend: key.bend))
                landed.insert(KeyRef(motionID: base.id, clockMS: clock))
            }
            made.append(base.rebuilt(from: list))
        }
        guard !made.isEmpty else { return [] }
        updateLayer(id: layerID) { edited in
            var motions = edited.motions ?? []
            for motion in made {
                if let index = motions.firstIndex(where: { $0.id == motion.id }) {
                    motions[index] = motion
                } else {
                    motions.append(motion)
                }
            }
            edited.motions = motions
        }
        return landed
    }

    // MARK: - The playhead on keys

    /// Every moment of the document a key sits at on these layers (every
    /// layer where nil): each keyed value's keys and each volume point, first
    /// to last, one moment for keys that share it. The same moments the
    /// panel's arrows step to.
    public func keyMoments(layerIDs: [UUID]?) -> [Int] {
        let shown = layerIDs.map { ids in ids.compactMap { layer(id: $0) } } ?? layers
        var moments = Set<Int>()
        for layer in shown {
            for motion in keyedMotions(of: layer) {
                for key in motion.keyframes {
                    if let at = layer.documentTimeMS(atMotionClockMS: key.atMS) { moments.insert(at) }
                }
            }
            for point in layer.soundLevel?.points ?? [] {
                moments.insert(point.atMS + (layer.time?.inMS ?? 0))
            }
        }
        return moments.sorted()
    }

    /// The key moment after (or before) `ms` on these layers, or nil where
    /// there is none that way. A key the playhead is already on is not the
    /// next one.
    public func neighbourKeyMoment(layerIDs: [UUID]?, from ms: Int, forward: Bool) -> Int? {
        let moments = keyMoments(layerIDs: layerIDs)
        if forward { return moments.first { $0 > ms + PropertyKeys.nearMS } }
        return moments.last { $0 < ms - PropertyKeys.nearMS }
    }
}
