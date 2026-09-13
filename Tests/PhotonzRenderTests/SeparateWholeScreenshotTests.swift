import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Separate into Layers run over a WHOLE screen rather than one pane.
///
/// The three things that only go wrong at that size, and that this pins:
///
/// 1. A dense picture must not hand back a layers list nobody can use
///    (`SeparateBudget`).
/// 2. Every piece it found is either taken or COUNTED — the number the pill
///    prints has to be the number of things still sitting in the picture, or it
///    is worse than saying nothing.
/// 3. What was left because of the limit is still there to take, so running the
///    command again reaches it. That is what the pill promises.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate over a whole screenshot")
struct SeparateWholeScreenshotTests {

    /// A page with `count` runs of text on it, laid out in columns the way a
    /// dense list is. Each run is five dark bars with daylight between them and
    /// with different heights, so it reads as WORDS: ink all the way round a
    /// component's outline is how the sweep knows a box from a sentence, and
    /// five bars of equal height would be a box.
    private func densePage(runs count: Int, columns: Int = 4) throws -> CGImage {
        let pitch = 30, columnWidth = 200
        let rows = (count + columns - 1) / columns
        let w = columns * columnWidth, h = rows * pitch + pitch
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            bytes[i * 4] = 245; bytes[i * 4 + 1] = 245
            bytes[i * 4 + 2] = 245; bytes[i * 4 + 3] = 255
        }
        for run in 0..<count {
            let column = run % columns, row = run / columns
            let x0 = column * columnWidth + 20, y0 = row * pitch + 10
            let heights = [12, 8, 10, 8, 12]
            for bar in 0..<5 {
                let top = y0 + (12 - heights[bar]) / 2
                for y in top..<(top + heights[bar]) {
                    for x in (x0 + bar * 12)..<(x0 + bar * 12 + 8) {
                        let i = (y * w + x) * 4
                        bytes[i] = 30; bytes[i + 1] = 30; bytes[i + 2] = 30
                    }
                }
            }
        }
        return try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
    }

    private func separate(_ image: CGImage) throws -> LayerSeparator.Result {
        let analysis = EdgeMapAnalyzer.analyzeFully(image)
        return try #require(LayerSeparator.separate(image, luma: analysis.luma))
    }

    @Test func aDensePictureStopsAtTheLimitInsteadOfHandingBackAWall() throws {
        let page = try densePage(runs: 200)
        let result = try separate(page)
        #expect(result.runs.count <= SeparateBudget.maxTextRuns)
        #expect(result.crowded == 200 - SeparateBudget.maxTextRuns)
        print("WHOLE dense page: \(result.runs.count) runs out, "
            + "\(result.skipped) unclear, \(result.crowded) crowded out")
    }

    @Test func everythingItFoundIsEitherTakenOrCounted() throws {
        // The number in the pill is the number of things still in the picture.
        // Anything found and quietly dropped would make that a lie, which is
        // the one thing the notice cannot be.
        let page = try densePage(runs: 200)
        let analysis = EdgeMapAnalyzer.analyzeFully(page)
        let found = TextRunSweep.sweep(in: analysis.luma).runs.count
        let result = try #require(LayerSeparator.separate(page, luma: analysis.luma))
        #expect(found == 200)
        #expect(result.runs.count + result.left == found)
    }

    @Test func runningItAgainTakesThePiecesTheLimitLeftBehind() throws {
        // What the pill tells you to do has to work. The first run takes its
        // hundred and fifty; the ones it left are still in the repaired
        // picture, so the second run finds exactly them.
        let page = try densePage(runs: 200)
        let first = try separate(page)
        let second = try separate(first.background)
        #expect(second.runs.count == 200 - SeparateBudget.maxTextRuns)
        #expect(second.crowded == 0)
        // And a third finds nothing at all: the picture is empty of text now,
        // so the pill says "nothing to separate" rather than offering another
        // run that would do nothing.
        let third = try separate(second.background)
        #expect(third.pieces.isEmpty)
        #expect(third.left == 0)
    }

    @Test func aPictureUnderTheLimitIsNotTouchedByIt() throws {
        let page = try densePage(runs: 40)
        let result = try separate(page)
        #expect(result.runs.count == 40)
        #expect(result.crowded == 0)
    }

    @Test func theTreeNeverIndentsDeeperThanTheLimit() throws {
        let page = try densePage(runs: 200)
        let result = try separate(page)
        #expect(LayerNesting.depth(of: result.nested) <= SeparateBudget.maxDepth)
    }
}
