import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Scrolling along time redraws as little as it can**
/// (`TimelineDrawnStretch`, `MotionStripRuler.measured(fromMS:)`).
///
/// A scroll held at the timeline's edge moves the window sixty times a second.
/// A clip's bar used to be drawn against the window itself, so every one of
/// those frames rebuilt every bar on every track. Now a bar is drawn against a
/// ruler measured from its own start, which a scroll does not change, and slid
/// into place; it is cut down to a stretch a good way wider than the window,
/// which moves only once the window has gone half its own width.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("Scrolling along time redraws as little as it can")
struct TimelineDrawnStretchTests {

    static let fourteenSeconds: Double = 14_000
    static let fiveMinutes: Double = 5 * 60 * 1000

    // MARK: - A ruler measured from somewhere else

    @Test func aRulerMeasuredFromAMomentPutsThatMomentAtTheLeftEdge() {
        let window = MotionStripRuler(documentMS: Int(Self.fourteenSeconds),
                                      zoom: TimelineZoom(scale: 2, startMS: 3000))
        let fromBar = window.measured(fromMS: 5000)
        #expect(fromBar.fraction(ofMS: 5000) == 0)
        #expect(fromBar.startMS == 5000)
    }

    @Test func aRulerMeasuredFromAMomentKeepsItsScale() {
        let window = MotionStripRuler(documentMS: Int(Self.fourteenSeconds),
                                      zoom: TimelineZoom(scale: 2, startMS: 3000))
        let fromBar = window.measured(fromMS: 5000)
        #expect(fromBar.spanMS == window.spanMS)
        #expect(fromBar.cycleMS == window.cycleMS)
        #expect(fromBar.repeats == window.repeats)
        #expect(fromBar.fraction(spanningMS: 1200) == window.fraction(spanningMS: 1200))
        #expect(fromBar.msSpanning(fraction: 0.25) == window.msSpanning(fraction: 0.25))
    }

    /// Drawn from the bar's start and slid along by where that start is in
    /// the window, everything lands where the window's own ruler puts it.
    @Test func slidAlongByItsStartEverythingLandsWhereTheWindowPutsIt() {
        let window = MotionStripRuler(documentMS: Int(Self.fourteenSeconds),
                                      zoom: TimelineZoom(scale: 2, startMS: 3000))
        let barStart = 5000.0
        let fromBar = window.measured(fromMS: barStart)
        for ms in [0.0, 2999, 5000, 6500, 9999, 14_000] {
            let slid = fromBar.fraction(ofMS: ms) + window.fraction(ofMS: barStart)
            #expect(abs(slid - window.fraction(ofMS: ms)) < 1e-12)
            #expect(abs(fromBar.ms(atFraction: fromBar.fraction(ofMS: ms)) - ms) < 1e-9)
        }
    }

    @Test func aLapRulerCanBeMeasuredFromAMomentToo() {
        let lap = MotionStripRuler(cycleMS: 2000)
        let fromBar = lap.measured(fromMS: 400)
        #expect(fromBar.repeats)
        #expect(fromBar.spanMS == lap.spanMS)
        #expect(abs(fromBar.fraction(ofMS: 900) + lap.fraction(ofMS: 400) - lap.fraction(ofMS: 900)) < 1e-12)
    }

    // MARK: - The stretch a bar is drawn across

    @Test func theStretchHoldsStillWhileTheWindowMovesLessThanHalfItsWidth() {
        // Seven seconds on screen, so a step of three and a half.
        let visible = Self.fourteenSeconds / 2
        let at = TimelineDrawnStretch(windowStartMS: 3600, visibleMS: visible)
        for start in stride(from: 3600.0, to: 6999, by: 250) {
            #expect(TimelineDrawnStretch(windowStartMS: start, visibleMS: visible) == at)
        }
        #expect(TimelineDrawnStretch(windowStartMS: 7000, visibleMS: visible) != at)
    }

    @Test func theStretchAlwaysCoversTheWindowWithRoomEitherSide() {
        let visible = 3500.0
        for start in stride(from: 0.0, through: Self.fourteenSeconds - visible, by: 137) {
            let stretch = TimelineDrawnStretch(windowStartMS: start, visibleMS: visible)
                .stretchMS(visibleMS: visible, documentMS: Self.fourteenSeconds)
            #expect(stretch.lowerBound <= max(0, start - visible / 2) + 0.001)
            #expect(stretch.upperBound >= start + visible + visible / 2 - 0.001)
        }
    }

    @Test func theStretchNeverStartsBeforeTheDocument() {
        let stretch = TimelineDrawnStretch(windowStartMS: 0, visibleMS: 3500)
            .stretchMS(visibleMS: 3500, documentMS: Self.fourteenSeconds)
        #expect(stretch.lowerBound == 0)
    }

    /// The document got shorter since the window was written, so the window
    /// is now held back against the end: the stretch follows it there.
    @Test func aDocumentThatShrankStillHasItsWindowCovered() {
        let visible = 30_000.0
        let written = TimelineDrawnStretch(windowStartMS: 250_000, visibleMS: visible)
        let shorter = 120_000.0
        let windowNow = TimelineZoom(scale: Self.fiveMinutes / visible, startMS: 250_000)
            .clamped(documentMS: shorter)
        let visibleNow = windowNow.visibleMS(documentMS: shorter)
        let stretch = written.stretchMS(visibleMS: visibleNow, documentMS: shorter)
        #expect(stretch.lowerBound <= windowNow.startMS)
        #expect(stretch.upperBound >= windowNow.startMS + visibleNow)
    }

    @Test func theLeftEdgeIsSomewhereInsideItsRange() {
        let visible = 3500.0
        for start in stride(from: 0.0, through: Self.fourteenSeconds - visible, by: 91) {
            let range = TimelineDrawnStretch(windowStartMS: start, visibleMS: visible)
                .leftEdgeMS(visibleMS: visible, documentMS: Self.fourteenSeconds)
            #expect(range.contains(start))
            #expect(range.upperBound - range.lowerBound <= visible / 2 + 0.001)
        }
    }

    // MARK: - Cut down to a stretch rather than to the window

    @Test func drawnBetweenTwoEdgesKeepsOnlyWhatIsBetweenThem() {
        let span = TimelineSpan.drawn(x: -500, width: 2000, from: -100, to: 900, slack: 0)
        #expect(span.x == -100)
        #expect(span.width == 1000)
        #expect(abs(span.startFraction - 0.2) < 1e-9)
        #expect(abs(span.endFraction - 0.7) < 1e-9)
    }

    @Test func drawnAcrossAWidthIsDrawnBetweenNoughtAndThatWidth() {
        for (x, width) in [(-300.0, 900.0), (40, 100), (700, 500), (-90, 20)] as [(CGFloat, CGFloat)] {
            #expect(TimelineSpan.drawn(x: x, width: width, across: 600)
                    == TimelineSpan.drawn(x: x, width: width, from: 0, to: 600))
        }
    }

    @Test func nothingBetweenTheEdgesIsNothingDrawn() {
        #expect(TimelineSpan.drawn(x: 1000, width: 50, from: 0, to: 600, slack: 0).width == 0)
    }
}
