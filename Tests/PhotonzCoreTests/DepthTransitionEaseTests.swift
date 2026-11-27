import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// 3D transitions ease in and out of the picture (task
/// `3d-transitions-ease-in-and-out-of-the-picture-in`): the incoming shot
/// fades in rather than slamming over the outgoing one, the planes are lit
/// and cast a soft shadow as they turn, what the move opens up is filled with
/// the shots themselves, blurred and dimmed, and a clip that has its own frame,
/// corners, shadow and tilt keeps them all the way through.
///
/// The pixel half of the bar is `DepthTransitionEaseRenderTests`.
@Suite("3D transitions ease in and out of the picture")
struct DepthTransitionEaseTests {

    static let size = CGSize(width: 1920, height: 1080)

    /// The incoming shot's opacity, `t` of the way through the move in TIME
    /// (through the kind's usual curve), counting only parts the camera sees.
    static func incomingOpacity(_ kind: ClipTransitionKind, at t: Double) -> Double {
        let transition = ClipTransition(kind: kind)
        let p = transition.curve.value(at: t)
        return DepthTransition.quads(kind, direction: .left, progress: p, size: size)
            .filter { $0.part.shot == .incoming && $0.quad != nil }
            .map(\.part.opacity).max() ?? 0
    }

    // MARK: - Fading in

    @Test("The incoming shot fades in over at least a quarter of the move from the moment it shows",
          arguments: ClipTransitionKind.inDepth)
    func incomingFadesIn(kind: ClipTransitionKind) throws {
        let steps = 400
        let opacities = (0...steps).map { Self.incomingOpacity(kind, at: Double($0) / Double(steps)) }
        let first = try #require(opacities.firstIndex { $0 > 0.01 }, "\(kind.title) never shows the incoming shot")
        let full = try #require(opacities.firstIndex { $0 >= 0.99 }, "\(kind.title) never lands")
        #expect(opacities[first] < 0.1, "\(kind.title) arrives at opacity \(opacities[first])")
        let span = Double(full - first) / Double(steps)
        #expect(span >= 0.25, "\(kind.title) fades in over only \(span) of the move")
        // ...and never dips once it has started.
        for (a, b) in zip(opacities[first...], opacities[(first + 1)...]) {
            #expect(b >= a - 1e-9, "\(kind.title) dips from \(a) to \(b)")
        }
        #expect(opacities[steps] >= 0.999, "\(kind.title) ends at \(opacities[steps])")
    }

    // MARK: - Light and shadow

    @Test("A plane turned away is darker than one facing you, and flat ones are as they were",
          arguments: ClipTransitionKind.inDepth)
    func turnedFacesAreLit(kind: ClipTransitionKind) {
        for part in DepthTransition.parts(kind, direction: .left, progress: 0, size: Self.size)
        where part.shot == .outgoing {
            #expect(part.light == 1, "\(kind.title) starts lit at \(part.light)")
            #expect(part.lift == 0, "\(kind.title) starts lifted \(part.lift)")
        }
        for part in DepthTransition.parts(kind, direction: .left, progress: 1, size: Self.size)
        where part.shot == .incoming {
            #expect(part.light == 1, "\(kind.title) ends lit at \(part.light)")
            #expect(part.lift == 0, "\(kind.title) ends lifted \(part.lift)")
        }
        for p in stride(from: 0.05, through: 0.95, by: 0.05) {
            for part in DepthTransition.parts(kind, direction: .left, progress: p, size: Self.size) {
                let angle = max(abs(part.turn.rotationX), abs(part.turn.rotationY))
                let facing = angle > 90 ? 180 - angle : angle
                if facing >= 40 { #expect(part.light < 0.9, "\(kind.title) at \(p): \(facing) degrees lit \(part.light)") }
                #expect(part.light > 0.3 && part.light <= 1)
            }
        }
        // Somewhere in the middle, something casts a shadow.
        let middle = DepthTransition.parts(kind, direction: .left, progress: 0.5, size: Self.size)
        #expect(middle.contains { $0.lift > 0.3 }, "\(kind.title) casts no shadow at its middle")
    }

    @Test("Drawn, a turned plane is darkened and casts a soft shadow; at rest neither")
    func drawnLightAndShadow() throws {
        let a = Self.shot("A"), b = Self.shot("B")
        let middle = Layer.depthTransitionDrawn(.cube, direction: .left, progress: 0.5, outgoing: a, incoming: b)
        let planes = middle.filter { $0.turn3D != nil }
        #expect(planes.count == 2)
        for plane in planes {
            #expect((plane.style.colorGrade?.exposure ?? 0) < -0.1, "\(plane.name) is not darkened")
            #expect(!plane.style.shadows.isEmpty, "\(plane.name) casts no shadow")
        }
        let start = Layer.depthTransitionDrawn(.cube, direction: .left, progress: 0, outgoing: a, incoming: b)
        let resting = try #require(start.first { $0.id == a.id })
        #expect(resting.style.colorGrade == nil && resting.style.shadows.isEmpty)
    }

    // MARK: - The space it opens

    static func shot(_ name: String, frame: CGRect = CGRect(origin: .zero, size: size)) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    @Test("Over a full-frame shot, what the move opens is the two shots blurred and dimmed, the incoming one fading in over the outgoing",
          arguments: ClipTransitionKind.inDepth)
    func backdropFillsTheVoid(kind: ClipTransitionKind) throws {
        let a = Self.shot("A"), b = Self.shot("B")
        for (p, incomingShare) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0)] {
            let drawn = Layer.depthTransitionDrawn(kind, direction: .left, progress: p, outgoing: a, incoming: b,
                                                   canvas: Self.size)
            let behind = drawn.prefix { $0.turn3D == nil && $0.style.blurRadius > 0 }
            #expect(behind.count == 2, "\(kind.title) at \(p): \(behind.count) layers behind")
            guard behind.count == 2 else { continue }
            for layer in behind {
                #expect((layer.style.colorGrade?.exposure ?? 0) < -0.5, "\(kind.title): the backdrop is not dimmed")
                #expect(layer.isLocked)
            }
            #expect(behind[behind.startIndex].style.opacity == 1)
            #expect(abs(behind[behind.startIndex + 1].style.opacity - incomingShare) < 0.1)
            #expect(Set(drawn.map(\.id)).count == drawn.count, "\(kind.title): two layers share an id")
        }
    }

    @Test("A title page, a group as big as the frame, fills it like a picture does")
    func titlePageFillsTheFrame() {
        let words = Layer(name: "Words", content: .text(TextContent(string: "Hello", fontSize: 72, colorHex: "#FFFFFF")),
                          frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let page = Layer(name: "Title Page", content: .group(GroupContent(children: [words])), frame: .zero)
        #expect(page.fillsTheFrame(of: Self.size))
        // ...and its backdrop is as soft as a picture's of the same size.
        let back = page.transitionBackdrop(amount: 1)
        #expect(back.style.blurRadius == Layer.transitionBackdropBlur(CGRect(origin: .zero, size: Self.size)))
    }

    @Test("Every built-in title page fills the frame, so a move in depth out of one is never over a void")
    func everyTitlePageFillsTheFrame() {
        let size = CGSize(width: 1280, height: 800)
        for title in BuiltInTitle.allCases where title.kind == .titlePage && !title.usesTheRecording {
            let layer = title.layer(in: size)
            #expect(layer.fillsTheFrame(of: size), "\(title.rawValue) is \(layer.isGroup ? layer.localBounds : layer.frame)")
        }
    }

    @Test("No backdrop where the edit has something of its own behind")
    func backdropOnlyOverNothing() {
        let a = Self.shot("A"), b = Self.shot("B")
        let none = Layer.depthTransitionDrawn(.flip, direction: .left, progress: 0.5, outgoing: a, incoming: b)
        #expect(!none.contains { $0.style.blurRadius > 0 })
    }

    @Test("A framed card turning over nothing: the frame glows with the shots mid move and is as it was at both ends",
          arguments: ClipTransitionKind.inDepth)
    func framedCardGlows(kind: ClipTransitionKind) {
        let card = CGRect(x: 260, y: 140, width: 1000, height: 600)
        let a = Self.shot("A", frame: card), b = Self.shot("B")
        for p in [0.0, 1.0] {
            let drawn = Layer.depthTransitionDrawn(kind, direction: .left, progress: p, outgoing: a, incoming: b,
                                                   canvas: Self.size)
            #expect(!drawn.contains { $0.turn3D == nil && $0.style.blurRadius > 0 && $0.style.opacity > 0.001 },
                    "\(kind.title) at \(p) shows a glow")
        }
        let middle = Layer.depthTransitionDrawn(kind, direction: .left, progress: 0.5, outgoing: a, incoming: b,
                                                canvas: Self.size)
        let glow = middle.filter { $0.turn3D == nil && $0.style.blurRadius > 0 }
        #expect(glow.count == 2)
        for layer in glow {
            // It covers the whole frame, whatever shape the card is.
            #expect(layer.frame.contains(CGRect(origin: .zero, size: Self.size).insetBy(dx: 1, dy: 1)))
            #expect(layer.style.cornerRadii == .none)
        }
        #expect((glow.first?.style.opacity ?? 0) > 0.9)
    }

    @Test("Between two clips with nothing under them the document fills the void; with a picture under them it does not")
    func documentBackdrop() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        var document = doc
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let put = document.setTransition(ClipTransition(kind: .flip, lengthMS: 800), at: place)
        #expect(put)
        let at = try #require(document.documentCut(at: place)?.atMS)
        let shown = document.drawn(atTimeMS: at - 100)
        #expect(shown.layers.contains { $0.style.blurRadius > 0 && $0.isLocked }, "no backdrop drawn")
        // Whichever clip is lower in the list, the one borrowed for the move
        // is not a picture under it.
        var flipped = document
        flipped.layers.reverse()
        #expect(flipped.drawn(atTimeMS: at - 100).layers.contains { $0.style.blurRadius > 0 && $0.isLocked })
        #expect(flipped.drawn(atTimeMS: at + 100).layers.contains { $0.style.blurRadius > 0 && $0.isLocked })
        #expect(document.drawn(atTimeMS: at + 100).layers.contains { $0.style.blurRadius > 0 && $0.isLocked })
        // A picture under the clips: the edit's own backdrop shows instead.
        var under = Layer(name: "Backdrop", content: .image(ImageRef(pixelSize: document.canvasSize)),
                          frame: CGRect(origin: .zero, size: document.canvasSize))
        under.isLocked = false
        document.layers.insert(under, at: 0)
        let over = document.drawn(atTimeMS: at - 100)
        #expect(!over.layers.contains { $0.style.blurRadius > 0 && $0.isLocked })
    }

    // MARK: - Framing kept

    /// The edit from `EditPointTransitionTests`, each clip framed as a card a
    /// little smaller than the frame, rounded, shadowed and tilted.
    static func framedEdit(_ kind: ClipTransitionKind) throws
        -> (doc: PhotonzDocument, take: UUID, broll: UUID, cutMS: Int, transition: ClipTransition) {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        for (id, tilt) in [(take, LayerTurn3D(rotationX: -5, rotationY: 12)),
                           (broll, LayerTurn3D(rotationX: 6, rotationY: -14))] {
            doc.updateLayer(id: id) { layer in
                layer.frame = CGRect(x: 12, y: 8, width: 72, height: 44)
                layer.turn3D = tilt
                layer.style.cornerRadii = CornerRadii(4)
                layer.style.shadow = ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 3), opacity: 0.5)
            }
        }
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let transition = ClipTransition(kind: kind, lengthMS: 800)
        let put = doc.setTransition(transition, at: place)
        #expect(put)
        let at = try #require(doc.documentCut(at: place)?.atMS)
        let drawnTransition = try #require(doc.documentCut(at: place)?.cut.drawnTransition)
        return (doc, take, broll, at, drawnTransition)
    }

    static func distance(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? .infinity
    }

    @Test("A framed, tilted clip goes into and comes out of every 3D move with its own tilt: no pop at either end",
          arguments: ClipTransitionKind.inDepth)
    func framingKept(kind: ClipTransitionKind) throws {
        let (doc, take, broll, cut, transition) = try Self.framedEdit(kind)
        let first = cut - transition.beforeMS, last = cut + transition.afterMS - 1
        // The outgoing clip at rest, just before, and at the move's first frame.
        let before = try #require(doc.drawn(atTimeMS: first - 40).drawnQuad(of: take))
        let into = try #require(doc.drawn(atTimeMS: first).drawnQuad(of: take))
        #expect(Self.distance(before, into) < 1.5, "\(kind.title): the outgoing card pops from \(before) to \(into)")
        // The incoming clip at the move's last frame, and at rest just after.
        let after = try #require(doc.drawn(atTimeMS: last + 40).drawnQuad(of: broll))
        let landing = try #require(doc.drawn(atTimeMS: last).drawnQuad(of: broll))
        #expect(Self.distance(after, landing) < 1.5, "\(kind.title): the incoming card pops from \(landing) to \(after)")
    }

    @Test("Mid move a framed clip is still the card it was: rounded, shadowed, its own size",
          arguments: ClipTransitionKind.inDepth)
    func framingMidMove(kind: ClipTransitionKind) throws {
        let (doc, take, broll, cut, _) = try Self.framedEdit(kind)
        let shown = doc.drawn(atTimeMS: cut)
        for id in [take, broll] {
            let partner = Layer.transitionPartnerID(of: id)
            let drawn = try #require(shown.layer(id: id) ?? shown.layer(id: partner),
                                     "\(kind.title): \(id) is not drawn mid move")
            #expect(drawn.frame.size == CGSize(width: 72, height: 44))
            #expect(drawn.style.cornerRadii == CornerRadii(4))
            #expect(!drawn.style.shadows.isEmpty)
            #expect(drawn.turn3D?.rotationY != 0 || drawn.turn3D?.rotationX != 0, "\(kind.title): tilt dropped")
        }
    }
}
