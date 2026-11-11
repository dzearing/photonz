import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A redline of a Retina screenshot says its numbers in points, and every
/// dimension line shows where it starts and stops.
///
/// The user's calm-redline checklist, 2026-10-20: "Units match the picture:
/// points on a 2x screenshot unless the person asked for pixels". A 248 pixel
/// button on a 2x capture is 124 points wide, and it used to read "124 px",
/// which a reader takes for a wrong number.
@Suite("Measurements read in points on a 2x picture and show their ends")
struct MeasurePointsAndEndsTests {

    private func caliper(_ mode: MeasureMode = .horizontal, unit: MeasureUnit = .points,
                         from start: CGPoint = CGPoint(x: 100, y: 200),
                         to end: CGPoint = CGPoint(x: 348, y: 200), head: CGFloat = 0) -> MeasureContent {
        var c = MeasureContent(mode: mode, unit: unit)
        c.start = start
        c.end = end
        c.headOffset = head
        return c
    }

    // MARK: Units

    @Test("Points read pt on a scaled picture and px on a 1x one; pixels always read px")
    func unitWords() {
        #expect(MeasureUnit.points.suffix(pixelScale: 2) == "pt")
        #expect(MeasureUnit.points.suffix(pixelScale: 3) == "pt")
        #expect(MeasureUnit.points.suffix(pixelScale: 1) == "px")
        #expect(MeasureUnit.points.suffix(pixelScale: 0) == "px")
        #expect(MeasureUnit.pixels.suffix(pixelScale: 2) == "px")
        #expect(MeasureUnit.pixels.suffix(pixelScale: 1) == "px")
    }

    @Test("A 248 pixel span on a 2x picture reads 124 pt, or 248 px when the person chose pixels")
    func buttonReadsInPoints() {
        #expect(caliper().label(pixelScale: 2) == "124 pt")
        #expect(caliper().chipText(pixelScale: 2) == "124 pt")
        #expect(caliper(unit: .pixels).label(pixelScale: 2) == "248 px")
        #expect(caliper().label(pixelScale: 1) == "248 px")
    }

    @Test("A size's row in the Measurements list says pt on a 2x picture")
    func sizeRowInPoints() throws {
        let box = CGRect(x: 100, y: 100, width: 248, height: 60)
        var width = caliper(from: CGPoint(x: box.minX, y: box.maxY), to: CGPoint(x: box.maxX, y: box.maxY),
                            head: 28)
        width.mode = .horizontal
        let height = caliper(.vertical, from: CGPoint(x: box.maxX, y: box.minY),
                             to: CGPoint(x: box.maxX, y: box.maxY), head: 28)
        let parts = [width, height].map { MeasureBuilder.layer(content: $0, from: $0.start, to: $0.end) }
        let group = MeasureSizeGroup.group(measuring: box, width: parts[0], height: parts[1],
                                           boxColorHex: "#FF0000", boxOpacity: 0.1, pixelScale: 2)
        #expect(MeasureSizeGroup.valueText(of: group, pixelScale: 2) == "124 × 30 pt")
        #expect(MeasureSizeGroup.valueText(of: group, pixelScale: 1) == "248 × 60 px")
    }

    @Test("The spec list heads a 2x picture in points, and names the scale")
    func specHeaderInPoints() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 960), pixelScale: 2)
        let c = caliper()
        document.addLayer(MeasureBuilder.layer(content: c, from: c.start, to: c.end))
        #expect(MeasureSpecList.headerSize(document: document) == "720 × 480 pt @2x")
    }

    // MARK: Ends

    @Test("A measuring line drawn on its own feet has a tick across each end, on the edge it measures")
    func flatLineHasEndTicks() {
        let ticks = caliper().endTicks
        #expect(ticks.count == 2)
        let half = MeasureBuilder.endTickHalf
        #expect(ticks[0].0 == CGPoint(x: 100, y: 200 - half))
        #expect(ticks[0].1 == CGPoint(x: 100, y: 200 + half))
        #expect(ticks[1].0 == CGPoint(x: 348, y: 200 - half))
        #expect(ticks[1].1 == CGPoint(x: 348, y: 200 + half))

        let vertical = caliper(.vertical, from: CGPoint(x: 50, y: 10), to: CGPoint(x: 50, y: 40))
        #expect(vertical.endTicks.map(\.0) == [CGPoint(x: 50 - half, y: 10), CGPoint(x: 50 - half, y: 40)])
    }

    @Test("A bracket needs no ticks: its legs already land on the edges")
    func bracketHasNoTicks() {
        #expect(caliper(head: 28).endTicks.isEmpty)
        #expect(caliper(head: -40).endTicks.isEmpty)
    }

    @Test("The layer a flat measurement lands as holds its ticks, so none is cut off")
    func layerHoldsTicks() {
        var c = caliper()
        c.showLabel = false
        let layer = MeasureBuilder.layer(content: c, from: c.start, to: c.end)
        let half = MeasureBuilder.endTickHalf
        #expect(layer.frame.minY <= 200 - half)
        #expect(layer.frame.maxY >= 200 + half)
    }

    @Test("A readout pushed off a flat line clears its ticks, not just the hairline")
    func readoutClearsTicks() {
        var c = caliper()
        c.labelPlacement = .clearPositive
        let rect = c.labelRect(chipSize: c.estimatedLabelSize)
        #expect(rect.minY >= 200 + MeasureBuilder.endTickHalf)
    }

    // MARK: A readout never hides the line it labels

    @Test("A readout on the line hides it when the line is shorter than the readout")
    func shortLineIsHidden() {
        let short = caliper(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 124, y: 200))
        #expect(short.labelHidesItsLine(chipSize: short.estimatedLabelSize))
        let long = caliper()
        #expect(!long.labelHidesItsLine(chipSize: long.estimatedLabelSize))
        var stepped = short
        stepped.labelPlacement = .afterEnd
        #expect(!stepped.labelHidesItsLine(chipSize: stepped.estimatedLabelSize))
    }
}
