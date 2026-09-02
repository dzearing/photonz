import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func captionedArrow(_ caption: String = "Save button",
                            from start: CGPoint = CGPoint(x: 300, y: 300),
                            to end: CGPoint = CGPoint(x: 460, y: 300),
                            offset: CGSize? = nil) -> Layer {
    var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
    content.caption = caption
    content.captionOffset = offset
    return AnnotationBuilder.layer(content: content, from: start, to: end)
}

private func caliper(placement: MeasureLabelPlacement = .onLine,
                     crossReach: CGFloat = 0) -> Layer {
    var m = MeasureContent(mode: .horizontal)
    m.labelPlacement = placement
    m.labelCrossReach = crossReach
    return MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                to: CGPoint(x: 380, y: 400))
}

@Suite("Grab cue for draggable readouts")
struct CanvasGrabTests {

    // MARK: Arrow caption pill

    @Test func pointerOnTheCaptionPillReadsAsAGrab() {
        let layer = captionedArrow()
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        #expect(CanvasGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .captionPill)
    }

    @Test func pointerOffThePillIsNotAGrab() {
        let layer = captionedArrow()
        // The arrow head, far from the pill (which sits past the tail).
        #expect(CanvasGrab.hit(at: CGPoint(x: 455, y: 300), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func anUncaptionedArrowOffersNoGrab() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = nil
        let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 300, y: 300),
                                            to: CGPoint(x: 460, y: 300))
        #expect(CanvasGrab.captionPillRect(of: layer) == nil)
        #expect(CanvasGrab.hit(at: CGPoint(x: 300, y: 300), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func captionsOffMeansNoCue() {
        let layer = captionedArrow()
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        #expect(CanvasGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: false) == nil)
    }

    @Test func theTailHandleKeepsPriorityWherePillAndHandleOverlap() {
        // A caption parked ON the tail: the press starts an endpoint drag
        // there, so the cue must not promise a pill drag.
        let layer = captionedArrow(offset: .zero)
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        let tail = try! #require(layer.annotationEndpoint(.start))
        #expect(pill.contains(tail))
        #expect(CanvasGrab.hit(at: tail, layer: layer, zoom: 1, captionsEnabled: true) == nil)
        // ...but the far end of the same pill, clear of the handle, still cues.
        #expect(CanvasGrab.hit(at: CGPoint(x: pill.minX + 4, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .captionPill)
    }

    @Test func aLockedLayerOffersNoGrab() {
        var layer = captionedArrow()
        layer.isLocked = true
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        #expect(CanvasGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func theSlopAroundThePillShrinksAsYouZoomIn() {
        let layer = captionedArrow()
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        // 3 document points outside the pill: inside the 6pt slop at 1:1,
        // outside it at 4x (where 6 screen points are 1.5 document points).
        let just = CGPoint(x: pill.midX, y: pill.minY - 3)
        #expect(CanvasGrab.hit(at: just, layer: layer, zoom: 1, captionsEnabled: true) == .captionPill)
        #expect(CanvasGrab.hit(at: just, layer: layer, zoom: 4, captionsEnabled: true) == nil)
    }

    // MARK: Caliper readout

    @Test func pointerOnTheCaliperNumberReadsAsAGrab() {
        let layer = caliper()
        let rect = try! #require(MeasureBuilder.readoutRect(of: layer))
        #expect(CanvasGrab.hit(at: CGPoint(x: rect.midX, y: rect.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func pointerOnEitherFootReadsAsAGrab() {
        let layer = caliper()
        for foot in [AnnotationEndpoint.start, .end] {
            let point = try! #require(layer.measureEndpoint(foot))
            #expect(CanvasGrab.hit(at: point, layer: layer, zoom: 1,
                                   captionsEnabled: true) == .measureHandle)
        }
    }

    @Test func aDrawnHeadDotReadsAsAGrab() {
        // Readout pushed clear of the head line: the head dot is drawn there,
        // so it is a grab of its own rather than part of the number.
        let layer = caliper(placement: .clearPositive, crossReach: 80)
        let m = try! #require(MeasureBuilder.documentSpaceContent(of: layer))
        #expect(!m.labelCoversHeadHandle(chipSize: m.estimatedLabelSize))
        #expect(CanvasGrab.hit(at: m.headHandle, layer: layer, zoom: 1,
                               captionsEnabled: true) == .measureHandle)
        // The readout itself, off the line, cues as the number.
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(CanvasGrab.hit(at: CGPoint(x: rect.midX, y: rect.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func theBarBetweenTheGrabsCuesNothing() {
        // Mid-span on the measuring line: draggable nowhere, so the arrow stays.
        let layer = caliper(placement: .clearPositive, crossReach: 80)
        #expect(CanvasGrab.hit(at: CGPoint(x: 290, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func aCaliperWithNoNumberStillCuesItsFeet() {
        // The number can be switched off; the feet still drag, so they still cue.
        var m = MeasureContent(mode: .horizontal)
        m.showLabel = false
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                         to: CGPoint(x: 380, y: 400))
        #expect(CanvasGrab.hit(at: CGPoint(x: 200, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureHandle)
    }

    @Test func theSlopAroundAFootShrinksAsYouZoomIn() {
        let layer = caliper()
        let foot = try! #require(layer.measureEndpoint(.start))
        // 7 document points off the foot: inside the 9pt grab at 1:1, outside
        // it at 4x (where 9 screen points are 2.25 document points).
        let just = CGPoint(x: foot.x, y: foot.y - 7)
        #expect(CanvasGrab.hit(at: just, layer: layer, zoom: 1,
                               captionsEnabled: true) == .measureHandle)
        #expect(CanvasGrab.hit(at: just, layer: layer, zoom: 4, captionsEnabled: true) == nil)
    }

    @Test func aLockedCaliperOffersNoGrabAtAll() {
        var layer = caliper()
        layer.isLocked = true
        let foot = try! #require(layer.measureEndpoint(.start))
        #expect(CanvasGrab.hit(at: foot, layer: layer, zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func theCueCoversTheWholeNumberWhenItSitsOnTheHead() {
        // Readout on the head line: no dot is drawn under the digits, so the
        // centre of the number cues just like its edges (no dead spot).
        let layer = caliper()
        let m = try! #require(MeasureBuilder.documentSpaceContent(of: layer))
        #expect(m.labelCoversHeadHandle(chipSize: m.estimatedLabelSize))
        #expect(CanvasGrab.hit(at: m.headHandle, layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func anAlignmentGuideOffersNoGrab() {
        var m = MeasureContent(mode: .horizontal)
        m.alignment = AlignmentCheck(items: [])
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                         to: CGPoint(x: 380, y: 400))
        #expect(CanvasGrab.hit(at: CGPoint(x: 290, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func aHiddenNumberOffersNoNumberGrab() {
        var m = MeasureContent(mode: .horizontal)
        m.showLabel = false
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                         to: CGPoint(x: 380, y: 400))
        // Mid-span, where the number would have been: nothing to grab.
        #expect(CanvasGrab.hit(at: CGPoint(x: 290, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func plainLayersOfferNoGrab() {
        let text = Layer(name: "Note", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(CanvasGrab.hit(at: CGPoint(x: 50, y: 20), layer: text,
                                zoom: 1, captionsEnabled: true) == nil)
    }
}
