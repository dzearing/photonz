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
struct ReadoutGrabTests {

    // MARK: Arrow caption pill

    @Test func pointerOnTheCaptionPillReadsAsAGrab() {
        let layer = captionedArrow()
        let pill = try! #require(ReadoutGrab.captionPillRect(of: layer))
        #expect(ReadoutGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .captionPill)
    }

    @Test func pointerOffThePillIsNotAGrab() {
        let layer = captionedArrow()
        // The arrow head, far from the pill (which sits past the tail).
        #expect(ReadoutGrab.hit(at: CGPoint(x: 455, y: 300), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func anUncaptionedArrowOffersNoGrab() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = nil
        let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 300, y: 300),
                                            to: CGPoint(x: 460, y: 300))
        #expect(ReadoutGrab.captionPillRect(of: layer) == nil)
        #expect(ReadoutGrab.hit(at: CGPoint(x: 300, y: 300), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func captionsOffMeansNoCue() {
        let layer = captionedArrow()
        let pill = try! #require(ReadoutGrab.captionPillRect(of: layer))
        #expect(ReadoutGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: false) == nil)
    }

    @Test func theTailHandleKeepsPriorityWherePillAndHandleOverlap() {
        // A caption parked ON the tail: the press starts an endpoint drag
        // there, so the cue must not promise a pill drag.
        let layer = captionedArrow(offset: .zero)
        let pill = try! #require(ReadoutGrab.captionPillRect(of: layer))
        let tail = try! #require(layer.annotationEndpoint(.start))
        #expect(pill.contains(tail))
        #expect(ReadoutGrab.hit(at: tail, layer: layer, zoom: 1, captionsEnabled: true) == nil)
        // ...but the far end of the same pill, clear of the handle, still cues.
        #expect(ReadoutGrab.hit(at: CGPoint(x: pill.minX + 4, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .captionPill)
    }

    @Test func aLockedLayerOffersNoGrab() {
        var layer = captionedArrow()
        layer.isLocked = true
        let pill = try! #require(ReadoutGrab.captionPillRect(of: layer))
        #expect(ReadoutGrab.hit(at: CGPoint(x: pill.midX, y: pill.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func theSlopAroundThePillShrinksAsYouZoomIn() {
        let layer = captionedArrow()
        let pill = try! #require(ReadoutGrab.captionPillRect(of: layer))
        // 3 document points outside the pill: inside the 6pt slop at 1:1,
        // outside it at 4x (where 6 screen points are 1.5 document points).
        let just = CGPoint(x: pill.midX, y: pill.minY - 3)
        #expect(ReadoutGrab.hit(at: just, layer: layer, zoom: 1, captionsEnabled: true) == .captionPill)
        #expect(ReadoutGrab.hit(at: just, layer: layer, zoom: 4, captionsEnabled: true) == nil)
    }

    // MARK: Caliper readout

    @Test func pointerOnTheCaliperNumberReadsAsAGrab() {
        let layer = caliper()
        let rect = try! #require(MeasureBuilder.readoutRect(of: layer))
        #expect(ReadoutGrab.hit(at: CGPoint(x: rect.midX, y: rect.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func theFeetKeepTheirOwnBehaviour() {
        let layer = caliper()
        for foot in [AnnotationEndpoint.start, .end] {
            let point = try! #require(layer.measureEndpoint(foot))
            #expect(ReadoutGrab.hit(at: point, layer: layer, zoom: 1, captionsEnabled: true) == nil)
        }
    }

    @Test func aDrawnHeadDotKeepsItsOwnBehaviour() {
        // Readout pushed clear of the head line: the head dot is drawn there,
        // so it stays a handle and gets no pill cue.
        let layer = caliper(placement: .clearPositive, crossReach: 80)
        let m = try! #require(MeasureBuilder.documentSpaceContent(of: layer))
        #expect(!m.labelCoversHeadHandle(chipSize: m.estimatedLabelSize))
        #expect(ReadoutGrab.hit(at: m.headHandle, layer: layer, zoom: 1, captionsEnabled: true) == nil)
        // The readout itself, off the line, still cues.
        let rect = m.labelRect(chipSize: m.estimatedLabelSize)
        #expect(ReadoutGrab.hit(at: CGPoint(x: rect.midX, y: rect.midY), layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func theCueCoversTheWholeNumberWhenItSitsOnTheHead() {
        // Readout on the head line: no dot is drawn under the digits, so the
        // centre of the number cues just like its edges (no dead spot).
        let layer = caliper()
        let m = try! #require(MeasureBuilder.documentSpaceContent(of: layer))
        #expect(m.labelCoversHeadHandle(chipSize: m.estimatedLabelSize))
        #expect(ReadoutGrab.hit(at: m.headHandle, layer: layer,
                                zoom: 1, captionsEnabled: true) == .measureReadout)
    }

    @Test func anAlignmentGuideOffersNoGrab() {
        var m = MeasureContent(mode: .horizontal)
        m.alignment = AlignmentCheck(items: [])
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                         to: CGPoint(x: 380, y: 400))
        #expect(ReadoutGrab.hit(at: CGPoint(x: 290, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func aReadoutThatIsHiddenOffersNoGrab() {
        var m = MeasureContent(mode: .horizontal)
        m.showLabel = false
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 200, y: 400),
                                         to: CGPoint(x: 380, y: 400))
        #expect(ReadoutGrab.hit(at: CGPoint(x: 290, y: 400), layer: layer,
                                zoom: 1, captionsEnabled: true) == nil)
    }

    @Test func plainLayersOfferNoGrab() {
        let text = Layer(name: "Note", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(ReadoutGrab.hit(at: CGPoint(x: 50, y: 20), layer: text,
                                zoom: 1, captionsEnabled: true) == nil)
    }
}
