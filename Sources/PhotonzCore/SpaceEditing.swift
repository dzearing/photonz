import CoreGraphics
import Foundation

// MARK: - Turning a layer in space by hand: the canvas handles and the panel
//
// The 2.5D model (`Space3D.swift`) says where a turned layer lands. This file
// is how a person gets it there (`docs/design/mocks/pages/video-depth.html`,
// design A on the decision card `...-how-do-you-turn-a-layer-toward-o`):
//
// - Two arcs on the turn knob. Rest on the knob and they appear; the flat arc
//   drags sideways to swing the layer (Rotation Y), the tall arc up and down to
//   tip it (Rotation X). The knob itself still turns it flat, as it always did.
// - A depth arrow off the pivot: drag it up to push the layer away.
// - The panel's 3D rows and the Layer menu's Reset 3D Rotation, Bring Nearer
//   and Send Further.
//
// Everything here is in the canvas VIEW's points (y down) for the handles, and
// in document points for the values, so the canvas only has to say where the
// layer's top edge and middle landed on screen.

/// One of the three 3D handles on a picked layer.
public enum SpaceHandle: String, Hashable, Sendable, CaseIterable {
    /// The flat arc across the knob: drag sideways to swing (Rotation Y).
    case swing
    /// The tall arc beside the knob: drag up or down to tip (Rotation X).
    case tip
    /// The arrow off the pivot: drag up to push away, down to pull nearer.
    case depth

    /// The value the handle changes.
    public var property: MotionProperty {
        switch self {
        case .swing: .rotationY
        case .tip: .rotationX
        case .depth: .depth
        }
    }
}

/// Where the 3D handles sit on screen for one picked layer, and which one a
/// point is on. Built from three points the canvas already has: the middle of
/// the layer's top edge and the layer's middle as DRAWN (so a layer already
/// turned wears its knob off the edge you can see), and its pivot.
public struct SpaceHandles: Hashable, Sendable {

    /// How far the knob floats off the top edge, in view points: the same 18
    /// the flat knob has always floated (`Layer.rotateKnobPoint`).
    public static let knobOffset: CGFloat = 18
    /// Inside this far from the knob a press is the knob's own (the flat
    /// turn), even where an arc passes close by.
    public static let knobKeeps: CGFloat = 7
    /// How far either side of an arc or the arrow a press still catches it.
    /// Generous on purpose: the arcs are small targets (the design audit,
    /// 2026-10-11).
    public static let grabReach: CGFloat = 9
    /// Resting this close to the knob brings the arcs out.
    public static let revealReach: CGFloat = 12
    /// Once out, the arcs stay while the pointer is this close to the knob,
    /// so the hand can travel to the far end of an arc without losing it.
    public static let holdReach: CGFloat = 62
    /// Half the flat arc's span, and how far it bows out from the knob.
    public static let swingHalfSpan: CGFloat = 26
    public static let swingBow: CGFloat = 10
    /// How far the tall arc sits beside the knob, half its height, its bow.
    public static let tipSide: CGFloat = 38
    public static let tipHalfSpan: CGFloat = 20
    public static let tipBow: CGFloat = 8
    /// The depth arrow: where it starts and ends off the pivot, up and to the
    /// right on screen.
    public static let depthStart: CGFloat = 7
    public static let depthEnd: CGFloat = 30

    /// Where the knob sits.
    public let knob: CGPoint
    /// Out from the layer's middle through its top edge, as a unit vector.
    public let up: CGPoint
    /// Along the top edge, a quarter turn from `up`, as a unit vector.
    public let along: CGPoint
    /// The point the layer turns about, where the depth arrow starts.
    public let pivot: CGPoint
    /// Where the stem leaves the top edge.
    public let topMid: CGPoint

    public init(topMid: CGPoint, middle: CGPoint, pivot: CGPoint) {
        let dx = topMid.x - middle.x, dy = topMid.y - middle.y
        let length = hypot(dx, dy)
        let up = length > 1e-9 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 0, y: -1)
        self.up = up
        self.along = CGPoint(x: -up.y, y: up.x)
        self.topMid = topMid
        self.knob = CGPoint(x: topMid.x + up.x * Self.knobOffset, y: topMid.y + up.y * Self.knobOffset)
        self.pivot = pivot
    }

    /// A quadratic curve, start, control and end.
    public struct Arc: Hashable, Sendable {
        public let start: CGPoint
        public let control: CGPoint
        public let end: CGPoint

        /// Points along it, start to end, for drawing and for measuring.
        public func points(_ count: Int = 16) -> [CGPoint] {
            (0...count).map { step in
                let t = CGFloat(step) / CGFloat(count), u = 1 - t
                return CGPoint(x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                               y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
            }
        }

        /// How far `p` is from the nearest point of the curve.
        public func distance(to p: CGPoint) -> CGFloat {
            let list = points(24)
            var best = CGFloat.infinity
            for (a, b) in zip(list, list.dropFirst()) {
                best = min(best, SpaceHandles.distance(p, toSegment: a, b))
            }
            return best
        }
    }

    /// The flat arc: across the knob, along the top edge, bowed outward.
    public var swingArc: Arc {
        let r = Self.swingHalfSpan, bow = Self.swingBow
        return Arc(start: CGPoint(x: knob.x - along.x * r, y: knob.y - along.y * r),
                   control: CGPoint(x: knob.x + up.x * bow, y: knob.y + up.y * bow),
                   end: CGPoint(x: knob.x + along.x * r, y: knob.y + along.y * r))
    }

    /// The tall arc: beside the knob, across the top edge, bowed outward.
    public var tipArc: Arc {
        let side = CGPoint(x: knob.x + along.x * Self.tipSide, y: knob.y + along.y * Self.tipSide)
        let h = Self.tipHalfSpan, bow = Self.tipBow
        return Arc(start: CGPoint(x: side.x - up.x * h, y: side.y - up.y * h),
                   control: CGPoint(x: side.x + along.x * bow, y: side.y + along.y * bow),
                   end: CGPoint(x: side.x + up.x * h, y: side.y + up.y * h))
    }

    /// The depth arrow, tail to head: up and to the right of the pivot on
    /// screen, whatever the layer's turn, so it always reads as "away".
    public var depthArrow: (tail: CGPoint, head: CGPoint) {
        let s = Self.depthStart, e = Self.depthEnd
        return (CGPoint(x: pivot.x + s, y: pivot.y - s), CGPoint(x: pivot.x + e, y: pivot.y - e))
    }

    /// Whether a point is on the knob itself, which the flat turn keeps.
    public func onKnob(_ p: CGPoint) -> Bool {
        hypot(p.x - knob.x, p.y - knob.y) <= Self.knobKeeps
    }

    /// The handle a press at `p` takes, of the ones showing, or nil. The knob
    /// keeps its own middle: a press there still turns the layer flat. Where
    /// two are in reach, the nearer wins.
    public func hit(at p: CGPoint, arcs: Bool, depth: Bool) -> SpaceHandle? {
        var best: (SpaceHandle, CGFloat)?
        func consider(_ handle: SpaceHandle, _ d: CGFloat) {
            guard d <= Self.grabReach, d < (best?.1 ?? .infinity) else { return }
            best = (handle, d)
        }
        if arcs {
            if onKnob(p) { return nil }
            consider(.swing, swingArc.distance(to: p))
            consider(.tip, tipArc.distance(to: p))
        }
        if depth {
            let arrow = depthArrow
            consider(.depth, Self.distance(p, toSegment: arrow.tail, arrow.head))
        }
        return best?.0
    }

    /// Whether resting at `p` brings the arcs out.
    public func reveals(at p: CGPoint) -> Bool {
        hypot(p.x - knob.x, p.y - knob.y) <= Self.revealReach
    }

    /// Whether arcs already out stay out with the pointer at `p`: near the
    /// knob, or anywhere over `drawn` (the layer as drawn, in view points),
    /// so the hand can go from the knob to the depth arrow without the
    /// handles vanishing on the way.
    public func holds(at p: CGPoint, over drawn: CGRect) -> Bool {
        if hypot(p.x - knob.x, p.y - knob.y) <= Self.holdReach { return true }
        return drawn.insetBy(dx: -Self.depthEnd - Self.grabReach, dy: -Self.depthEnd - Self.grabReach)
            .contains(p)
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-12 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t))
    }
}

// MARK: - What a drag does

/// The values a drag on a 3D handle makes, and what its readout says.
public enum SpaceDrag {
    /// Degrees per view point the arcs turn by: a 150 point sweep is 90°.
    public static let degreesPerPoint: Double = 0.6
    /// Document points of depth per view point the arrow travels, at 100%.
    public static let depthPerPoint: Double = 2.5
    /// The furthest either arc goes: a whole flip each way.
    public static let mostTurn: Double = 180
    /// Shift steps turns by this much.
    public static let snapStep: Double = 15
    /// The furthest away the arrow pushes, in document points.
    public static let furthest: Double = -10000

    /// `start` with the handle dragged `delta` view points (x right, y down)
    /// at `zoom`. Shift snaps a turn to 15° steps; otherwise turns are whole
    /// degrees and depths whole points. `nearest` is the most a layer may come
    /// toward the viewer before it would pass the camera, nil for no limit.
    public static func turned(_ start: LayerTurn3D, by handle: SpaceHandle, delta: CGPoint,
                              zoom: CGFloat, snapped: Bool, nearest: Double? = nil) -> LayerTurn3D {
        var turned = start
        func degrees(_ value: Double) -> Double {
            let bounded = min(max(value, -mostTurn), mostTurn)
            return snapped ? (bounded / snapStep).rounded() * snapStep : bounded.rounded()
        }
        switch handle {
        case .swing:
            turned.rotationY = degrees(start.rotationY + Double(delta.x) * degreesPerPoint)
        case .tip:
            turned.rotationX = degrees(start.rotationX - Double(delta.y) * degreesPerPoint)
        case .depth:
            // Up and right is away: the arrow points into the picture.
            let scale = zoom > 0 ? Double(zoom) : 1
            let moved = start.depth + Double(delta.y - delta.x) * depthPerPoint / scale
            let near = nearest ?? .infinity
            turned.depth = min(max(moved, furthest), near).rounded()
        }
        return turned
    }

    /// The pill under the drag: the value it is changing, named.
    public static func readout(_ handle: SpaceHandle, _ turn: LayerTurn3D) -> String {
        switch handle {
        case .swing: "Rotation Y \(MotionNumber.text(turn.rotationY))°"
        case .tip: "Rotation X \(MotionNumber.text(turn.rotationX))°"
        case .depth: "Depth \(MotionNumber.text(turn.depth))"
        }
    }
}

// MARK: - The document: the values, read and written

extension PhotonzDocument {

    /// How far one Bring Nearer or Send Further moves a layer, in points.
    public static let depthStep: Double = 100

    /// One of a layer's four 3D values as it shows at `ms`: between keys where
    /// it is keyed, its own otherwise.
    public func spaceValue(_ property: MotionProperty, layerID: UUID, atDocumentTimeMS ms: Int) -> Double? {
        guard property.isSpace, let layer = layer(id: layerID), !layer.isSoundOnly else { return nil }
        if hasTime, layer.keyedMotion(property) != nil,
           case let .number(number)? = keyedValue(layerID: layerID, .motion(property), atDocumentTimeMS: ms) {
            return number
        }
        return (layer.turn3D ?? LayerTurn3D()).value(of: property) ?? 0
    }

    /// The value every one of `ids` agrees on, or nil where they differ (the
    /// panel's Mixed) or none can be turned.
    public func sharedSpaceValue(_ property: MotionProperty, layerIDs ids: [UUID],
                                 atDocumentTimeMS ms: Int) -> Double? {
        let values = ids.compactMap { spaceValue(property, layerID: $0, atDocumentTimeMS: ms) }
        guard let first = values.first, values.allSatisfy({ abs($0 - first) < 1e-6 }) else { return nil }
        return first
    }

    /// The values that say where a layer is, in the plane and in space: what
    /// the track's diamond keys (`transformKeyProperties`) less its opacity,
    /// which is a look, plus the four 3D values.
    public static let placeProperties: [MotionProperty] =
        [.position, .scale, .rotation] + MotionProperty.spaceProperties

    /// Whether where a layer is, is animating: any of `placeProperties` keyed.
    /// On such a layer a 3D value changed by hand is a key at the playhead,
    /// the way a move is once the track's diamond has keyed its place.
    func animatesItsPlace(_ layer: Layer) -> Bool {
        (layer.motions ?? []).contains { Self.placeProperties.contains($0.property) }
    }

    /// The moments either side of `ms` where anything about a layer's place
    /// has a key: where a 3D value starting to key holds the value it had, so
    /// the layer stays as it was at every moment the hand did not touch (the
    /// same rule a reframe's Centre follows, `reframeAnchors`).
    func placeAnchors(layerID: UUID, atDocumentTimeMS ms: Int) -> [Int] {
        guard let layer = layer(id: layerID) else { return [] }
        let keyed = Set((layer.motions ?? []).map(\.property)).filter { Self.placeProperties.contains($0) }
        return [false, true].compactMap { forward in
            let moments = keyed.compactMap {
                neighbourKeyTime(layerID: layerID, .motion($0), from: ms, forward: forward)
            }
            return forward ? moments.min() : moments.max()
        }
    }

    /// Writes one 3D value on each of `ids` at `ms`. In a document with time
    /// it is a key there where the value is keyed, and also where the layer's
    /// place is animating (`animatesItsPlace`): a tilt keys like a move. The
    /// layer's own value otherwise. A layer left with nothing turned goes back
    /// to having no turn at all, so it saves byte for byte as it did before it
    /// was ever touched.
    public mutating func setSpaceValue(_ property: MotionProperty, _ value: Double, layerIDs ids: [UUID],
                                       atDocumentTimeMS ms: Int, ease: KeyEase? = nil) {
        guard property.isSpace, value.isFinite else { return }
        for id in ids {
            guard let layer = layer(id: id), !layer.isSoundOnly else { continue }
            if hasTime, layer.keyedMotion(property) != nil {
                setKeyedValue(.number(value), layerID: id, .motion(property), atDocumentTimeMS: ms, ease: ease)
            } else if hasTime, animatesItsPlace(layer) {
                // Starts keying holding the value it has at the place's keys
                // either side, then the hand's value at the playhead.
                let keyed = KeyedProperty.motion(property)
                let held = layer.keyStill(property).flatMap { value -> Double? in
                    if case let .number(number) = value { return number }
                    return nil
                } ?? 0
                for (index, anchor) in placeAnchors(layerID: id, atDocumentTimeMS: ms).enumerated() {
                    if index == 0 {
                        startKeying(layerID: id, keyed, atDocumentTimeMS: anchor, ease: ease)
                    } else {
                        setKeyedValue(.number(held), layerID: id, keyed, atDocumentTimeMS: anchor, ease: ease)
                    }
                }
                if keyCount(layerID: id, keyed) == 0 {
                    startKeying(layerID: id, keyed, atDocumentTimeMS: ms, ease: ease)
                }
                setKeyedValue(.number(value), layerID: id, keyed, atDocumentTimeMS: ms, ease: ease)
            } else {
                updateLayer(id: id) { edited in
                    var turn = edited.turn3D ?? LayerTurn3D()
                    switch property {
                    case .rotationX: turn.rotationX = value
                    case .rotationY: turn.rotationY = value
                    case .depth: turn.depth = value
                    default: turn.pivotDepth = value
                    }
                    edited.turn3D = turn
                    edited.settleTurn3D()
                }
            }
        }
    }

    /// A whole turn from a drag on one layer: each of the four values that
    /// differs from what the layer shows at `ms` is written as
    /// `setSpaceValue` writes it.
    public mutating func setSpaceTurn(_ turn: LayerTurn3D, layerID: UUID,
                                      atDocumentTimeMS ms: Int, ease: KeyEase? = nil) {
        for property in MotionProperty.spaceProperties {
            guard let wanted = turn.value(of: property),
                  let now = spaceValue(property, layerID: layerID, atDocumentTimeMS: ms),
                  abs(wanted - now) > 1e-9 else { continue }
            setSpaceValue(property, wanted, layerIDs: [layerID], atDocumentTimeMS: ms, ease: ease)
        }
    }

    /// The turn a layer shows at `ms`, keys and all.
    public func shownSpaceTurn(layerID: UUID, atDocumentTimeMS ms: Int) -> LayerTurn3D {
        var turn = layer(id: layerID)?.turn3D ?? LayerTurn3D()
        turn.rotationX = spaceValue(.rotationX, layerID: layerID, atDocumentTimeMS: ms) ?? 0
        turn.rotationY = spaceValue(.rotationY, layerID: layerID, atDocumentTimeMS: ms) ?? 0
        turn.depth = spaceValue(.depth, layerID: layerID, atDocumentTimeMS: ms) ?? 0
        turn.pivotDepth = spaceValue(.pivotDepth, layerID: layerID, atDocumentTimeMS: ms) ?? 0
        return turn
    }

    /// Whether any of `ids` is turned about X or Y, at its own value or by a
    /// key: what Reset 3D Rotation has to put back.
    public func hasSpaceRotation(layerIDs ids: [UUID]) -> Bool {
        ids.contains { id in
            guard let layer = layer(id: id) else { return false }
            if let turn = layer.turn3D, turn.rotationX != 0 || turn.rotationY != 0 { return true }
            return layer.keyedMotion(.rotationX) != nil || layer.keyedMotion(.rotationY) != nil
        }
    }

    /// Layer, Reset 3D Rotation: each of `ids` faces the camera again. Its
    /// Rotation X and Y keys go too, because a key would turn it straight
    /// back; its depth stays where it is.
    public mutating func resetSpaceRotation(layerIDs ids: [UUID]) {
        for id in ids {
            updateLayer(id: id) { edited in
                if let motions = edited.motions {
                    let kept = motions.filter { $0.property != .rotationX && $0.property != .rotationY }
                    edited.motions = kept.isEmpty ? nil : kept
                }
                guard var turn = edited.turn3D else { return }
                turn.rotationX = 0
                turn.rotationY = 0
                edited.turn3D = turn
                edited.settleTurn3D()
            }
        }
    }

    /// Bring Nearer (positive) and Send Further (negative): each of `ids`
    /// moves `step` points toward the camera, from where it shows at `ms`.
    public mutating func pushDepth(by step: Double, layerIDs ids: [UUID],
                                   atDocumentTimeMS ms: Int, ease: KeyEase? = nil) {
        for id in ids {
            guard let now = spaceValue(.depth, layerID: id, atDocumentTimeMS: ms) else { continue }
            setSpaceValue(.depth, now + step, layerIDs: [id], atDocumentTimeMS: ms, ease: ease)
        }
    }
}

extension Layer {
    /// Drops a turn that turns nothing and moves nothing, so a layer put back
    /// flat writes no turn at all.
    mutating func settleTurn3D() {
        guard let turn = turn3D else { return }
        if turn.rotationX == 0, turn.rotationY == 0, turn.depth == 0, turn.pivotDepth == 0,
           turn.showsBackFace == nil, turn.hinge == nil {
            turn3D = nil
        }
    }
}

// MARK: - The camera's keys, on the document's own clock

extension PhotonzDocument {

    /// The camera's value of one of its four properties at `ms`.
    public func cameraValue(_ property: MotionProperty, atDocumentTimeMS ms: Int) -> Double? {
        guard property.isCamera else { return nil }
        let camera = shownCamera
        if let keyed = camera.motions?.first(where: { $0.property == property }),
           case let .number(number) = keyed.value(atMS: ms, cycleMS: max(1, documentDurationMS)) {
            return number
        }
        if case let .number(number)? = camera.current(property) { return number }
        return nil
    }

    /// How many keys a camera value has.
    public func cameraKeyCount(_ property: MotionProperty) -> Int {
        camera?.motions?.first { $0.property == property }?.keyframes.count ?? 0
    }

    /// What the diamond beside a camera value shows with the playhead at `ms`.
    public func cameraKeyDiamond(_ property: MotionProperty, atDocumentTimeMS ms: Int) -> KeyDiamond {
        guard let keyed = camera?.motions?.first(where: { $0.property == property }) else { return .dormant }
        return keyed.keyframes.contains { abs($0.atMS - ms) <= PropertyKeys.nearMS } ? .onKey : .betweenKeys
    }

    /// A camera value set at `ms`: a key there where it is keyed, the
    /// camera's own value otherwise.
    public mutating func setCameraValue(_ property: MotionProperty, _ value: Double,
                                        atDocumentTimeMS ms: Int, ease: KeyEase? = nil) {
        guard property.isCamera, value.isFinite else { return }
        var camera = self.camera ?? .default
        if let keyed = camera.motions?.first(where: { $0.property == property }) {
            let bounded = SceneCamera.default.applying(.number(value), for: property).current(property)
                ?? .number(value)
            let next = keyed.settingKey(atMS: max(0, ms), value: bounded, ease: ease)
            camera.motions = camera.motions?.map { $0.id == keyed.id ? next : $0 }
        } else {
            camera = camera.applying(.number(value), for: property)
        }
        self.camera = camera
    }

    /// The camera value's diamond, clicked: not keyed, it starts keying with
    /// one key at `ms` holding what it shows; on a key, that key goes (the
    /// last one going leaves the value it held); between keys, a key is added.
    public mutating func toggleCameraKey(_ property: MotionProperty, atDocumentTimeMS ms: Int,
                                         ease: KeyEase? = nil) {
        guard property.isCamera, let value = cameraValue(property, atDocumentTimeMS: ms) else { return }
        var camera = self.camera ?? .default
        var motions = camera.motions ?? []
        switch cameraKeyDiamond(property, atDocumentTimeMS: ms) {
        case .dormant:
            motions.append(.keyed(property, atMS: max(0, ms), value: .number(value), ease: ease))
        case .betweenKeys:
            motions = motions.map {
                $0.property == property ? $0.settingKey(atMS: max(0, ms), value: .number(value), ease: ease) : $0
            }
        case .onKey:
            motions = motions.compactMap { motion in
                guard motion.property == property else { return motion }
                guard let next = motion.removingKey(atMS: ms) else {
                    camera = camera.applying(.number(value), for: property)
                    return nil
                }
                return next
            }
        }
        camera.motions = motions.isEmpty ? nil : motions
        self.camera = camera
    }

    /// Whether the camera has been changed from the one every document starts
    /// with: what View, Reset Camera has to put back.
    public var hasCameraChanges: Bool { camera.map { $0 != .default } ?? false }

    /// View, Reset Camera: the camera every document starts with, keys and
    /// all gone.
    public mutating func resetCamera() { camera = nil }
}

// MARK: - How tilted a layer is drawn

extension PhotonzDocument {

    /// How tilted a layer is DRAWN at `ms`: the longer of each pair of
    /// opposite edges of the quad the camera sees it as, over the shorter,
    /// whichever pair differs more. 1 for a layer drawn flat or only pushed
    /// straight back; above 1 once its near edge is taller than its far one.
    /// What a walk reads to claim a keyed tilt really plays.
    public func drawnTilt(of id: UUID, atDocumentTimeMS ms: Int) -> Double {
        let posed = hasTime ? posedForCanvas(atTimeMS: ms) : self
        guard let quad = posed.drawnQuad(of: id), quad.count == 4 else { return 1 }
        func length(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(b.x - a.x, b.y - a.y)) }
        let edges = (0..<4).map { length(quad[$0], quad[($0 + 1) % 4]) }
        func ratio(_ a: Double, _ b: Double) -> Double {
            guard min(a, b) > 1e-9 else { return 1 }
            return max(a, b) / min(a, b)
        }
        return max(ratio(edges[0], edges[2]), ratio(edges[1], edges[3]))
    }
}
