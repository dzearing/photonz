import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Center on the Artboard: what is picked moves, as one piece, so its middle is
/// the middle of the frame it sits on (`icon-draw-wt.html`, `#layerMenu`).
@Suite("Center on the artboard")
struct CenterOnArtboardTests {

    // MARK: Fixtures

    /// A 24 unit icon frame at (100, 50) on the canvas, holding what it is given.
    private func iconDoc(_ children: [Layer]) -> PhotonzDocument {
        let frame = Layer.frameLayer(name: "Icon", origin: CGPoint(x: 100, y: 50),
                                     size: CGSize(width: 24, height: 24), children: children)
        return PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [frame])
    }

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 2, colorHex: "#112233",
                                        start: .zero, end: CGPoint(x: frame.width, y: frame.height))
        return Layer(name: name, content: .annotation(content), frame: frame)
    }

    private func id(_ doc: PhotonzDocument, _ name: String) -> UUID {
        doc.allLayers.first { $0.name == name }?.id ?? UUID()
    }

    private func centre(_ rect: CGRect?) -> CGPoint? {
        rect.map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    // MARK: Where it lands

    @Test func oneShapeLandsOnTheMiddleOfItsFrame() throws {
        var d = iconDoc([box("Box", CGRect(x: 2, y: 3, width: 6, height: 4))])
        #expect(d.canCenterOnArtboard(ids: [id(d, "Box")]))
        let moved = d.centerOnArtboard(ids: [id(d, "Box")])
        #expect(moved)
        let layer = try #require(d.layer(id: id(d, "Box")))
        #expect(layer.frame == CGRect(x: 9, y: 10, width: 6, height: 4))
        // On the canvas that is the frame's own middle.
        #expect(centre(d.canvasFrame(of: layer.id)) == CGPoint(x: 112, y: 62))
    }

    @Test func severalShapesMoveAsOnePieceAndKeepTheirSpacing() throws {
        var d = iconDoc([box("A", CGRect(x: 0, y: 0, width: 4, height: 4)),
                         box("B", CGRect(x: 6, y: 2, width: 4, height: 4))])
        let moved = d.centerOnArtboard(ids: [id(d, "A"), id(d, "B")])
        #expect(moved)
        // Together they spanned 0...10 by 0...6, so the middle was (5, 3); it
        // is now (12, 12), and each moved by the same (7, 9).
        #expect(d.layer(id: id(d, "A"))?.frame == CGRect(x: 7, y: 9, width: 4, height: 4))
        #expect(d.layer(id: id(d, "B"))?.frame == CGRect(x: 13, y: 11, width: 4, height: 4))
    }

    @Test func aShapeOnNoFrameCentresOnTheCanvas() throws {
        let loose = box("Loose", CGRect(x: 10, y: 10, width: 40, height: 20))
        var d = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [loose])
        let moved = d.centerOnArtboard(ids: [id(d, "Loose")])
        #expect(moved)
        #expect(centre(d.layer(id: id(d, "Loose"))?.frame) == CGPoint(x: 200, y: 150))
    }

    @Test func aShapeInsideAGroupOnAFrameStillCentresOnTheFrame() throws {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [
            box("Inner", CGRect(x: 0, y: 0, width: 4, height: 4)),
        ])), frame: CGRect(x: 2, y: 3, width: 0, height: 0))
        var d = iconDoc([group])
        let moved = d.centerOnArtboard(ids: [id(d, "Inner")])
        #expect(moved)
        #expect(centre(d.canvasFrame(of: id(d, "Inner"))) == CGPoint(x: 112, y: 62))
    }

    @Test func aFramePickedOnItsOwnCentresOnTheCanvas() throws {
        var d = iconDoc([])
        let moved = d.centerOnArtboard(ids: [id(d, "Icon")])
        #expect(moved)
        #expect(centre(d.layer(id: id(d, "Icon"))?.frame) == CGPoint(x: 200, y: 150))
    }

    @Test func aShapeInsideAPickedGroupIsCarriedNotMovedTwice() throws {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [
            box("Inner", CGRect(x: 0, y: 0, width: 4, height: 4)),
        ])), frame: CGRect(x: 2, y: 3, width: 0, height: 0))
        var d = iconDoc([group])
        let moved = d.centerOnArtboard(ids: [id(d, "Group"), id(d, "Inner")])
        #expect(moved)
        #expect(centre(d.canvasFrame(of: id(d, "Inner"))) == CGPoint(x: 112, y: 62))
    }

    @Test func picksOnTwoFramesEachCentreOnTheirOwn() throws {
        let one = Layer.frameLayer(name: "One", origin: .zero, size: CGSize(width: 24, height: 24),
                                   children: [box("A", CGRect(x: 0, y: 0, width: 4, height: 4))])
        let two = Layer.frameLayer(name: "Two", origin: CGPoint(x: 100, y: 0),
                                   size: CGSize(width: 48, height: 48),
                                   children: [box("B", CGRect(x: 0, y: 0, width: 4, height: 4))])
        var d = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [one, two])
        let moved = d.centerOnArtboard(ids: [id(d, "A"), id(d, "B")])
        #expect(moved)
        #expect(centre(d.canvasFrame(of: id(d, "A"))) == CGPoint(x: 12, y: 12))
        #expect(centre(d.canvasFrame(of: id(d, "B"))) == CGPoint(x: 124, y: 24))
    }

    // MARK: When there is nothing to do

    @Test func somethingAlreadyCentredHasNowhereToGo() {
        var d = iconDoc([box("Box", CGRect(x: 9, y: 10, width: 6, height: 4))])
        #expect(!d.canCenterOnArtboard(ids: [id(d, "Box")]))
        let before = d
        let moved = d.centerOnArtboard(ids: [id(d, "Box")])
        #expect(!moved)
        #expect(d == before)
    }

    @Test func aLockedShapeStaysPut() {
        var locked = box("Box", CGRect(x: 2, y: 3, width: 6, height: 4))
        locked.isLocked = true
        let d = iconDoc([locked])
        #expect(!d.canCenterOnArtboard(ids: [id(d, "Box")]))
        #expect(!d.canCenterOnArtboard(ids: []))
    }

    @Test func theMenuWordsAreTheMocks() {
        #expect(CenterOnArtboard.title == "Center on the Artboard")
    }
}
