import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Lining measurements up with each other: the snap lines the OTHER
/// measurements on the canvas offer while one of them is being dragged.
@Suite("Measurement snapping")
struct MeasureSnappingTests {

    private func caliper(from start: CGPoint, to end: CGPoint,
                         headOffset: CGFloat, mode: MeasureMode = .horizontal,
                         isVisible: Bool = true) -> Layer {
        let content = MeasureContent(headOffset: headOffset, mode: mode)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        layer.isVisible = isVisible
        return layer
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: layers)
    }

    // MARK: Chip centres

    @Test func chipCentreSitsOnTheHeadLineOfAnUnmovedReadout() throws {
        let layer = caliper(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200),
                            headOffset: -40)
        let centre = try #require(MeasureSnapping.chipCentre(of: layer))
        // Feet at y 200, head 40 above them; the chip centres on the head line
        // midway between the feet.
        #expect(abs(centre.y - 160) < 0.001)
        #expect(abs(centre.x - 200) < 0.001)
    }

    @Test func chipCentreFollowsAReadoutPushedClearOfItsSubject() throws {
        var content = MeasureContent(headOffset: -40, mode: .horizontal)
        content.labelPlacement = .clearPositive
        let layer = MeasureBuilder.layer(content: content,
                                         from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200))
        let centre = try #require(MeasureSnapping.chipCentre(of: layer))
        // The head stands 40 above the feet, but this readout was pushed clear
        // to the other side. Lining chips up has to follow the chip a person
        // can see, not the head line it came from.
        #expect(centre.y != 160)
        #expect(centre.y > 200)
    }

    // MARK: Candidate collection

    @Test func chipLinesComeFromTheOtherMeasurementsOnly() {
        let dragged = caliper(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200),
                              headOffset: -40)
        let other = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400),
                            headOffset: -40)
        let lines = MeasureSnapping.chipLines(in: document([dragged, other]), excluding: dragged.id)
        #expect(lines.horizontal.contains { abs($0 - 360) < 0.001 })
        #expect(!lines.horizontal.contains { abs($0 - 160) < 0.001 })
    }

    @Test func chipLinesCarryBothAxesSoEitherModeCanUseThem() {
        let other = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400),
                            headOffset: -40)
        let lines = MeasureSnapping.chipLines(in: document([other]), excluding: UUID())
        #expect(lines.horizontal.contains { abs($0 - 360) < 0.001 })
        #expect(lines.vertical.contains { abs($0 - 200) < 0.001 })
    }

    @Test func caliperLinesCarryTheFeetLineTheHeadLineAndBothEnds() {
        let other = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400),
                            headOffset: -40)
        let lines = MeasureSnapping.lines(in: document([other]), excluding: UUID())
        #expect(lines.horizontal.contains { abs($0 - 400) < 0.001 })  // feet line
        #expect(lines.horizontal.contains { abs($0 - 360) < 0.001 })  // head line
        #expect(lines.vertical.contains { abs($0 - 100) < 0.001 })    // foot A
        #expect(lines.vertical.contains { abs($0 - 300) < 0.001 })    // foot B
    }

    @Test func verticalCaliperOffersItsHeadLineAsAVerticalCandidate() {
        let other = caliper(from: CGPoint(x: 500, y: 100), to: CGPoint(x: 500, y: 300),
                            headOffset: 40, mode: .vertical)
        let lines = MeasureSnapping.lines(in: document([other]), excluding: UUID())
        #expect(lines.vertical.contains { abs($0 - 500) < 0.001 })
        #expect(lines.vertical.contains { abs($0 - 540) < 0.001 })
        #expect(lines.horizontal.contains { abs($0 - 100) < 0.001 })
        #expect(lines.horizontal.contains { abs($0 - 300) < 0.001 })
    }

    @Test func hiddenMeasurementsOfferNothingToLineUpWith() {
        let other = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400),
                            headOffset: -40, isVisible: false)
        #expect(MeasureSnapping.lines(in: document([other]), excluding: UUID()).isEmpty)
        #expect(MeasureSnapping.chipLines(in: document([other]), excluding: UUID()).isEmpty)
    }

    @Test func nonMeasureLayersOfferNothingToLineUpWith() {
        let text = Layer(name: "Text", content: .text(TextContent(string: "hi")),
                         frame: CGRect(x: 10, y: 10, width: 50, height: 20))
        #expect(MeasureSnapping.lines(in: document([text]), excluding: UUID()).isEmpty)
    }

    @Test func aReadoutThatIsSwitchedOffOffersNoChipLine() {
        var content = MeasureContent(headOffset: -40, mode: .horizontal)
        content.showLabel = false
        let layer = MeasureBuilder.layer(content: content,
                                         from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400))
        #expect(MeasureSnapping.chipLines(in: document([layer]), excluding: UUID()).isEmpty)
    }

    @Test func linesAreSortedAndDeduplicated() {
        let a = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400), headOffset: -40)
        let b = caliper(from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400), headOffset: -40)
        let lines = MeasureSnapping.lines(in: document([a, b]), excluding: UUID())
        #expect(lines.horizontal == lines.horizontal.sorted())
        #expect(lines.vertical == lines.vertical.sorted())
        #expect(Set(lines.horizontal).count == lines.horizontal.count)
        #expect(Set(lines.vertical).count == lines.vertical.count)
    }
}
