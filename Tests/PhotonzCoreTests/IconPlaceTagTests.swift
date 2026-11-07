import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The tag above a shape picked in an icon: where it sits and how big it is, in
/// units (`a-shape-picked-in-an-icon-names-its-place-and-si`, the icon mock's
/// `#igTag`). The rule that matters most is the second half: it never sits on
/// the shape or on anything you would reach for.
@Suite("A shape picked in an icon names its place and size")
struct IconPlaceTagTests {

    private static let frame = CGRect(x: 100, y: 100, width: 24, height: 24)
    private static let tag = CGSize(width: 90, height: 20)
    private static let view = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private static func quad(_ box: CGRect) -> [CGPoint] {
        [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
         CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
    }

    private static func grips(_ box: CGRect, rotates: Bool = true,
                              resizes: Bool = true) -> SelectionGrips {
        SelectionGrips(quad: quad(box), mode: .size, rotates: rotates, resizes: resizes,
                       modes: [.size, .reshape, .space])
    }

    // MARK: The words

    @Test func aBoxSaysItsCornerAndItsSize() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.readout(box: CGRect(x: 109, y: 110, width: 6, height: 3), shape: .rectangle)
                == "9, 10 · 6 × 3")
    }

    @Test func aCircleSaysItsCentreAndDiameter() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.readout(box: CGRect(x: 108, y: 104, width: 8, height: 8), shape: .ellipse)
                == "center 12, 8 · d 8")
    }

    @Test func anOvalSaysItsCentreAndBothSides() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.readout(box: CGRect(x: 108, y: 105, width: 8, height: 6), shape: .ellipse)
                == "center 12, 8 · 8 × 6")
    }

    @Test func aPathOrAnythingElseSaysItsBounds() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.readout(box: CGRect(x: 106, y: 104, width: 12, height: 9), shape: nil)
                == "6, 4 · 12 × 9")
    }

    @Test func aPlaceOffTheUnitsSaysItsFraction() {
        let snap = IconSnap(frame: Self.frame)
        #expect(snap.readout(box: CGRect(x: 109.5, y: 110, width: 6.25, height: 3), shape: nil)
                == "9.5, 10 · 6.25 × 3")
    }

    @Test func unitsAreTheIconsOwnNotCanvasPoints() {
        // A picture made as a 24 unit icon can be 480 points across.
        let snap = IconSnap(frame: CGRect(x: 0, y: 0, width: 480, height: 480), unit: 20)
        #expect(snap.readout(box: CGRect(x: 180, y: 200, width: 120, height: 60), shape: .rectangle)
                == "9, 10 · 6 × 3")
    }

    @Test func aTurnedShapeSaysItsTurnToo() {
        #expect(SelectionTag.iconPlace("9, 10 · 6 × 3", rotation: 30) == "9, 10 · 6 × 3 · 30°")
        #expect(SelectionTag.iconPlace("9, 10 · 6 × 3", rotation: 0) == "9, 10 · 6 × 3")
        #expect(SelectionTag.iconPlace("9, 10 · 6 × 3", rotation: 360) == "9, 10 · 6 × 3")
    }

    // MARK: Which layers wear it

    private static func iconDocument() -> (PhotonzDocument, frame: UUID, shape: UUID) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1600, height: 1100))
        let icon = document.addFrame(origin: CGPoint(x: 100, y: 100),
                                     size: CGSize(width: 24, height: 24))
        let drawn = PathContent(anchors: [PathAnchor(point: CGPoint(x: 109, y: 110)),
                                          PathAnchor(point: CGPoint(x: 115, y: 110)),
                                          PathAnchor(point: CGPoint(x: 115, y: 113))],
                                isClosed: true)
        let shape = PenSession.layer(from: drawn)
        document.addLayerDrawnOnFrame(shape)
        return (document, icon.id, shape.id)
    }

    @Test func aShapeInAnIconHasWordsAndTheIconItselfHasNone() {
        let (document, frame, shape) = Self.iconDocument()
        let box = CGRect(x: 109, y: 110, width: 6, height: 3)
        #expect(document.iconPlaceWords(of: shape, box: box) == "9, 10 · 6 × 3")
        #expect(document.iconPlaceWords(of: frame, box: Self.frame) == nil)
    }

    @Test func aShapeOnNoIconHasNoWords() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400))
        let shape = PenSession.layer(from: PathContent(anchors: [PathAnchor(point: CGPoint(x: 9, y: 10)),
                                                                 PathAnchor(point: CGPoint(x: 15, y: 13))],
                                                       isClosed: false))
        document.layers = [shape]
        #expect(document.iconPlaceWords(of: shape.id, box: shape.frame) == nil)
    }

    @Test func theWordsFollowTheBoxInTheHandNotTheStoredOne() {
        let (document, _, shape) = Self.iconDocument()
        let dragged = CGRect(x: 111, y: 112, width: 8, height: 3)
        #expect(document.iconPlaceWords(of: shape, box: dragged) == "11, 12 · 8 × 3")
    }

    // MARK: Where it goes

    /// Everything the tag must keep off, for a test to measure against.
    private static func clear(_ plate: CGRect, of grips: SelectionGrips, box: CGRect) -> Bool {
        !plate.intersects(box) && grips.occupied.allSatisfy { !plate.intersects($0) }
    }

    @Test func aWideShapeWearsItAboveAtItsLeftEdgeClearOfTheKnob() throws {
        let box = CGRect(x: 300, y: 300, width: 400, height: 100)
        let g = Self.grips(box)
        let plate = try #require(g.placeTagFrame(size: Self.tag, in: Self.view))
        #expect(plate.minX == box.minX)
        #expect(plate.maxY < box.minY)
        #expect(Self.clear(plate, of: g, box: box))
    }

    @Test func aSmallShapeWearsItAboveAndLeftOfTheKnob() throws {
        // The mock's 6 × 3 box at 800%: narrower than its own tag.
        let box = CGRect(x: 300, y: 300, width: 48, height: 24)
        let g = Self.grips(box)
        let plate = try #require(g.placeTagFrame(size: Self.tag, in: Self.view))
        let knob = try #require(g.knob)
        #expect(plate.maxX < knob.x - SelectionGrips.knobRadius)
        #expect(plate.maxY < box.minY)
        #expect(Self.clear(plate, of: g, box: box))
    }

    @Test func aShapeThatCannotTurnWearsItCentredAboveAsTheMockDraws() throws {
        let box = CGRect(x: 300, y: 300, width: 48, height: 24)
        let g = Self.grips(box, rotates: false)
        let plate = try #require(g.placeTagFrame(size: Self.tag, in: Self.view))
        #expect(abs(plate.midX - box.midX) < 0.01)
        #expect(plate.maxY < box.minY)
    }

    @Test func atTheTopOfTheViewItFlipsBelowPastTheHintsRow() throws {
        let box = CGRect(x: 300, y: 12, width: 200, height: 100)
        let g = Self.grips(box)
        let plate = try #require(g.placeTagFrame(size: Self.tag, in: Self.view))
        let hint = g.tagFrame(size: Self.tag, in: Self.view)
        #expect(plate.minY >= box.maxY)
        #expect(!plate.intersects(hint))
        #expect(Self.clear(plate, of: g, box: box))
    }

    @Test func withNoRoomAboveOrBelowItGoesBeside() throws {
        let box = CGRect(x: 300, y: 10, width: 200, height: 780)
        let g = Self.grips(box)
        let plate = try #require(g.placeTagFrame(size: Self.tag, in: Self.view))
        #expect(plate.maxX <= box.minX || plate.minX >= box.maxX)
        #expect(Self.clear(plate, of: g, box: box))
    }

    @Test func aShapeFillingTheViewWearsNoTagRatherThanCoverIt() {
        let g = Self.grips(Self.view.insetBy(dx: -40, dy: -40))
        #expect(g.placeTagFrame(size: Self.tag, in: Self.view) == nil)
    }

    @Test func everyPlacementStaysInsideTheView() {
        for x in stride(from: CGFloat(-20), through: 960, by: 70) {
            for y in stride(from: CGFloat(-20), through: 760, by: 70) {
                let box = CGRect(x: x, y: y, width: 48, height: 24)
                let g = Self.grips(box)
                guard let plate = g.placeTagFrame(size: Self.tag, in: Self.view) else { continue }
                #expect(Self.view.contains(plate))
                #expect(Self.clear(plate, of: g, box: box))
            }
        }
    }
}
