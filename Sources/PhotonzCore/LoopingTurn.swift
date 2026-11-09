import CoreGraphics
import Foundation

// A looping turn comes home and spins evenly without extra keys
// (task `a-looping-turn-comes-home-and-spins-evenly-witho`).
//
// A picture's keys go round with its lap (`PhotonzDocument.lappingKeys`), and
// a lap starts over at its first moment. Keys of 0, 15 at half a second and
// -15 at a second and a half on a two second lap held at -15 and started
// again at 0: a fifteen degree jump every lap, which nobody setting a swing
// ever wants. Saying so took a fourth key at 0:02.00, a moment the ruler
// cannot even reach (its last is the lap less a millisecond). A spin of 0 to
// 360 ran on the new key's ease in and out, so it slowed to a stop at the lap
// until Linear was picked by hand.
//
// So on a picture whose lap repeats, a TURN looks after its seam:
//
//  - **It comes home.** A turn that moves, whose last key is short of the lap
//    end and not at the angle it started (whole turns aside), gets a real key
//    at the lap end holding its first angle. It is on the strip like any key:
//    change it, ease it or delete it. Moving the first angle carries that key
//    along while it still holds the old first angle.
//  - **The lap end can be keyed.** A key set within a frame of the lap end
//    lands ON it, where the next lap begins, rather than a hundredth short.
//  - **A key on the lap end rides the repeats mark** when the lap is made
//    longer or shorter, so a home key never strands itself mid-lap or stops
//    the lap being shortened.
//  - **It does not stop at the seam it passes through.** Where the turn is
//    still travelling the same way through the seam (a spin, or a swing
//    crossing its start) and nobody has eased either seam key, the two are
//    given a straight tangent there at one pace: Linear on a two key spin,
//    Bezier handles otherwise. Both read in the key's own ease menu.
//
// Only a turn. A fade or a move that snaps back each lap can be what was
// meant (a blink, a slide that restarts); a turn that jumps never is.

extension PhotonzDocument {

    /// The lap a picture's keys go round on, or nil where they do not go
    /// round: a video, a still, or a picture set to play once.
    var repeatingKeyLapMS: Int? {
        guard !hasTime, keyLap?.repeats == true, isKeyedPicture else { return nil }
        return max(1, motionCycleLengthMS)
    }

    /// Where a key set at `clock` on `layer` lands: on the lap end when it is
    /// within a frame of it, since the ruler stops a millisecond short.
    func keyLanding(_ clock: Int, on layer: Layer) -> Int {
        guard layer.time == nil, let lap = repeatingKeyLapMS,
              clock < lap, clock >= lap - PropertyKeys.nearMS else { return clock }
        return lap
    }

    /// After a turn on `layerID` has been keyed: bring it home and keep it
    /// moving through the seam (see the top of this file). `before` is the
    /// turn as it was before the edit, nil where it was not keyed.
    mutating func closeTurnLap(layerID: UUID, effect: Int, before: LayerMotion?) {
        guard let lap = repeatingKeyLapMS, let layer = layer(id: layerID), layer.time == nil,
              let motion = layer.keyedMotion(.rotation, effect: effect) else { return }
        guard let closed = motion.closingTheLap(lapMS: lap, before: before) else { return }
        updateLayer(id: layerID) { edited in
            edited.motions = edited.motions?.map { $0.id == motion.id ? closed : $0 }
        }
    }

    /// The lap made `ms` long, with every key standing on the old lap end
    /// carried to the new one: what letting go of the repeats mark does on a
    /// keyed picture.
    public mutating func setKeyLapLength(_ ms: Int) {
        let old = motionCycleLengthMS
        let new = max(1, ms)
        let carries = isKeyedPicture && !hasTime && old != new
        motionCycleMS = new
        guard carries else { return }
        layers = layers.map { $0.carryingLapEndKeys(fromMS: old, toMS: new) }
    }

    /// The shortest the repeats mark can be dragged to: just past the last
    /// key that does not ride it. A key standing on the lap end moves with
    /// the mark (`setKeyLapLength`), so it does not hold the lap long.
    public var shortestDraggedKeyLapMS: Int {
        let lap = motionCycleLengthMS
        var last = 0
        for layer in allLayers {
            let marks = clipKeyMarks(layerID: layer.id).map(\.documentMS).filter { $0 != lap }
            last = max(last, marks.max() ?? 0)
        }
        return last + 1
    }
}

extension Layer {

    /// This layer and everything inside it with every keyed motion whose last
    /// key stands on `old` ending on `new` instead, where that keeps the keys
    /// in order.
    func carryingLapEndKeys(fromMS old: Int, toMS new: Int) -> Layer {
        var layer = self
        layer.motions = motions?.map { motion in
            guard motion.repeats == .once else { return motion }
            var list = motion.keyframes
            guard list.count >= 2, list[list.count - 1].atMS == old,
                  list[list.count - 2].atMS < new else { return motion }
            list[list.count - 1].atMS = new
            return motion.rebuilt(from: list)
        }
        if var group = layer.group {
            group.children = group.children.map { $0.carryingLapEndKeys(fromMS: old, toMS: new) }
            layer.content = .group(group)
        }
        return layer
    }
}

extension LayerMotion {

    /// This turn brought home and kept moving through the seam of a lap
    /// `lap` long, or nil where there is nothing to do.
    func closingTheLap(lapMS lap: Int, before: LayerMotion?) -> LayerMotion? {
        guard property == .rotation, repeats == .once else { return nil }
        var list = keyframes
        guard list.count >= 2, let start = Self.degrees(list[0].value) else { return nil }
        var changed = false
        let end = list.count - 1

        // The first angle moved: a lap end key still holding the old one
        // goes with it, or the seam would jump by however far it moved.
        if let old = before?.keyframes, old.count >= 2, old[0].atMS == list[0].atMS,
           old[0].value != list[0].value, old[old.count - 1].atMS == lap,
           old[old.count - 1].value == old[0].value,
           list[end].atMS == lap, list[end].value == old[0].value {
            list[end].value = list[0].value
            changed = true
        }

        // Home: short of the lap end, somewhere else, so the lap end says
        // where it started.
        if list[end].atMS < lap, list.contains(where: { $0.value != list[0].value }),
           let finish = Self.degrees(list[end].value), !Self.sameHeading(finish, start) {
            list.append(MotionStop(atMS: lap, value: list[0].value))
            changed = true
        }

        if Self.straighteningTheSeam(&list, lapMS: lap) { changed = true }
        return changed ? rebuilt(from: list) : nil
    }

    /// Where the turn passes THROUGH the seam (the same way into the lap end
    /// as out of the start) and neither seam key has been eased, a straight
    /// tangent there at one pace. True where anything changed.
    static func straighteningTheSeam(_ list: inout [MotionStop], lapMS lap: Int) -> Bool {
        let count = list.count
        guard count >= 2, list[0].atMS == 0, list[count - 1].atMS == lap,
              list[0].ease == nil, list[count - 1].ease == nil,
              list[0].curve == nil, list[count - 2].curve == nil,
              let a = degrees(list[0].value), let b = degrees(list[1].value),
              let y = degrees(list[count - 2].value), let z = degrees(list[count - 1].value) else { return false }
        let leaving = b - a
        let arriving = z - y
        guard leaving != 0, arriving != 0, (leaving > 0) == (arriving > 0) else { return false }
        if count == 2 {
            // One stretch, end to end: a spin, straight all the way.
            list[0].ease = .linear
            list[1].ease = .linear
            return true
        }
        let outSpan = Double(max(1, list[1].atMS - list[0].atMS))
        let inSpan = Double(max(1, list[count - 1].atMS - list[count - 2].atMS))
        let outPace = abs(leaving) / outSpan
        let inPace = abs(arriving) / inSpan
        let pace = (outPace + inPace) / 2
        // A handle's slope is the pace over the stretch's own average; three
        // is as steep as a handle a third of the way along can be and stay
        // inside the square SVG allows.
        let outSlope = min(3, pace / outPace)
        let inSlope = min(3, pace / inPace)
        let eased = KeyHandles.implied(by: .easeInAndOut)
        list[0].ease = .bezier
        list[0].handles = KeyHandles(arriving: eased.arriving,
                                     leaving: CGPoint(x: 1.0 / 3, y: outSlope / 3))
        list[count - 1].ease = .bezier
        list[count - 1].handles = KeyHandles(arriving: CGPoint(x: 2.0 / 3, y: 1 - inSlope / 3),
                                             leaving: eased.leaving)
        return true
    }

    static func degrees(_ value: MotionValue) -> Double? {
        if case let .number(number) = value { return number }
        return nil
    }

    /// Whether two angles point the same way, whole turns aside.
    static func sameHeading(_ a: Double, _ b: Double) -> Bool {
        abs(remainder(a - b, 360)) < 0.001
    }
}

// MARK: - Reading the seam

/// How a turning layer plays across its lap's seam, read off the picture the
/// canvas is handed to draw (`PhotonzDocument.moved(toMotionTimeMS:)`): what a
/// walk measures to prove a loop runs smoothly.
public struct LapSeamReading: Hashable, Sendable {
    public var layerName: String
    /// How far apart, in degrees and whole turns aside, the angle drawn a
    /// millisecond before the lap ends and the one drawn as it starts are.
    public var jump: Double
    /// Degrees turned over the last tenth of a second of the lap, and over
    /// the first: either near nought where it passes through is a stop.
    public var arriving: Double
    public var leaving: Double
    /// The largest share by which a tenth of a second of the lap turns more
    /// or less than the average tenth: nought is a perfectly steady pace.
    public var paceSpread: Double
}

extension PhotonzDocument {

    /// The seam of every layer whose turn is keyed, on a picture whose keys
    /// go round.
    public func lapSeamReadings() -> [LapSeamReading] {
        guard repeatingKeyLapMS != nil else { return [] }
        let lap = motionCycleLengthMS
        let turning = allLayers.filter { $0.keyedMotion(.rotation) != nil }
        guard !turning.isEmpty else { return [] }
        func drawn(_ id: UUID, _ ms: Int) -> Double {
            Double(moved(layerID: id, toMotionTimeMS: ms).layer(id: id)?.transform.rotation ?? 0) * 180 / .pi
        }
        return turning.map { layer in
            let tenth = max(1, lap / 20)
            // The angle through one lap, unwound so a whole turn reads 360.
            var angles: [Double] = []
            for ms in stride(from: 0, through: lap - 1, by: tenth) {
                let raw = drawn(layer.id, ms)
                if let last = angles.last {
                    angles.append(last + remainder(raw - last, 360))
                } else {
                    angles.append(raw)
                }
            }
            let steps = zip(angles, angles.dropFirst()).map { $1 - $0 }
            let mean = steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count)
            let spread = abs(mean) < 0.0001 ? .infinity
                : steps.map { abs($0 - mean) / abs(mean) }.max() ?? 0
            let end = drawn(layer.id, lap - 1)
            let start = drawn(layer.id, 0)
            return LapSeamReading(
                layerName: layer.name,
                jump: abs(remainder(end - start, 360)),
                arriving: abs(remainder(end - drawn(layer.id, lap - 1 - tenth), 360)),
                leaving: abs(remainder(drawn(layer.id, tenth) - start, 360)),
                paceSpread: spread)
        }
    }
}
