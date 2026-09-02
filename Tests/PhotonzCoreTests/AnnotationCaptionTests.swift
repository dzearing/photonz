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

    @Test func wholeArrowDraggedToTheLeftEdgeKeepsItsPillOnThePicture() {
        // Drawn in open space (pill behind the tail), then the whole arrow is
        // dragged so its tail touches the left edge: the frame offset alone
        // pushes the pill off the picture, and the re-plan brings it back.
        let bounds = CGRect(origin: .zero, size: canvas)
        let layer = AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                    from: CGPoint(x: 400, y: 496), to: CGPoint(x: 880, y: 496)),
            canvas: canvas)
        #expect(layer.annotation?.captionOffset == nil)
        let tail = layer.annotationEndpoint(.start)!
        let dropped = layer.resized(to: layer.frame.offsetBy(dx: 4 - tail.x, dy: 0))
        #expect(!bounds.contains(pillRect(dropped)))
        let planned = AnnotationBuilder.planningCaption(dropped, canvas: canvas)
        let pill = pillRect(planned)
        #expect(bounds.contains(pill))
        #expect(planned.frame.contains(pill))
        // The drop landed where the user put it: endpoints moved by the drag, nothing else.
        #expect(planned.annotationEndpoint(.start) == CGPoint(x: 4, y: 496))
        #expect(planned.annotationEndpoint(.end) == CGPoint(x: 484, y: 496))
    }

    @Test func nudgingToTheBottomEdgeKeepsThePillOnThePictureEveryStep() {
        // Arrow keys move the frame one point at a time and commit each step;
        // the pill must be on the picture after every one, with no flicker
        // between spots once it has settled.
        let bounds = CGRect(origin: .zero, size: canvas)
        var layer = AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: arrowContent(caption: "Secondary"),
                                    from: CGPoint(x: 300, y: 900), to: CGPoint(x: 300, y: 790)),
            canvas: canvas)
        // Which side of the tail the pill sits on: the planner may slide the
        // pill along the edge as the tail keeps moving, but it must not hop
        // between sides from one key press to the next.
        func side(_ layer: Layer) -> String {
            let tail = layer.annotationEndpoint(.start)!
            let pill = pillRect(layer)
            if pill.maxX < tail.x { return "left" }
            if pill.minX > tail.x { return "right" }
            return pill.midY < tail.y ? "above" : "below"
        }
        var sides: [String] = []
        for step in 1...59 {
            layer = AnnotationBuilder.planningCaption(layer.resized(to: layer.frame.offsetBy(dx: 0, dy: 1)),
                                                      canvas: canvas)
            #expect(bounds.contains(pillRect(layer)), "step \(step)")
            #expect(layer.annotationEndpoint(.start) == CGPoint(x: 300, y: 900 + CGFloat(step)))
            sides.append(side(layer))
        }
        #expect(layer.annotationEndpoint(.start) == CGPoint(x: 300, y: 959))
        #expect(layer.annotation?.captionOffset != nil)
        // Starts below the tail (the default), moves beside it once, and stays.
        let hops = zip(sides, sides.dropFirst()).filter { $0 != $1 }.count
        #expect(hops == 1, "sides: \(sides)")
        #expect(sides.last != "below")
    }

    @Test func wholeArrowDraggedInOpenSpaceKeepsThePillBehindTheTail() {
        // Nowhere near an edge: the pill rides along exactly, frame included.
        let layer = AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: arrowContent(caption: "Primary action"),
                                    from: CGPoint(x: 760, y: 650), to: CGPoint(x: 500, y: 770)),
            canvas: canvas)
        let target = layer.frame.offsetBy(dx: -120, dy: -200)
        let planned = AnnotationBuilder.planningCaption(layer.resized(to: target), canvas: canvas)
        #expect(planned.annotation?.captionOffset == nil)
        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.001 && abs(a.minY - b.minY) < 0.001
                && abs(a.width - b.width) < 0.001 && abs(a.height - b.height) < 0.001
        }
        #expect(close(planned.frame, target))
        #expect(close(pillRect(planned), pillRect(layer).offsetBy(dx: -120, dy: -200)))
    }

    @Test func arrowDraggedBackIntoOpenSpaceReturnsThePillBehindTheTail() {
        // Planned beside the tail at the margin; once there is room again the
        // pill goes back to its default spot instead of staying displaced.
        let edge = AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: arrowContent(caption: "Path field"),
                                    from: CGPoint(x: 24, y: 496), to: CGPoint(x: 880, y: 496)),
            canvas: canvas)
        #expect(edge.annotation?.captionOffset != nil)
        let planned = AnnotationBuilder.planningCaption(
            edge.resized(to: edge.frame.offsetBy(dx: 300, dy: 0)), canvas: canvas)
        #expect(planned.annotation?.captionOffset == nil)
        #expect(planned.annotationEndpoint(.start) == CGPoint(x: 324, y: 496))
        #expect(CGRect(origin: .zero, size: canvas).contains(pillRect(planned)))
    }

    /// An arrow with both ends on the same point has no shaft, so there is
    /// nothing for the pill to run across and it keeps its first choice — the
    /// default spot behind the point, pulled back onto the picture. It used to
    /// be charged for crossing a shaft of zero length and stepped down the
    /// order to avoid a line that was not there.
    @Test func aZeroLengthArrowHasNoShaftForItsPillToCross() {
        let corner = CGPoint(x: 0, y: 0)
        var content = arrowContent(caption: "Save")
        content.start = corner
        content.end = corner
        let size = content.estimatedCaptionSize
        let plan = CaptionPlanner.plan(for: content, canvas: canvas)
        #expect(plan == CGSize(width: size.width / 2, height: size.height / 2))
        // Which is the default spot clamped onto the picture, not a step down
        // the order: the pill's corner sits on the picture's corner.
        #expect(CGRect(origin: .zero, size: canvas)
            .contains(CGRect(x: 0, y: 0, width: size.width, height: size.height)))
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

// MARK: - Hand-placed pills

@Suite("Annotation caption pinning")
struct AnnotationCaptionPinningTests {

    private let canvas = CGSize(width: 1440, height: 960)
    private var bounds: CGRect { CGRect(origin: .zero, size: canvas) }

    /// A captioned arrow in open space, planned (so the pill is at its default).
    private func openSpaceArrow() -> Layer {
        AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: arrowContent(caption: "Primary action"),
                                    from: CGPoint(x: 760, y: 650), to: CGPoint(x: 500, y: 770)),
            canvas: canvas)
    }

    @Test func placingPinsThePillWhereItWasDropped() {
        let layer = openSpaceArrow()
        #expect(layer.annotation?.captionPinned == false)
        let target = CGPoint(x: 900, y: 500)
        let placed = AnnotationBuilder.placingCaption(layer, at: target, canvas: canvas)
        #expect(placed.annotation?.captionPinned == true)
        let pill = pillRect(placed)
        #expect(abs(pill.midX - target.x) < 0.5)
        #expect(abs(pill.midY - target.y) < 0.5)
        // Endpoints did not move; the frame reserves room for the pill.
        #expect(placed.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(placed.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
        #expect(placed.frame.contains(pill))
        // The offset is relative to the tail.
        let tail = placed.annotationEndpoint(.start)!
        #expect(placed.annotation?.captionOffset == CGSize(width: target.x - tail.x, height: target.y - tail.y))
    }

    @Test func plannerLeavesAPinnedPillAlone() {
        let target = CGPoint(x: 900, y: 500)
        let placed = AnnotationBuilder.placingCaption(openSpaceArrow(), at: target, canvas: canvas)
        let replanned = AnnotationBuilder.planningCaption(placed, canvas: canvas)
        #expect(replanned == placed)
    }

    @Test func pinnedPillRidesWithTheTailWhenTheArrowMoves() {
        let target = CGPoint(x: 900, y: 500)
        let placed = AnnotationBuilder.placingCaption(openSpaceArrow(), at: target, canvas: canvas)
        let moved = AnnotationBuilder.planningCaption(
            placed.resized(to: placed.frame.offsetBy(dx: -200, dy: 100)), canvas: canvas)
        #expect(moved.annotation?.captionPinned == true)
        #expect(moved.annotation?.captionOffset == placed.annotation?.captionOffset)
        let pill = pillRect(moved)
        #expect(abs(pill.midX - (target.x - 200)) < 0.5)
        #expect(abs(pill.midY - (target.y + 100)) < 0.5)
    }

    @Test func pinnedPillStaysPutWhenAnEndpointMoves() {
        // Only the head moves: the pill keeps its spot relative to the tail,
        // which did not move, so it stays exactly where it was dropped.
        let target = CGPoint(x: 900, y: 500)
        let placed = AnnotationBuilder.placingCaption(openSpaceArrow(), at: target, canvas: canvas)
        let tail = placed.annotationEndpoint(.start)!
        let moved = AnnotationBuilder.planningCaption(
            AnnotationBuilder.updating(placed, start: tail, end: CGPoint(x: 300, y: 900)), canvas: canvas)
        #expect(moved.annotation?.captionPinned == true)
        let pill = pillRect(moved)
        #expect(abs(pill.midX - target.x) < 0.5)
        #expect(abs(pill.midY - target.y) < 0.5)
    }

    @Test func pinnedPillSurvivesTextAndSizeEdits() {
        let target = CGPoint(x: 900, y: 500)
        let placed = AnnotationBuilder.placingCaption(openSpaceArrow(), at: target, canvas: canvas)
        let retyped = AnnotationBuilder.planningCaption(
            AnnotationBuilder.restyled(placed, caption: .some("A much longer caption than before")),
            canvas: canvas)
        #expect(retyped.annotation?.captionPinned == true)
        #expect(abs(pillRect(retyped).midX - target.x) < 0.5)
        #expect(abs(pillRect(retyped).midY - target.y) < 0.5)
        #expect(retyped.frame.contains(pillRect(retyped)))
        let resized = AnnotationBuilder.planningCaption(
            AnnotationBuilder.restyled(placed, captionFontSize: 36), canvas: canvas)
        #expect(resized.annotation?.captionPinned == true)
        #expect(abs(pillRect(resized).midX - target.x) < 0.5)
        #expect(abs(pillRect(resized).midY - target.y) < 0.5)
    }

    @Test func pinnedPillIsPulledBackOntoThePicture() {
        // Dropped past the right edge: it lands as far right as it can go, and
        // stays pinned there.
        let placed = AnnotationBuilder.placingCaption(openSpaceArrow(), at: CGPoint(x: 1500, y: 500),
                                                      canvas: canvas)
        #expect(placed.annotation?.captionPinned == true)
        let pill = pillRect(placed)
        #expect(bounds.contains(pill))
        #expect(abs(pill.maxX - canvas.width) < 0.5)
        #expect(abs(pill.midY - 500) < 0.5)
        // Then the arrow is dragged so the pinned spot would be off the top:
        // the pill is pulled back on but keeps its x.
        let dragged = AnnotationBuilder.planningCaption(
            placed.resized(to: placed.frame.offsetBy(dx: 0, dy: -600)), canvas: canvas)
        let pulled = pillRect(dragged)
        #expect(bounds.contains(pulled))
        #expect(dragged.annotation?.captionPinned == true)
        #expect(abs(pulled.midX - pill.midX) < 0.5)
        #expect(abs(pulled.minY) < 0.5)
    }

    @Test func releasingReturnsThePillToTheAutomaticSpot() {
        let layer = openSpaceArrow()
        let placed = AnnotationBuilder.placingCaption(layer, at: CGPoint(x: 900, y: 500), canvas: canvas)
        let released = AnnotationBuilder.releasingCaption(placed, canvas: canvas)
        #expect(released.annotation?.captionPinned == false)
        #expect(released.annotation?.captionOffset == nil)
        #expect(released == layer)
    }

    @Test func placingACaptionlessArrowDoesNothing() {
        let plain = AnnotationBuilder.layer(content: arrowContent(), from: CGPoint(x: 100, y: 100),
                                            to: CGPoint(x: 300, y: 100))
        #expect(AnnotationBuilder.placingCaption(plain, at: CGPoint(x: 50, y: 50), canvas: canvas) == plain)
    }

    @Test func pinnedFlagRoundTripsAndLegacyPayloadsAreUnpinned() throws {
        var content = arrowContent(caption: "x")
        content.captionPinned = true
        content.captionOffset = CGSize(width: 40, height: -30)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: JSONEncoder().encode(content))
        #expect(decoded.captionPinned)
        #expect(decoded.captionOffset == CGSize(width: 40, height: -30))
        let legacy = """
        {"shape":"arrow","strokeWidth":4,"colorHex":"#FF3B30","start":[10,20],"end":[110,20],
         "caption":"x","captionOffset":[12,-40]}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(AnnotationContent.self, from: legacy)
        #expect(!old.captionPinned)
        #expect(old.captionOffset == CGSize(width: 12, height: -40))
    }
}
