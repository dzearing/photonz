import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func arrowContent(caption: String? = nil) -> AnnotationContent {
    var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
    content.caption = caption
    return content
}

@Suite("Annotation caption model")
struct AnnotationCaptionModelTests {

    @Test func legacyPayloadDecodesWithoutCaption() throws {
        // A pre-caption payload: exactly the fields v1 wrote.
        let json = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#FF3B30",
         "start":[10,20],"end":[110,20]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: json)
        #expect(decoded.caption == nil)
        #expect(decoded.captionFontSize == AnnotationContent.captionFontSizeDefault)
    }

    @Test func captionRoundTripsThroughCodable() throws {
        var content = arrowContent(caption: "Save button")
        content.captionFontSize = 28
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(decoded.caption == "Save button")
        #expect(decoded.captionFontSize == 28)
    }

    @Test func hasCaptionRequiresArrowAndRealText() {
        #expect(arrowContent(caption: "Fix this").hasCaption)
        #expect(!arrowContent(caption: nil).hasCaption)
        #expect(!arrowContent(caption: "   ").hasCaption)
        var line = arrowContent(caption: "Fix this")
        line.shape = .line
        #expect(!line.hasCaption)
    }

    @Test func chipToneIsDarkenedStrokeColor() {
        // The measure tool's red pair: #FF3B30 stroke over a #8C201A chip.
        // The caption chip derives the same tone from the arrow's color.
        let content = arrowContent(caption: "x")
        #expect(content.captionChipColor.hexString == "#8C201A")
    }
}

@Suite("Annotation caption geometry")
struct AnnotationCaptionGeometryTests {

    @Test func anchorSitsBeyondTheTailOppositeTheHead() {
        // Arrow pointing right: tail at start, head at end. The pill hangs off
        // the tail, past the caption gap, level with the shaft.
        var content = arrowContent(caption: "Here")
        content.start = CGPoint(x: 100, y: 100)
        content.end = CGPoint(x: 200, y: 100)
        let anchor = content.captionAnchor()
        #expect(anchor.y == 100)
        #expect(anchor.x < 100 - AnnotationContent.captionGap)
        // The pill's near edge clears the tail by exactly the gap.
        let size = content.estimatedCaptionSize
        #expect(abs((anchor.x + size.width / 2) - (100 - AnnotationContent.captionGap)) < 0.5)
    }

    @Test func anchorForVerticalArrowUsesChipHeight() {
        // Arrow pointing up (end above start): the pill hangs below the tail,
        // its extent governed by the chip's height, not width.
        var content = arrowContent(caption: "Wide caption text")
        content.start = CGPoint(x: 50, y: 100)
        content.end = CGPoint(x: 50, y: 20)
        let anchor = content.captionAnchor()
        let size = content.estimatedCaptionSize
        #expect(anchor.x == 50)
        #expect(abs((anchor.y - size.height / 2) - (100 + AnnotationContent.captionGap)) < 0.5)
    }

    @Test func degenerateArrowAnchorsAboveTheTail() {
        var content = arrowContent(caption: "Dot")
        content.start = CGPoint(x: 40, y: 40)
        content.end = CGPoint(x: 40, y: 40)
        let anchor = content.captionAnchor()
        #expect(anchor.x == 40)
        #expect(anchor.y < 40)
    }

    @Test func estimatedSizeGrowsWithTextAndFont() {
        let short = arrowContent(caption: "Hi").estimatedCaptionSize
        let long = arrowContent(caption: "A much longer caption").estimatedCaptionSize
        #expect(long.width > short.width)
        #expect(long.height == short.height)
        var big = arrowContent(caption: "Hi")
        big.captionFontSize = 40
        #expect(big.estimatedCaptionSize.height > short.height)
    }
}

@Suite("Annotation caption frames and hit-testing")
struct AnnotationCaptionFrameTests {

    private let start = CGPoint(x: 300, y: 200)
    private let end = CGPoint(x: 420, y: 260)

    @Test func builderReservesFrameRoomForTheChip() {
        let plain = AnnotationBuilder.layer(content: arrowContent(), from: start, to: end)
        let captioned = AnnotationBuilder.layer(content: arrowContent(caption: "Check this"),
                                                from: start, to: end)
        #expect(captioned.frame.contains(plain.frame))
        #expect(captioned.frame != plain.frame)
        // The chip rect (plus shadow slack) fits inside the frame.
        guard let content = captioned.annotation else {
            Issue.record("expected annotation content")
            return
        }
        let anchor = content.captionAnchor()
        let size = content.estimatedCaptionSize
        let chip = CGRect(x: captioned.frame.minX + anchor.x - size.width / 2,
                          y: captioned.frame.minY + anchor.y - size.height / 2,
                          width: size.width, height: size.height)
            .insetBy(dx: -AnnotationContent.captionShadowPadding,
                     dy: -AnnotationContent.captionShadowPadding)
        #expect(captioned.frame.contains(chip))
    }

    @Test func captionlessFrameIsUnchangedByTheFeature() {
        // No caption -> exactly the frame the padded drag bbox always produced.
        let layer = AnnotationBuilder.layer(content: arrowContent(), from: start, to: end)
        let pad = arrowContent().renderPadding
        let expected = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                              width: abs(end.x - start.x), height: abs(end.y - start.y))
            .insetBy(dx: -pad, dy: -pad)
        #expect(layer.frame == expected)
    }

    @Test func chipFootprintIsHittable() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Label"),
                                            from: start, to: end)
        guard let content = layer.annotation else {
            Issue.record("expected annotation content")
            return
        }
        let anchor = content.captionAnchor()
        let docAnchor = CGPoint(x: layer.frame.minX + anchor.x, y: layer.frame.minY + anchor.y)
        #expect(layer.contains(canvasPoint: docAnchor, zoom: 1))
        // The same spot misses when there is no caption.
        let plain = AnnotationBuilder.layer(content: arrowContent(), from: start, to: end)
        #expect(!plain.contains(canvasPoint: docAnchor, zoom: 1))
        // Far corner of the (enlarged) frame still misses.
        let corner = CGPoint(x: layer.frame.maxX - 1, y: layer.frame.minY + 1)
        #expect(!layer.contains(canvasPoint: corner, zoom: 1))
    }

    @Test func restyledSetsAndClearsTheCaption() {
        let layer = AnnotationBuilder.layer(content: arrowContent(), from: start, to: end)
        let captioned = AnnotationBuilder.restyled(layer, caption: "Now labeled")
        #expect(captioned.annotation?.caption == "Now labeled")
        #expect(captioned.frame.contains(layer.frame))
        #expect(captioned.frame != layer.frame)
        // Endpoints stay anchored in document space through the frame change.
        #expect(captioned.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(captioned.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
        let cleared = AnnotationBuilder.restyled(captioned, caption: .some(nil))
        #expect(cleared.annotation?.caption == nil)
        #expect(cleared.frame == layer.frame)
    }
}
