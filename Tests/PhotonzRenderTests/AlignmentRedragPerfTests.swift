import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// What one move of a dragged alignment guide costs: the guide is measured
/// again on every pointer move (`keepAlignmentGuidesMeasured`), so that work
/// has to fit inside one 120 Hz frame, 8.3ms, or the verdict lags the hand
/// (the user, 2026-10-30: "please make it recompute when i drag it around (do
/// it quickly ideally)").
///
/// Measured the way a drag pays for it: the edge map already built (it is
/// built once, when the picture is analysed), then for each move the guide's
/// frame shifted and the whole document pass run, which finds the moved
/// guide, scans the edges it crosses, merges the drawn boxes, judges them and
/// places the readout.
///
/// This suite runs in a DEBUG build, where the same work is about 80 times
/// slower than in the app. Built with `-O` on 2026-10-30, the same sweep read
/// a p95 of 0.50ms for this 2800 px vertical guide and 0.66ms for a 3800 px
/// horizontal one, down from 7.6ms and 8.1ms before the scan stopped reading
/// whole rows (`EdgeMap.verticalEdges(inYRange:near:)`) and pixel accessors
/// (`AlignmentScan.groupedByPixels`). Here it read a p95 of 40ms against 716ms
/// before either change and 95ms with only the first; the budget fails both.
@Suite("What a dragged alignment guide costs per move", .serialized)
struct AlignmentRedragPerfTests {

    /// A 12 megapixel screenshot: the app window capture tiled to 4000 by 3000,
    /// so every column the guide crosses is a real UI's edges and text.
    private static func twelveMegapixelCapture() throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/app-window-2x",
                                                 withExtension: "png"))
        let tile = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        let context = try #require(CGContext(data: nil, width: 4000, height: 3000, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        for x in stride(from: 0, to: 4000, by: tile.width) {
            for y in stride(from: 0, to: 3000, by: tile.height) {
                context.draw(tile, in: CGRect(x: x, y: y, width: tile.width, height: tile.height))
            }
        }
        return try #require(context.makeImage())
    }

    @Test("A guide dragged across a 12 megapixel screenshot is measured again without reading whole rows")
    func remeasureFitsAFrame() throws {
        let analysis = EdgeMapAnalyzer.analyzeFully(try Self.twelveMegapixelCapture())
        let picture = AlignmentPicture(edges: analysis.edges, luma: analysis.luma, pixelScale: 2)
        let canvas = CGSize(width: 4000, height: 3000)

        // A guide down most of the screen, the longest thing a person drags:
        // the further it runs, the more it crosses.
        let line = AlignmentGuideLine(axis: .vertical, position: 200, span: 100...2900)
        var content = MeasureContent(headOffset: 0, mode: .vertical)
        content.alignment = AlignmentCheck(items: [], tolerance: 2)
        let seed = MeasureBuilder.layer(content: content, from: line.start, to: line.end)
        let guide = MeasureBuilder.remeasured(seed, along: line, picture: picture, boxes: [],
                                              canvas: canvas, avoiding: [])
        let document = PhotonzDocument(canvasSize: canvas, layers: [guide], pixelScale: 2)

        // The hand's path: three pixels a move across 300 pixels of window,
        // over buttons, labels and the gaps between them.
        let steps = (1...100).map { CGFloat($0) * 3 }
        var next = 0
        var moveMS: [Double] = []
        let clock = ContinuousClock()
        let move = {
            var moved = document
            let dx = steps[next % steps.count]
            next += 1
            moved.updateLayer(id: guide.id) { $0.frame = $0.frame.offsetBy(dx: dx, dy: 0) }
            let took = clock.measure { moved.keepAlignmentGuidesMeasured(since: document, picture: picture) }
            moveMS.append(Double(took.components.attoseconds) / 1e15 + Double(took.components.seconds) * 1000)
        }
        let reading = MachineSpeed.measureInterleaved(yardstick: .frame, rounds: 60, subject: move)
        let sorted = moveMS.sorted()
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let worst = sorted.last ?? .infinity
        // Printed rather than only asserted, so the audit's number comes from
        // the log.
        print(String(format: "[perf] alignment guide re-measure per move on 12 MP, debug build: median "
                     + "%.2fms, p95 %.2fms, worst %.2fms over %d moves",
                     reading.rawMS, p95, worst, sorted.count))
        // Judged at the 95th percentile, scaled by the frame ruler read in the
        // same rounds, so a busy machine is not read as a slow scan.
        let atP95 = MachineSpeed.Interleaved(normalizedMS: reading.normalizedMS * p95 / max(reading.rawMS, 0.001),
                                             rawMS: p95, yardstickMS: reading.yardstickMS,
                                             yardstick: reading.yardstick, rounds: reading.rounds)
        MachineSpeed.judgeScaled("a guide re-measured per move on a 12 megapixel screenshot (p95)", atP95,
                                 baselineMS: 40, tolerance: 1.5,
                                 sourceLocation: SourceLocation(fileID: #fileID, filePath: #filePath,
                                                                line: #line, column: #column))
    }
}
