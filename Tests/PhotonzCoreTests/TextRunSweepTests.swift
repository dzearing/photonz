import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The sweep that finds every run of text in a picture at once
/// (`docs/design/separate-into-layers.md`).
///
/// Drawn scenes here, a real capture in `PhotonzRenderTests`: these pin the
/// rules one at a time, where a screenshot can only say whether the whole thing
/// agrees with a person looking at it.
@Suite("Sweeping a picture for runs of text")
struct TextRunSweepTests {

    /// A brightness field with a background and things painted on it, in the
    /// same top-left, row-major shape a real capture arrives in.
    private struct Scene {
        var width: Int
        var height: Int
        var samples: [UInt8]

        init(width: Int, height: Int, background: UInt8) {
            self.width = width
            self.height = height
            samples = [UInt8](repeating: background, count: width * height)
        }

        mutating func fill(_ rect: CGRect, _ value: UInt8) {
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) where
                    x >= 0 && y >= 0 && x < width && y < height {
                    samples[y * width + x] = value
                }
            }
        }

        /// A line of "words": stems of `ink`, `stem` wide, with daylight
        /// between them, shaped the way letters actually are — most of them x
        /// height, two reaching the ascender line, the last one dropping a
        /// descender below the baseline. Returns the ink box it drew.
        ///
        /// The shape matters. A row of identical full-height bars has ink right
        /// round its own outline, which is what a BOX looks like, and the sweep
        /// is right to refuse it.
        @discardableResult
        mutating func words(at origin: CGPoint, letters: Int, height: Int,
                            stem: Int = 3, spacing: Int = 6, ink: UInt8) -> CGRect {
            let x = Int(origin.x), y = Int(origin.y)
            let xHeight = max(1, height / 4)
            let descender = max(2, height / 5)
            for i in 0..<letters {
                let reachesUp = i == 0 || i == 3
                let top = reachesUp ? y : y + xHeight
                let bottom = i == letters - 1 ? y + height + descender : y + height
                fill(CGRect(x: x + i * spacing, y: top, width: stem, height: bottom - top), ink)
            }
            return CGRect(x: x, y: y, width: (letters - 1) * spacing + stem,
                          height: height + descender)
        }

        var field: LumaField { LumaField(width: width, height: height, samples: samples) }
    }

    @Test func aLineOfWordsIsOneRun() {
        var scene = Scene(width: 400, height: 200, background: 240)
        let drawn = scene.words(at: CGPoint(x: 100, y: 90), letters: 14, height: 20, ink: 20)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        #expect(runs.count == 1)
        // The ink box: first stem to last, ascender top to descender bottom.
        #expect(runs.first == drawn)
    }

    @Test func twoLabelsFurtherApartThanAGapAreTwoRuns() {
        var scene = Scene(width: 600, height: 200, background: 240)
        scene.words(at: CGPoint(x: 60, y: 90), letters: 10, height: 20, ink: 20)
        // Well past the 16 px stretch that ends a line.
        scene.words(at: CGPoint(x: 300, y: 90), letters: 10, height: 20, ink: 20)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        #expect(runs.count == 2)
    }

    @Test func aFilledBlockIsNotARun() {
        var scene = Scene(width: 400, height: 200, background: 240)
        scene.fill(CGRect(x: 100, y: 80, width: 120, height: 30), 20)
        #expect(TextRunSweep.sweep(in: scene.field).runs.isEmpty)
    }

    @Test func aDividerIsNotARun() {
        var scene = Scene(width: 400, height: 200, background: 240)
        scene.fill(CGRect(x: 40, y: 100, width: 320, height: 2), 120)
        #expect(TextRunSweep.sweep(in: scene.field).runs.isEmpty)
    }

    @Test func anOutlinedBoxIsNotARun() {
        // A button: ink all the way round its own outline, which is the one
        // thing a line of text never has.
        var scene = Scene(width: 400, height: 240, background: 240)
        scene.fill(CGRect(x: 80, y: 80, width: 200, height: 60), 240)
        for edge in [CGRect(x: 80, y: 80, width: 200, height: 3),
                     CGRect(x: 80, y: 137, width: 200, height: 3),
                     CGRect(x: 80, y: 80, width: 3, height: 60),
                     CGRect(x: 277, y: 80, width: 3, height: 60)] {
            scene.fill(edge, 20)
        }
        #expect(TextRunSweep.sweep(in: scene.field).runs.isEmpty)
    }

    @Test func theLabelInsideAButtonComesOutAndTheButtonDoesNot() {
        var scene = Scene(width: 400, height: 240, background: 240)
        for edge in [CGRect(x: 60, y: 70, width: 260, height: 3),
                     CGRect(x: 60, y: 157, width: 260, height: 3),
                     CGRect(x: 60, y: 70, width: 3, height: 90),
                     CGRect(x: 317, y: 70, width: 3, height: 90)] {
            scene.fill(edge, 20)
        }
        scene.words(at: CGPoint(x: 120, y: 100), letters: 12, height: 20, ink: 20)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        #expect(runs.count == 1)
        #expect(runs.first?.minX == 120)
        // 20 of x height plus the last letter's descender.
        #expect(runs.first?.height == 24)
    }

    @Test func lightWordsOnADarkBarReadTheSameAsDarkOnLight() {
        var scene = Scene(width: 400, height: 200, background: 240)
        scene.fill(CGRect(x: 40, y: 60, width: 320, height: 80), 30)
        scene.words(at: CGPoint(x: 120, y: 90), letters: 14, height: 20, ink: 250)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        #expect(runs.count == 1)
        #expect(runs.first?.minX == 120)
    }

    @Test func aHairlineOfInkIsNotARun() {
        // The antialiased under-edge of a heading, which is what used to come
        // back as a run of its own before there was a floor under the height.
        var scene = Scene(width: 400, height: 200, background: 240)
        scene.words(at: CGPoint(x: 100, y: 100), letters: 20, height: 3, ink: 20)
        #expect(TextRunSweep.sweep(in: scene.field).runs.isEmpty)
    }

    @Test func runsComeBackInReadingOrder() {
        var scene = Scene(width: 600, height: 400, background: 240)
        // Deliberately painted bottom-right first.
        scene.words(at: CGPoint(x: 320, y: 300), letters: 10, height: 20, ink: 20)
        scene.words(at: CGPoint(x: 60, y: 300), letters: 10, height: 20, ink: 20)
        scene.words(at: CGPoint(x: 320, y: 100), letters: 10, height: 20, ink: 20)
        scene.words(at: CGPoint(x: 60, y: 100), letters: 10, height: 20, ink: 20)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        #expect(runs.count == 4)
        #expect(runs.map { ($0.minX, $0.minY) }.map { "\(Int($0.0)),\(Int($0.1))" }
            == ["60,100", "320,100", "60,300", "320,300"])
    }

    @Test func noTwoRunsClaimTheSamePixel() {
        var scene = Scene(width: 600, height: 400, background: 240)
        scene.words(at: CGPoint(x: 60, y: 100), letters: 12, height: 20, ink: 20)
        scene.words(at: CGPoint(x: 60, y: 200), letters: 12, height: 20, ink: 250)
        let runs = TextRunSweep.sweep(in: scene.field).runs
        for (i, a) in runs.enumerated() {
            for b in runs[(i + 1)...] { #expect(!a.intersects(b)) }
        }
    }

    @Test func theInkMaskMarksTheLettersAndNotThePanel() {
        var scene = Scene(width: 400, height: 200, background: 240)
        scene.words(at: CGPoint(x: 100, y: 90), letters: 14, height: 20, ink: 20)
        let ink = TextRunSweep.sweep(in: scene.field).ink
        #expect(ink.isInk(101, 95))
        #expect(!ink.isInk(300, 30))
        // Outside the picture reads as background rather than trapping.
        #expect(!ink.isInk(-4, 95))
        #expect(!ink.isInk(4000, 95))
    }

    @Test func anEmptyFieldSweepsToNothing() {
        let sweep = TextRunSweep.sweep(in: .empty)
        #expect(sweep.runs.isEmpty)
        #expect(sweep.ink.isEmpty)
    }

    @Test func aBlankPictureHasNoRuns() {
        let scene = Scene(width: 400, height: 200, background: 240)
        #expect(TextRunSweep.sweep(in: scene.field).runs.isEmpty)
    }

    @Test func theSweepStopsAtTheLimitItIsGiven() {
        var scene = Scene(width: 600, height: 600, background: 240)
        for row in 0..<8 { scene.words(at: CGPoint(x: 60, y: 40 + row * 60), letters: 10,
                                       height: 20, ink: 20) }
        #expect(TextRunSweep.sweep(in: scene.field, limit: 3).runs.count == 3)
    }
}
