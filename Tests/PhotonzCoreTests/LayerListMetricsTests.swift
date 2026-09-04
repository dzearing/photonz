import CoreGraphics
import Testing
@testable import PhotonzCore

/// The layers list hugs a short document and caps a long one. Once the list
/// builds only the rows you can see it can no longer MEASURE how tall it wants
/// to be, so it works the number out from the row count instead. These pin that
/// arithmetic, because getting it wrong is how the list stops hugging.
@Suite("Layers list height")
struct LayerListMetricsTests {

    @Test("An empty document is just the Canvas row")
    func emptyIsCanvasOnly() {
        let h = LayerListMetrics.naturalHeight(rowCount: 0, rowHeight: 38, canvasRowHeight: 38)
        #expect(h == 38 + LayerListMetrics.bottomPadding)
    }

    @Test("One layer is that row, a gap, and the Canvas row")
    func oneRow() {
        let h = LayerListMetrics.naturalHeight(rowCount: 1, rowHeight: 38, canvasRowHeight: 38)
        #expect(h == 38 + LayerListMetrics.spacing + 38 + LayerListMetrics.bottomPadding)
    }

    @Test("Each further row adds its own height plus one gap")
    func growsByOneRowAtATime() {
        let step = LayerListMetrics.naturalHeight(rowCount: 4, rowHeight: 38, canvasRowHeight: 38)
            - LayerListMetrics.naturalHeight(rowCount: 3, rowHeight: 38, canvasRowHeight: 38)
        #expect(step == 38 + LayerListMetrics.spacing)
    }

    @Test("A hundred rows is a hundred times one row's stride above the empty list")
    func scalesLinearly() {
        let empty = LayerListMetrics.naturalHeight(rowCount: 0, rowHeight: 38, canvasRowHeight: 38)
        let many = LayerListMetrics.naturalHeight(rowCount: 100, rowHeight: 38, canvasRowHeight: 38)
        #expect(many - empty == 100 * (38 + LayerListMetrics.spacing))
    }

    @Test("The Canvas row is measured separately, so a taller one still counts once")
    func canvasRowCountsOnce() {
        let h = LayerListMetrics.naturalHeight(rowCount: 3, rowHeight: 38, canvasRowHeight: 50)
        #expect(h == 3 * (38 + LayerListMetrics.spacing) + 50 + LayerListMetrics.bottomPadding)
    }

    /// A row height arrives from a live measurement, and before the first one
    /// lands it can be zero or nonsense. The list must never ask for a negative
    /// frame: that is a crash in one place and an inverted layout in another.
    @Test("Nonsense measurements never produce a negative height")
    func clampsNonsense() {
        #expect(LayerListMetrics.naturalHeight(rowCount: -5, rowHeight: 38, canvasRowHeight: 38)
                == 38 + LayerListMetrics.bottomPadding)
        #expect(LayerListMetrics.naturalHeight(rowCount: 3, rowHeight: -10, canvasRowHeight: -10)
                >= 0)
    }
}

/// Which rows the layers list should make pictures for. A document with a
/// hundred and twenty layers shows five of them, and asking for a hundred and
/// twenty little renders to fill five slots is a hundred and fifteen renders
/// nobody looks at. These pin the window: the rows on screen, plus a few off
/// each edge so a scroll does not outrun the pictures.
@Suite("Layers list thumbnail window")
struct LayerThumbnailWindowTests {

    /// A 38pt row and a 2pt gap: the stride the panel actually uses.
    private let stride: CGFloat = 38

    @Test("A list short enough to fit asks for every row")
    func shortListAsksForEverything() {
        let w = LayerListMetrics.thumbnailWindow(rowCount: 6, rowHeight: stride,
                                                 firstVisibleRow: 0, viewportHeight: 240)
        #expect(w == 0..<6)
    }

    @Test("An empty list asks for nothing")
    func emptyAsksForNothing() {
        #expect(LayerListMetrics.thumbnailWindow(rowCount: 0, rowHeight: stride,
                                                 firstVisibleRow: 0, viewportHeight: 200).isEmpty)
    }

    /// The point of the whole thing: the number of pictures a freshly opened
    /// document asks for does not grow with the document.
    @Test("A hundred layer document asks for no more than a ten layer one")
    func longListCostsTheSameAsAShortOne() {
        let ten = LayerListMetrics.thumbnailWindow(rowCount: 10, rowHeight: stride,
                                                   firstVisibleRow: 0, viewportHeight: 200)
        let hundred = LayerListMetrics.thumbnailWindow(rowCount: 100, rowHeight: stride,
                                                       firstVisibleRow: 0, viewportHeight: 200)
        #expect(hundred.count <= ten.count)
        #expect(hundred.lowerBound == 0)
    }

    @Test("Scrolled into the middle, the window follows the rows on screen")
    func windowFollowsTheScroll() {
        let w = LayerListMetrics.thumbnailWindow(rowCount: 120, rowHeight: stride,
                                                 firstVisibleRow: 60, viewportHeight: 200)
        #expect(w.contains(60))
        #expect(w.contains(64))
        #expect(!w.contains(0))
        #expect(!w.contains(119))
    }

    /// Runway matters more than symmetry: the rows above have been looked at
    /// already and their pictures are kept, the rows below have not.
    @Test("There is a buffer of unseen rows on each side of the screen")
    func bufferSitsOnBothSides() {
        let w = LayerListMetrics.thumbnailWindow(rowCount: 120, rowHeight: stride,
                                                 firstVisibleRow: 60, viewportHeight: 200)
        #expect(w.lowerBound < 60)
        #expect(w.upperBound > 60 + 5)
    }

    @Test("The window never runs off either end of the list")
    func clampsToTheList() {
        let top = LayerListMetrics.thumbnailWindow(rowCount: 120, rowHeight: stride,
                                                   firstVisibleRow: 0, viewportHeight: 200)
        #expect(top.lowerBound == 0)
        let bottom = LayerListMetrics.thumbnailWindow(rowCount: 120, rowHeight: stride,
                                                      firstVisibleRow: 119, viewportHeight: 200)
        #expect(bottom.upperBound == 120)
        #expect(bottom.contains(119))
    }

    /// Every one of a hundred and twenty rows has to be reachable, or scrolling
    /// to the bottom and back leaves grey squares behind.
    @Test("Scrolling the whole list covers every row exactly once at least")
    func everyRowIsReachable() {
        var seen = Set<Int>()
        for first in 0..<120 {
            seen.formUnion(LayerListMetrics.thumbnailWindow(rowCount: 120, rowHeight: stride,
                                                            firstVisibleRow: first,
                                                            viewportHeight: 200))
        }
        #expect(seen.count == 120)
    }

    /// The measured row height arrives late and can be zero. Dividing by it
    /// must not produce a window of every row, which is the bug this fixes.
    @Test("A row height that has not been measured yet does not ask for everything")
    func nonsenseHeightStaysBounded() {
        let w = LayerListMetrics.thumbnailWindow(rowCount: 500, rowHeight: 0,
                                                 firstVisibleRow: 0, viewportHeight: 200)
        #expect(w.count < 500)
        let negative = LayerListMetrics.thumbnailWindow(rowCount: 500, rowHeight: -8,
                                                        firstVisibleRow: -3, viewportHeight: -200)
        #expect(negative.lowerBound >= 0)
        #expect(negative.upperBound <= 500)
    }

    /// The list reports how far it has scrolled in points; the window is
    /// counted in rows, so the panel needs the conversion in the same place as
    /// the rest of the arithmetic.
    @Test("A scroll offset in points becomes the index of the top row")
    func offsetBecomesARowIndex() {
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: 0, rowHeight: stride) == 0)
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: 39, rowHeight: stride) == 0)
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: 40, rowHeight: stride) == 1)
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: 401, rowHeight: stride) == 10)
    }

    @Test("A rubber banded scroll above the top is still the top row")
    func negativeOffsetIsTheTop() {
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: -80, rowHeight: stride) == 0)
        #expect(LayerListMetrics.firstVisibleRow(scrollOffset: 100, rowHeight: 0) == 0)
    }
}
