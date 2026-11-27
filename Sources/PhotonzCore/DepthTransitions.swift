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
    /// How much light falls on it: one square on to the viewer, less the
    /// further it has turned away, the way a card turned from a lamp darkens.
    public var light: Double
    /// How far it has lifted off where it rests, nought to one: how strong the
    /// soft shadow it casts is. Nought at both ends of every move, so nothing
    /// appears or vanishes as a move starts or lands.
    public var lift: Double

    public init(shot: Shot, window: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                shift: CGPoint = .zero, turn: LayerTurn3D, opacity: Double = 1,
                light: Double = 1, lift: Double = 0) {
        self.shot = shot
        self.window = window
        self.shift = shift
        self.turn = turn
        self.opacity = opacity
        self.light = light
        self.lift = lift
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
        // Lifted most in the middle of the move and not at all at its ends.
        let lift = p <= 0 || p >= 1 ? 0 : sin(p * .pi)
        return turnedParts(kind, direction: direction, progress: p, size: size).map { part in
            var lit = part
            lit.light = light(part.turn)
            lit.lift = lift
            return lit
        }
    }

    /// How much light falls on a plane turned `turn`: all of it square on,
    /// falling off with the cosine of the angle to a little under half edge
    /// on, never to black (Final Cut's doors and Keynote's cube both darken
    /// a face as it turns away, which is most of what makes them read as
    /// solid).
    static func light(_ turn: LayerTurn3D) -> Double {
        let angle = max(abs(turn.rotationX), abs(turn.rotationY)).truncatingRemainder(dividingBy: 360)
        let facing = angle > 90 ? max(0, 180 - angle) : angle
        guard facing > 0.01 else { return 1 }
        return 0.45 + 0.55 * cos(facing * .pi / 180)
    }

    /// Nought up to `from`, one from `to`, eased both ways between: how an
    /// incoming shot fades in, so it settles onto the picture instead of
    /// landing on it at full strength (the user, 2026-11-26: "3d transitions
    /// wouldn't fade in and would immediately cover content").
    static func fadeIn(_ p: Double, from: Double, to: Double) -> Double {
        guard p > from else { return 0 }
        guard p < to else { return 1 }
        let x = (p - from) / (to - from)
        return x * x * (3 - 2 * x)
    }

    private static func turnedParts(_ kind: ClipTransitionKind, direction: TitleDirection,
                                    progress p: Double, size: CGSize) -> [DepthTransitionPart] {
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
                DepthTransitionPart(shot: .incoming, turn: axis.turn(angle - 180, depth: back, showsBack: false),
                                    opacity: fadeIn(p, from: 0.5, to: 0.93)),
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
                                                           showsBack: false),
                                           opacity: fadeIn(p, from: 0.1, to: 0.85))
            // The face turning away goes first, so the one coming round is
            // drawn over it.
            return p < 0.5 ? [into, out] : [out, into]
        case .swing:
            // The outgoing shot is a door on its leading edge, swinging its far
            // edge away; the incoming one comes forward underneath.
            let out = DepthTransitionPart(shot: .outgoing,
                                          turn: axis.turn(-90 * p, hinge: axis.leading),
                                          opacity: fade(p, from: 0.85))
            let into = DepthTransitionPart(shot: .incoming, turn: axis.turn(0, depth: -0.35 * length * (1 - p)),
                                           opacity: fadeIn(p, from: 0, to: 0.65))
            return [into, out]
        case .doorway:
            // The outgoing shot parts down the middle into two doors hinged
            // on its outer edges that open toward you, and the incoming one
            // comes forward through them.
            // Doors take the curve's rush evenly: everything here runs on
            // `even`, which is quick where the curve is slow and slow where it
            // rushes, so the gap between the doors and the shot coming through
            // it open at an even pace instead of all within a few frames
            // (`DepthTransitionEaseRenderTests`: before, a sixth of the frame
            // and more appeared between two frames).
            let even = acos(1 - 2 * p) / .pi
            let opening = 70 * even
            let into = DepthTransitionPart(shot: .incoming, turn: axis.turn(0, depth: -0.5 * length * (1 - p)),
                                           opacity: fadeIn(even, from: 0, to: 0.8))
            // Fading from early and gone before they sweep past the edges of
            // the frame, which is where a door near the camera moves fastest.
            let fades = fade(even, from: 0.2, to: 0.85)
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
                                          opacity: fade(p, from: 0.5, to: 0.8))
            let into = DepthTransitionPart(shot: .incoming,
                                           turn: axis.turn(90 * (1 - arrives), hinge: axis.trailing),
                                           opacity: fadeIn(p, from: 0.3, to: 0.85))
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
                                                           depth: -max(sink, half * sin(arriving * .pi / 180))),
                                           opacity: fadeIn(p, from: 0, to: 0.65))
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
    /// window of its half. The clip's own look (frame, corners, effects, its
    /// own tilt) goes with each picture, because each picture IS the clip.
    ///
    /// Each turned plane is lit by how far it has turned from the viewer and,
    /// lifted off its rest, casts a soft shadow, unless the clip casts one of
    /// its own. Given the `canvas`, and two shots that fill it, the space the
    /// move opens up is filled with the two shots themselves, blurred, dimmed
    /// and crossing over, rather than left black: what is behind a card in
    /// Apple's own product films is never a void (task
    /// `3d-transitions-ease-in-and-out-of-the-picture-in`). Leave it out where
    /// the edit has a picture of its own under the shots.
    public static func depthTransitionDrawn(_ kind: ClipTransitionKind, direction: TitleDirection, progress: Double,
                                            outgoing: Layer, incoming: Layer, canvas: CGSize? = nil) -> [Layer] {
        let p = min(max(progress, 0), 1)
        var drawn: [Layer] = []
        if let canvas {
            let arriving = DepthTransition.fadeIn(p, from: 0.05, to: 0.9)
            if outgoing.fillsTheFrame(of: canvas), incoming.fillsTheFrame(of: canvas) {
                // Two whole-frame shots: the space behind is each one's own
                // box, so the bars beside a recording stay black.
                drawn.append(outgoing.transitionBackdrop(amount: 1))
                drawn.append(incoming.transitionBackdrop(amount: arriving))
            } else {
                // A framed card turning over nothing: the frame glows with the
                // two shots' own colours while the move runs, rising from
                // nothing and settling back to it, so the card sits on what it
                // sat on at both ends and the middle of a flip is never black
                // (the intake's flip-14s-black-void.png was a framed card).
                let swell = sin(p * .pi)
                let fill = CGRect(origin: .zero, size: canvas)
                if swell > 0.001 {
                    drawn.append(outgoing.transitionBackdrop(amount: swell, filling: fill))
                    drawn.append(incoming.transitionBackdrop(amount: swell * arriving, filling: fill))
                }
            }
        }
        var doors = 0
        for part in DepthTransition.parts(kind, direction: direction, progress: p, size: outgoing.frame.size)
        where part.opacity > 0.001 {
            let shot = part.shot == .outgoing ? outgoing : incoming
            let dx = part.shift.x * shot.frame.width, dy = part.shift.y * shot.frame.height
            if part.isWhole {
                var plane = shot
                plane.frame = shot.frame.offsetBy(dx: dx, dy: dy)
                plane.style.opacity = shot.style.opacity * part.opacity
                plane.lit(by: part)
                guard let own = shot.turn3D, !own.isFlat else {
                    plane.turn3D = part.turn
                    drawn.append(plane)
                    continue
                }
                // A clip with a tilt of its own keeps it: the move turns a
                // card that holds the clip, turned as it was, so the two turns
                // compose the way a hand turning a tilted card would.
                plane.frame.origin = .zero
                plane.turn3D?.showsBackFace = part.turn.showsBackFace
                var holds = GroupContent(children: [plane])
                holds.keeps3D = true
                var holder = Layer(id: Layer.transitionHolderID(of: shot.id), name: shot.name,
                                   content: .group(holds),
                                   frame: shot.frame.offsetBy(dx: dx, dy: dy), isVisible: true, isLocked: true)
                holder.turn3D = part.turn
                drawn.append(holder)
                continue
            }
            // A door: the shot inside a window of its own part, and the window
            // is what turns. A card that hangs past its own box (a tilt, a
            // shadow) gets windows that reach past it on every side but the
            // one where the doors part, so nothing of it is cut off.
            let reach = shot.hangsPastItsBox ? 0.25 * max(shot.frame.width, shot.frame.height) : 0
            let part0 = CGRect(x: shot.frame.minX + part.window.minX * shot.frame.width + dx,
                               y: shot.frame.minY + part.window.minY * shot.frame.height + dy,
                               width: part.window.width * shot.frame.width,
                               height: part.window.height * shot.frame.height)
            let box = shot.frame.offsetBy(dx: dx, dy: dy)
            let minX = part0.minX <= box.minX + 0.5 ? part0.minX - reach : part0.minX
            let minY = part0.minY <= box.minY + 0.5 ? part0.minY - reach : part0.minY
            let maxX = part0.maxX >= box.maxX - 0.5 ? part0.maxX + reach : part0.maxX
            let maxY = part0.maxY >= box.maxY - 0.5 ? part0.maxY + reach : part0.maxY
            let window = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            guard part0.width >= 0.5, part0.height >= 0.5 else { continue }
            var inside = shot
            inside.frame = shot.frame.offsetBy(dx: dx - window.minX, dy: dy - window.minY)
            let id = doors == 0 ? Layer.transitionWindowID(of: shot.id)
                : Layer.transitionWindowID(of: Layer.transitionPartnerID(of: shot.id))
            doors += 1
            var door = Layer(id: id, name: shot.name,
                             content: .group(GroupContent(children: [inside], isFrame: true)),
                             frame: window, isVisible: true, isLocked: true)
            var turn = part.turn
            // The hinge, where the part said, measured in the wider window.
            if let hinge = part.turn.hinge {
                let point = CGPoint(x: part0.minX + part0.width * hinge.x, y: part0.minY + part0.height * hinge.y)
                turn.hinge = CGPoint(x: (point.x - window.minX) / window.width,
                                     y: (point.y - window.minY) / window.height)
            }
            door.turn3D = turn
            door.style.opacity = part.opacity
            door.lit(by: part, castsOwnShadow: !shot.style.shadows.isEmpty)
            drawn.append(door)
        }
        return drawn
    }

    /// Whether this shot is a whole-frame picture of `canvas` the move can
    /// open up: upright, unturned, covering most of it (a recording between
    /// bars, or a title page), rather than a card framed on something.
    func fillsTheFrame(of canvas: CGSize) -> Bool {
        guard canvas.width > 0, canvas.height > 0, turn3D?.isFlat ?? true, transform.isIdentity else { return false }
        // A group (a title page) is as big as what it holds.
        let seen = (isGroup ? localBounds : frame).intersection(CGRect(origin: .zero, size: canvas))
        guard !seen.isNull else { return false }
        return seen.width * seen.height >= 0.75 * canvas.width * canvas.height
    }

    /// Whether this layer, as a moment has it, puts any picture on screen: it
    /// is switched on and is not a sound. What decides whether a move in depth
    /// above it may fill the space it opens up with its own backdrop.
    var drawsAPicture: Bool {
        guard isVisible else { return false }
        if case .sound = content { return false }
        return true
    }

    /// Whether anything of this layer is drawn past its own box: a tilt or a
    /// shadow.
    var hangsPastItsBox: Bool {
        !(turn3D?.isFlat ?? true) || !style.shadows.isEmpty || style.blurRadius > 0
    }

    /// How dark the space behind a move is: the shots at half their
    /// brightness, so whatever turns in front reads as nearer and lit and the
    /// back never competes with it, while a dark title page behind a move
    /// still reads as its own colour rather than as black.
    static let transitionBackdropStops = -1.0

    /// How soft it is: a few percent of the shot, enough that nothing in it
    /// can be read, the way a picture far behind the focus is.
    static func transitionBackdropBlur(_ frame: CGRect) -> CGFloat {
        max(6, min(frame.width, frame.height) * 0.035)
    }

    /// This shot, flat where it lives, blurred and dimmed: what fills the
    /// space a move in depth opens up. Its blur is a photograph's, held to its
    /// own box, so the black bars beside a recording stay black.
    ///
    /// `filling`, given, is a box it is stretched to cover instead, keeping
    /// its own shape (a framed card's glow behind it fills the frame).
    func transitionBackdrop(amount: Double, filling box: CGRect? = nil) -> Layer {
        var place = frame
        var look = style
        if let box, frame.width > 0, frame.height > 0 {
            let scale = max(box.width / frame.width, box.height / frame.height)
            let size = CGSize(width: frame.width * scale, height: frame.height * scale)
            place = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                           width: size.width, height: size.height)
            look.cornerRadii = .none
        }
        var back = Layer(id: Layer.transitionBackdropID(of: id), name: "\(name) backdrop", content: content,
                         frame: place, crop: crop, transform: box == nil ? transform : .identity, style: look,
                         isVisible: true, isLocked: true, placement: placement)
        back.movie = movie
        back.style.shadows = []
        back.style.opacity = style.opacity * amount
        // A group (a title page) is as big as what it holds, not its frame.
        back.style.blurRadius = max(style.blurRadius,
                                    Self.transitionBackdropBlur(box == nil && isGroup ? localBounds : place))
        back.darken(byStops: Self.transitionBackdropStops)
        return back
    }

    /// Lit as `part` says: darkened as it turns away, and casting a soft
    /// shadow as it lifts, unless it already casts one of its own.
    mutating func lit(by part: DepthTransitionPart, castsOwnShadow: Bool? = nil) {
        if part.light < 0.995 { darken(byStops: log2(max(part.light, 0.05))) }
        let owns = castsOwnShadow ?? !style.shadows.isEmpty
        guard !owns, part.lift > 0.01 else { return }
        let size = min(frame.width, frame.height)
        style.shadow = ShadowStyle(radius: max(4, size * 0.05), offset: CGSize(width: 0, height: size * 0.03),
                                   opacity: 0.5 * part.lift)
    }

    /// This layer's picture taken down `stops` of exposure, on top of any
    /// grade it already has.
    mutating func darken(byStops stops: Double) {
        if let index = style.effects.firstIndex(where: { $0.colorGrade?.paints == true }),
           var grade = style.effects[index].colorGrade {
            grade.exposure += stops
            style.effects[index] = .colorGrade(grade)
        } else {
            style.effects.append(.colorGrade(ColorGradeEffect(exposure: stops)))
        }
    }

    /// The id the card holding a tilted clip through a move is drawn under.
    static func transitionHolderID(of id: UUID) -> UUID { transitionID(of: id, flipping: (2, 13), by: 0x3C) }

    /// The id a shot's backdrop is drawn under.
    static func transitionBackdropID(of id: UUID) -> UUID { transitionID(of: id, flipping: (3, 12), by: 0x69) }

    private static func transitionID(of id: UUID, flipping bytes: (Int, Int), by mask: UInt8) -> UUID {
        var raw = withUnsafeBytes(of: id.uuid) { Array($0) }
        raw[bytes.0] ^= mask
        raw[bytes.1] ^= mask
        return UUID(uuid: (raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
                           raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]))
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
