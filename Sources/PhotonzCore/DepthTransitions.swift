import CoreGraphics
import Foundation

// Transitions that turn in depth (task
// `3d-transitions-and-title-entrances-flip-cube-swi`, `docs/design/space-3d.md`).
//
// Flip, Cube, Swing, Doorway, Revolve and Push in Depth are made of nothing but
// the 2.5D model: each shot (or each half of one, for a doorway's doors) is the
// same clip turned about X or Y and moved in depth, exactly as a person could
// turn it by hand (`LayerTurn3D`). So the renderer draws them with the warp it
// already has, the camera's depth of field already softens what goes far away,
// and the canvas, playback and the export all read this one file.
//
// **One rule keeps every one of them inside the frame**: nothing comes nearer
// the viewer than the canvas itself. Where a turn would swing an edge toward
// the camera, the whole move backs off into depth by exactly that much, so the
// nearest edge rides along the glass and the picture is never bigger than the
// shot it started as. Only the doorway's doors break it, on purpose, and they
// fade out as they open past you.
//
// **Which way.** `direction` is the way the outgoing shot leaves; the incoming
// one arrives from the other side. In this file an angle is measured so
// that a positive one takes the LEADING edge (the edge facing the way the move
// goes) away from the viewer, whichever axis that is.

/// One picture of a transition in depth at one moment.
public struct DepthTransitionPart: Hashable, Sendable {
    public enum Shot: Hashable, Sendable { case outgoing, incoming }

    public var shot: Shot
    /// The part of the shot drawn, as a fraction of its box: all of it, or one
    /// door.
    public var window: CGRect
    /// How far the part is carried across the canvas, as a fraction of the
    /// shot's own width and height.
    public var shift: CGPoint
    /// Its turn, with depths in document points. A hinge is a fraction of the
    /// part's own box.
    public var turn: LayerTurn3D
    public var opacity: Double

    public init(shot: Shot, window: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                shift: CGPoint = .zero, turn: LayerTurn3D, opacity: Double = 1) {
        self.shot = shot
        self.window = window
        self.shift = shift
        self.turn = turn
        self.opacity = opacity
    }

    /// Whether this is the whole shot rather than a part of it.
    public var isWhole: Bool { window == CGRect(x: 0, y: 0, width: 1, height: 1) }
}

public enum DepthTransition {

    /// The pictures `kind` is made of, `progress` of the way through (already
    /// run through its curve), for shots `size` points big, in the order they
    /// are drawn. Empty for a kind that does not turn in depth.
    public static func parts(_ kind: ClipTransitionKind, direction: TitleDirection,
                             progress: Double, size: CGSize) -> [DepthTransitionPart] {
        let p = min(max(progress, 0), 1)
        let axis = Axis(direction)
        let length = Double(axis.horizontal ? size.width : size.height)
        let half = length / 2
        switch kind {
        case .flip:
            // A card with the outgoing shot on its front and the incoming one
            // on its back, turned over about its middle. Each face hides once
            // it faces away.
            let angle = 180 * p
            let back = -half * abs(sin(p * .pi))
            return [
                DepthTransitionPart(shot: .outgoing, turn: axis.turn(angle, depth: back, showsBack: false)),
                DepthTransitionPart(shot: .incoming, turn: axis.turn(angle - 180, depth: back, showsBack: false)),
            ]
        case .cube:
            // Two faces of a box as deep as the shot is wide, turning about
            // the box's middle (half the shot behind each face).
            // It backs off a little more toward its middle (the mock's
            // "Depth backs off a little at the midpoint"): with the camera as
            // near as a 45 degree view puts it, the face coming round is seen
            // from behind until the box is far enough away to show its side.
            let angle = 90 * p
            let r = angle * .pi / 180
            let back = -half * (sin(r) + cos(r) - 1) - 0.3 * length * sin(p * .pi)
            let out = DepthTransitionPart(shot: .outgoing,
                                          turn: axis.turn(angle, depth: back, pivotDepth: -half, showsBack: false))
            let into = DepthTransitionPart(shot: .incoming,
                                           turn: axis.turn(angle - 90, depth: back, pivotDepth: -half,
                                                           showsBack: false))
            // The face turning away goes first, so the one coming round is
            // drawn over it.
            return p < 0.5 ? [into, out] : [out, into]
        case .swing:
            // The outgoing shot is a door on its leading edge, swinging its far
            // edge away; the incoming one comes forward underneath.
            let out = DepthTransitionPart(shot: .outgoing,
                                          turn: axis.turn(-90 * p, hinge: axis.leading),
                                          opacity: fade(p, from: 0.85))
            let into = DepthTransitionPart(shot: .incoming, turn: axis.turn(0, depth: -0.35 * length * (1 - p)))
            return [into, out]
        case .doorway:
            // The outgoing shot parts down the middle into two doors hinged
            // on its outer edges that open toward you, and the incoming one
            // comes forward through them.
            let opening = 70 * p
            let into = DepthTransitionPart(shot: .incoming, turn: axis.turn(0, depth: -0.5 * length * (1 - p)))
            let fades = fade(p, from: 0.5)
            let doors: [DepthTransitionPart] = axis.horizontal
                ? [DepthTransitionPart(shot: .outgoing, window: CGRect(x: 0, y: 0, width: 0.5, height: 1),
                                       turn: LayerTurn3D(rotationY: -opening, hinge: CGPoint(x: 0, y: 0.5)),
                                       opacity: fades),
                   DepthTransitionPart(shot: .outgoing, window: CGRect(x: 0.5, y: 0, width: 0.5, height: 1),
                                       turn: LayerTurn3D(rotationY: opening, hinge: CGPoint(x: 1, y: 0.5)),
                                       opacity: fades)]
                : [DepthTransitionPart(shot: .outgoing, window: CGRect(x: 0, y: 0, width: 1, height: 0.5),
                                       turn: LayerTurn3D(rotationX: opening, hinge: CGPoint(x: 0.5, y: 0)),
                                       opacity: fades),
                   DepthTransitionPart(shot: .outgoing, window: CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                                       turn: LayerTurn3D(rotationX: -opening, hinge: CGPoint(x: 0.5, y: 1)),
                                       opacity: fades)]
            return [into] + doors
        case .revolve:
            // A revolving door: the outgoing shot swings away on its leading
            // edge while the incoming one swings in on its trailing edge,
            // both turning away from you, never toward.
            let leaves = min(p / 0.7, 1)
            let arrives = min(max((p - 0.3) / 0.7, 0), 1)
            let out = DepthTransitionPart(shot: .outgoing, turn: axis.turn(-90 * leaves, hinge: axis.leading),
                                          opacity: fade(p, from: 0.6, to: 0.7))
            let into = DepthTransitionPart(shot: .incoming,
                                           turn: axis.turn(90 * (1 - arrives), hinge: axis.trailing),
                                           opacity: p < 0.3 ? 0 : min(1, (p - 0.3) / 0.1))
            return [out, into]
        case .pushInDepth:
            // Both shots sink back, slide the way the move goes turned like
            // cards on a carousel, and the incoming one comes forward. Each
            // sinks at least as far as its near edge has swung toward you, so
            // the one still off the frame never reaches across it.
            let sink = 0.6 * length * sin(p * .pi)
            let travel = axis.travel
            let leaving = 45 * p, arriving = 45 * (1 - p)
            let out = DepthTransitionPart(shot: .outgoing, shift: CGPoint(x: travel.x * p, y: travel.y * p),
                                          turn: axis.turn(leaving, depth: -max(sink, half * sin(leaving * .pi / 180))))
            let into = DepthTransitionPart(shot: .incoming,
                                           shift: CGPoint(x: -travel.x * (1 - p), y: -travel.y * (1 - p)),
                                           turn: axis.turn(-arriving,
                                                           depth: -max(sink, half * sin(arriving * .pi / 180))))
            return [out, into]
        case .dissolve, .dipToBlack, .dipToWhite, .push, .wipe, .blurThrough:
            return []
        }
    }

    /// Where each part lands on a canvas exactly the size of the shots, seen
    /// through the default camera: what a picker tile draws, and what the
    /// tests measure. A part whose corners pass the eye has no quad.
    public static func quads(_ kind: ClipTransitionKind, direction: TitleDirection, progress: Double,
                             size: CGSize, camera: SceneCamera? = nil)
        -> [(part: DepthTransitionPart, quad: [CGPoint]?)] {
        let projection = Projection3D(camera: camera, canvas: size)
        return parts(kind, direction: direction, progress: progress, size: size).map { part in
            let box = CGRect(x: (part.window.minX + part.shift.x) * size.width,
                             y: (part.window.minY + part.shift.y) * size.height,
                             width: part.window.width * size.width, height: part.window.height * size.height)
            let pivot = part.turn.hinge.map {
                CGPoint(x: box.minX + box.width * $0.x, y: box.minY + box.height * $0.y)
            } ?? CGPoint(x: box.midX, y: box.midY)
            var quad = Space3D.quad(of: box, through: part.turn.affine(pivot: pivot), projection)
            if let found = quad, part.turn.showsBackFace == false, !Space3D.facesViewer(found) { quad = nil }
            return (part, quad)
        }
    }

    /// One up to `from`, then down to nought by `to`.
    private static func fade(_ p: Double, from: Double, to: Double = 1) -> Double {
        guard p > from else { return 1 }
        return max(0, 1 - (p - from) / max(0.0001, to - from))
    }

    /// The axis a direction turns about, and which edge leads.
    private struct Axis {
        let horizontal: Bool
        /// One where the leading edge is the top or left one.
        let sign: Double
        let travel: CGPoint

        init(_ direction: TitleDirection) {
            horizontal = direction == .left || direction == .right
            sign = direction == .left || direction == .up ? 1 : -1
            travel = direction.vector
        }

        /// The middle of the edge facing the way the move goes.
        var leading: CGPoint {
            horizontal ? CGPoint(x: sign > 0 ? 0 : 1, y: 0.5) : CGPoint(x: 0.5, y: sign > 0 ? 0 : 1)
        }

        /// The middle of the edge it moves away from.
        var trailing: CGPoint { CGPoint(x: 1 - leading.x, y: 1 - leading.y) }

        /// A turn of `angle` degrees taking the leading edge away. Positive Y
        /// takes the right edge away and positive X the top one.
        func turn(_ angle: Double, depth: Double = 0, pivotDepth: Double = 0, showsBack: Bool? = nil,
                  hinge: CGPoint? = nil) -> LayerTurn3D {
            horizontal
                ? LayerTurn3D(rotationY: -sign * angle, depth: depth, pivotDepth: pivotDepth,
                              showsBackFace: showsBack, hinge: hinge)
                : LayerTurn3D(rotationX: sign * angle, depth: depth, pivotDepth: pivotDepth,
                              showsBackFace: showsBack, hinge: hinge)
        }
    }
}

// MARK: - Drawn as ordinary layers

extension Layer {

    /// The pictures of a transition in depth, as ordinary layers: each shot
    /// turned the way `DepthTransition.parts` says, a door drawn through a
    /// window of its half. The clip's own look (corners, effects) goes with
    /// each picture, because each picture IS the clip.
    public static func depthTransitionDrawn(_ kind: ClipTransitionKind, direction: TitleDirection, progress: Double,
                                     outgoing: Layer, incoming: Layer) -> [Layer] {
        var doors = 0
        return DepthTransition.parts(kind, direction: direction, progress: progress,
                                     size: outgoing.frame.size).compactMap { part in
            guard part.opacity > 0.001 else { return nil }
            let shot = part.shot == .outgoing ? outgoing : incoming
            let dx = part.shift.x * shot.frame.width, dy = part.shift.y * shot.frame.height
            if part.isWhole {
                var drawn = shot
                drawn.frame = shot.frame.offsetBy(dx: dx, dy: dy)
                drawn.turn3D = part.turn
                drawn.style.opacity = shot.style.opacity * part.opacity
                return drawn
            }
            // A door: the shot inside a window of its own part, and the window
            // is what turns.
            let window = CGRect(x: shot.frame.minX + part.window.minX * shot.frame.width + dx,
                                y: shot.frame.minY + part.window.minY * shot.frame.height + dy,
                                width: part.window.width * shot.frame.width,
                                height: part.window.height * shot.frame.height)
            guard window.width >= 0.5, window.height >= 0.5 else { return nil }
            var inside = shot
            inside.frame = shot.frame.offsetBy(dx: dx - window.minX, dy: dy - window.minY)
            defer { doors += 1 }
            let id = doors == 0 ? Layer.transitionWindowID(of: shot.id)
                : Layer.transitionWindowID(of: Layer.transitionPartnerID(of: shot.id))
            var door = Layer(id: id, name: shot.name,
                             content: .group(GroupContent(children: [inside], isFrame: true)),
                             frame: window, isVisible: true, isLocked: true)
            door.turn3D = part.turn
            door.style.opacity = part.opacity
            return door
        }
    }
}

// MARK: - Smeared while the shutter is open

extension Layer {

    /// How long the shutter is open over a transition with its motion blur
    /// on: a 180 degree shutter, the one Motion Blur starts at.
    static var transitionShutterMS: Double { MotionBlurEffect.startingAngle / 360 * MotionBlurEffect.frameMS }

    /// The pictures of a transition at `ms`, each told where it went while the
    /// shutter was open (`MotionSmear.swift`), measured where the camera sees
    /// it. `drawnAt` is the same transition's pictures at another whole
    /// millisecond, nil once it is not running there.
    static func smearedTransition(_ pictures: [Layer], atMS ms: Int, projection: Projection3D,
                                  drawnAt: (Int) -> [Layer]?) -> [Layer] {
        let shutter = transitionShutterMS
        let from = Int((Double(ms) - shutter / 2).rounded(.down))
        let to = Int((Double(ms) + shutter / 2).rounded(.up))
        let reads = (from...to).map { $0 == ms ? pictures : (drawnAt($0) ?? pictures) }
        let clock = SmearClock(fromMS: from, moment: ms)
        return pictures.map { picture in
            guard picture.isVisible else { return picture }
            let quads = reads.map { read -> [CGPoint] in
                let then = read.first { $0.id == picture.id } ?? picture
                return then.drawnQuad(origin: .zero, sizedLike: picture, projection: projection)
            }
            var smeared = picture
            smeared.motionSmear = MotionSmear.across(quads: quads, clock: clock, shutterMS: shutter)
            return smeared
        }
    }
}
