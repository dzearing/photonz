import CoreGraphics
import Foundation

// MARK: - 2.5D: flat layers turned and moved in space, seen through one camera
//
// Keynote's and Apple Motion's kind of 3D, not a modelling app's: every layer
// stays a flat card. It can tip about its sideways axis (Rotation X), swing
// about its upright one (Rotation Y) and move nearer or further away (Depth),
// and the whole frame is seen through one camera with real perspective
// (`docs/design/mocks/pages/video-depth.html`).
//
// Coordinates are the document's: x to the right, y DOWN, and z toward the
// viewer, so a layer with a positive depth is nearer and draws bigger. The
// canvas itself is the plane z = 0, and the camera looks straight at it from
// in front, so anything left at depth 0 and unturned projects onto exactly the
// pixels it covers today. That is the whole of the compatibility promise: a
// document nobody has turned in 3D looks exactly as it did.
//
// Nothing here is pixels. The renderer asks this file where a layer's four
// corners land (`Space3D.quad`) and warps the layer's finished picture onto
// them; the outline, the click and the export ask the same question, so none
// of them can put a turned layer anywhere the others do not.

/// How one layer is turned and placed in depth.
///
/// Nil on a layer is the common case and always means flat, so a layer that
/// has never been turned writes nothing and reads back byte for byte the same.
public struct LayerTurn3D: Hashable, Codable, Sendable {
    /// Tip about the sideways axis, in degrees. Positive tips the TOP edge
    /// away from the viewer, the way CSS's `rotateX` does.
    public var rotationX: Double
    /// Swing about the upright axis, in degrees. Positive swings the RIGHT
    /// edge away from the viewer, the way CSS's `rotateY` does.
    public var rotationY: Double
    /// How far toward the viewer, in document points. Negative is further
    /// away, which is where a title swinging in from depth starts.
    public var depth: Double
    /// How far in front of the layer the point it turns about sits, in
    /// document points: the pivot crosshair's depth arrow. A cube's face turns
    /// about the middle of the cube, which is half its width BEHIND the face,
    /// so a negative number.
    public var pivotDepth: Double
    /// Whether the layer is still drawn once it has turned its back on the
    /// viewer. Nil is yes, which is what CSS and Motion do: a card flipped
    /// over shows its picture mirrored. Off is how a two sided card is made,
    /// a front and a back laid back to back, each hiding when it faces away.
    public var showsBackFace: Bool?
    /// Where on its box the layer turns in space, as a fraction of the box
    /// (`(0, 0.5)` is the middle of its left edge): a hinge. Nil turns it
    /// about the same point its flat turn takes (`Layer.turnPivot`), which is
    /// every turn made by hand. A door, a swing and a title hinged at an edge
    /// set it (`DepthTransitions.swift`, `TitleDesign.swift`).
    public var hinge: CGPoint?

    public init(rotationX: Double = 0, rotationY: Double = 0, depth: Double = 0,
                pivotDepth: Double = 0, showsBackFace: Bool? = nil, hinge: CGPoint? = nil) {
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.depth = depth
        self.pivotDepth = pivotDepth
        self.showsBackFace = showsBackFace
        self.hinge = hinge
    }

    /// Nothing turned and nothing moved: the layer sits on the canvas as it
    /// always did. A pivot depth on its own moves nothing, because there is no
    /// turn to take about it.
    public var isFlat: Bool {
        Self.isNought(rotationX) && Self.isNought(rotationY) && Self.isNought(depth)
    }

    /// Whether the back of this layer is drawn when it faces away.
    public var drawsBackFace: Bool { showsBackFace ?? true }

    private static func isNought(_ value: Double) -> Bool { !value.isFinite || abs(value) < 1e-9 }

    private enum CodingKeys: String, CodingKey {
        case rotationX, rotationY, depth, pivotDepth, showsBackFace, hinge
    }

    /// Only what is not nought is written, so a layer turned about Y alone
    /// writes one number.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if rotationX != 0 { try c.encode(rotationX, forKey: .rotationX) }
        if rotationY != 0 { try c.encode(rotationY, forKey: .rotationY) }
        if depth != 0 { try c.encode(depth, forKey: .depth) }
        if pivotDepth != 0 { try c.encode(pivotDepth, forKey: .pivotDepth) }
        try c.encodeIfPresent(showsBackFace, forKey: .showsBackFace)
        try c.encodeIfPresent(hinge, forKey: .hinge)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? 0
            return value.isFinite ? value : 0
        }
        rotationX = try number(.rotationX)
        rotationY = try number(.rotationY)
        depth = try number(.depth)
        pivotDepth = try number(.pivotDepth)
        showsBackFace = try c.decodeIfPresent(Bool.self, forKey: .showsBackFace)
        hinge = try c.decodeIfPresent(CGPoint.self, forKey: .hinge)
    }

    /// The turn as a move in space, about `pivot` (the 2D pivot, in the same
    /// canvas space the layer is drawn in) with the pivot depth in front of
    /// it: tip first, then swing, then the push toward the viewer.
    ///
    /// The 2D turn has already been taken by then, in the plane of the layer,
    /// so a card turned 10 degrees on the canvas and then swung about Y swings
    /// about the screen's upright, which is the axis the canvas handle drags.
    public func affine(pivot: CGPoint) -> Affine3D {
        let a = rotationX * .pi / 180
        let b = rotationY * .pi / 180
        let rx = Matrix3(1, 0, 0,
                         0, cos(a), -sin(a),
                         0, sin(a), cos(a))
        let ry = Matrix3(cos(b), 0, sin(b),
                         0, 1, 0,
                         -sin(b), 0, cos(b))
        let turn = ry * rx
        let mount = Point3D(x: Double(pivot.x), y: Double(pivot.y), z: pivotDepth)
        // Into the mount's own space, turned, back out, then pushed.
        let back = turn.apply(Point3D(x: -mount.x, y: -mount.y, z: -mount.z))
        return Affine3D(m: turn, t: Point3D(x: back.x + mount.x, y: back.y + mount.y,
                                            z: back.z + mount.z + depth))
    }

    /// This turn with every length multiplied by `scale`, for a document
    /// stated in a bigger unit (`PhotonzDocument.magnified(by:)`). Angles have
    /// no size.
    public func magnified(by scale: Double) -> LayerTurn3D {
        var turned = self
        turned.depth *= scale
        turned.pivotDepth *= scale
        return turned
    }
}

// MARK: - The camera

/// The one camera every frame is seen through: a setting of the frame, not a
/// layer (the decision card `...-where-does-the-camera-live`, option A).
///
/// Nil on a document is the default camera, which is what every document
/// written before this has: perspective on at 45 degrees, straight in front of
/// the canvas. A layer at depth 0 projects onto exactly the pixels it covers
/// whatever the perspective, so the default changes nothing until something
/// is turned.
public struct SceneCamera: Hashable, Codable, Sendable {
    /// How strong the perspective is, as the camera's angle of view top to
    /// bottom in degrees: Motion's Angle of View. Wider is stronger. Nought
    /// is no perspective at all, so a turned card foreshortens but its far
    /// edge is no smaller than its near one.
    public var perspective: Double
    /// How far the camera has been pushed in toward the canvas, in document
    /// points. Positive is a push in, which makes the whole frame bigger.
    public var depth: Double
    /// Where the camera has been moved across the canvas, in document points.
    /// Moving the camera right moves the picture left.
    public var x: Double
    public var y: Double
    /// Blur by distance from a depth that stays sharp, where it is on. Nil is
    /// everything sharp, which is every camera until somebody asks.
    public var focus: CameraFocus?
    /// The camera's keys, read with the same machinery as a layer's: the
    /// properties are the four camera ones (`MotionProperty.cameraProperties`),
    /// on the document's own clock.
    public var motions: [LayerMotion]?

    /// Motion's default angle of view.
    public static let defaultPerspective: Double = 45
    /// The widest the perspective may be: past this a near layer's edges run
    /// off to infinity faster than anybody could mean.
    public static let widestPerspective: Double = 150

    public static let `default` = SceneCamera()

    public init(perspective: Double = SceneCamera.defaultPerspective, depth: Double = 0,
                x: Double = 0, y: Double = 0, focus: CameraFocus? = nil,
                motions: [LayerMotion]? = nil) {
        self.perspective = perspective
        self.depth = depth
        self.x = x
        self.y = y
        self.focus = focus
        self.motions = motions
    }

    /// Whether the camera sees the canvas exactly as it is: not moved, not
    /// pushed. The perspective does not matter to that, because the canvas
    /// plane is where the perspective is measured from.
    public var leavesTheCanvasAlone: Bool { depth == 0 && x == 0 && y == 0 }

    private enum CodingKeys: String, CodingKey {
        case perspective, depth, x, y, focus, motions
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(perspective, forKey: .perspective)
        if depth != 0 { try c.encode(depth, forKey: .depth) }
        if x != 0 { try c.encode(x, forKey: .x) }
        if y != 0 { try c.encode(y, forKey: .y) }
        try c.encodeIfPresent(focus, forKey: .focus)
        if let motions, !motions.isEmpty { try c.encode(motions, forKey: .motions) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, _ fallback: Double) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: key) ?? fallback
            return value.isFinite ? value : fallback
        }
        perspective = try number(.perspective, Self.defaultPerspective)
        depth = try number(.depth, 0)
        x = try number(.x, 0)
        y = try number(.y, 0)
        focus = try c.decodeIfPresent(CameraFocus.self, forKey: .focus)
        motions = try c.decodeIfPresent([LayerMotion].self, forKey: .motions)
    }

    /// The camera's value of one of its properties, or nil for a property
    /// that is not the camera's.
    public func current(_ property: MotionProperty) -> MotionValue? {
        switch property {
        case .cameraPerspective: .number(perspective)
        case .cameraDepth: .number(depth)
        case .cameraX: .number(x)
        case .cameraY: .number(y)
        default: nil
        }
    }

    /// The camera wearing `value` for `property`.
    public func applying(_ value: MotionValue, for property: MotionProperty) -> SceneCamera {
        guard case let .number(number) = value, number.isFinite else { return self }
        var moved = self
        switch property {
        case .cameraPerspective: moved.perspective = min(max(number, 0), Self.widestPerspective)
        case .cameraDepth: moved.depth = number
        case .cameraX: moved.x = number
        case .cameraY: moved.y = number
        default: break
        }
        return moved
    }

    /// The camera as it is `ms` along a clock whose lap is `cycleMS`: every
    /// key sampled, nothing stored.
    public func shown(atMS ms: Int, cycleMS: Int) -> SceneCamera {
        guard let motions, motions.contains(where: \.isOn) else { return self }
        var moved = self
        for motion in motions where motion.isOn {
            moved = moved.applying(motion.value(atMS: ms, cycleMS: cycleMS), for: motion.property)
        }
        return moved
    }

    /// This camera with every length multiplied by `scale`.
    public func magnified(by scale: Double) -> SceneCamera {
        var moved = self
        moved.depth *= scale
        moved.x *= scale
        moved.y *= scale
        moved.focus = focus?.magnified(by: scale)
        return moved
    }
}

/// Depth of field: one depth stays sharp, and everything blurs the further it
/// is from it.
public struct CameraFocus: Hashable, Codable, Sendable {
    /// The depth that stays sharp, in document points toward the viewer.
    public var depth: Double
    /// How soft, as points of blur for every hundred points away from it.
    public var amount: Double

    public init(depth: Double = 0, amount: Double = 4) {
        self.depth = depth
        self.amount = amount
    }

    /// The blur radius, in points, of something whose middle is at `z`.
    public func blurRadius(atDepth z: Double) -> Double {
        guard amount > 0, z.isFinite else { return 0 }
        return abs(z - depth) * amount / 100
    }

    public func magnified(by scale: Double) -> CameraFocus {
        // The amount is a ratio of blur to distance, both lengths, so only
        // the depth that stays sharp moves.
        CameraFocus(depth: depth * scale, amount: amount)
    }
}

// MARK: - The arithmetic

/// A point in space, in document points: x right, y down, z toward the viewer.
public struct Point3D: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ point: CGPoint, z: Double = 0) {
        self.init(x: Double(point.x), y: Double(point.y), z: z)
    }
}

/// A three by three matrix, rows first.
public struct Matrix3: Hashable, Sendable {
    public var e: [Double]

    public init(_ a: Double, _ b: Double, _ c: Double,
                _ d: Double, _ e: Double, _ f: Double,
                _ g: Double, _ h: Double, _ i: Double) {
        self.e = [a, b, c, d, e, f, g, h, i]
    }

    public static let identity = Matrix3(1, 0, 0, 0, 1, 0, 0, 0, 1)

    public func apply(_ p: Point3D) -> Point3D {
        Point3D(x: e[0] * p.x + e[1] * p.y + e[2] * p.z,
                y: e[3] * p.x + e[4] * p.y + e[5] * p.z,
                z: e[6] * p.x + e[7] * p.y + e[8] * p.z)
    }

    public static func * (l: Matrix3, r: Matrix3) -> Matrix3 {
        var out = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += l.e[row * 3 + k] * r.e[k * 3 + column] }
                out[row * 3 + column] = sum
            }
        }
        return Matrix3(out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7], out[8])
    }

    public var determinant: Double {
        e[0] * (e[4] * e[8] - e[5] * e[7])
            - e[1] * (e[3] * e[8] - e[5] * e[6])
            + e[2] * (e[3] * e[7] - e[4] * e[6])
    }

    /// The inverse, or nil for a matrix that squashes space flat.
    public var inverted: Matrix3? {
        let det = determinant
        guard abs(det) > 1e-12, det.isFinite else { return nil }
        let i = 1 / det
        return Matrix3(
            (e[4] * e[8] - e[5] * e[7]) * i, (e[2] * e[7] - e[1] * e[8]) * i, (e[1] * e[5] - e[2] * e[4]) * i,
            (e[5] * e[6] - e[3] * e[8]) * i, (e[0] * e[8] - e[2] * e[6]) * i, (e[2] * e[3] - e[0] * e[5]) * i,
            (e[3] * e[7] - e[4] * e[6]) * i, (e[1] * e[6] - e[0] * e[7]) * i, (e[0] * e[4] - e[1] * e[3]) * i)
    }
}

/// A move in space that keeps straight lines straight: a turn and a slide.
public struct Affine3D: Hashable, Sendable {
    public var m: Matrix3
    public var t: Point3D

    public init(m: Matrix3, t: Point3D) {
        self.m = m
        self.t = t
    }

    public static let identity = Affine3D(m: .identity, t: Point3D(x: 0, y: 0, z: 0))

    public var isIdentity: Bool { self == .identity }

    public func apply(_ p: Point3D) -> Point3D {
        let turned = m.apply(p)
        return Point3D(x: turned.x + t.x, y: turned.y + t.y, z: turned.z + t.z)
    }

    /// This move, then `next`.
    public func then(_ next: Affine3D) -> Affine3D {
        let slid = next.m.apply(t)
        return Affine3D(m: next.m * m, t: Point3D(x: slid.x + next.t.x, y: slid.y + next.t.y,
                                                    z: slid.z + next.t.z))
    }
}

/// The camera resolved against one canvas: where the eye is and how far in
/// front of it the picture is formed.
public struct Projection3D: Hashable, Sendable {
    /// The middle of the canvas, which the camera looks straight at.
    public var centre: CGPoint
    /// How far the eye is in front of the canvas when the camera has not been
    /// pushed: the distance at which the canvas fills the angle of view top
    /// to bottom. Infinite when there is no perspective.
    public var eyeDistance: Double
    /// The camera's own move: across, and pushed in.
    public var offset: Point3D

    /// Nothing nearer the eye than this is drawn. A layer that has come right
    /// up to the camera would otherwise fill the frame with one pixel of it.
    public static let nearest: Double = 1

    public init(camera: SceneCamera?, canvas: CGSize) {
        let camera = camera ?? .default
        centre = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let angle = min(max(camera.perspective, 0), SceneCamera.widestPerspective) * .pi / 180
        if angle > 1e-6, canvas.height > 0 {
            eyeDistance = Double(canvas.height) / 2 / tan(angle / 2)
        } else {
            eyeDistance = .infinity
        }
        offset = Point3D(x: camera.x, y: camera.y, z: camera.depth)
    }

    /// Whether it has perspective at all.
    public var hasPerspective: Bool { eyeDistance.isFinite }

    /// Whether a flat, unturned layer comes out exactly where it is stored.
    public var leavesTheCanvasAlone: Bool { offset.x == 0 && offset.y == 0 && offset.z == 0 }

    /// The same perspective with the camera put back where it started: what
    /// the layers INSIDE a flattened group are seen through, so the camera's
    /// own move is taken once, by the group's card, and never twice.
    public var unmoved: Projection3D {
        var copy = self
        copy.offset = Point3D(x: 0, y: 0, z: 0)
        return copy
    }

    /// Where a point in space lands on the canvas, or nil when it is level
    /// with the eye or behind it.
    public func project(_ p: Point3D) -> CGPoint? {
        let dx = p.x - Double(centre.x) - offset.x
        let dy = p.y - Double(centre.y) - offset.y
        guard hasPerspective else {
            return CGPoint(x: Double(centre.x) + dx, y: Double(centre.y) + dy)
        }
        let eye = eyeDistance - offset.z
        let away = eye - p.z
        guard away >= Self.nearest, away.isFinite else { return nil }
        let factor = eyeDistance / away
        return CGPoint(x: Double(centre.x) + dx * factor, y: Double(centre.y) + dy * factor)
    }
}

/// A plane-to-plane map, the kind a flat card seen in perspective makes: four
/// corners anywhere, straight lines kept straight.
public struct Homography: Hashable, Sendable {
    public var h: Matrix3

    public init(h: Matrix3) { self.h = h }

    /// The map that sends the four corners of `box` (clockwise from top-left)
    /// to `quad`, or nil where `quad` has collapsed.
    public init?(box: CGRect, to quad: [CGPoint]) {
        guard quad.count == 4, box.width > 0, box.height > 0,
              let square = Self.squareToQuad(quad) else { return nil }
        // The box into the unit square, then the square onto the quad.
        let toSquare = Matrix3(1 / Double(box.width), 0, -Double(box.minX) / Double(box.width),
                               0, 1 / Double(box.height), -Double(box.minY) / Double(box.height),
                               0, 0, 1)
        h = square * toSquare
    }

    /// Heckbert's square-to-quad: (0,0) (1,0) (1,1) (0,1) to the four points.
    private static func squareToQuad(_ q: [CGPoint]) -> Matrix3? {
        let x0 = Double(q[0].x), y0 = Double(q[0].y)
        let x1 = Double(q[1].x), y1 = Double(q[1].y)
        let x2 = Double(q[2].x), y2 = Double(q[2].y)
        let x3 = Double(q[3].x), y3 = Double(q[3].y)
        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3
        if abs(sx) < 1e-12, abs(sy) < 1e-12 {
            return Matrix3(x1 - x0, x3 - x0, x0,
                           y1 - y0, y3 - y0, y0,
                           0, 0, 1)
        }
        let dx1 = x1 - x2, dx2 = x3 - x2
        let dy1 = y1 - y2, dy2 = y3 - y2
        let den = dx1 * dy2 - dx2 * dy1
        guard abs(den) > 1e-12 else { return nil }
        let g = (sx * dy2 - dx2 * sy) / den
        let hh = (dx1 * sy - sx * dy1) / den
        return Matrix3(x1 - x0 + g * x1, x3 - x0 + hh * x3, x0,
                       y1 - y0 + g * y1, y3 - y0 + hh * y3, y0,
                       g, hh, 1)
    }

    public func apply(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let w = h.e[6] * x + h.e[7] * y + h.e[8]
        guard abs(w) > 1e-12 else { return nil }
        return CGPoint(x: (h.e[0] * x + h.e[1] * y + h.e[2]) / w,
                       y: (h.e[3] * x + h.e[4] * y + h.e[5]) / w)
    }

    public var inverted: Homography? { h.inverted.map(Homography.init(h:)) }
}

// MARK: - Where a layer lands

public enum Space3D {

    /// The corners of `box` (clockwise from top-left, in canvas space), moved
    /// by `turn` and seen through `projection`. Nil when any corner reaches
    /// the eye or passes behind it: a card that close is not drawn at all.
    public static func quad(of box: CGRect, through turn: Affine3D,
                            _ projection: Projection3D) -> [CGPoint]? {
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        var out: [CGPoint] = []
        for corner in corners {
            guard let landed = projection.project(turn.apply(Point3D(corner))) else { return nil }
            out.append(landed)
        }
        return out
    }

    /// The whole canvas plane moved by `turn` and projected, as one map, built
    /// from `box` (any box on the plane does). Nil where the plane is seen
    /// edge on or passes behind the eye.
    public static func map(around box: CGRect, through turn: Affine3D,
                           _ projection: Projection3D) -> Homography? {
        guard let quad = quad(of: box, through: turn, projection) else { return nil }
        return Homography(box: box, to: quad)
    }

    /// Whether a quad made from a box's corners clockwise from top-left still
    /// runs clockwise, which is what facing the viewer is in a y-down space.
    /// A card seen exactly edge on faces nobody.
    public static func facesViewer(_ quad: [CGPoint]) -> Bool {
        signedArea(quad) > 1e-9
    }

    /// Twice the area inside the quad, positive when it runs clockwise on a
    /// screen whose y grows downward.
    public static func signedArea(_ quad: [CGPoint]) -> Double {
        guard quad.count >= 3 else { return 0 }
        var sum = 0.0
        for index in quad.indices {
            let a = quad[index], b = quad[(index + 1) % quad.count]
            sum += Double(a.x * b.y - b.x * a.y)
        }
        return sum
    }

    /// How far toward the viewer the middle of `box` ends up under `turn`:
    /// what layers drawn in depth order are sorted by, and what depth of field
    /// blurs by.
    public static func depth(of box: CGRect, through turn: Affine3D) -> Double {
        turn.apply(Point3D(CGPoint(x: box.midX, y: box.midY))).z
    }

    /// The box round a quad.
    public static func bounds(of quad: [CGPoint]) -> CGRect {
        guard let first = quad.first else { return .null }
        return quad.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
    }
}

// MARK: - The layer and the document

extension Layer {

    /// This layer's turn in space, where it is turned or moved in depth at
    /// all. Nil for a flat layer, which is nearly every layer.
    public var spaceTurn: LayerTurn3D? {
        guard let turn3D, !turn3D.isFlat else { return nil }
        return turn3D
    }

    /// Whether this layer is turned or moved in depth.
    public var isTurnedInSpace: Bool { spaceTurn != nil }

    /// Whether this layer or anything inside it is turned in space.
    public var hasSpaceTurnInside: Bool {
        isTurnedInSpace || (group?.children.contains { $0.hasSpaceTurnInside } ?? false)
    }

    /// The move in space this layer's own turn makes, about its pivot, with
    /// the layer stored `offset` from the canvas's corner (its group's corner
    /// for a child). Nil for a flat layer.
    public func spaceAffine(offset: CGPoint = .zero) -> Affine3D? {
        guard let turn = spaceTurn else { return nil }
        let pivot = spacePivot
        return turn.affine(pivot: CGPoint(x: pivot.x + offset.x, y: pivot.y + offset.y))
    }

    /// The point this layer turns about IN SPACE, in the same space as its
    /// frame: its hinge where its turn names one, and otherwise the point its
    /// flat turn takes. The crosshair on the canvas sits here.
    public var spacePivot: CGPoint {
        guard let hinge = turn3D?.hinge else { return turnPivot }
        let box = turnPivotBox
        return CGPoint(x: box.minX + box.width * hinge.x, y: box.minY + box.height * hinge.y)
    }

    /// Whether a group draws its contents straight onto the canvas below it
    /// rather than into a card of its own first. One answer, read by the
    /// renderer and the click alike: a group with no styling, no edge to cut
    /// at, no 2D turn, and no turn in space unless it keeps its contents in
    /// space (`GroupContent.keeps3D`).
    public var drawsStraightThrough: Bool {
        guard let group, !group.isFrame, !clipsToBounds, style.isPlain,
              transform.isIdentity else { return false }
        return !isTurnedInSpace || group.keeps3D == true
    }

    /// Whether this group keeps what it holds in space: its children are
    /// turned along with it and drawn nearest last, Apple Motion's 3D group
    /// and CSS's `preserve-3d`. Only a group that draws straight through can,
    /// because a group with a card of its own (a shadow, a corner, a frame)
    /// has to be one flat picture before that card can be cast.
    public var keepsItsContentsInSpace: Bool {
        group?.keeps3D == true && drawsStraightThrough
    }
}

extension PhotonzDocument {

    /// The camera this document is seen through, with its default standing in
    /// where nobody has set one.
    public var shownCamera: SceneCamera { camera ?? .default }

    /// The camera resolved against this document's canvas.
    public var projection: Projection3D { Projection3D(camera: camera, canvas: canvasSize) }

    /// Whether anything in this document is drawn other than flat on the
    /// canvas: a layer turned in space, or a camera that has been moved.
    public var isSeenInSpace: Bool {
        if !(camera?.leavesTheCanvasAlone ?? true) { return true }
        return layers.contains { $0.hasSpaceTurnInside }
    }

    /// The indices of a stack of layers in the order they are DRAWN when the
    /// group holding them keeps them in space: furthest first, nearest last,
    /// with layers at the same depth keeping the order the layers list gives
    /// them. `offset` is where the stack's own space starts on the canvas and
    /// `inherited` the move its group makes in space.
    public static func depthOrder(of layers: [Layer], offset: CGPoint,
                                  inherited: Affine3D) -> [Int] {
        let depths = layers.map { layer -> Double in
            let box = (layer.isGroup ? layer.localBounds : layer.frame)
                .offsetBy(dx: offset.x, dy: offset.y)
            let own = layer.spaceAffine(offset: offset) ?? .identity
            return Space3D.depth(of: box, through: own.then(inherited))
        }
        return layers.indices.sorted { left, right in
            if abs(depths[left] - depths[right]) > 1e-9 { return depths[left] < depths[right] }
            return left < right
        }
    }

    /// Where the four corners of a layer's box land on the canvas as it is
    /// DRAWN, clockwise from top-left, for a layer seen in space; nil for a
    /// layer that is drawn flat (read `transformedCorners` for that), and nil
    /// when the layer has come so near it is not drawn.
    ///
    /// Everything that draws round a layer asks this: the selection outline,
    /// the click and the export's picture box, so none of them can put a
    /// turned layer anywhere the renderer does not.
    public func drawnQuad(of id: UUID) -> [CGPoint]? {
        guard isSeenInSpace, let chain = spaceChain(of: id) else { return nil }
        guard let layer = layer(id: id) else { return nil }
        let corners = layer.transformedCorners.map {
            CGPoint(x: $0.x + chain.offset.x, y: $0.y + chain.offset.y)
        }
        return chain.carry(corners)
    }

    /// How a layer is carried from its own upright space onto the canvas, for
    /// a layer that is seen in space: one step for each card it is drawn on,
    /// innermost first. Nil for a layer drawn flat, or one not in this
    /// document.
    public func spaceChain(of id: UUID) -> SpaceChain? {
        guard isSeenInSpace else { return nil }
        var steps: [SpaceChain.Step] = []
        var found = false
        // Walks down from the top, collecting a step for every card the layer
        // ends up drawn on; `projection` is the camera the current stack is
        // seen through and `inherited` the move a group keeping its contents
        // in space hands down.
        func walk(_ list: [Layer], offset: CGPoint, projection: Projection3D,
                  inherited: Affine3D?, cards: [SpaceChain.Step]) {
            for layer in list where !found {
                let own = layer.spaceAffine(offset: offset)
                let move = Self.joined(own, inherited)
                if layer.id == id {
                    var mine = cards
                    if move != nil || !projection.leavesTheCanvasAlone {
                        mine.insert(SpaceChain.Step(flatTurn: nil, turn: move ?? .identity,
                                                    projection: projection), at: 0)
                    }
                    steps = mine
                    found = true
                    return
                }
                guard let group = layer.group else { continue }
                let inner = CGPoint(x: offset.x + layer.frame.origin.x, y: offset.y + layer.frame.origin.y)
                if layer.drawsStraightThrough {
                    // Not a card: its children are carried one by one, by
                    // whatever move it hands down.
                    walk(group.children, offset: inner, projection: projection,
                         inherited: move, cards: cards)
                } else {
                    // A card of its own: what is inside is seen through the
                    // camera put back where it started, then the card takes
                    // its 2D turn and is carried by its own move and the real
                    // camera.
                    var cardSteps = cards
                    let pivot = CGPoint(x: layer.turnPivot.x + offset.x, y: layer.turnPivot.y + offset.y)
                    let flat = layer.transform.isIdentity ? nil : layer.transform.affineTransform(around: pivot)
                    if move != nil || !projection.leavesTheCanvasAlone || flat != nil {
                        cardSteps.insert(SpaceChain.Step(flatTurn: flat, turn: move ?? .identity,
                                                         projection: projection), at: 0)
                    }
                    walk(group.children, offset: inner, projection: projection.unmoved,
                         inherited: nil, cards: cardSteps)
                }
            }
        }
        walk(layers, offset: .zero, projection: projection, inherited: nil, cards: [])
        guard found, !steps.isEmpty else { return nil }
        return SpaceChain(offset: parentOrigin(of: id) ?? .zero, steps: steps)
    }

    /// A layer's own move in space followed by the one handed down to it.
    public static func joined(_ own: Affine3D?, _ inherited: Affine3D?) -> Affine3D? {
        switch (own, inherited) {
        case (nil, nil): nil
        case let (own?, nil): own
        case let (nil, inherited?): inherited
        case let (own?, inherited?): own.then(inherited)
        }
    }
}

/// How a point on a layer is carried onto the canvas when something on the
/// way is seen in space: innermost card first.
public struct SpaceChain: Hashable, Sendable {
    /// One card a layer is drawn on, innermost first: the layer itself, then
    /// every group above it that draws as one picture.
    public struct Step: Hashable, Sendable {
        /// The card's 2D turn, taken before it is carried. Nil on the layer's
        /// own step, whose 2D turn is already in its corners
        /// (`Layer.transformedCorners`), and on a card that is not turned.
        public var flatTurn: CGAffineTransform?
        /// The card's move in space, with any group keeping it in space
        /// folded in.
        public var turn: Affine3D
        /// The camera the card is seen through.
        public var projection: Projection3D
    }

    /// Where the layer's own space starts on the canvas.
    public var offset: CGPoint
    public var steps: [Step]

    /// `points` (canvas space, with the layer's own 2D turn in them) carried
    /// through every step, or nil where one passes the eye.
    public func carry(_ points: [CGPoint]) -> [CGPoint]? {
        var out = points
        for step in steps {
            if let flat = step.flatTurn { out = out.map { $0.applying(flat) } }
            var landed: [CGPoint] = []
            for point in out {
                guard let p = step.projection.project(step.turn.apply(Point3D(point))) else { return nil }
                landed.append(p)
            }
            out = landed
        }
        return out
    }

    /// A canvas point carried back to where it sits before any step (canvas
    /// space, the layer's own 2D turn still in it), or nil where it misses
    /// the plane. `box` is any box on the plane near the layer, which the map
    /// is built from.
    public func uncarry(_ point: CGPoint, around box: CGRect) -> CGPoint? {
        var p = point
        for step in steps.reversed() {
            guard let map = Space3D.map(around: box, through: step.turn, step.projection),
                  let back = map.inverted?.apply(p) else { return nil }
            p = back
            if let flat = step.flatTurn { p = p.applying(flat.inverted()) }
        }
        return p
    }
}

extension LayerTurn3D {
    /// The value of one of the four 3D properties.
    func value(of property: MotionProperty) -> Double? {
        switch property {
        case .rotationX: rotationX
        case .rotationY: rotationY
        case .depth: depth
        case .pivotDepth: pivotDepth
        default: nil
        }
    }
}

extension PhotonzDocument {

    /// The whole way from a layer's own upright box (canvas space, before its
    /// 2D turn) to where it is drawn, as one plane map, for a layer seen in
    /// space; nil for a layer drawn flat. A chain of turns, cards and cameras
    /// is still one map of a plane onto the screen, so four corners decide
    /// it and every handle, dot and outline point goes through the same one.
    public func drawnMap(of id: UUID) -> Homography? {
        guard let quad = drawnQuad(of: id), let layer = layer(id: id),
              let origin = parentOrigin(of: id) else { return nil }
        return Homography(box: layer.turnBox.offsetBy(dx: origin.x, dy: origin.y), to: quad)
    }
}

extension SelectionOutlineShape {

    /// The outline round `box` for a layer seen in space: the same rounded
    /// box, carried point by point through `map` (the layer's `drawnMap`)
    /// and then `transform` (the camera onto the screen). A plane map bends
    /// a curve into another curve, so each corner's curve is walked in short
    /// steps rather than handed over as control points that would land
    /// slightly off it.
    public static func path(box: CGRect, cornerRadii: CornerRadii, through map: Homography,
                            transform: CGAffineTransform = .identity) -> CGPath {
        let flat = cornerRadii.path(in: box, transform: .identity)
        var points: [[CGPoint]] = []
        var current: [CGPoint] = []
        var last = CGPoint.zero
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) {
            for step in 1...8 {
                let t = CGFloat(step) / 8, u = 1 - t
                current.append(CGPoint(
                    x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                    y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y))
            }
        }
        flat.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint:
                if !current.isEmpty { points.append(current) }
                current = [e.points[0]]
                last = e.points[0]
            case .addLineToPoint:
                current.append(e.points[0])
                last = e.points[0]
            case .addQuadCurveToPoint:
                let c = e.points[0], d = e.points[1]
                cubic(last, CGPoint(x: last.x + 2 / 3 * (c.x - last.x), y: last.y + 2 / 3 * (c.y - last.y)),
                      CGPoint(x: d.x + 2 / 3 * (c.x - d.x), y: d.y + 2 / 3 * (c.y - d.y)), d)
                last = d
            case .addCurveToPoint:
                cubic(last, e.points[0], e.points[1], e.points[2])
                last = e.points[2]
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        if !current.isEmpty { points.append(current) }
        let path = CGMutablePath()
        for run in points {
            let landed = run.compactMap { map.apply($0)?.applying(transform) }
            guard let first = landed.first else { continue }
            path.move(to: first)
            for point in landed.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}
