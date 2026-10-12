import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Title parts and words that come in through depth: Swing In, Flip Up, Fly In
/// From Depth and Tilt Settle, with their outs (task
/// `3d-transitions-and-title-entrances-flip-cube-swi`).
///
/// A part compiles to ordinary keys on Rotation X, Rotation Y and Depth, plus
/// the hinge it hangs from; words by line, word or letter turn piece by piece
/// in their own reveal. The bar: at the midpoint of each, what moves is turned
/// at least 20 degrees from flat and lands visibly non-rectangular, and frames
/// a tenth of a second apart differ.
@Suite("Titles come in through depth")
struct TitleDepthBuildTests {

    static func angle(_ layer: Layer?) -> Double {
        guard let turn = layer?.turn3D else { return 0 }
        return max(abs(turn.rotationX), abs(turn.rotationY))
    }

    static func quad(_ doc: PhotonzDocument, _ group: UUID, _ path: String, atMS ms: Int) -> [CGPoint]? {
        let drawn = doc.drawn(atTimeMS: ms)
        guard let title = drawn.layer(id: group), let piece = TitleDesign.find(path, in: title) else { return nil }
        return drawn.drawnQuad(of: piece.id)
    }

    @Test("Four kinds turn in depth, each named, each easing in and out so the turn shows half way")
    func theFourKinds() {
        #expect(TitleBuildKind.inDepth.map(\.title) == ["Swing In", "Flip Up", "Fly In From Depth", "Tilt Settle"])
        for kind in TitleBuildKind.inDepth {
            #expect(TitleBuildKind.allCases.contains(kind))
            #expect(TitleBuild(kind, delayMS: 0, lengthMS: 600).curve == kind.defaultCurve)
        }
        #expect(TitleBuild(.rise, delayMS: 0, lengthMS: 600).curve == .easeOutExpo)
    }

    @Test("At the midpoint of each, the part is turned at least 20 degrees and lands visibly off square",
          arguments: TitleBuildKind.inDepth)
    func midpointIsTurned(kind: TitleBuildKind) throws {
        let (doc, id) = try TitleDesignTests.oneBox(TitlePart(path: "Box", role: .accent,
                                                              in: TitleBuild(kind, delayMS: 0, lengthMS: 600)))
        let mid = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 300))
        #expect(Self.angle(mid) >= 20, "\(kind.title) is turned \(Self.angle(mid)) at its midpoint")
        let quad = try #require(Self.quad(doc, id, "Box", atMS: 300))
        let box = CGRect(x: 200, y: 300, width: 400, height: 100)
        let share = abs(Space3D.signedArea(quad)) / 2 / Double(box.width * box.height)
        let skew = DepthTransitionTests.skew(quad)
        #expect(skew >= 3 || share < 0.9, "\(kind.title): corners off by \(skew), covers \(share)")
        // A tenth of a second apart, the corners have moved.
        let early = try #require(Self.quad(doc, id, "Box", atMS: 250))
        let late = try #require(Self.quad(doc, id, "Box", atMS: 350))
        let moved = zip(early, late).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        #expect(moved > 5, "\(kind.title) moved \(moved) points in 100 ms")
        // And it lands flat, exactly where it was drawn.
        let landed = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 600))
        #expect(!landed.isTurnedInSpace)
        #expect(landed.style.opacity > 0.99)
    }

    @Test("Swing In rising up hangs from its bottom edge, which stays put while it swings")
    func swingHangsFromItsEdge() throws {
        let (doc, id) = try TitleDesignTests.oneBox(TitlePart(path: "Box", role: .accent,
                                                              in: TitleBuild(.swingIn, delayMS: 0, lengthMS: 600)))
        let start = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 0))
        #expect(start.turn3D?.hinge == CGPoint(x: 0.5, y: 1))
        #expect(abs((start.turn3D?.rotationX ?? 0) - 90) < 0.01)
        #expect(start.style.opacity < 0.01)
        let quad = try #require(Self.quad(doc, id, "Box", atMS: 300))
        // The bottom edge, quad[2] and quad[3], is where it was drawn.
        #expect(abs(quad[2].y - 400) < 0.5 && abs(quad[3].y - 400) < 0.5)
        #expect(quad[0].y > 300.5)
    }

    @Test("Flip Up hides its back, so it shows from edge on")
    func flipHidesItsBack() throws {
        let (doc, id) = try TitleDesignTests.oneBox(TitlePart(path: "Box", role: .accent,
                                                              in: TitleBuild(.flipUp, delayMS: 0, lengthMS: 600)))
        let start = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 0))
        #expect(start.turn3D?.showsBackFace == false)
        let facing = try #require(Self.quad(doc, id, "Box", atMS: 20))
        #expect(!Space3D.facesViewer(facing))
        #expect(Space3D.facesViewer(try #require(Self.quad(doc, id, "Box", atMS: 400))))
    }

    @Test("Fly In From Depth starts far back and small")
    func flyStartsFar() throws {
        let (doc, id) = try TitleDesignTests.oneBox(
            TitlePart(path: "Box", role: .accent,
                      in: TitleBuild(.flyInFromDepth, delayMS: 0, lengthMS: 600, direction: .left)))
        let start = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 0))
        #expect(abs((start.turn3D?.depth ?? 0) + 900) < 0.01)
        let quad = try #require(Self.quad(doc, id, "Box", atMS: 250))
        // Far back, it covers less of the frame than it does at home.
        #expect(abs(Space3D.signedArea(quad)) / 2 < 400 * 100 * 0.8)
    }

    @Test("Each has an out that turns it away again", arguments: TitleBuildKind.inDepth)
    func outsTurnAway(kind: TitleBuildKind) throws {
        let (doc, id) = try TitleDesignTests.oneBox(TitlePart(path: "Box", role: .accent,
                                                              out: TitleBuild.off(kind, delayMS: 0, lengthMS: 600)))
        #expect(!(try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 3000))).isTurnedInSpace)
        let leaving = try #require(TitleDesignTests.piece(doc, id, "Box", atMS: 3999))
        #expect(Self.angle(leaving) > 20)
    }

    @Test("A design that stops turning in depth takes its hinge and hidden back with it")
    func clearingTakesTheSetupOff() throws {
        var (doc, id) = try TitleDesignTests.oneBox(TitlePart(path: "Box", role: .accent,
                                                              in: TitleBuild(.swingIn, delayMS: 0, lengthMS: 600)))
        let design = TitleDesign(parts: [TitlePart(path: "Box", role: .accent,
                                                   in: TitleBuild(.swingIn, delayMS: 0, lengthMS: 600))])
        doc.clearTitleDesign(design, layerID: id)
        let title = try #require(doc.layer(id: id))
        let box = try #require(TitleDesign.find("Box", in: title))
        #expect(box.turn3D == nil)
        #expect((box.motions ?? []).allSatisfy { !MotionProperty.spaceProperties.contains($0.property) })
    }

    // MARK: - By word and by letter

    @Test("By word, the words swing in one after another, each turned at its own midpoint",
          arguments: TitleBuildKind.inDepth)
    func byWord(kind: TitleBuildKind) throws {
        let (doc, id) = try TitleDesignTests.oneBox(
            TitlePart(path: "Words", role: .headline,
                      in: TitleBuild(kind, delayMS: 0, lengthMS: 600, by: .word, staggerMS: 100)))
        let title = try #require(doc.layer(id: id))
        let words = try #require(TitleDesign.find("Words", in: title))
        let reveal = try #require(words.text?.reveal)
        #expect(reveal.style.isInDepth)
        #expect(reveal.unit == .word)
        // The first word half way through its own arrival.
        let pose = reveal.pose(rank: 0, atElapsedMS: 300)
        #expect(max(abs(pose.turnX), abs(pose.turnY)) >= 20, "\(kind.title): \(pose)")
        // The second word starts a stagger later, so it is further from home.
        let next = reveal.pose(rank: 1, atElapsedMS: 300)
        #expect(max(abs(next.turnX), abs(next.turnY)) > max(abs(pose.turnX), abs(pose.turnY))
                || next.depthEm < pose.depthEm)
        // A tenth of a second later the first word has turned on.
        let later = reveal.pose(rank: 0, atElapsedMS: 400)
        #expect(later.turnX != pose.turnX || later.turnY != pose.turnY || later.depthEm != pose.depthEm)
        #expect(reveal.pose(rank: 0, atElapsedMS: 600).isAtRest)
    }

    @Test("A by-letter swing hangs each letter from the edge it swings from")
    func byLetterHinges() {
        let up = TextReveal(style: .swingIn, unit: .letter, direction: .up)
        #expect(up.pose(rank: 0, atElapsedMS: 100).hinge == CGPoint(x: 0.5, y: 1))
        let left = TextReveal(style: .swingIn, unit: .letter, direction: .left)
        #expect(left.pose(rank: 0, atElapsedMS: 100).hinge == CGPoint(x: 1, y: 0.5))
        #expect(TextReveal(style: .flipUp, unit: .letter).pose(rank: 0, atElapsedMS: 100).hidesBack)
    }

    // MARK: - Motion blur

    @Test("Under a motion blur, a layer swinging in space is smeared along where the camera sees it go")
    func smearSeesTheSwing() throws {
        var doc = TitleDesignTests.tenSeconds()
        var card = Space3DTests.box(CGRect(x: 760, y: 340, width: 400, height: 400))
        card.style.effects.append(.motionBlur(MotionBlurEffect(shutterAngle: 180, isOn: true)))
        card.motions = [LayerMotion.keyed(.rotationY, atMS: 0, value: .number(0))
            .rebuilt(from: [MotionStop(atMS: 0, value: .number(0)), MotionStop(atMS: 1000, value: .number(180))])]
        doc.layers.append(card)
        let shown = doc.drawn(atTimeMS: 400)
        let smear = try #require(shown.layer(id: card.id)?.motionSmear)
        #expect(smear.span > 10)
        // A flat box with the same keys measured flat would not have moved
        // at all: its box never changes.
        #expect(card.drawnQuad(origin: .zero, sizedLike: card) == card.drawnQuad(origin: .zero, sizedLike: card,
                                                                                    projection: nil))
    }

    @Test("A transition with its motion blur on smears its pictures; off, it leaves them sharp")
    func transitionMotionBlur() throws {
        for blurred in [false, true] {
            var pieces = ClipTransitionTests.cutClip()
            let put = pieces.setTransition(ClipTransition(kind: .cube, lengthMS: 1000, motionBlur: blurred),
                                           atCut: 1)
            #expect(put)
            let shown = ClipTransitionTests.clipDocument(pieces).drawn(atTimeMS: 3000)
            #expect(shown.layers.count == 2)
            #expect(shown.layers.allSatisfy { ($0.motionSmear != nil) == blurred })
        }
    }
}
