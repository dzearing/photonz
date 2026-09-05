import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Canvas grid")
struct CanvasGridTests {

    // MARK: Settings

    @Test func startsOffAtFourPointsWithBothAxes() {
        let g = CanvasGridSettings()
        #expect(g.isVisible == false)
        #expect(g.spacing == 4)
        #expect(g.axes == .columnsAndRows)
        #expect(g.majorEvery == 8)
    }

    @Test func spacingIsClampedToSomethingDrawable() {
        #expect(CanvasGridSettings(spacing: 0).spacing == CanvasGridSettings.spacingRange.lowerBound)
        #expect(CanvasGridSettings(spacing: -12).spacing == CanvasGridSettings.spacingRange.lowerBound)
        #expect(CanvasGridSettings(spacing: 99_999).spacing == CanvasGridSettings.spacingRange.upperBound)
        #expect(CanvasGridSettings(spacing: .nan).spacing == CanvasGridSettings.defaultSpacing)
        #expect(CanvasGridSettings(spacing: 12).spacing == 12)
    }

    @Test func theStrongLineMultipleIsClampedToAtLeastTwo() {
        #expect(CanvasGridSettings(majorEvery: 1).majorEvery == CanvasGridSettings.majorEveryRange.lowerBound)
        #expect(CanvasGridSettings(majorEvery: 10).majorEvery == 10)
        #expect(CanvasGridSettings(majorEvery: 5_000).majorEvery == CanvasGridSettings.majorEveryRange.upperBound)
    }

    @Test func survivesARoundTripThroughJSON() throws {
        let g = CanvasGridSettings(isVisible: true, axes: .columns, spacing: 12, majorEvery: 10)
        let data = try JSONEncoder().encode(g)
        #expect(try JSONDecoder().decode(CanvasGridSettings.self, from: data) == g)
    }

    @Test func decodingOlderStoredSettingsFillsInWhatIsMissing() throws {
        // A settings blob written before a field existed still reads back, and
        // an out-of-range number stored by hand is clamped rather than drawn.
        let data = Data(#"{"isVisible":true,"spacing":0}"#.utf8)
        let g = try JSONDecoder().decode(CanvasGridSettings.self, from: data)
        #expect(g.isVisible)
        #expect(g.spacing == CanvasGridSettings.spacingRange.lowerBound)
        #expect(g.axes == .columnsAndRows)
        #expect(g.majorEvery == CanvasGridSettings.defaultMajorEvery)
    }

    // MARK: Levels of detail

    private func levels(_ zoom: CGFloat, spacing: CGFloat = 4, majorEvery: Int = 8) -> [CanvasGridLevel] {
        CanvasGridLevels.levels(spacing: spacing, majorEvery: majorEvery, zoom: zoom)
    }

    @Test func noLevelIsEverFinerThanTheReadableBand() {
        // Every zoom from far out to far in: the finest level drawn is never
        // closer together on screen than the band's floor, which is what stops
        // the grid turning to mush.
        for step in 0...200 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) * 10.0 / 200.0))
            let drawn = levels(zoom)
            #expect(!drawn.isEmpty)
            for level in drawn {
                #expect(level.onScreenSpacing >= CanvasGridLevels.minimumOnScreenSpacing - 0.0001)
                #expect(level.opacity > 0)
                #expect(level.opacity <= CanvasGridLevels.maximumOpacity + 0.0001)
            }
        }
    }

    @Test func everyLevelIsAWholeMultipleOfTheOneBelowIt() {
        // The strong lines ARE the next level up, so they can only stay on the
        // grid if each level's spacing is a whole multiple of the finer one.
        for step in 0...80 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 8.0))
            let drawn = levels(zoom, spacing: 4, majorEvery: 8)
            for (finer, coarser) in zip(drawn, drawn.dropFirst()) {
                let ratio = coarser.spacing / finer.spacing
                #expect(abs(ratio - 8) < 0.0001)
            }
        }
    }

    @Test func everyLevelIsAWholeMultipleOfTheTypedSpacing() {
        for step in 0...80 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 8.0))
            for level in levels(zoom, spacing: 6, majorEvery: 10) {
                let multiple = level.spacing / 6
                #expect(abs(multiple - multiple.rounded()) < 0.0001)
            }
        }
    }

    @Test func aLevelFadesInFromNothingRatherThanArriving() {
        // Sweep the zoom continuously: no level's opacity may jump, which is
        // what "no popping" means. Compare the two sweeps level by level, by
        // spacing, so a level appearing or leaving has to do it from zero.
        var previous: [CGFloat: CGFloat] = [:]
        var first = true
        for step in 0...4000 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) * 10.0 / 4000.0))
            var current: [CGFloat: CGFloat] = [:]
            for level in levels(zoom) { current[level.spacing] = level.opacity }
            if !first {
                for spacing in Set(previous.keys).union(current.keys) {
                    let before = previous[spacing] ?? 0
                    let after = current[spacing] ?? 0
                    #expect(abs(after - before) < 0.01,
                            "level \(spacing) jumped from \(before) to \(after) at zoom \(zoom)")
                }
            }
            previous = current
            first = false
        }
    }

    @Test func zoomingInBringsTheTypedSpacingBack() {
        // At 100% a 4pt grid would be four screen points apart, so the finest
        // level on screen is a coarser rung. Zoom right in and the typed
        // spacing itself is what you see, at full strength.
        let atOne = levels(1)
        #expect(atOne.first!.spacing > 4)
        let closeUp = levels(32)
        #expect(closeUp.first!.spacing == 4)
        #expect(closeUp.first!.opacity == CanvasGridLevels.maximumOpacity)
    }

    @Test func zoomingOutDropsTheFineLinesAndKeepsTheCoarseOnes() {
        let near = levels(4).map(\.spacing)
        let far = levels(0.125).map(\.spacing)
        #expect(far.first! > near.first!)
        #expect(far.count <= 3)
    }

    @Test func aCoarserLineAlwaysComesOutStrongerThanAFinerOne() {
        // The hierarchy is the whole point: a person counts by the strong
        // lines. Each rung's lines sit on top of the finer rung's, so what an
        // eye sees at a rung is every rung up to it composited — and THAT is
        // what has to climb, so a fine line can never out-weigh the line above
        // it however the fade is sitting.
        for step in 0...400 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 40.0))
            let drawn = levels(zoom)
            guard drawn.count >= 2 else { continue }
            var seen: CGFloat = 0
            for level in drawn {
                let composited = 1 - (1 - seen) * (1 - level.opacity)
                #expect(composited > seen)
                seen = composited
            }
        }
    }

    @Test func theFinestLinesAreFullyThereOnceTheyAreFarEnoughApart() {
        // The band has a top as well as a floor. Once the finest lines on
        // screen are `fullStrengthOnScreenSpacing` apart they are drawn at full
        // strength, whatever multiple was typed — so the grid really arrives
        // instead of hovering half faded at every zoom anyone uses.
        for majorEvery in [2, 4, 8, 10, 16] {
            for step in 0...300 {
                let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 30.0))
                guard let finest = levels(zoom, spacing: 4, majorEvery: majorEvery).first,
                      finest.onScreenSpacing >= CanvasGridLevels.fullStrengthOnScreenSpacing
                else { continue }
                #expect(finest.opacity == CanvasGridLevels.maximumOpacity,
                        "every \(majorEvery) at zoom \(zoom)")
            }
        }
    }

    @Test func neverDrawsMoreThanThreeLevels() {
        for step in 0...200 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 20.0))
            #expect(levels(zoom).count <= 3)
        }
    }

    @Test func nonsenseInputsDrawNothingRatherThanCrashing() {
        #expect(CanvasGridLevels.levels(spacing: 4, majorEvery: 8, zoom: 0).isEmpty)
        #expect(CanvasGridLevels.levels(spacing: 4, majorEvery: 8, zoom: -2).isEmpty)
        #expect(CanvasGridLevels.levels(spacing: 0, majorEvery: 8, zoom: 1).isEmpty)
        #expect(CanvasGridLevels.levels(spacing: .nan, majorEvery: 8, zoom: 1).isEmpty)
        #expect(CanvasGridLevels.levels(spacing: 4, majorEvery: 8, zoom: .infinity).isEmpty)
    }

    // MARK: Where the lines go

    @Test func linesLandOnMultiplesOfTheSpacingInsideTheRange() {
        let lines = CanvasGridLevels.lines(spacing: 10, from: 5, to: 46)
        #expect(lines == [10, 20, 30, 40])
    }

    @Test func aLineExactlyOnEachEndOfTheRangeCounts() {
        #expect(CanvasGridLevels.lines(spacing: 10, from: 0, to: 20) == [0, 10, 20])
    }

    @Test func anEmptyOrBackwardsRangeHasNoLines() {
        #expect(CanvasGridLevels.lines(spacing: 10, from: 40, to: 20).isEmpty)
        #expect(CanvasGridLevels.lines(spacing: 10, from: 41, to: 49).isEmpty)
        #expect(CanvasGridLevels.lines(spacing: 0, from: 0, to: 100).isEmpty)
    }

    @Test func theLineCountIsCappedSoAWildSpacingCannotStallTheCanvas() {
        let lines = CanvasGridLevels.lines(spacing: 0.001, from: 0, to: 1_000_000, limit: 500)
        #expect(lines.count == 500)
    }
}
