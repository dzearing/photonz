import CoreGraphics
import PhotonzCore
import Testing

/// Resizing the selection outline to an exact box: the same act as typing a
/// width into the panel while a selection tool has the arrow keys.
@Suite("Resize a selection region")
struct SelectionRegionResizeTests {

    private func region(_ rect: CGRect) -> SelectionRegion {
        guard let region = SelectionRegion.rect(rect) else {
            fatalError("test fixture: \(rect) encloses no area")
        }
        return region
    }

    private func expectBounds(_ region: SelectionRegion?, _ box: CGRect,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        guard let bounds = region?.bounds else {
            Issue.record("no region", sourceLocation: sourceLocation)
            return
        }
        // Scaling a path and re-measuring it is float work, so the box is
        // compared to within a thousandth of a point rather than exactly.
        let tolerance: CGFloat = 0.001
        #expect(abs(bounds.minX - box.minX) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(bounds.minY - box.minY) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(bounds.width - box.width) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(bounds.height - box.height) < tolerance, sourceLocation: sourceLocation)
    }

    @Test func aRectRegionTakesTheBoxExactly() {
        let start = region(CGRect(x: 10, y: 20, width: 40, height: 30))
        expectBounds(start.resized(to: CGRect(x: 100, y: 200, width: 60, height: 15)),
                     CGRect(x: 100, y: 200, width: 60, height: 15))
    }

    @Test func anEllipseKeepsItsShapeWhileItsBoxChanges() throws {
        let start = try #require(SelectionRegion.ellipse(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let resized = try #require(start.resized(to: CGRect(x: 0, y: 0, width: 200, height: 200)))
        expectBounds(resized, CGRect(x: 0, y: 0, width: 200, height: 200))
        // Still an ellipse: the middle is in, the corners of the box are not.
        #expect(resized.contains(CGPoint(x: 100, y: 100)))
        #expect(!resized.contains(CGPoint(x: 6, y: 6)))
    }

    @Test func theSameBoxIsNoChangeAtAll() {
        let box = CGRect(x: 10, y: 20, width: 40, height: 30)
        #expect(region(box).resized(to: box) == region(box))
    }

    @Test func aBoxWithNoAreaIsRefused() {
        let start = region(CGRect(x: 10, y: 20, width: 40, height: 30))
        #expect(start.resized(to: CGRect(x: 0, y: 0, width: 0, height: 30)) == nil)
        #expect(start.resized(to: CGRect(x: 0, y: 0, width: 40, height: 0)) == nil)
    }

    @Test func aBoxThatIsNotARealNumberIsRefused() {
        let start = region(CGRect(x: 10, y: 20, width: 40, height: 30))
        #expect(start.resized(to: CGRect(x: CGFloat.nan, y: 0, width: 40, height: 30)) == nil)
        #expect(start.resized(to: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 30)) == nil)
    }
}

/// The selection box as the four numbers the Position & Size panel shows while
/// a selection tool has the arrow keys.
@Suite("Region geometry")
struct RegionGeometryTests {

    private let box = CGRect(x: 12, y: 34, width: 56, height: 78)

    @Test func everyFieldShowsTheSelectionBoxsOwnNumber() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.reading(.x) == .agreed(12))
        #expect(geometry.reading(.y) == .agreed(34))
        #expect(geometry.reading(.width) == .agreed(56))
        #expect(geometry.reading(.height) == .agreed(78))
    }

    @Test func theNumbersAreWholePointsLikeTheLayerFields() {
        let geometry = RegionGeometry(bounds: CGRect(x: 12.4, y: 33.6, width: 56.5, height: 78.2))
        #expect(geometry.reading(.x) == .agreed(12))
        #expect(geometry.reading(.y) == .agreed(34))
        #expect(geometry.reading(.height) == .agreed(78))
    }

    @Test func typingAPositionMovesTheBoxAndLeavesItsSizeAlone() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.applying(100, to: .x) == CGRect(x: 100, y: 34, width: 56, height: 78))
        #expect(geometry.applying(0, to: .y) == CGRect(x: 12, y: 0, width: 56, height: 78))
    }

    @Test func typingASizeGrowsTheBoxFromItsTopLeftCorner() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.applying(200, to: .width) == CGRect(x: 12, y: 34, width: 200, height: 78))
        #expect(geometry.applying(10, to: .height) == CGRect(x: 12, y: 34, width: 56, height: 10))
    }

    @Test func aSizeStopsWhereALayersWouldStop() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.applying(0, to: .width)?.width == LayerGeometry.minimumSide)
        #expect(geometry.applying(-40, to: .height)?.height == LayerGeometry.minimumSide)
    }

    @Test func aNumberThatChangesNothingIsNoMoveAtAll() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.applying(12, to: .x) == nil)
        #expect(geometry.applying(56, to: .width) == nil)
    }

    @Test func typingSomethingThatIsNotANumberLeavesTheBoxAlone() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.applying(CGFloat.nan, to: .x) == nil)
        #expect(geometry.applying(CGFloat.infinity, to: .width) == nil)
    }

    @Test func anArrowKeyStepsByOneAndShiftByTen() {
        let geometry = RegionGeometry(bounds: box)
        #expect(geometry.stepping(.x, direction: 1, coarse: false)?.minX == 13)
        #expect(geometry.stepping(.x, direction: -1, coarse: false)?.minX == 11)
        #expect(geometry.stepping(.y, direction: 1, coarse: true)?.minY == 44)
        #expect(geometry.stepping(.width, direction: -1, coarse: true)?.width == 46)
    }

    @Test func steppingCountsFromTheWholeNumberOnScreen() {
        // 56.4 shows as 56, so one press up has to produce 57 rather than 57.4.
        let geometry = RegionGeometry(bounds: CGRect(x: 0, y: 0, width: 56.4, height: 10))
        #expect(geometry.stepping(.width, direction: 1, coarse: false)?.width == 57)
    }

    @Test func steppingDownAtTheFloorHoldsAtTheFloor() {
        let geometry = RegionGeometry(bounds: CGRect(x: 0, y: 0, width: 1, height: 10))
        #expect(geometry.stepping(.width, direction: -1, coarse: false) == nil)
    }

    @Test func theCaptionSaysWhoseNumbersTheseAre() {
        let caption = RegionGeometry(bounds: box).caption
        #expect(caption.contains("selection"))
        #expect(!caption.contains("—"))
    }

    @Test func everyFieldHasATipThatNamesTheSelection() {
        for field in LayerGeometryField.allCases {
            #expect(RegionGeometry.help(field).lowercased().contains("selection"))
        }
    }
}
