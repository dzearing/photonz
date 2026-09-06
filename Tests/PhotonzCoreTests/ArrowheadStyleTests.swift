import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The arrow's choice of ending, and the caption pill's choice of corner.
@Suite("Arrow endings")
struct ArrowheadStyleTests {

    // MARK: - The set of endings

    @Test func fiveEndingsInPickerOrder() {
        #expect(ArrowheadStyle.allCases == [.triangle, .open, .dot, .hollowDot, .plain])
    }

    @Test func triangleIsTheDefault() {
        #expect(ArrowheadStyle.standard == .triangle)
        #expect(AnnotationContent(shape: .arrow).arrowheadStyle == .triangle)
    }

    @Test func everyEndingHasAName() {
        for style in ArrowheadStyle.allCases {
            #expect(!style.title.isEmpty)
        }
    }

    // MARK: - Where each ending sits

    /// A triangle and an open head are pointers: their tip is ON the point.
    @Test func pointedEndingsPutTheirTipOnThePoint() {
        for style in [ArrowheadStyle.triangle, .open] {
            let head = Geometry.arrowhead(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 200, y: 50),
                                          strokeWidth: 4, scale: 1, style: style)
            #expect(head.first == CGPoint(x: 200, y: 50))
        }
    }

    /// A dot is a marker: its CENTRE is on the point, so it reaches past it.
    @Test func roundEndingsAreCentredOnThePoint() {
        for style in [ArrowheadStyle.dot, .hollowDot] {
            let circle = Geometry.arrowheadCircle(at: CGPoint(x: 200, y: 50),
                                                  strokeWidth: 4, scale: 1, style: style)
            #expect(circle?.center == CGPoint(x: 200, y: 50))
            #expect((circle?.radius ?? 0) > 0)
        }
    }

    @Test func pointedAndPlainEndingsHaveNoCircle() {
        for style in [ArrowheadStyle.triangle, .open, .plain] {
            #expect(Geometry.arrowheadCircle(at: CGPoint(x: 100, y: 0),
                                             strokeWidth: 4, scale: 1, style: style) == nil)
        }
    }

    @Test func plainEndingDrawsNothingAtAll() {
        let head = Geometry.arrowhead(start: .zero, end: CGPoint(x: 100, y: 0),
                                      strokeWidth: 4, scale: 1, style: .plain)
        #expect(head.isEmpty)
    }

    // MARK: - Every ending scales the same way

    @Test func everyEndingGrowsWithTheHeadSizeSlider() {
        for style in ArrowheadStyle.allCases where style != .plain {
            let small = Geometry.arrowheadReach(strokeWidth: 4, scale: 1, style: style)
            let big = Geometry.arrowheadReach(strokeWidth: 4, scale: 2, style: style)
            #expect(big > small, "\(style) should grow with the head size")
        }
    }

    /// The triangle's thick-shaft floor is what stops a heavy line out-widening
    /// its own head; every ending inherits it, because they all measure from
    /// the same half-width.
    @Test func everyEndingKeepsTheThickShaftFloor() {
        for style in ArrowheadStyle.allCases where style != .plain {
            let thin = Geometry.arrowheadReach(strokeWidth: 2, scale: 0.5, style: style)
            let thick = Geometry.arrowheadReach(strokeWidth: 40, scale: 0.5, style: style)
            #expect(thick > thin, "\(style) should not be out-widened by a heavy shaft")
        }
    }

    @Test func plainEndingReachesNoFurtherThanTheLineItself() {
        #expect(Geometry.arrowheadReach(strokeWidth: 8, scale: 3, style: .plain) == 4)
    }

    // MARK: - Where the shaft stops

    /// A hollow dot must stay hollow: the shaft stops on the ring, not through it.
    @Test func shaftStopsOnAHollowDotsNearEdge() {
        let end = CGPoint(x: 200, y: 50)
        let circle = Geometry.arrowheadCircle(at: end, strokeWidth: 4, scale: 1,
                                              style: .hollowDot)!
        let shaftEnd = Geometry.arrowShaftEnd(start: CGPoint(x: 0, y: 50), end: end,
                                              strokeWidth: 4, scale: 1, style: .hollowDot)
        #expect(abs(shaftEnd.x - (end.x - circle.radius)) < 1e-6)
    }

    /// An open head is one V the shaft runs into, so the line reaches the tip.
    @Test func shaftReachesTheTipForOpenAndPlainEndings() {
        let end = CGPoint(x: 200, y: 50)
        for style in [ArrowheadStyle.open, .plain, .dot] {
            let shaftEnd = Geometry.arrowShaftEnd(start: CGPoint(x: 0, y: 50), end: end,
                                                  strokeWidth: 4, scale: 1, style: style)
            #expect(shaftEnd == end, "\(style) should let the shaft run to the point")
        }
    }

    /// The triangle keeps exactly the stop it always had.
    @Test func triangleShaftStopIsUnchanged() {
        let start = CGPoint(x: 0, y: 50), end = CGPoint(x: 200, y: 50)
        let styled = Geometry.arrowShaftEnd(start: start, end: end, strokeWidth: 4,
                                            scale: 1, style: .triangle)
        let legacy = Geometry.arrowShaftEnd(start: start, end: end, strokeWidth: 4, scale: 1)
        #expect(styled == legacy)
    }

    // MARK: - The frame the ink needs

    /// A dot hangs past the point it marks, so the layer frame has to grow or
    /// the ending clips at the edge.
    @Test func roundEndingsPadTheFrameMoreThanTheirRadius() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: .zero, end: CGPoint(x: 100, y: 0))
        content.arrowheadStyle = .hollowDot
        let circle = Geometry.arrowheadCircle(at: content.end, strokeWidth: 4, scale: 1,
                                              style: .hollowDot)!
        #expect(content.renderPadding >= circle.radius + 2)
    }

    @Test func aPlainEndingNeedsOnlyTheLinesOwnPadding() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 6,
                                        start: .zero, end: CGPoint(x: 100, y: 0))
        content.arrowheadStyle = .plain
        #expect(content.renderPadding == 3)
    }

    @Test func triangleRenderPaddingIsUnchanged() {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: .zero, end: CGPoint(x: 100, y: 0))
        #expect(content.renderPadding
                == Geometry.arrowheadHalfWidth(strokeWidth: 4, scale: 1).rounded(.up))
    }

    /// The selection box round an arrow follows the ink, so a dot's overshoot
    /// belongs inside it.
    @Test func drawnBoundsContainTheDot() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 20))
        content.arrowheadStyle = .dot
        let layer = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        let bounds = layer.drawnBounds()
        let circle = Geometry.arrowheadCircle(at: CGPoint(x: 120, y: 20),
                                              strokeWidth: 4, scale: 1, style: .dot)!
        #expect(bounds.maxX >= 120 + circle.radius - 1e-6)
    }

    // MARK: - Old documents

    @Test func anArrowSavedBeforeThisOpensAsATriangle() throws {
        // Exactly what an older document held: no ending, no roundness.
        let json = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#FF3B30",
         "start":[10,10],"end":[100,100],"arrowheadScale":1,"cornerRadius":0,
         "caption":"Tap target","captionFontSize":20,"captionPinned":false}
        """
        let content = try JSONDecoder().decode(AnnotationContent.self, from: Data(json.utf8))
        #expect(content.arrowheadStyle == .triangle)
        #expect(content.captionRoundness == 1)
        #expect(content.captionCornerRadius(pillHeight: 44) == 22)
    }

    @Test func endingAndCornerSurviveARoundTrip() throws {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        content.arrowheadStyle = .hollowDot
        content.captionRoundness = 0.25
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(back.arrowheadStyle == .hollowDot)
        #expect(back.captionRoundness == 0.25)
    }

    // MARK: - The caption corner

    @Test func fullyRoundIsTheDefaultCorner() {
        let content = AnnotationContent(shape: .arrow, caption: "Gap")
        #expect(content.captionRoundness == AnnotationContent.captionRoundnessDefault)
        #expect(content.captionCornerRadius(pillHeight: 40) == 20)
    }

    @Test func squareCornerIsSquare() {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        content.captionRoundness = 0
        #expect(content.captionCornerRadius(pillHeight: 40) == 0)
    }

    @Test func aBadgeSitsBetweenSquareAndPill() {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        content.captionRoundness = 0.3
        #expect(content.captionCornerRadius(pillHeight: 40) == 6)
    }

    /// The corner is a proportion, so making the words bigger keeps the shape:
    /// a badge stays a badge instead of creeping towards square.
    @Test func theCornerKeepsItsShapeWhenTheLabelResizes() {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        content.captionRoundness = 0.5
        #expect(content.captionCornerRadius(pillHeight: 40) / 40
                == content.captionCornerRadius(pillHeight: 80) / 80)
    }

    /// A caption of several lines keeps the corner a ONE LINE pill wears.
    /// Half of a tall pill's own height turns four short words into an egg
    /// standing on end — the very shape the badge floor exists to stop — so the
    /// curve is taken from one line's share of the pill and the label reads as
    /// the same kind of object, only taller.
    @Test func aTallCaptionKeepsTheCornerOfASingleLinePill() {
        let one = AnnotationContent(shape: .arrow, caption: "one")
        var four = one
        four.caption = "one\ntwo\nthree\nfour"
        let tall = one.captionPillHeight(forLines: 4)
        let short = one.captionCornerRadius(pillHeight: one.captionPillHeight)
        let corner = four.captionCornerRadius(pillHeight: tall)
        #expect(abs(corner - short) < 4, "four lines rounded by \(corner), one by \(short)")
        #expect(corner < tall / 2 - 1)
    }

    @Test func aWildRoundnessIsClampedRatherThanDrawn() {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        content.captionRoundness = 4
        #expect(content.captionCornerRadius(pillHeight: 40) == 20)
        content.captionRoundness = -1
        #expect(content.captionCornerRadius(pillHeight: 40) == 0)
    }

    // MARK: - Remembered for the next arrow

    @Test func theStylesStoreRemembersBoth() {
        var styles = AnnotationStyles()
        #expect(styles.arrowheadStyle(forShape: .arrow) == .triangle)
        #expect(styles.captionRoundness(forShape: .arrow) == 1)
        styles.setArrowheadStyle(.dot, forShape: .arrow)
        styles.setCaptionRoundness(0.2, forShape: .arrow)
        #expect(styles.arrowheadStyle(forShape: .arrow) == .dot)
        #expect(styles.captionRoundness(forShape: .arrow) == 0.2)
    }

    @Test func theNextArrowIsDrawnWithBoth() throws {
        var styles = AnnotationStyles()
        styles.setArrowheadStyle(.open, forShape: .arrow)
        styles.setCaptionRoundness(0.4, forShape: .arrow)
        let content = try #require(styles.content(for: .arrow))
        #expect(content.arrowheadStyle == .open)
        #expect(content.captionRoundness == 0.4)
    }

    @Test func remembersAcrossALaunch() throws {
        var styles = AnnotationStyles()
        styles.setArrowheadStyle(.hollowDot, forShape: .arrow)
        styles.setCaptionRoundness(0.1, forShape: .arrow)
        let data = try JSONEncoder().encode(styles)
        let back = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(back.arrowheadStyle(forShape: .arrow) == .hollowDot)
        #expect(back.captionRoundness(forShape: .arrow) == 0.1)
    }

    /// Preferences written before endings existed still start every arrow the
    /// way they always did.
    @Test func prefsWrittenBeforeThisStillDrawATriangle() throws {
        let json = """
        {"shapes":{"arrow":{"colorHex":"#FF3B30","strokeWidth":4,"arrowheadScale":1}}}
        """
        let styles = try JSONDecoder().decode(AnnotationStyles.self, from: Data(json.utf8))
        #expect(styles.arrowheadStyle(forShape: .arrow) == .triangle)
        #expect(styles.captionRoundness(forShape: .arrow) == 1)
    }

    // MARK: - The rows the panel offers

    @Test func anArrowOffersBothNewRows() {
        var content = AnnotationContent(shape: .arrow, caption: "Gap")
        #expect(content.settingRows.contains(.headStyle))
        #expect(content.settingRows.contains(.labelCorners))
        content.caption = nil
        #expect(content.settingRows.contains(.headStyle))
        #expect(!content.settingRows.contains(.labelCorners),
                "no words, no corner to shape")
    }

    @Test func aBoxOffersNeither() {
        let content = AnnotationContent(shape: .rectangle)
        #expect(!content.settingRows.contains(.headStyle))
        #expect(!content.settingRows.contains(.labelCorners))
    }

    @Test func headStyleSitsWithTheOtherHeadRow() {
        let rows = AnnotationContent(shape: .arrow, caption: "Gap").settingRows
        #expect(rows.firstIndex(of: .headStyle) ?? .max < rows.firstIndex(of: .headSize) ?? .max,
                "pick the ending, then size it")
    }

    // MARK: - Restyling an existing arrow

    @Test func restylingSetsTheEndingAndKeepsTheRest() throws {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: .zero, end: CGPoint(x: 100, y: 0),
                                        caption: "Gap")
        content.captionRoundness = 1
        let layer = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 140, height: 40))
        let restyled = AnnotationBuilder.restyled(layer, arrowheadStyle: .dot,
                                                  captionRoundness: 0.2)
        let a = try #require(restyled.annotation)
        #expect(a.arrowheadStyle == .dot)
        #expect(a.captionRoundness == 0.2)
        #expect(a.caption == "Gap")
        #expect(a.strokeWidth == 4)
    }

    /// Switching to a dot grows the frame, because the dot hangs past the tip.
    @Test func switchingToADotRepadsTheFrame() throws {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4,
                                        start: CGPoint(x: 20, y: 20), end: CGPoint(x: 120, y: 20))
        let layer = Layer(name: "Arrow", content: .annotation(content),
                          frame: CGRect(x: 0, y: 0, width: 140, height: 40))
        let dotted = AnnotationBuilder.restyled(layer, arrowheadStyle: .dot)
        let a = try #require(dotted.annotation)
        // The endpoints stay put in document space...
        #expect(dotted.frame.minX + a.start.x == layer.frame.minX + content.start.x)
        // ...and the frame carries the dot's reach.
        #expect(dotted.frame.maxX >= dotted.frame.minX + a.end.x
                + Geometry.arrowheadCircle(at: a.end, strokeWidth: 4,
                                           scale: 1, style: .dot)!.radius - 1e-6)
    }
}

@Suite("Arrow endings: rows that make sense")
struct ArrowheadRowVisibilityTests {

    /// An arrow that ends in nothing has no head to size, so the size row goes
    /// away rather than sitting there doing nothing.
    @Test func aPlainEndingHidesTheHeadSizeRow() {
        var content = AnnotationContent(shape: .arrow)
        content.arrowheadStyle = .plain
        #expect(content.settingRows.contains(.headStyle))
        #expect(!content.settingRows.contains(.headSize))
    }

    @Test func everyOtherEndingKeepsIt() {
        for style in ArrowheadStyle.allCases where style != .plain {
            var content = AnnotationContent(shape: .arrow)
            content.arrowheadStyle = style
            #expect(content.settingRows.contains(.headSize), "\(style) has a head to size")
        }
    }
}

@Suite("Arrow endings: a heavy line never swallows its ending")
struct ArrowheadHeavyLineTests {

    /// A dot only a fraction wider than the line it ends reads as a bulge in
    /// the line, not as a mark on the point. It stays a dot at every weight.
    @Test func aRoundEndingIsAlwaysWiderThanItsLine() {
        for width in [CGFloat(2), 6, 12, 24, 40] {
            for scale in [CGFloat(0.5), 1, 2.2, 5] {
                let radius = Geometry.arrowheadCircle(at: CGPoint(x: 100, y: 0),
                                                      strokeWidth: width, scale: scale,
                                                      style: .dot)?.radius ?? 0
                #expect(radius >= width,
                        "a \(width)pt line at ×\(scale) must not out-width its own dot")
            }
        }
    }

    /// The same promise the triangle has always made.
    @Test func aPointedEndingIsAlwaysWiderThanItsLine() {
        for width in [CGFloat(2), 6, 12, 24, 40] {
            let half = Geometry.arrowheadHalfWidth(strokeWidth: width, scale: 0.5)
            #expect(2 * half >= width * 1.2)
        }
    }
}
