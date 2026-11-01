import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The rest of 3D on the reworked selection
/// (`perspective-pill-and-a-shadow-that-grows-as-a-3d`, prototype
/// `selection-transform.html`): a pill beside the mode chip that shows and
/// changes the camera's perspective, Option on an edge pill that scrubs it,
/// dashed lines to the vanishing point while it moves, and a shadow that grows
/// as a layer comes forward.
@Suite("Perspective pill and depth shadow")
struct PerspectivePillTests {

    static let card: [CGPoint] = [CGPoint(x: 150, y: 150), CGPoint(x: 450, y: 150),
                                  CGPoint(x: 450, y: 360), CGPoint(x: 150, y: 360)]

    static func grips(_ mode: TransformMode, rotates: Bool = true,
                      modes: [TransformMode] = TransformMode.offered) -> SelectionGrips {
        SelectionGrips(quad: card, mode: mode, rotates: rotates, resizes: true, modes: modes)
    }

    // MARK: The pill

    @Test("In 3D a pill sits six points right of the chip, on the chip's row")
    func pillBesideTheChip() throws {
        let g = Self.grips(.space)
        let plate = try #require(g.chipPlate)
        let pill = try #require(g.perspective)
        #expect(abs(pill.minX - (plate.maxX + SelectionGrips.perspectiveGap)) < 0.01)
        #expect(abs(pill.midY - plate.midY) < 0.01)
        #expect(pill.size == SelectionGrips.perspectiveSize)
        #expect(SelectionGrips.perspectiveGap == 6)
        #expect(SelectionGrips.perspectiveSize.height == 24)
    }

    @Test("Size and Skew & distort have no pill, and nor does a layer with no chip")
    func pillOnlyIn3D() {
        #expect(Self.grips(.size).perspective == nil)
        #expect(Self.grips(.reshape).perspective == nil)
        #expect(Self.grips(.space, rotates: false).perspective == nil)
    }

    @Test("A press on the pill takes it, and its own target is the whole pill")
    func pillTakesItsPress() throws {
        let g = Self.grips(.space)
        let pill = try #require(g.perspective)
        #expect(g.hit(CGPoint(x: pill.midX, y: pill.midY)) == .perspective)
        #expect(g.hit(CGPoint(x: pill.minX + 1, y: pill.minY + 1)) == .perspective)
        #expect(g.hit(CGPoint(x: pill.maxX + 3, y: pill.midY)) != .perspective)
        // (The area is sampled within 30 points of the middle, a point short
        // of each end of the 62 point pill.)
        #expect(g.hitArea(of: .perspective) >= (pill.width - 2) * pill.height - 1)
        // The chip keeps its own buttons.
        let space = try #require(g.chip.first { $0.mode == .space })
        #expect(g.hit(CGPoint(x: space.frame.midX, y: space.frame.midY)) == .chip(.space))
    }

    @Test("A walk names it perspective")
    func walkName() {
        #expect(SelectionGrip.perspective.name == "perspective")
        #expect(SelectionGrip(name: "perspective") == .perspective)
    }

    @Test("Resting on it, the tag says it changes every 3D layer, inside the chrome's thirty characters")
    func pillTag() {
        let words = SelectionTag.does(.perspective, mode: .space)
        #expect(words == "Perspective · all 3D layers")
        #expect(words.count <= 30)
        #expect(SelectionTag.does(.edge(.top), mode: .space) == "Tip and swing · ⌥ perspective")
        #expect(SelectionTag.does(.edge(.top), mode: .space).count <= 30)
        for value in [0.0, 20, 45, 90, 120, 150] {
            #expect(SelectionTag.perspective(value).count <= 30)
        }
        #expect(SelectionTag.perspective(45) == "Perspective 45° · 3D layers")
        #expect(SelectionTag.perspective(0) == "No perspective · 3D layers")
    }

    @Test("The tag under a card in 3D, put above it, clears the pill too")
    func tagAboveClearsThePill() throws {
        let g = Self.grips(.space)
        let pill = try #require(g.perspective)
        // No room below: the tag goes above, clear of the chip row and pill.
        let tag = g.tagFrame(size: CGSize(width: 400, height: 20), in: CGRect(x: 0, y: 0, width: 900, height: 380))
        #expect(!tag.intersects(pill))
    }

    // MARK: The values

    @Test("The presets are the prototype's: None, Subtle, Normal, Strong")
    func presets() {
        #expect(PerspectiveControl.presets.map(\.name) == ["None", "Subtle", "Normal", "Strong"])
        #expect(PerspectiveControl.presets.map(\.degrees) == [0, 20, 45, 90])
        #expect(PerspectiveControl.range == 0...120)
        #expect(PerspectiveControl.preset(matching: 45)?.name == "Normal")
        #expect(PerspectiveControl.preset(matching: 46) == nil)
        // The default camera is Normal.
        #expect(PerspectiveControl.preset(matching: SceneCamera.defaultPerspective)?.name == "Normal")
    }

    @Test("The pill reads None, or whole degrees")
    func pillWords() {
        #expect(PerspectiveControl.label(0) == "None")
        #expect(PerspectiveControl.label(0.3) == "None")
        #expect(PerspectiveControl.label(45) == "45°")
        #expect(PerspectiveControl.label(89.6) == "90°")
    }

    @Test("A sideways drag on the pill scrubs a degree for every two points, held to the slider's range")
    func pillScrub() {
        #expect(PerspectiveControl.scrubbed(from: 45, by: 30) == 60)
        #expect(PerspectiveControl.scrubbed(from: 45, by: -30) == 30)
        #expect(PerspectiveControl.scrubbed(from: 45, by: -400) == 0)
        #expect(PerspectiveControl.scrubbed(from: 100, by: 400) == 120)
        // A camera set wider than the slider goes no wider for a scrub, and
        // comes down from where it is.
        #expect(PerspectiveControl.scrubbed(from: 140, by: 10) == 140)
        #expect(PerspectiveControl.scrubbed(from: 140, by: -10) == 135)
        // The pill only becomes a scrub once the hand has really moved.
        #expect(!PerspectiveControl.isScrub(CGPoint(x: 3, y: 0)))
        #expect(PerspectiveControl.isScrub(CGPoint(x: 4, y: 0)))
    }

    @Test("Option on an edge pill scrubs a degree for every three points")
    func optionScrub() {
        #expect(PerspectiveControl.scrubbed(from: 45, by: 30, pointsPerDegree: PerspectiveControl.edgeRate) == 55)
        #expect(PerspectiveControl.scrubbed(from: 10, by: -90, pointsPerDegree: PerspectiveControl.edgeRate) == 0)
    }

    // MARK: The vanishing point

    static func tippedQuad(perspective: Double, tip: Double = 35) -> [CGPoint]? {
        let canvas = CGSize(width: 1200, height: 800)
        let projection = Projection3D(camera: SceneCamera(perspective: perspective), canvas: canvas)
        let box = CGRect(x: 400, y: 300, width: 400, height: 200)
        let turn = LayerTurn3D(rotationX: tip).affine(pivot: CGPoint(x: box.midX, y: box.midY))
        return Space3D.quad(of: box, through: turn, projection)
    }

    @Test("A card tipped back: its side edges, carried on, meet at the vanishing point")
    func vanishingPointOfATippedCard() throws {
        let quad = try #require(Self.tippedQuad(perspective: 60))
        let vp = Space3D.vanishingPoint(ofQuad: quad, fallback: CGPoint(x: -1, y: -1))
        func collinear(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
            let cross = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
            return abs(cross) / max(1, hypot(b.x - a.x, b.y - a.y)) < 0.5
        }
        #expect(collinear(quad[3], quad[0], vp))
        #expect(collinear(quad[2], quad[1], vp))
        // Tipped back, the top recedes: the point is above the card, on the
        // canvas's upright through the middle (where the camera looks).
        #expect(vp.y < quad[0].y)
        #expect(abs(vp.x - 600) < 0.5)
        // ...and it is the camera's own vanishing point for that direction:
        // the eye's distance times the edge's slope, from the middle.
        let eye = 400 / tan(30 * Double.pi / 180)
        let tip = 35 * Double.pi / 180
        #expect(abs(Double(vp.y) - (400 - eye * cos(tip) / sin(tip))) < 0.5)
    }

    @Test("Stronger perspective pulls the vanishing point in toward the card")
    func strongerIsNearer() throws {
        let subtle = Space3D.vanishingPoint(ofQuad: try #require(Self.tippedQuad(perspective: 20)), fallback: .zero)
        let strong = Space3D.vanishingPoint(ofQuad: try #require(Self.tippedQuad(perspective: 90)), fallback: .zero)
        #expect(abs(strong.y - 400) < abs(subtle.y - 400))
    }

    @Test("A card square on to the camera has no receding edge: lines go to the fallback")
    func flatCardGoesToTheFallback() throws {
        let flat = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 200), CGPoint(x: 100, y: 200)]
        #expect(Space3D.vanishingPoint(ofQuad: flat, fallback: CGPoint(x: 600, y: 400)) == CGPoint(x: 600, y: 400))
        // A tip too slight to see converges too far away to draw toward.
        let slight = try #require(Self.tippedQuad(perspective: 20, tip: 0.01))
        #expect(Space3D.vanishingPoint(ofQuad: slight, fallback: CGPoint(x: 1, y: 2)) == CGPoint(x: 1, y: 2))
    }

    // MARK: The shadow

    @Test("Forward grows a layer's shadow and back shrinks it; on the canvas it is untouched")
    func shadowScale() {
        #expect(DepthShadow.scale(forDepth: 0) == 1)
        #expect(abs(DepthShadow.scale(forDepth: DepthShadow.doublingDepth) - 2) < 1e-9)
        #expect(abs(DepthShadow.scale(forDepth: -DepthShadow.doublingDepth) - 0.5) < 1e-9)
        #expect(DepthShadow.scale(forDepth: 100_000) == DepthShadow.largest)
        #expect(DepthShadow.scale(forDepth: -100_000) == DepthShadow.smallest)
        #expect(DepthShadow.scale(forDepth: .nan) == 1)
    }

    @Test("A drop shadow lifted forward is further off, softer and a little lighter; an inner one is left alone")
    func liftedShadows() {
        let drop = ShadowStyle(radius: 12, offset: CGSize(width: 2, height: 4), spread: 1, opacity: 0.4)
        let inner = ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 2), opacity: 0.5, kind: .inner)
        let up = DepthShadow.lifted([drop, inner], depth: DepthShadow.doublingDepth)
        #expect(up[0].radius == 24)
        #expect(up[0].offset == CGSize(width: 4, height: 8))
        #expect(up[0].spread == 1)
        #expect(up[0].opacity < 0.4 && up[0].opacity > 0.25)
        #expect(up[1] == inner)
        let back = DepthShadow.lifted([drop], depth: -DepthShadow.doublingDepth)
        #expect(back[0].radius == 6)
        #expect(back[0].offset == CGSize(width: 1, height: 2))
        #expect(back[0].opacity == 0.4)
        #expect(DepthShadow.lifted([drop, inner], depth: 0) == [drop, inner])
    }
}
