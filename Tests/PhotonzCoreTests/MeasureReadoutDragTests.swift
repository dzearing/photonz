import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Sliding a measurement's number along its own measuring line, and lining it
/// up with the numbers already on the picture.
@Suite("Readout drag")
struct MeasureReadoutDragTests {

    /// A horizontal caliper 200 wide, its head 40 below the feet.
    private func caliper(start: CGPoint = CGPoint(x: 100, y: 300),
                         width: CGFloat = 200,
                         headOffset: CGFloat = 40) -> MeasureContent {
        MeasureContent(start: start,
                       end: CGPoint(x: start.x + width, y: start.y),
                       headOffset: headOffset, mode: .horizontal)
    }

    private func chipCentre(_ m: MeasureContent) -> CGPoint {
        m.labelPosition(chipSize: m.estimatedLabelSize)
    }

    // MARK: - The two directions

    @Test func draggingAlongTheLineMovesOnlyTheNumber() {
        let m = caliper()
        let centre = chipCentre(m)
        // Grabbed dead centre, dragged 60 to the right and not at all down.
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 60, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: false)
        #expect(abs(result.labelNudge - 60) < 0.001)
        #expect(abs(result.headOffset - m.headOffset) < 0.001)
    }

    @Test func draggingAlongTheLineNeverChangesTheMeasuredValue() {
        var m = caliper()
        let before = m.rawDistance
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x - 140, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: false)
        m.labelNudge = result.labelNudge
        m.headOffset = result.headOffset
        #expect(abs(m.rawDistance - before) < 0.001)
        #expect(m.start == CGPoint(x: 100, y: 300))
        #expect(m.end == CGPoint(x: 300, y: 300))
    }

    @Test func draggingAcrossTheLineStillMovesTheHead() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x, y: centre.y + 25),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: false)
        #expect(abs(result.headOffset - 65) < 0.001)
        #expect(abs(result.labelNudge) < 0.001)
    }

    @Test func theNumberLandsWhereThePointerPutItOnBothAxes() {
        var m = caliper()
        let centre = chipCentre(m)
        let target = CGPoint(x: centre.x + 73, y: centre.y - 18)
        let result = MeasureReadoutDrag.resolve(m, pointer: target, grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: false)
        m.headOffset = result.headOffset
        m.labelNudge = result.labelNudge
        let landed = chipCentre(m)
        #expect(abs(landed.x - target.x) < 0.001)
        #expect(abs(landed.y - target.y) < 0.001)
    }

    /// A pill taken hold of near its edge keeps that grip, both ways.
    @Test func theGripIsKeptOnBothAxes() {
        var m = caliper()
        let centre = chipCentre(m)
        let grab = CGPoint(x: centre.x + 30, y: centre.y + 6)
        let moved = CGPoint(x: grab.x + 50, y: grab.y + 10)
        let result = MeasureReadoutDrag.resolve(m, pointer: moved,
                                                grabCross: grab.y - m.labelAnchor.y,
                                                grabAlong: grab.x - centre.x,
                                                guides: .none, zoom: 1, snapping: false)
        m.headOffset = result.headOffset
        m.labelNudge = result.labelNudge
        let landed = chipCentre(m)
        #expect(abs(landed.x - (centre.x + 50)) < 0.001)
        #expect(abs(landed.y - (centre.y + 10)) < 0.001)
    }

    // MARK: - Lining up with the other numbers

    @Test func theNumberSnapsIntoAColumnWithAnotherNumber() {
        var m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 64
        // Dropped three points short of the column: within reach, so it clicks on.
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: column - 3, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: EdgeSnapping.GuideLines(vertical: [column]),
                                                zoom: 1, snapping: true)
        #expect(result.guideX == column)
        m.headOffset = result.headOffset
        m.labelNudge = result.labelNudge
        #expect(abs(chipCentre(m).x - column) < 0.001)
    }

    @Test func aColumnOutOfReachIsNotSnappedTo() {
        let m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 64
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: column - 40, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: EdgeSnapping.GuideLines(vertical: [column]),
                                                zoom: 1, snapping: true)
        #expect(result.guideX == nil)
        #expect(abs(result.labelNudge - 24) < 0.001)
    }

    /// The reach is constant on screen, so zoomed out it covers more image.
    @Test func theColumnReachScalesWithZoom() {
        let m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 64
        let guides = EdgeSnapping.GuideLines(vertical: [column])
        let far = CGPoint(x: column - 20, y: centre.y)
        #expect(MeasureReadoutDrag.resolve(m, pointer: far, grabCross: 0, grabAlong: 0,
                                           guides: guides, zoom: 1, snapping: true).guideX == nil)
        #expect(MeasureReadoutDrag.resolve(m, pointer: far, grabCross: 0, grabAlong: 0,
                                           guides: guides, zoom: 0.25, snapping: true).guideX == column)
    }

    @Test func bothAxesCanSnapAtOnce() {
        var m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 40, row = centre.y + 30
        let result = MeasureReadoutDrag.resolve(
            m, pointer: CGPoint(x: column - 4, y: row + 4), grabCross: 0, grabAlong: 0,
            guides: EdgeSnapping.GuideLines(vertical: [column], horizontal: [row]),
            zoom: 1, snapping: true)
        #expect(result.guideX == column)
        #expect(result.guideY == row)
        m.headOffset = result.headOffset
        m.labelNudge = result.labelNudge
        #expect(abs(chipCentre(m).x - column) < 0.001)
        #expect(abs(chipCentre(m).y - row) < 0.001)
    }

    /// The free-drag modifier ignores every line, on both axes.
    @Test func freeDragIgnoresEveryLine() {
        let m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 40, row = centre.y + 30
        let result = MeasureReadoutDrag.resolve(
            m, pointer: CGPoint(x: column - 4, y: row + 4), grabCross: 0, grabAlong: 0,
            guides: EdgeSnapping.GuideLines(vertical: [column], horizontal: [row]),
            zoom: 1, snapping: false)
        #expect(result.guideX == nil)
        #expect(result.guideY == nil)
        #expect(abs(result.labelNudge - 36) < 0.001)
        #expect(abs(result.headOffset - (m.headOffset + 34)) < 0.001)
    }

    /// Slid back near its own centre, the number clicks home — and says nothing,
    /// because there is no other readout it is lined up with.
    @Test func theNumberClicksBackOntoItsOwnCentre() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 3, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: true)
        #expect(abs(result.labelNudge) < 0.001)
        #expect(result.guideX == nil)
    }

    @Test func anotherNumbersColumnBeatsTheHomeDetent() {
        let m = caliper()
        let centre = chipCentre(m)
        let column = centre.x + 4
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 3, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: EdgeSnapping.GuideLines(vertical: [column]),
                                                zoom: 1, snapping: true)
        #expect(result.guideX == column)
        #expect(abs(result.labelNudge - 4) < 0.001)
    }

    // MARK: - A vertical caliper transposes

    @Test func aVerticalCaliperSlidesUpAndDown() {
        var m = MeasureContent(start: CGPoint(x: 200, y: 100), end: CGPoint(x: 200, y: 400),
                               headOffset: 50, mode: .vertical)
        let centre = chipCentre(m)
        let row = centre.y - 70
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x, y: row + 3),
                                                grabCross: 0, grabAlong: 0,
                                                guides: EdgeSnapping.GuideLines(horizontal: [row]),
                                                zoom: 1, snapping: true)
        #expect(result.guideY == row)
        #expect(result.guideX == nil)
        m.headOffset = result.headOffset
        m.labelNudge = result.labelNudge
        #expect(abs(chipCentre(m).y - row) < 0.001)
        #expect(abs(m.rawDistance - 300) < 0.001)
    }

    // MARK: - A hand-placed number is left alone

    @Test func aHandPlacedNumberIsPinnedAndSurvivesAReplan() {
        let layer = MeasureBuilder.layer(content: caliper(),
                                         from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        let slid = MeasureBuilder.updating(layer, start: CGPoint(x: 100, y: 300),
                                           end: CGPoint(x: 300, y: 300), headOffset: 40,
                                           readout: MeasureReadoutPlacement(nudge: 55, pinned: true))
        #expect(slid.measure?.labelNudge == 55)
        #expect(slid.measure?.labelPinned == true)

        let replanned = MeasureBuilder.replanningLabel(slid, canvas: CGSize(width: 800, height: 600))
        #expect(replanned.measure?.labelNudge == 55)
        #expect(replanned.measure?.labelPlacement == slid.measure?.labelPlacement)
    }

    @Test func anUntouchedNumberIsStillPlacedAutomatically() {
        var content = caliper()
        content.labelNudge = 55
        let layer = MeasureBuilder.layer(content: content,
                                         from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        #expect(layer.measure?.labelPinned == false)
        let replanned = MeasureBuilder.replanningLabel(layer, canvas: CGSize(width: 800, height: 600))
        #expect(replanned.measure?.labelNudge == 0)
    }

    @Test func pinningSurvivesASaveAndReload() throws {
        var content = caliper()
        content.labelNudge = 42
        content.labelPinned = true
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.labelNudge == 42)
        #expect(back.labelPinned)
    }

    @Test func aDocumentSavedBeforePinningDecodesUnpinned() throws {
        let json = """
        {"start":[100,300],"end":[300,300],"headOffset":40,"mode":"horizontal",
         "strokeWidth":1,"showLabel":true,"unit":"pixels","decimals":0,"labelNudge":12}
        """
        let back = try JSONDecoder().decode(MeasureContent.self, from: Data(json.utf8))
        #expect(back.labelPinned == false)
        #expect(back.labelNudge == 12)
    }

    /// A drag that only deepens the fork leaves the number where the placer put
    /// it, and does not claim it was placed by hand.
    @Test func aDragThatDoesNotTouchTheNumberDoesNotPinIt() {
        var content = caliper()
        content.labelNudge = 12
        let layer = MeasureBuilder.layer(content: content,
                                         from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        let deeper = MeasureBuilder.updating(layer, start: CGPoint(x: 100, y: 300),
                                             end: CGPoint(x: 300, y: 300), headOffset: 70)
        #expect(deeper.measure?.labelPinned == false)
        #expect(deeper.measure?.labelNudge == 12)
    }

    /// Esc puts an unpinned number back exactly as it was, pin included.
    @Test func theOriginalPlacementCanBePutBack() {
        let layer = MeasureBuilder.layer(content: caliper(),
                                         from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 300))
        let slid = MeasureBuilder.updating(layer, start: CGPoint(x: 100, y: 300),
                                           end: CGPoint(x: 300, y: 300), headOffset: 40,
                                           readout: MeasureReadoutPlacement(nudge: 55, pinned: true))
        let cancelled = MeasureBuilder.updating(slid, start: CGPoint(x: 100, y: 300),
                                                end: CGPoint(x: 300, y: 300), headOffset: 40,
                                                readout: MeasureReadoutPlacement(nudge: 0,
                                                                                 pinned: false))
        #expect(cancelled.measure?.labelNudge == 0)
        #expect(cancelled.measure?.labelPinned == false)
    }

    // MARK: - The older across-only drag

    /// With sliding switched off the drag is what it always was: the number
    /// keeps its place along the line however far sideways the pointer goes.
    @Test func slidingOffLeavesTheNumberWhereItWas() {
        var m = caliper()
        m.labelNudge = 12
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 90,
                                                                   y: centre.y + 25),
                                                grabCross: 0, grabAlong: 0, guides: .none,
                                                zoom: 1, snapping: false, slidesAlong: false)
        #expect(result.labelNudge == 12)
        #expect(abs(result.headOffset - 65) < 0.001)
    }

    /// ...and it is offered no line to snap to on an axis it cannot move on.
    @Test func slidingOffOffersNoColumnGuide() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(
            m, pointer: CGPoint(x: centre.x + 2, y: centre.y),
            grabCross: 0, grabAlong: 0,
            guides: EdgeSnapping.GuideLines(vertical: [centre.x + 4]),
            zoom: 1, snapping: true, slidesAlong: false)
        #expect(result.guideX == nil)
    }

    // MARK: - Who owns the number afterwards

    /// A number left somewhere of your choosing is yours, and nothing re-places it.
    @Test func aSlidNumberIsHandPlaced() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 60, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: true)
        #expect(result.readout.pinned)
        #expect(abs(result.readout.nudge - 60) < 0.001)
    }

    /// Pushed straight away from the measurement without sliding, the number is
    /// still where the app put it, so the app keeps it.
    @Test func aNumberOnlyPushedAcrossIsNotHandPlaced() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x, y: centre.y + 40),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: true)
        #expect(!result.readout.pinned)
    }

    /// Slid back onto its own centre, the number is handed back: it can dodge
    /// again, which is the only way back short of undoing.
    @Test func slidingItHomeHandsTheNumberBack() {
        let m = caliper()
        let centre = chipCentre(m)
        let result = MeasureReadoutDrag.resolve(m, pointer: CGPoint(x: centre.x + 3, y: centre.y),
                                                grabCross: 0, grabAlong: 0,
                                                guides: .none, zoom: 1, snapping: true)
        #expect(result.readout.nudge == 0)
        #expect(!result.readout.pinned)
    }

    // MARK: - A number slid off its bar stays attached

    /// Slid a little, the number is still on its own head bar, which splits
    /// around it exactly as before.
    @Test func aNumberStillOnItsBarKeepsRidingTheLine() {
        var m = caliper()
        m.labelNudge = 20
        #expect(m.labelRidesTheLine(chipSize: m.estimatedLabelSize))
    }

    /// Slid clean off the end of the bar there is no line left under it, so it
    /// stops splitting one and is drawn as a relocated readout (which is what
    /// earns it a connector back to its caliper).
    @Test func aNumberSlidOffItsBarStopsRidingTheLine() {
        var m = caliper()
        m.labelNudge = m.rawDistance / 2 + m.chipAxisHalfExtent(chipSize: m.estimatedLabelSize) + 4
        #expect(!m.labelRidesTheLine(chipSize: m.estimatedLabelSize))
    }
}
