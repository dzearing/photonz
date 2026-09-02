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

// MARK: - Placement against the canvas

/// The pill's rect in document space, from the same estimate the model hits
/// and reserves with.
private func pillRect(_ layer: Layer) -> CGRect {
    let a = layer.annotation!
    let anchor = a.captionAnchor()
    let size = a.estimatedCaptionSize
    return CGRect(x: layer.frame.minX + anchor.x - size.width / 2,
                  y: layer.frame.minY + anchor.y - size.height / 2,
                  width: size.width, height: size.height)
}

@Suite("Annotation caption placement")
struct AnnotationCaptionPlacementTests {

    private let canvas = CGSize(width: 1440, height: 960)

    @Test func openSpaceKeepsTheTailPlacementAndFrame() {
        // Plenty of room behind the tail: nothing changes, the frame included.
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Primary action"),
                                            from: CGPoint(x: 760, y: 650), to: CGPoint(x: 500, y: 770))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        #expect(planned.annotation?.captionOffset == nil)
        #expect(planned.frame == layer.frame)
        #expect(planned.annotation?.captionAnchor() == layer.annotation?.captionAnchor())
    }

    @Test func arrowFromTheLeftMarginKeepsItsPillOnThePicture() {
        // Drawn from the margin inward: the default spot is off the left edge.
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                            from: CGPoint(x: 24, y: 496), to: CGPoint(x: 880, y: 496))
        #expect(!CGRect(origin: .zero, size: canvas).contains(pillRect(layer)))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        let pill = pillRect(planned)
        #expect(CGRect(origin: .zero, size: canvas).contains(pill))
        // Clear of the shaft (y = 496) and nowhere near the head at x = 880.
        #expect(pill.minY > 496 + 2 || pill.maxY < 496 - 2)
        #expect(pill.maxX < 800)
        // The frame still reserves room for wherever the pill went.
        #expect(planned.frame.contains(pill))
        // Endpoints did not move.
        #expect(planned.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(planned.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
    }

    @Test func arrowFromTheBottomMarginKeepsItsPillOnThePicture() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Secondary"),
                                            from: CGPoint(x: 136, y: 940), to: CGPoint(x: 136, y: 830))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        let pill = pillRect(planned)
        #expect(CGRect(origin: .zero, size: canvas).contains(pill))
        // Not sitting on the shaft (x = 136 between y 830 and 940).
        let onShaft = pill.minX <= 136 && pill.maxX >= 136 && pill.maxY >= 830 && pill.minY <= 940
        #expect(!onShaft)
    }

    @Test func topRightCornerArrowStaysInsideBothEdges() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Login toggle"),
                                            from: CGPoint(x: 1300, y: 20), to: CGPoint(x: 1300, y: 160))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        #expect(CGRect(origin: .zero, size: canvas).contains(pillRect(planned)))
    }

    @Test func plannedPillIsHittableWhereItLanded() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                            from: CGPoint(x: 24, y: 496), to: CGPoint(x: 880, y: 496))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        let center = CGPoint(x: pillRect(planned).midX, y: pillRect(planned).midY)
        #expect(planned.contains(canvasPoint: center, zoom: 1))
    }

    @Test func endpointRebuildKeepsTheOffsetRelativeToTheTail() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                            from: CGPoint(x: 24, y: 496), to: CGPoint(x: 880, y: 496))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        let offset = planned.annotation?.captionOffset
        #expect(offset != nil)
        let moved = AnnotationBuilder.updating(planned, start: CGPoint(x: 60, y: 300), end: CGPoint(x: 700, y: 300))
        #expect(moved.annotation?.captionOffset == offset)
        let tail = moved.annotationEndpoint(.start)!
        let pill = pillRect(moved)
        #expect(abs(pill.midX - (tail.x + (offset?.width ?? 0))) < 0.5)
        #expect(abs(pill.midY - (tail.y + (offset?.height ?? 0))) < 0.5)
    }

    @Test func noCanvasMeansNoPlan() {
        let layer = AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                            from: CGPoint(x: 24, y: 496), to: CGPoint(x: 880, y: 496))
        let planned = AnnotationBuilder.planningCaption(layer, canvas: nil)
        #expect(planned == layer)
    }

    @Test func offsetRoundTripsAndLegacyPayloadsHaveNone() throws {
        var content = arrowContent(caption: "x")
        content.captionOffset = CGSize(width: 12, height: -40)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.captionOffset == CGSize(width: 12, height: -40))
        let legacy = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#FF3B30","start":[10,20],"end":[110,20],"caption":"x"}
        """.data(using: .utf8)!
        #expect(try JSONDecoder().decode(AnnotationContent.self, from: legacy).captionOffset == nil)
    }
}

@Suite("Annotation caption legibility")
struct AnnotationCaptionLegibilityTests {

    @Test func lightInkStillGetsADarkChip() {
        // White text sits on the chip, so a white or yellow arrow cannot keep
        // the plain 55 percent tone (a mid gray, an olive): the chip darkens
        // until white reads on it.
        for hex in ["#FFFFFF", "#FFD60A", "#34C759"] {
            var content = arrowContent(caption: "x")
            content.colorHex = hex
            #expect(content.captionChipColor.relativeLuminance <= AnnotationContent.captionChipMaxLuminance + 1e-9)
        }
        // The default red pair is unchanged.
        #expect(arrowContent(caption: "x").captionChipColor.hexString == "#8C201A")
    }

    @Test func captionSizeIsRememberedPerShape() throws {
        var styles = AnnotationStyles()
        #expect(styles.captionFontSize(forShape: .arrow) == AnnotationContent.captionFontSizeDefault)
        styles.setCaptionFontSize(28, forShape: .arrow)
        #expect(styles.content(for: .arrow)?.captionFontSize == 28)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: JSONEncoder().encode(styles))
        #expect(decoded.captionFontSize(forShape: .arrow) == 28)
    }
}
