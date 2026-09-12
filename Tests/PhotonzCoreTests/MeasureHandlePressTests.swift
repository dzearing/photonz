import CoreGraphics
import PhotonzCore
import Testing

/// When a press on a measurement's handle becomes a drag.
///
/// The rule under test: a handle is grabbed with several points of slack
/// around its dot, so the point a press lands on is usually NOT the handle.
/// Taking hold of an end must not move it. Only once the pointer has actually
/// travelled is the press an edit.
@Suite("Measure handle press")
struct MeasureHandlePressTests {

    @Test func aPressThatNeverMovesIsNotADrag() {
        #expect(!MeasureHandlePress.travelled(from: CGPoint(x: 795, y: 504),
                                              to: CGPoint(x: 795, y: 504), zoom: 1))
    }

    @Test func aJitterOfAPointIsNotADrag() {
        // A hand resting on a mouse button wobbles; that is still a click.
        #expect(!MeasureHandlePress.travelled(from: CGPoint(x: 795, y: 504),
                                              to: CGPoint(x: 795.5, y: 504.5), zoom: 1))
    }

    @Test func aRealPullIsADrag() {
        #expect(MeasureHandlePress.travelled(from: CGPoint(x: 795, y: 504),
                                             to: CGPoint(x: 812, y: 504), zoom: 1))
    }

    /// The threshold is what the HAND moved on screen, so it does not get
    /// easier or harder to click depending on how far you are zoomed in.
    @Test func theThresholdIsMeasuredInViewPointsNotDocumentPoints() {
        let start = CGPoint(x: 600, y: 500)
        let nudged = CGPoint(x: 603, y: 500)   // 3 document points
        // Zoomed out to a quarter, 3 document points is under a point of hand
        // movement: still a click.
        #expect(!MeasureHandlePress.travelled(from: start, to: nudged, zoom: 0.25))
        // At 1:1 the same 3 points is a real pull.
        #expect(MeasureHandlePress.travelled(from: start, to: nudged, zoom: 1))
    }

    @Test func theThresholdIsExactlyReachedNotJustPassed() {
        let start = CGPoint.zero
        #expect(MeasureHandlePress.travelled(from: start,
                                             to: CGPoint(x: MeasureHandlePress.travelThreshold, y: 0),
                                             zoom: 1))
    }

    /// A degenerate zoom must not turn every click into a drag.
    @Test func aZeroZoomNeverReadsAsTravel() {
        #expect(!MeasureHandlePress.travelled(from: .zero, to: CGPoint(x: 1000, y: 1000), zoom: 0))
    }
}
