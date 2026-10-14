import CoreGraphics
import Foundation

// MARK: - The camera's keys on a thin row at the top of the timeline
//
// `docs/design/mocks/pages/video-depth.html`, "Camera A · a setting of the
// frame": "Keyed camera moves show on a thin row at the top of the timeline."
// The camera is a setting of the frame, not a layer, so it has no track of its
// own; once any of its values is keyed, the row appears and holds its keys.
//
// A diamond is one MOMENT, the way a clip's bar draws its keys
// (`ClipKeys.swift`): a push in that also drifts keys Camera depth and Camera
// X at the same two moments, and that reads as two diamonds, not four.
// Dragging or deleting a diamond carries every camera key at that moment.

/// One diamond on the Camera row.
public struct CameraKeyMoment: Hashable, Sendable {
    /// Where it sits, on the document's own clock.
    public let ms: Int
    /// The camera values keyed here, in the panel's order.
    public let properties: [MotionProperty]
    /// What they hold here, in the panel's words ("Camera depth 400 pt").
    public let reading: String
    /// How they move through here, where every key at the moment agrees;
    /// nil where they differ.
    public let ease: KeyEase?
}

extension PhotonzDocument {

    /// Whether any camera value is keyed: what earns the timeline its Camera
    /// row.
    public var hasCameraKeys: Bool {
        camera?.motions?.contains { $0.property.isCamera && !$0.keyframes.isEmpty } ?? false
    }

    /// The Camera row's diamonds, first to last. Keys on different values
    /// within `PropertyKeys.nearMS` of each other are one diamond.
    public var cameraKeyMoments: [CameraKeyMoment] {
        guard let motions = camera?.motions else { return [] }
        let order = MotionProperty.cameraProperties
        let keys = motions.filter(\.property.isCamera).flatMap { motion in
            motion.keyframes.map { (ms: $0.atMS, property: motion.property, value: $0.value) }
        }.sorted { $0.ms < $1.ms }
        var groups: [[(ms: Int, property: MotionProperty, value: MotionValue)]] = []
        for key in keys {
            if let first = groups.last?.first, key.ms - first.ms <= PropertyKeys.nearMS {
                groups[groups.count - 1].append(key)
            } else {
                groups.append([key])
            }
        }
        return groups.compactMap { group in
            guard let first = group.first else { return nil }
            let sorted = group.sorted {
                (order.firstIndex(of: $0.property) ?? order.count) < (order.firstIndex(of: $1.property) ?? order.count)
            }
            let reading = sorted.map { "\($0.property.title) \(Self.cameraReading($0.property, $0.value))" }
                .joined(separator: ", ")
            return CameraKeyMoment(ms: first.ms, properties: sorted.map(\.property), reading: reading,
                                   ease: cameraKeysEase(atMS: first.ms))
        }
    }

    /// A camera value in the panel's words: its lengths say px, as the
    /// Camera section's fields do.
    static func cameraReading(_ property: MotionProperty, _ value: MotionValue) -> String {
        guard property != .cameraPerspective, case let .number(points) = value else { return property.format(value) }
        return "\(MotionNumber.text(points)) px"
    }

    /// Every camera key at the diamond near `from`, carried to `to`: their
    /// values and eases go with them, and a key already where they land on
    /// the same value gives way. The moment stays on the document's clock.
    /// Returns where they landed, or nil when nothing was keyed there.
    @discardableResult
    public mutating func moveCameraKeys(atMS from: Int, toMS to: Int) -> Int? {
        guard var moved = camera, let motions = moved.motions,
              motions.contains(where: { $0.property.isCamera && $0.keyIndex(near: from) != nil })
        else { return nil }
        let landing = min(max(0, to), max(0, documentDurationMS))
        moved.motions = motions.map { motion in
            guard motion.property.isCamera, let index = motion.keyIndex(near: from) else { return motion }
            var list = motion.keyframes
            var carried = list.remove(at: index)
            carried.atMS = landing
            list.removeAll { abs($0.atMS - landing) <= PropertyKeys.nearMS }
            list.append(carried)
            return motion.rebuilt(from: list)
        }
        camera = moved
        return landing
    }

    /// Every camera key at the diamond near `ms`, deleted. A value losing its
    /// last key keeps what it held there, the way its panel diamond does.
    /// Returns whether anything was keyed there.
    @discardableResult
    public mutating func removeCameraKeys(atMS ms: Int) -> Bool {
        guard var moved = camera, let motions = moved.motions,
              motions.contains(where: { $0.property.isCamera && $0.keyIndex(near: ms) != nil })
        else { return false }
        var kept: [LayerMotion] = []
        for motion in motions {
            guard motion.property.isCamera, let index = motion.keyIndex(near: ms) else {
                kept.append(motion)
                continue
            }
            if let next = motion.removingKey(atMS: ms) {
                kept.append(next)
            } else {
                moved = moved.applying(motion.keyframes[index].value, for: motion.property)
            }
        }
        moved.motions = kept.isEmpty ? nil : kept
        camera = moved
        return true
    }

    // MARK: Easing (`camera-keys-ease-in-and-out-like-every-other-key`)

    /// Every camera value keyed near `ms`, with the index of its key there.
    private func cameraKeys(near ms: Int) -> [(motion: LayerMotion, index: Int)] {
        (camera?.motions ?? []).compactMap { motion in
            guard motion.property.isCamera, let index = motion.keyIndex(near: ms) else { return nil }
            return (motion, index)
        }
    }

    /// How the camera keys at the diamond near `ms` move, where they all
    /// agree; nil where they differ or nothing is keyed there. A key nobody
    /// has eased reads as what its motion's curve does there, as a layer's
    /// key does, so the menu ticks what the picture is actually doing.
    public func cameraKeysEase(atMS ms: Int) -> KeyEase? {
        let eases = cameraKeys(near: ms).map { hit in
            hit.motion.keyframes[hit.index].ease ?? KeyEase(following: hit.motion.curve)
        }
        guard let first = eases.first, eases.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Every camera key at the diamond near `ms` takes `ease`: a right click
    /// on the diamond, or the timeline bar's Easing with it picked. Returns
    /// whether anything was keyed there.
    @discardableResult
    public mutating func easeCameraKeys(atMS ms: Int, _ ease: KeyEase) -> Bool {
        let hits = cameraKeys(near: ms)
        guard var eased = camera, !hits.isEmpty else { return false }
        eased.motions = eased.motions?.map { motion in
            guard let hit = hits.first(where: { $0.motion.id == motion.id }) else { return motion }
            return motion.easing(key: hit.index, ease)
        }
        camera = eased
        return true
    }

    /// The camera values moving at `ms`, each with the stretch it is in:
    /// those whose keys reach either side of the moment, and where none do
    /// (the playhead before, after or between moves), every value with two
    /// keys, each on its nearest stretch, as a layer's Between the keys reads.
    private func cameraStretches(atDocumentTimeMS ms: Int) -> [(motion: LayerMotion, stretch: Int)] {
        let moving = (camera?.motions ?? []).filter { $0.property.isCamera && $0.keyframes.count > 1 }
        let spanning = moving.filter { motion in
            guard let first = motion.keyframes.first, let last = motion.keyframes.last else { return false }
            return first.atMS <= ms && ms <= last.atMS
        }
        return (spanning.isEmpty ? moving : spanning).compactMap { motion in
            motion.stretch(atMS: ms).map { (motion, $0) }
        }
    }

    /// Whether the camera has a stretch at `ms` for the Curve row to shape.
    public func cameraHasStretch(atDocumentTimeMS ms: Int) -> Bool {
        !cameraStretches(atDocumentTimeMS: ms).isEmpty
    }

    /// The curve the camera's stretch at `ms` runs on, where every value
    /// moving there agrees; nil where they differ (Mixed) or nothing moves.
    public func cameraStretchCurve(atDocumentTimeMS ms: Int) -> EasingCurve? {
        let curves = cameraStretches(atDocumentTimeMS: ms).map { $0.motion.stretchCurve($0.stretch) }
        guard let first = curves.first, curves.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// The Camera section's Curve row: every camera value moving at `ms`
    /// runs that stretch on `curve`, the way a layer's stretch does
    /// (`LayerMotion.curvingStretch`).
    public mutating func curveCameraStretch(atDocumentTimeMS ms: Int, _ curve: EasingCurve) {
        let hits = cameraStretches(atDocumentTimeMS: ms)
        guard var curved = camera, !hits.isEmpty else { return }
        curved.motions = curved.motions?.map { motion in
            guard let hit = hits.first(where: { $0.motion.id == motion.id }) else { return motion }
            return motion.curvingStretch(hit.stretch, curve)
        }
        camera = curved
    }
}
