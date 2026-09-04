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
