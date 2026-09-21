import CoreGraphics
import Foundation

// Reframing a clip: where the camera is pointed, and where it goes next
// (`docs/design/mocks/pages/video-zoom-wt.html`).
//
// **There is no zoom tool here and no crop mode.** A punch-in is Scale and
// Position on the clip, the same two properties a title or a piece of clip art
// would be animated on, so it gets the curve list, the lane on the strip, undo,
// the export and everything else for free. What this file adds is not a
// mechanism, it is ARITHMETIC: turning "that thing, there, on the picture" into
// the two numbers those two properties want, so nobody has to type a percentage
// or a centre point to move the eye.
//
// The three things the mock could not have known, all of them found by trying
// to build it:
//
// 1. A move that goes out, HOLDS and comes back needs more than two keys on one
//    property. That is `MotionStop`, and it is general: any property can hold
//    now, not just this one.
// 2. A move on a clip belongs to the clip's own clock, or a trim slides the
//    frames out from under it (`Layer.motionClockMS(atDocumentTimeMS:)`).
// 3. The mock's open question — "220% of a 1080p source is soft, should the
//    canvas warn" — has a better answer than a warning: the app knows exactly
//    how much of the source it has left, so it says the number
//    (`ReframeReading.nativePercent`).

/// The numbers a reframe is built out of.
public enum ClipReframe {

    /// How long a push takes when there is room for it. Long enough to read as
    /// a camera move, short enough that nobody waits for it: the mock's own two
    /// seconds felt slow to sit through twice, so it is a little under.
    public static let moveMS = 1200

    /// The shortest a push is allowed to be. Below this it stops reading as a
    /// move and starts reading as a cut, and a cut is a different thing with
    /// its own name.
    public static let shortestMoveMS = 300

    /// As far in as a punch-in will go on one gesture. Past this there is
    /// nothing of the recording left to see, whatever the source resolution.
    public static let mostScalePercent: Double = 800

    /// How big a region has to be before it is a region rather than a slip of
    /// the hand, in document points.
    public static let smallestRegionPoints: CGFloat = 8

    /// The scale that makes `region` fill as much of `frame` as it can without
    /// any of it falling off the edge.
    ///
    /// The SMALLER of the two fits, so everything inside the box the hand drew
    /// stays on screen: taking the larger would fill the frame and cut the ends
    /// off the very thing that was pointed at.
    public static func scalePercent(fitting region: CGRect, into frame: CGRect) -> Double? {
        let box = region.standardized
        let outer = frame.standardized
        guard box.width >= smallestRegionPoints, box.height >= smallestRegionPoints,
              outer.width > 0, outer.height > 0 else { return nil }
        let fit = min(outer.width / box.width, outer.height / box.height)
        guard fit.isFinite, fit > 0 else { return nil }
        return min(max(Double(fit) * 100, 100), mostScalePercent)
    }

    /// Where the layer's origin has to travel to so that `point` of the drawing
    /// as it was drawn ends up in the middle of `frame`, once the drawing has
    /// been magnified by `percent` about that same middle.
    ///
    /// The two properties are applied one inside the other — scale first, then
    /// position (`MotionProperty.nestingOrder`) — so the distance the origin
    /// moves is the distance the point is from the middle, magnified. Getting
    /// this the other way round is what makes a punch-in drift off its subject
    /// as it arrives.
    public static func origin(centring point: CGPoint, in frame: CGRect,
                              atScalePercent percent: Double) -> CGPoint {
        let outer = frame.standardized
        let factor = CGFloat(percent / 100)
        let middle = CGPoint(x: outer.midX, y: outer.midY)
        return CGPoint(x: outer.origin.x - (point.x - middle.x) * factor,
                       y: outer.origin.y - (point.y - middle.y) * factor)
    }

    /// The reverse: which point of the drawing as it was drawn is in the middle
    /// of the frame right now. This is the "Centre" the panel prints.
    public static func centred(originAt origin: CGPoint, in frame: CGRect,
                              atScalePercent percent: Double) -> CGPoint {
        let outer = frame.standardized
        let factor = CGFloat(percent / 100)
        guard factor > 0 else { return CGPoint(x: outer.midX, y: outer.midY) }
        let middle = CGPoint(x: outer.midX, y: outer.midY)
        return CGPoint(x: middle.x + (outer.origin.x - origin.x) / factor,
                       y: middle.y + (outer.origin.y - origin.y) / factor)
    }
}

// MARK: - What the panel reads

/// What a clip's reframe is doing at one moment: how far in, what is in the
/// middle, and whether there are any source pixels left at that size.
public struct ReframeReading: Hashable, Sendable {

    /// How far in, as a percentage of the size the clip was laid out at.
    public let scalePercent: Double
    /// Which point of the recording is in the middle of the frame, in the
    /// clip's own drawn coordinates.
    public let centre: CGPoint
    /// The scale at which one pixel of the source lands on one point of the
    /// document: the last size at which there is nothing left to magnify.
    /// Nil where the layer does not come from a bitmap at all.
    public let nativePercent: Double?
    /// Whether anything about this clip's framing changes over time.
    public let moves: Bool

    public init(scalePercent: Double, centre: CGPoint,
                nativePercent: Double?, moves: Bool) {
        self.scalePercent = scalePercent
        self.centre = centre
        self.nativePercent = nativePercent
        self.moves = moves
    }

    /// Whether this framing has run past the detail the recording holds, so
    /// what is on screen is being invented rather than shown.
    public var isPastNative: Bool {
        guard let nativePercent else { return false }
        return scalePercent > nativePercent + 0.5
    }

    /// How much further in it could go before that happens. Nil where there is
    /// nothing to measure against.
    public var headroomPercent: Double? {
        nativePercent.map { max(0, $0 - scalePercent) }
    }

    /// The line the panel prints under the numbers. It says what IS rather than
    /// what might go wrong: "sharp to 246%" is a budget somebody can spend, and
    /// a warning triangle is not.
    public var sharpnessNote: String {
        guard let nativePercent else { return "" }
        let native = MotionNumber.text((nativePercent * 10).rounded() / 10)
        if isPastNative { return "Past the recording's own detail, which is \(native)%" }
        return "Sharp to \(native)%"
    }
}

extension Layer {

    /// The two motions a reframe is made of, where they are there.
    var reframeScale: LayerMotion? {
        (motions ?? []).first { $0.property == .scale }
    }

    var reframePosition: LayerMotion? {
        (motions ?? []).first { $0.property == .position }
    }

    /// Whether this layer has been reframed at all.
    public var isReframed: Bool { reframeScale != nil || reframePosition != nil }

    /// Whether this layer is one a reframe can be pointed at: it occupies a
    /// stretch of time and it draws a picture. A title has no camera to move
    /// and a sound draws nothing to move it across.
    public var takesAReframe: Bool {
        guard occupiesTime else { return false }
        switch content {
        case .image: return true
        default: return false
        }
    }

    /// How big the source behind this layer is in its own pixels, where it
    /// comes from one.
    var reframeSourcePixels: CGSize? {
        if let movie { return movie.pixelSize }
        if case let .image(ref) = content { return ref.pixelSize }
        return nil
    }

    /// The scale at which the source runs out of pixels to give.
    public var reframeNativePercent: Double? {
        guard let pixels = reframeSourcePixels else { return nil }
        let box = frame.standardized
        guard box.width > 0, box.height > 0, pixels.width > 0, pixels.height > 0 else { return nil }
        let fit = min(pixels.width / box.width, pixels.height / box.height)
        guard fit.isFinite, fit > 0 else { return nil }
        return Double(fit) * 100
    }

    /// What the framing is at a moment of the DOCUMENT's clock.
    public func reframeReading(atDocumentTimeMS ms: Int, documentCycleMS: Int) -> ReframeReading? {
        guard takesAReframe else { return nil }
        let clock = motionClockMS(atDocumentTimeMS: ms)
        let cycle = motionCycleMS(documentCycleMS: documentCycleMS)
        var percent: Double = 100
        if let scale = reframeScale, case let .number(number) = scale.value(atMS: clock, cycleMS: cycle) {
            percent = number
        }
        var origin = frame.standardized.origin
        if let move = reframePosition, case let .point(point) = move.value(atMS: clock, cycleMS: cycle) {
            origin = point
        }
        return ReframeReading(
            scalePercent: percent,
            centre: ClipReframe.centred(originAt: origin, in: frame, atScalePercent: percent),
            nativePercent: reframeNativePercent,
            moves: isReframed)
    }
}

// MARK: - Making the move

extension PhotonzDocument {

    /// Push in on a region of a clip, arriving there by `ms`.
    ///
    /// **It arrives at the playhead rather than setting off from it.** You
    /// scrub to the moment the thing matters, point at it, and by that moment
    /// the camera is on it, having started to move a beat earlier. That is the
    /// one reading under which the gesture answers itself: let go of the box
    /// and the canvas is already showing what you asked for. Setting off from
    /// the playhead would leave the frame exactly as it was and ask you to
    /// scrub forward to find out whether it had worked.
    ///
    /// Where there is not a whole move's worth of clip before the playhead the
    /// push starts at the clip's first frame and is correspondingly quicker,
    /// never shorter than `ClipReframe.shortestMoveMS`.
    @discardableResult
    public mutating func punchIn(layerID: UUID, onRegion region: CGRect,
                                 atTimeMS ms: Int,
                                 overMS: Int = ClipReframe.moveMS) -> Bool {
        guard let layer = layer(id: layerID), layer.takesAReframe,
              let percent = ClipReframe.scalePercent(fitting: region, into: layer.frame)
        else { return false }
        let box = region.standardized
        let target = ClipReframe.origin(centring: CGPoint(x: box.midX, y: box.midY),
                                        in: layer.frame, atScalePercent: percent)
        return reframe(layerID: layerID, toScalePercent: percent, origin: target,
                       atTimeMS: ms, overMS: overMS, arriving: true)
    }

    /// Pull back out to the whole frame, setting off at `ms`.
    ///
    /// **It sets off from the playhead**, which is the mirror of the push and
    /// the same rule read from the other end: at the playhead, what you asked
    /// for is what is happening. You are done with the detail HERE, so here is
    /// where the camera starts to leave. Everything between the punch-in's last
    /// key and this one is the hold, and nobody had to ask for it.
    @discardableResult
    public mutating func pullBackOut(layerID: UUID, atTimeMS ms: Int,
                                     overMS: Int = ClipReframe.moveMS) -> Bool {
        guard let layer = layer(id: layerID), layer.isReframed else { return false }
        return reframe(layerID: layerID, toScalePercent: 100,
                       origin: layer.frame.standardized.origin,
                       atTimeMS: ms, overMS: overMS, arriving: false)
    }

    /// Put the camera back where it started and forget every move on it.
    @discardableResult
    public mutating func resetReframe(layerID: UUID) -> Bool {
        guard let layer = layer(id: layerID), layer.isReframed else { return false }
        updateLayer(id: layerID) { found in
            let kept = (found.motions ?? []).filter { $0.property != .scale && $0.property != .position }
            found.motions = kept.isEmpty ? nil : kept
        }
        return true
    }

    /// The one move both gestures are made of: get the framing to these two
    /// numbers, either arriving at this moment or setting off from it.
    ///
    /// A clip that is already reframed is EXTENDED rather than replaced, so a
    /// second punch-in travels from where the camera is instead of cutting back
    /// to wide and starting again. That is what makes the hold appear on its
    /// own: the gap between the last key of one move and the first key of the
    /// next is a stretch where nothing changes.
    mutating func reframe(layerID: UUID, toScalePercent percent: Double, origin: CGPoint,
                          atTimeMS ms: Int, overMS: Int, arriving: Bool) -> Bool {
        guard let layer = layer(id: layerID), let time = layer.time else { return false }
        let clock = layer.motionClockMS(atDocumentTimeMS: ms)
        let firstFrame = layer.motionClockMS(atDocumentTimeMS: time.inMS)
        let wanted = max(ClipReframe.shortestMoveMS, overMS)

        // Where the existing move, if any, has finished. Nothing new is allowed
        // to start before that: two keys of one property at the same moment are
        // two answers to one question.
        let already = max(layer.reframeScale?.timing.endMS ?? Int.min,
                          layer.reframePosition?.timing.endMS ?? Int.min)
        let floor = already == Int.min ? firstFrame : max(firstFrame, already)

        let startMS: Int
        let endMS: Int
        if arriving {
            let room = max(0, clock - floor)
            let length = min(wanted, max(ClipReframe.shortestMoveMS, room))
            endMS = max(clock, floor + length)
            startMS = endMS - length
        } else {
            startMS = max(clock, floor)
            endMS = startMS + wanted
        }
        guard endMS > startMS else { return false }

        let scaleTo = MotionValue.number(percent)
        let originTo = MotionValue.point(origin)
        updateLayer(id: layerID) { found in
            var motions = (found.motions ?? []).filter {
                $0.property != .scale && $0.property != .position
            }
            motions.append(Self.extended(found.reframeScale, property: .scale,
                                         restingAt: .number(100), to: scaleTo,
                                         startMS: startMS, endMS: endMS))
            motions.append(Self.extended(found.reframePosition, property: .position,
                                         restingAt: .point(found.frame.standardized.origin),
                                         to: originTo,
                                         startMS: startMS, endMS: endMS))
            found.motions = motions
        }
        return true
    }

    /// One property's motion, with a new leg added on the end.
    ///
    /// With nothing there before it is an ordinary two-key motion, exactly what
    /// the plus on the Motion header would have made. With something there, the
    /// value it had reached is nailed down twice — once where the old move
    /// finished and once where the new one begins — and those two identical
    /// keys ARE the hold.
    static func extended(_ existing: LayerMotion?, property: MotionProperty,
                         restingAt resting: MotionValue, to: MotionValue,
                         startMS: Int, endMS: Int) -> LayerMotion {
        guard let existing else {
            return LayerMotion(property: property, from: resting, to: to,
                               timing: MotionTiming(startMS: startMS,
                                                    durationMS: endMS - startMS),
                               curve: .easeInOut, repeats: .once)
        }
        var stops = existing.stops ?? []
        stops.append(MotionStop(atMS: existing.timing.endMS, value: existing.to))
        if startMS > existing.timing.endMS {
            stops.append(MotionStop(atMS: startMS, value: existing.to))
        }
        var grown = existing
        grown.stops = stops.sorted { $0.atMS < $1.atMS }
        grown.to = to
        grown.timing = MotionTiming(startMS: existing.timing.startMS,
                                    durationMS: endMS - existing.timing.startMS)
        grown.curve = .easeInOut
        grown.repeats = .once
        grown.isOn = true
        return grown
    }
}
