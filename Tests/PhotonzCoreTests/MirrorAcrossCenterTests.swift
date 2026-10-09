import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Mirror Across Center: the second half of a symmetrical drawing is a copy of
/// the first, reflected about the middle of the frame it sits on, so it is
/// exact by construction rather than by aim (`icon-draw-wt.html`, step 7).
@Suite("Mirror across center")
struct MirrorAcrossCenterTests {

    // MARK: Fixtures

    /// A 24 unit icon frame at (100, 50) on the canvas, holding what it is given.
    private func iconDoc(_ children: [Layer]) -> PhotonzDocument {
        let frame = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 100, y: 50),
                                     size: CGSize(width: 24, height: 24), children: children)
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [frame])
    }

    /// An ellipse of diameter `d` centred on `centre`, filled and outlined.
    private func ellipse(centre: CGPoint, d: CGFloat) -> Layer {
        var content = AnnotationContent(shape: .ellipse, strokeWidth: 0, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: d, y: d),
                                        fillColorHex: "#445566")
        content.strokeWidth = 0
        return Layer(name: "Ellipse", content: .annotation(content),
                     frame: CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d))
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func centre(_ rect: CGRect?) -> CGPoint? {
        rect.map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    // MARK: The mock's shoulder

    @Test func theShoulderAtNineTenLandsAtFifteenTen() throws {
        var d = iconDoc([ellipse(centre: CGPoint(x: 9, y: 10), d: 6)])
        let source = id(d, "Ellipse")
        let made = d.mirrorAcrossCenter(ids: [source])
        #expect(made.count == 1)
        let copy = try #require(d.layer(id: made[0]))
        // In the frame's own units: 9 reflected about x = 12 is 15.
        #expect(centre(copy.frame) == CGPoint(x: 15, y: 10))
        #expect(copy.frame.size == CGSize(width: 6, height: 6))
        // The original has not moved.
        #expect(centre(d.layer(id: source)?.frame) == CGPoint(x: 9, y: 10))
    }

    @Test func theCopyWearsTheSameFillOutlineAndEffects() throws {
        var shape = ellipse(centre: CGPoint(x: 9, y: 10), d: 6)
        shape.style.opacity = 0.5
        var d = iconDoc([shape])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse")])
        let copy = try #require(d.layer(id: made[0]))
        let source = try #require(d.layer(id: id(d, "Ellipse")))
        #expect(copy.content == source.content)
        #expect(copy.style == source.style)
        #expect(copy.id != source.id)
    }

    @Test func theCopySitsDirectlyAboveItsOriginalOnTheSameFrame() throws {
        let other = ellipse(centre: CGPoint(x: 4, y: 4), d: 2)
        var renamed = other
        renamed.name = "Dot"
        var d = iconDoc([ellipse(centre: CGPoint(x: 9, y: 10), d: 6), renamed])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse")])
        let frame = try #require(d.layers.first)
        #expect(frame.children.map(\.id) == [id(d, "Ellipse"), made[0], id(d, "Dot")])
    }

    @Test func theCopyTakesTheNameADuplicateWould() throws {
        var d = iconDoc([ellipse(centre: CGPoint(x: 9, y: 10), d: 6)])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse")])
        #expect(d.layer(id: made[0])?.name == "Ellipse 2")
    }

    @Test func aLeftHalfNamedByAPersonComesBackAsTheRightHalf() throws {
        var shape = ellipse(centre: CGPoint(x: 9, y: 10), d: 6)
        shape.name = "Shoulder left"
        var d = iconDoc([shape])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Shoulder left")])
        #expect(d.layer(id: made[0])?.name == "Shoulder right")
    }

    @Test func theSideWordSwapsEitherWayAndKeepsItsCase() {
        #expect(MirrorAcrossCenter.mirroredName("Right Wing") == "Left Wing")
        #expect(MirrorAcrossCenter.mirroredName("LEFT ear") == "RIGHT ear")
        #expect(MirrorAcrossCenter.mirroredName("arm-left") == "arm-right")
        // Only a whole word: "Leftover" is not a side.
        #expect(MirrorAcrossCenter.mirroredName("Leftover") == nil)
        #expect(MirrorAcrossCenter.mirroredName("Ellipse") == nil)
    }

    @Test func aSwappedNameAlreadyTakenFallsBackToTheCopyName() throws {
        var left = ellipse(centre: CGPoint(x: 9, y: 10), d: 6)
        left.name = "Shoulder left"
        var right = ellipse(centre: CGPoint(x: 15, y: 10), d: 6)
        right.name = "Shoulder right"
        var d = iconDoc([left, right])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Shoulder left")])
        #expect(d.layer(id: made[0])?.name == "Shoulder left copy")
    }

    // MARK: Paths, point for point

    @Test func aPathIsMirroredPointForPointHandlesIncluded() throws {
        // A curved wedge in its own 6 x 8 box, standing at (3, 2) on the frame.
        let anchors = [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 6, y: 4), handleIn: CGPoint(x: -1, y: -2),
                       handleOut: CGPoint(x: 1, y: 2), kind: .smooth),
            PathAnchor(point: CGPoint(x: 2, y: 8), cornerRadius: 1.5),
        ]
        let content = PathContent(anchors: anchors, isClosed: true)
        let path = Layer(name: "Path", content: .path(content),
                         frame: CGRect(x: 3, y: 2, width: 6, height: 8))
        var d = iconDoc([path])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Path")])
        let copy = try #require(d.layer(id: made[0]))
        // The box: 3...9 reflected about 12 is 15...21.
        #expect(copy.frame == CGRect(x: 15, y: 2, width: 6, height: 8))
        let mirrored = try #require(copy.path)
        #expect(mirrored.anchors.map(\.point) == [CGPoint(x: 6, y: 0),
                                                   CGPoint(x: 0, y: 4),
                                                   CGPoint(x: 4, y: 8)])
        #expect(mirrored.anchors[1].handleIn == CGPoint(x: 1, y: -2))
        #expect(mirrored.anchors[1].handleOut == CGPoint(x: -1, y: 2))
        #expect(mirrored.anchors[1].kind == .smooth)
        #expect(mirrored.anchors[2].cornerRadius == 1.5)
        #expect(mirrored.isClosed)
        // Every point lands where the original's reflection is, on the canvas.
        let source = try #require(d.layer(id: id(d, "Path")))
        let sourceOrigin = try #require(d.parentOrigin(of: source.id))
        for (a, b) in zip(content.anchors, mirrored.anchors) {
            let was = a.point.x + source.frame.minX + sourceOrigin.x
            let now = b.point.x + copy.frame.minX + sourceOrigin.x
            #expect(was + now == 224, "\(was) + \(now)")
        }
    }

    // MARK: Which middle

    @Test func aShapeOnNoFrameMirrorsAboutTheCanvasMiddle() throws {
        var shape = ellipse(centre: CGPoint(x: 50, y: 40), d: 20)
        shape.name = "Loose"
        var d = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [shape])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Loose")])
        let copy = try #require(d.layer(id: made[0]))
        #expect(centre(copy.frame) == CGPoint(x: 350, y: 40))
    }

    @Test func aShapeInsideAGroupOnAFrameStillMirrorsAboutTheFrame() throws {
        // A group anchored at (2, 3) inside the frame, the ellipse at 7, 7 in
        // the group's space, so 9, 10 in the frame's.
        let group = Layer(name: "Group", content: .group(GroupContent(children: [
            ellipse(centre: CGPoint(x: 7, y: 7), d: 6),
        ])), frame: CGRect(x: 2, y: 3, width: 0, height: 0))
        var d = iconDoc([group])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse")])
        let box = try #require(d.canvasFrame(of: made[0]))
        // Frame at 100, 50: 15, 10 on the frame is 115, 60 on the canvas.
        #expect(centre(box) == CGPoint(x: 115, y: 60))
        #expect(d.parentID(of: made[0]) == id(d, "Group"))
    }

    @Test func aWholeGroupMirrorsWithItsContentsReflected() throws {
        let left = ellipse(centre: CGPoint(x: 1, y: 1), d: 2)
        var right = ellipse(centre: CGPoint(x: 5, y: 1), d: 2)
        right.name = "Right"
        let group = Layer(name: "Pair", content: .group(GroupContent(children: [left, right])),
                          frame: CGRect(x: 2, y: 3, width: 0, height: 0))
        var d = iconDoc([group])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Pair")])
        let copyID = try #require(made.first)
        let kids = try #require(d.layer(id: copyID)?.children)
        let boxes = kids.compactMap { d.canvasFrame(of: $0.id) }.map { centre($0)?.x }
        // On the frame the pair sat at x = 3 and 7, so the copies are at 21 and 17.
        #expect(boxes == [121, 117])
    }

    @Test func aTurnedShapeTurnsTheOtherWay() throws {
        var shape = ellipse(centre: CGPoint(x: 9, y: 10), d: 6)
        shape.transform = LayerTransform(rotation: 30, skewX: 5, skewY: -4)
        var d = iconDoc([shape])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse")])
        let copy = try #require(d.layer(id: made[0]))
        #expect(copy.transform == LayerTransform(rotation: -30, skewX: -5, skewY: 4))
    }

    @Test func aRoundedBoxSwapsItsLeftAndRightCorners() throws {
        var content = AnnotationContent(shape: .rectangle, start: .zero, end: CGPoint(x: 8, y: 4),
                                        cornerRadii: CornerRadii(topLeft: 1, topRight: 2,
                                                                 bottomRight: 3, bottomLeft: 4))
        content.strokeWidth = 0
        let box = Layer(name: "Box", content: .annotation(content),
                        frame: CGRect(x: 2, y: 2, width: 8, height: 4))
        var d = iconDoc([box])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Box")])
        guard case .annotation(let mirrored) = d.layer(id: made[0])?.content else {
            Issue.record("not an annotation"); return
        }
        #expect(mirrored.cornerRadii == CornerRadii(topLeft: 2, topRight: 1,
                                                    bottomRight: 4, bottomLeft: 3))
    }

    @Test func anArrowsEndsAndBendAreReflected() throws {
        var content = AnnotationContent(shape: .arrow, start: CGPoint(x: 1, y: 1),
                                        end: CGPoint(x: 9, y: 5))
        content.bend = ArrowBend(along: 0.5, across: 3)
        let arrow = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 6))
        var d = iconDoc([arrow])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Arrow")])
        guard case .annotation(let mirrored) = d.layer(id: made[0])?.content else {
            Issue.record("not an annotation"); return
        }
        #expect(mirrored.start == CGPoint(x: 9, y: 1))
        #expect(mirrored.end == CGPoint(x: 1, y: 5))
        #expect(mirrored.bend == ArrowBend(along: 0.5, across: -3))
    }

    @Test func aPictureIsFlippedRatherThanRedrawn() throws {
        let picture = Layer(name: "Picture", content: .image(ImageRef(pixelSize: CGSize(width: 4, height: 4))),
                            frame: CGRect(x: 2, y: 2, width: 4, height: 4))
        var d = iconDoc([picture])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Picture")])
        let copy = try #require(d.layer(id: made[0]))
        #expect(copy.transform.flipHorizontal)
        #expect(copy.frame == CGRect(x: 18, y: 2, width: 4, height: 4))
    }

    // MARK: Several at once, and what is refused

    @Test func severalShapesMirrorInOneGo() throws {
        var dot = ellipse(centre: CGPoint(x: 3, y: 3), d: 2)
        dot.name = "Dot"
        var d = iconDoc([ellipse(centre: CGPoint(x: 9, y: 10), d: 6), dot])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Ellipse"), id(d, "Dot")])
        #expect(made.count == 2)
        let centres = Set(made.compactMap { centre(d.layer(id: $0)?.frame) }.map { "\($0.x),\($0.y)" })
        #expect(centres == ["15.0,10.0", "21.0,3.0"])
    }

    @Test func aShapeInsideAPickedGroupIsCarriedNotCopiedTwice() throws {
        let group = Layer(name: "Pair", content: .group(GroupContent(children: [
            ellipse(centre: CGPoint(x: 1, y: 1), d: 2),
        ])), frame: CGRect(x: 2, y: 3, width: 0, height: 0))
        var d = iconDoc([group])
        let made = d.mirrorAcrossCenter(ids: [id(d, "Pair"), id(d, "Ellipse")])
        #expect(made.count == 1)
        #expect(d.allLayers.filter { $0.name.hasPrefix("Ellipse") }.count == 2)
    }

    @Test func nothingMirrorsWhenNothingCanBe() {
        var locked = ellipse(centre: CGPoint(x: 9, y: 10), d: 6)
        locked.isLocked = true
        var d = iconDoc([locked])
        let lockedID = id(d, "Ellipse")
        #expect(!d.canMirrorAcrossCenter(ids: [lockedID]))
        #expect(!d.canMirrorAcrossCenter(ids: []))
        #expect(d.mirrorAcrossCenter(ids: [lockedID]).isEmpty)
        let open = iconDoc([ellipse(centre: CGPoint(x: 9, y: 10), d: 6)])
        #expect(open.canMirrorAcrossCenter(ids: [id(open, "Ellipse")]))
    }

    @Test func aMeasurementIsNotMirrored() {
        let measure = Layer(name: "Measure", content: .measure(MeasureContent(
            start: .zero, end: CGPoint(x: 10, y: 0))),
                            frame: CGRect(x: 2, y: 2, width: 10, height: 1))
        let d = iconDoc([measure])
        #expect(!d.canMirrorAcrossCenter(ids: [id(d, "Measure")]))
    }

    @Test func theMenuWordsAreTheMocks() {
        #expect(MirrorAcrossCenter.title == "Mirror Across Center")
        #expect(LayersPanelHeader.MenuRow.allCases.firstIndex(of: .mirrorAcrossCenter)
                == (LayersPanelHeader.MenuRow.allCases.firstIndex(of: .groupSelection) ?? -9) + 1)
        #expect(LayersPanelHeader.MenuRow.mirrorAcrossCenter.title == "Mirror Across Center")
        #expect(LayersPanelHeader.MenuRow.mirrorAcrossCenter.shortcut
                == LayersPanelHeader.Shortcut(key: "m", modifiers: [.shift, .command]))
    }
}
