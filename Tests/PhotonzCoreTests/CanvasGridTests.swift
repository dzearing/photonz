import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Canvas grid")
struct CanvasGridTests {

    // MARK: What the settings say for themselves

    @Test func everyControlHasAPlainWordCaption() {
        for caption in CanvasGridCopy.captions {
            #expect(!caption.isEmpty)
            // User facing copy never carries an em dash.
            #expect(!caption.contains("\u{2014}"))
            // A caption that is one word is a second label, not an explanation.
            #expect(caption.split(separator: " ").count >= 5)
            #expect(caption.hasSuffix("."))
        }
    }

    @Test func theSmallestCellCaptionSaysWhatItActuallyDoes() {
        // The one number nobody can guess from its name: it is about how far
        // you may zoom in, and about what a drag can land on.
        let caption = CanvasGridCopy.minimumCell + " " + CanvasGridCopy.minimumCellCaption
        #expect(caption.localizedCaseInsensitiveContains("zoom"))
        #expect(caption.localizedCaseInsensitiveContains("finest")
                || caption.localizedCaseInsensitiveContains("smallest"))
    }

    @Test func theSnapCaptionSaysTheKeysUseTheGridToo() {
        // Nobody discovers that the arrow keys changed by pressing one and
        // watching a layer travel thirty two points, so the switch says so.
        #expect(CanvasGridCopy.snapCaption.localizedCaseInsensitiveContains("arrow keys"))
    }

    @Test func theSpacingReadsAsANumberWithItsUnit() {
        #expect(CanvasGridSettings(spacing: 4).spacingText == "4 pt")
        #expect(CanvasGridSettings(spacing: 12).spacingText == "12 pt")
        // Half points survive: a grid actually sitting on 7.5 must not say 8.
        #expect(CanvasGridSettings(spacing: 7.5).spacingText == "7.5 pt")
    }

    @Test func aNumberThatIsNotANumberStillReadsAsZero() {
        #expect(CanvasGridNumber.text(.nan) == "0")
        #expect(CanvasGridNumber.text(24) == "24")
        #expect(CanvasGridNumber.text(-16.5) == "-16.5")
    }

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

    @Test func someLineIsAlwaysFullyThereAtEveryZoomInTheWholeRange() {
        // The guard against the grid blinking out. Sweep the WHOLE zoom range
        // the canvas allows, in steps far finer than a pinch can move, for
        // every multiple and every spacing anyone can ask for: at each step
        // there has to be a line drawn, and the strongest one has to be at
        // FULL strength. "At least one line somewhere" would not be enough —
        // a grid drawn only at 0.004 is a grid nobody can see.
        for majorEvery in [2, 3, 4, 8, 10, 16, 100] {
            for spacing in [CGFloat(1), 4, 6, 8, 256, 512] {
                for step in 0...2000 {
                    let t = Double(step) / 2000
                    let zoom = Viewport.minZoom
                        * CGFloat(pow(Double(Viewport.maxZoom / Viewport.minZoom), t))
                    let drawn = levels(zoom, spacing: spacing, majorEvery: majorEvery)
                    let strongest = drawn.map(\.opacity).max() ?? 0
                    #expect(strongest == CanvasGridLevels.maximumOpacity,
                            "spacing \(spacing) every \(majorEvery) at zoom \(zoom) drew \(drawn.count) levels, strongest \(strongest)")
                }
            }
        }
    }

    @Test func theFinestRungGoingQuietNeverTakesTheWholeGridWithIt() {
        // The finest rung sits at the band's floor and is drawn at nothing
        // there, which is exactly how it leaves without popping. What must
        // never happen is the rung ABOVE it going quiet at the same moment.
        for step in 0...600 {
            let zoom = CGFloat(pow(2.0, -5.0 + Double(step) / 60.0))
            let drawn = levels(zoom)
            #expect(drawn.count >= 1)
            #expect(drawn.contains { $0.opacity == CanvasGridLevels.maximumOpacity })
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

    // MARK: Where the grid starts

    @Test func aGridNobodyHasTouchedStartsAtTheCorner() {
        let g = CanvasGridSettings()
        #expect(g.origin == .zero)
        #expect(g.minimumCell == CanvasGridSettings.noMinimumCell)
        // No floor means the ladder is exactly the one it has always been.
        #expect(g.drawnSpacing == g.spacing)
    }

    @Test func theZeroPointIsRememberedWithEverythingElse() throws {
        let g = CanvasGridSettings(origin: CGPoint(x: 24, y: -16), minimumCell: 8)
        let data = try JSONEncoder().encode(g)
        #expect(try JSONDecoder().decode(CanvasGridSettings.self, from: data) == g)
    }

    @Test func settingsWrittenBeforeThereWasAZeroPointStillRead() throws {
        let data = Data(#"{"isVisible":true,"spacing":8,"majorEvery":4}"#.utf8)
        let g = try JSONDecoder().decode(CanvasGridSettings.self, from: data)
        #expect(g.origin == .zero)
        #expect(g.minimumCell == CanvasGridSettings.noMinimumCell)
    }

    @Test func aZeroPointThatIsNotANumberIsIgnoredRatherThanDrawn() {
        #expect(CanvasGridSettings(origin: CGPoint(x: CGFloat.nan, y: 4)).origin == .zero)
        #expect(CanvasGridSettings(origin: CGPoint(x: CGFloat.infinity, y: 0)).origin == .zero)
    }

    @Test func linesRunFromTheZeroPointRatherThanFromTheCorner() {
        #expect(CanvasGridLevels.lines(spacing: 10, from: 0, to: 30, origin: 3) == [3, 13, 23])
    }

    @Test func aNegativeZeroPointWorksTheSameWay() {
        #expect(CanvasGridLevels.lines(spacing: 10, from: 0, to: 20, origin: -7) == [3, 13])
    }

    @Test func anOffsetGridStillLandsOnWholeStepsAtEveryZoom() {
        // The promise of a zero point: however far you zoom and wherever you
        // put it, every line drawn is a whole number of cells away from it.
        // A line that drifted a fraction of a point would put a snapped edge
        // beside the line it snapped to rather than on it.
        let origin: CGFloat = 13.5
        for step in 0...80 {
            let zoom = pow(2, CGFloat(step) / 10 - 4)
            let settings = CanvasGridSettings(spacing: 4, origin: CGPoint(x: origin, y: origin))
            for level in CanvasGridLevels.levels(spacing: settings.drawnSpacing,
                                                 majorEvery: settings.majorEvery,
                                                 zoom: zoom) {
                for line in CanvasGridLevels.lines(spacing: level.spacing,
                                                   from: -500, to: 500, origin: origin) {
                    let steps = (line - origin) / level.spacing
                    #expect(abs(steps - steps.rounded()) < 1e-6)
                }
            }
        }
    }

    @Test func everyRungStillContainsTheOneAboveItWhenTheGridIsOffset() {
        // The rungs stack, which is what makes every Nth line stronger. An
        // offset must not break that: a coarse line has to sit exactly on a
        // fine one, or the strong lines would be drawn beside the grid.
        let origin: CGFloat = -6.25
        let fine = CanvasGridLevels.lines(spacing: 4, from: 0, to: 400, origin: origin)
        let coarse = CanvasGridLevels.lines(spacing: 32, from: 0, to: 400, origin: origin)
        for line in coarse {
            #expect(fine.contains { abs($0 - line) < 1e-6 })
        }
    }

    // MARK: The smallest cell

    @Test func theSmallestCellIsClampedToSomethingDrawable() {
        #expect(CanvasGridSettings(minimumCell: 0).minimumCell == CanvasGridSettings.noMinimumCell)
        #expect(CanvasGridSettings(minimumCell: .nan).minimumCell == CanvasGridSettings.noMinimumCell)
        #expect(CanvasGridSettings(minimumCell: 99_999).minimumCell
                == CanvasGridSettings.minimumCellRange.upperBound)
        #expect(CanvasGridSettings(minimumCell: 8).minimumCell == 8)
    }

    @Test func theSmallestCellRaisesTheFinestCellDrawn() {
        #expect(CanvasGridSettings(spacing: 2, minimumCell: 8).drawnSpacing == 8)
        // A floor under the spacing changes nothing: the spacing was already
        // coarser than the floor asked for.
        #expect(CanvasGridSettings(spacing: 16, minimumCell: 8).drawnSpacing == 16)
    }

    @Test func nothingIsEverDrawnFinerThanTheSmallestCellHoweverFarYouZoom() {
        for step in 0...120 {
            let zoom = pow(2, CGFloat(step) / 10 - 4)
            let levels = CanvasGridLevels.levels(spacing: 1, majorEvery: 8,
                                                 zoom: zoom, minimumCell: 8)
            for level in levels { #expect(level.spacing >= 8 - 1e-9) }
        }
    }

    @Test func theSmallestCellOnlyEverRaisesTheLadderNeverLowersIt() {
        // Asking for a floor below the spacing is a no-op, at every zoom.
        for step in 0...60 {
            let zoom = pow(2, CGFloat(step) / 10 - 2)
            let floored = CanvasGridLevels.levels(spacing: 4, majorEvery: 8,
                                                  zoom: zoom, minimumCell: 2)
            let plain = CanvasGridLevels.levels(spacing: 4, majorEvery: 8, zoom: zoom)
            #expect(floored == plain)
        }
    }

    @Test func theSmallestCellRaisesWhatADragLandsOnToo() {
        // The floor says what you LOOK at, and a drag lands on what you are
        // looking at, so asking for sixteen point cells is asking to work in
        // sixteens. Anything finer would be a pull to lines that are not there.
        let g = CanvasGridSettings(isVisible: true, spacing: 2, minimumCell: 16)
        #expect(g.snapSpacing(atZoom: 1) == 16)
        #expect(g.snapSpacing(atZoom: 4) == 16)
    }

    // MARK: Placing the zero point

    @Test func placingStartsFromWhereTheGridAlreadyIs() {
        let before = CanvasGridSettings(isVisible: false, spacing: 8,
                                        origin: CGPoint(x: 3, y: 5), minimumCell: 4)
        let session = CanvasGridOriginAdjustment(settings: before)
        #expect(session.origin == CGPoint(x: 3, y: 5))
        #expect(session.minimumCell == 4)
        // Nobody adjusts a grid they cannot see, so placing shows it.
        #expect(session.live.isVisible)
        #expect(session.live.spacing == 8)
    }

    @Test func theArrowKeysMoveTheZeroPointByOnePointAndTenWithShift() {
        var session = CanvasGridOriginAdjustment(settings: CanvasGridSettings())
        session.nudge(CGVector(dx: 1, dy: 0))
        #expect(session.origin == CGPoint(x: 1, y: 0))
        session.nudge(CGVector(dx: 0, dy: -10))
        #expect(session.origin == CGPoint(x: 1, y: -10))
    }

    @Test func theLiveGridCarriesWhatYouAreAdjustingAndNothingElse() {
        var session = CanvasGridOriginAdjustment(
            settings: CanvasGridSettings(isVisible: true, axes: .columns, spacing: 6, majorEvery: 4))
        session.origin = CGPoint(x: 12, y: 20)
        session.minimumCell = 12
        let live = session.live
        #expect(live.origin == CGPoint(x: 12, y: 20))
        #expect(live.minimumCell == 12)
        #expect(live.axes == .columns)
        #expect(live.spacing == 6)
        #expect(live.majorEvery == 4)
    }

    @Test func leavingWithoutKeepingItPutsBackEverythingItTouched() {
        let before = CanvasGridSettings(isVisible: false, snapsToGrid: false, axes: .columns,
                                        spacing: 6, majorEvery: 4,
                                        origin: CGPoint(x: 2, y: 2), minimumCell: 4)
        var session = CanvasGridOriginAdjustment(settings: before)
        session.origin = CGPoint(x: 40, y: 40)
        session.minimumCell = 32
        #expect(session.cancelled == before)
    }

    @Test func keepingItWritesTheZeroPointAndTheSmallestCellBack() {
        let before = CanvasGridSettings(spacing: 6)
        var session = CanvasGridOriginAdjustment(settings: before)
        session.origin = CGPoint(x: 40, y: 12)
        session.minimumCell = 32
        let kept = session.committed
        #expect(kept.origin == CGPoint(x: 40, y: 12))
        #expect(kept.minimumCell == 32)
        #expect(kept.spacing == 6)
        // Placing switched the grid on, and keeping it keeps it on.
        #expect(kept.isVisible)
    }

    @Test func anOutOfRangeSmallestCellCannotBeTypedIntoTheSession() {
        var session = CanvasGridOriginAdjustment(settings: CanvasGridSettings())
        session.minimumCell = 100_000
        #expect(session.live.minimumCell == CanvasGridSettings.minimumCellRange.upperBound)
    }

    // MARK: Saying where it starts, in words

    @Test func theZeroPointReadsAsTwoWholeNumbers() {
        #expect(CanvasGridOriginLabel.text(CGPoint(x: 24, y: 16)) == "24, 16")
        #expect(CanvasGridOriginLabel.text(.zero) == "0, 0")
        #expect(CanvasGridOriginLabel.text(CGPoint(x: -8, y: 12)) == "-8, 12")
    }

    @Test func aHalfPointIsShownRatherThanQuietlyRounded() {
        // A number that rounded away would be a lie about where the grid is.
        #expect(CanvasGridOriginLabel.text(CGPoint(x: 24.5, y: 16)) == "24.5, 16")
        #expect(CanvasGridOriginLabel.text(CGPoint(x: 24.26, y: 16)) == "24.5, 16")
    }
}

