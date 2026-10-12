import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Transitions that turn in depth: Flip, Cube, Swing, Doorway, Revolve and Push
/// in Depth (task `3d-transitions-and-title-entrances-flip-cube-swi`,
/// `DepthTransitions.swift`).
///
/// The bar the task sets, measured here: at the midpoint of each one the moving
/// picture is turned at least 20 degrees from flat and lands as a visibly
/// non-rectangular shape, and two frames a tenth of a second apart differ
/// obviously.
@Suite("Transitions that turn in depth")
struct DepthTransitionTests {

    static let size = CGSize(width: 1920, height: 1080)

    /// How far a turn is from flat, in degrees.
    static func angle(_ turn: LayerTurn3D) -> Double { max(abs(turn.rotationX), abs(turn.rotationY)) }

    /// The most any corner of a quad is off a right angle, in degrees.
    static func skew(_ quad: [CGPoint]) -> Double {
        var worst = 0.0
        for index in 0..<4 {
            let a = quad[(index + 3) % 4], b = quad[index], c = quad[(index + 1) % 4]
            let u = CGVector(dx: a.x - b.x, dy: a.y - b.y), v = CGVector(dx: c.x - b.x, dy: c.y - b.y)
            let lengths = hypot(u.dx, u.dy) * hypot(v.dx, v.dy)
            guard lengths > 1e-6 else { return 90 }
            let cosine = (u.dx * v.dx + u.dy * v.dy) / lengths
            worst = max(worst, abs(acos(min(max(Double(cosine), -1), 1)) * 180 / .pi - 90))
        }
        return worst
    }

    /// How much of the box the quad still covers.
    static func areaShare(_ quad: [CGPoint], of box: CGRect) -> Double {
        abs(Space3D.signedArea(quad)) / 2 / Double(box.width * box.height)
    }

    // MARK: - The six, and where they live

    @Test("Six kinds turn in depth, each with a name, a direction and an overlap")
    func theSixKinds() {
        #expect(ClipTransitionKind.inDepth == [.flip, .cube, .swing, .doorway, .revolve, .pushInDepth])
        #expect(ClipTransitionKind.inDepth.map(\.title)
                    == ["Flip", "Cube", "Swing", "Doorway", "Revolve", "Push in depth"])
        for kind in ClipTransitionKind.inDepth {
            #expect(kind.isInDepth && kind.hasDirection && kind.needsOverlap)
            #expect(kind.defaultCurve == .easeInOut)
            #expect(ClipTransition(kind: kind).curve == .easeInOut)
            // Every kind is offered wherever the flat ones are: the picker and
            // the Add Transition menu both list `allCases`.
            #expect(ClipTransitionKind.allCases.contains(kind))
        }
        for kind in [ClipTransitionKind.dissolve, .push, .wipe, .dipToBlack] {
            #expect(!kind.isInDepth && !kind.hasDirection)
            #expect(ClipTransition(kind: kind).curve == .linear)
        }
    }

    @Test("Put on a cut, one in depth eases in and out; a curve somebody chose stays when the kind changes")
    func fittedCurves() throws {
        var pieces = ClipTransitionTests.cutClip()
        let cut = try #require(pieces.cut(at: 1))
        #expect(cut.fitted(.cube)?.curve == .easeInOut)
        #expect(cut.fitted(.dissolve)?.curve == .linear)
        _ = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 800), atCut: 1)
        let plain = try #require(pieces.cut(at: 1))
        #expect(plain.fitted(.flip)?.curve == .easeInOut)
        _ = pieces.setTransition(ClipTransition(kind: .dissolve, lengthMS: 800, curve: .easeOutBack,
                                                direction: .up, motionBlur: true), atCut: 1)
        let chosen = try #require(pieces.cut(at: 1))
        let kept = try #require(chosen.fitted(.flip))
        #expect(kept.curve == .easeOutBack && kept.direction == .up && kept.motionBlur)
    }

    @Test("A transition written before directions existed reads back going left, unblurred, and writes nothing new")
    func oldTransitionsReadAsBefore() throws {
        let json = #"{"kind":"dissolve","lengthMS":400}"#
        let old = try JSONDecoder().decode(ClipTransition.self, from: Data(json.utf8))
        #expect(old.direction == .left && !old.motionBlur && old.curve == .linear)
        let written = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!written.contains("direction") && !written.contains("motionBlur"))
        var flip = ClipTransition(kind: .flip, lengthMS: 900)
        flip.direction = .up
        flip.motionBlur = true
        let back = try JSONDecoder().decode(ClipTransition.self, from: JSONEncoder().encode(flip))
        #expect(back == flip)
        // Changing the length keeps everything else.
        #expect(flip.withLength(600).direction == .up && flip.withLength(600).motionBlur)
    }

    // MARK: - The visible motion bar

    @Test("At the midpoint every one is turned at least 20 degrees and lands visibly non-rectangular",
          arguments: ClipTransitionKind.inDepth)
    func midpointIsVisiblyTurned(kind: ClipTransitionKind) throws {
        let p = ClipTransition(kind: kind).curve.value(at: 0.5)
        let parts = DepthTransition.parts(kind, direction: .left, progress: p, size: Self.size)
        let moving = try #require(parts.max { Self.angle($0.turn) < Self.angle($1.turn) })
        #expect(Self.angle(moving.turn) >= 20, "\(kind.title) is turned \(Self.angle(moving.turn)) degrees")
        // Its shape on the canvas, drawn whatever way it faces.
        var seen = moving
        seen.turn.showsBackFace = nil
        let box = CGRect(x: (seen.window.minX + seen.shift.x) * Self.size.width,
                         y: (seen.window.minY + seen.shift.y) * Self.size.height,
                         width: seen.window.width * Self.size.width, height: seen.window.height * Self.size.height)
        let pivot = seen.turn.hinge.map { CGPoint(x: box.minX + box.width * $0.x, y: box.minY + box.height * $0.y) }
            ?? CGPoint(x: box.midX, y: box.midY)
        let quad = try #require(Space3D.quad(of: box, through: seen.turn.affine(pivot: pivot),
                                             Projection3D(camera: nil, canvas: Self.size)))
        let skew = Self.skew(quad), share = Self.areaShare(quad, of: box)
        #expect(skew >= 3 || share < 0.9, "\(kind.title): corners off square by \(skew), covers \(share)")
    }

    @Test("Two frames a tenth of a second apart differ obviously", arguments: ClipTransitionKind.inDepth)
    func framesApartDiffer(kind: ClipTransitionKind) throws {
        let transition = ClipTransition(kind: kind)
        let length = Double(transition.lengthMS)
        let a = transition.curve.value(at: (length / 2 - 50) / length)
        let b = transition.curve.value(at: (length / 2 + 50) / length)
        let early = DepthTransition.quads(kind, direction: .left, progress: a, size: Self.size)
        let late = DepthTransition.quads(kind, direction: .left, progress: b, size: Self.size)
        #expect(early.count == late.count)
        var moved: CGFloat = 0
        for (one, two) in zip(early, late) {
            switch (one.quad, two.quad) {
            case let (x?, y?):
                for (p, q) in zip(x, y) { moved = max(moved, hypot(p.x - q.x, p.y - q.y)) }
            case (nil, nil):
                continue
            default:
                // One frame shows it and the other does not.
                moved = max(moved, 1000)
            }
        }
        #expect(moved > 40, "\(kind.title) moved only \(moved) points in 100 ms")
    }

    // MARK: - Where they start and end

    @Test("Each starts on the outgoing shot, flat where it was, and ends on the incoming one",
          arguments: ClipTransitionKind.inDepth)
    func startsAndEndsFlat(kind: ClipTransitionKind) throws {
        let box = CGRect(origin: .zero, size: Self.size)
        let first = DepthTransition.quads(kind, direction: .left, progress: 0, size: Self.size)
        let last = DepthTransition.quads(kind, direction: .left, progress: 1, size: Self.size)
        func topmostCovering(_ quads: [(part: DepthTransitionPart, quad: [CGPoint]?)])
            -> DepthTransitionPart.Shot? {
            quads.last { entry in
                guard let quad = entry.quad, entry.part.opacity > 0.99 else { return false }
                return Self.areaShare(quad, of: box) > 0.2 && Space3D.bounds(of: quad).insetBy(dx: -1, dy: -1)
                    .contains(CGPoint(x: box.midX + (entry.part.window.minX > 0 ? 10 : -10), y: box.midY))
            }?.part.shot
        }
        #expect(topmostCovering(first) == .outgoing, "\(kind.title) at its start")
        #expect(topmostCovering(last) == .incoming, "\(kind.title) at its end")
        // ...and at its end the incoming shot is exactly where it lives.
        let landed = try #require(last.first { $0.part.shot == .incoming && $0.part.opacity > 0.99 }?.quad)
        for (p, q) in zip(landed, [CGPoint(x: 0, y: 0), CGPoint(x: 1920, y: 0),
                                   CGPoint(x: 1920, y: 1080), CGPoint(x: 0, y: 1080)]) {
            #expect(hypot(p.x - q.x, p.y - q.y) < 0.5, "\(kind.title) lands off by \(p) vs \(q)")
        }
    }

    @Test("Nothing but a doorway's doors ever comes nearer than the canvas, so a shot is never bigger than itself",
          arguments: ClipTransitionKind.inDepth.filter { $0 != .doorway })
    func staysBehindTheGlass(kind: ClipTransitionKind) {
        for step in 0...20 {
            let p = Double(step) / 20
            for part in DepthTransition.parts(kind, direction: .left, progress: p, size: Self.size)
            where part.opacity > 0.001 {
                let box = CGRect(x: (part.window.minX + part.shift.x) * Self.size.width,
                                 y: (part.window.minY + part.shift.y) * Self.size.height,
                                 width: part.window.width * Self.size.width,
                                 height: part.window.height * Self.size.height)
                let pivot = part.turn.hinge.map {
                    CGPoint(x: box.minX + box.width * $0.x, y: box.minY + box.height * $0.y)
                } ?? CGPoint(x: box.midX, y: box.midY)
                let move = part.turn.affine(pivot: pivot)
                for corner in [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                               CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)] {
                    #expect(move.apply(Point3D(corner)).z <= 1e-6, "\(kind.title) at \(p)")
                }
            }
        }
    }

    @Test("A quarter of the way round, a cube shows both faces: the one leaving and the one coming round")
    func cubeShowsBothFaces() {
        for size in [Self.size, CGSize(width: 1080, height: 1920)] {
            let quads = DepthTransition.quads(.cube, direction: .left, progress: 0.25, size: size)
            #expect(quads.allSatisfy { $0.quad != nil }, "\(size)")
        }
    }

    @Test("Going right mirrors going left, and up and down turn about the other axis",
          arguments: ClipTransitionKind.inDepth)
    func directionsMirror(kind: ClipTransitionKind) {
        let left = DepthTransition.parts(kind, direction: .left, progress: 0.4, size: Self.size)
        let right = DepthTransition.parts(kind, direction: .right, progress: 0.4, size: Self.size)
        let up = DepthTransition.parts(kind, direction: .up, progress: 0.4, size: Self.size)
        #expect(left.count == right.count && left.count == up.count)
        for (l, r) in zip(left, right) where kind != .doorway {
            #expect(abs(l.turn.rotationY + r.turn.rotationY) < 1e-9)
            #expect(abs(l.shift.x + r.shift.x) < 1e-9)
        }
        #expect(up.allSatisfy { $0.turn.rotationY == 0 })
        #expect(up.contains { abs($0.turn.rotationX) > 1 })
    }

    // MARK: - Drawn by the document

    @Test("Mid flip the document hands the renderer two turned pictures, and the frame is seen in space")
    func theDocumentDrawsAFlip() throws {
        var pieces = ClipTransitionTests.cutClip()
        let put = pieces.setTransition(ClipTransition(kind: .flip, lengthMS: 1000), atCut: 1)
        #expect(put)
        let document = ClipTransitionTests.clipDocument(pieces)
        #expect(!document.isSeenInSpace)
        let shown = document.drawn(atTimeMS: 2800)
        #expect(shown.layers.count == 2)
        #expect(shown.isSeenInSpace)
        #expect(shown.layers.allSatisfy { $0.turn3D?.showsBackFace == false })
        #expect(shown.layers.contains { abs($0.turn3D?.rotationY ?? 0) > 20 })
        // Away from it, one flat picture again.
        #expect(document.drawn(atTimeMS: 500).layers.count == 1)
        #expect(!document.drawn(atTimeMS: 500).isSeenInSpace)
    }

    @Test("A doorway's two doors are windows on the outgoing shot, each with an id of its own, hinged on its outer edge")
    func doorwayDoors() throws {
        var pieces = ClipTransitionTests.cutClip()
        _ = pieces.setTransition(ClipTransition(kind: .doorway, lengthMS: 1000), atCut: 1)
        let document = ClipTransitionTests.clipDocument(pieces)
        let shown = document.drawn(atTimeMS: 2900)
        #expect(shown.layers.count == 3)
        let doors = shown.layers.filter { $0.group?.isFrame == true }
        #expect(doors.count == 2)
        #expect(Set(shown.layers.map(\.id)).count == 3)
        #expect(Set(doors.compactMap { $0.turn3D?.hinge }) == [CGPoint(x: 0, y: 0.5), CGPoint(x: 1, y: 0.5)])
        // The left door's outer edge stays put while it opens.
        let left = try #require(doors.first { $0.turn3D?.hinge == CGPoint(x: 0, y: 0.5) })
        let quad = try #require(shown.drawnQuad(of: left.id))
        #expect(abs(quad[0].x) < 0.5 && abs(quad[3].x) < 0.5)
    }

    @Test("A cut between two clips draws a cube the same way")
    func editPointCube() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        var document = doc
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let cube = ClipTransition(kind: .cube, lengthMS: 800, direction: .right)
        let put = document.setTransition(cube, at: place)
        #expect(put)
        let at = try #require(document.documentCut(at: place)?.atMS)
        let shown = document.drawn(atTimeMS: at)
        #expect(shown.isSeenInSpace)
        let turned = shown.layers.compactMap(\.turn3D)
        #expect(turned.count >= 2)
        #expect(turned.allSatisfy { $0.pivotDepth < 0 })
    }

    // MARK: - A hinge

    @Test("A layer hinged on its left edge swings about that edge, and the hinge alone turns nothing")
    func hinge() throws {
        var layer = Space3DTests.box(CGRect(x: 400, y: 200, width: 600, height: 400))
        layer.turn3D = LayerTurn3D(hinge: CGPoint(x: 0, y: 0.5))
        #expect(!layer.isTurnedInSpace)
        layer.turn3D?.rotationY = 60
        #expect(layer.spacePivot == CGPoint(x: 400, y: 400))
        let document = PhotonzDocument(canvasSize: Space3DTests.canvas, layers: [layer])
        let quad = try #require(document.drawnQuad(of: layer.id))
        #expect(abs(quad[0].x - 400) < 0.01 && abs(quad[3].x - 400) < 0.01)
        #expect(quad[1].x < 1000)
        let back = try JSONDecoder().decode(LayerTurn3D.self, from: JSONEncoder().encode(layer.turn3D))
        #expect(back.hinge == CGPoint(x: 0, y: 0.5))
        // A turn with no hinge writes none.
        let plain = String(decoding: try JSONEncoder().encode(LayerTurn3D(rotationY: 10)), as: UTF8.self)
        #expect(!plain.contains("hinge"))
    }
}
