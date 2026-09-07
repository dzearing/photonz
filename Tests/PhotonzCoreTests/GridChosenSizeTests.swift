import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A size you choose is the size you get.
///
/// The grid has two ways of deciding how fine it is, and they are not the same
/// promise. **Automatic** says "follow the zoom", so the level-of-detail ladder
/// is the whole point of it: rungs fade in and out as you come closer.
/// **A chosen size** says "draw me this", and the only honest answer to that is
/// one spacing, the same everywhere, at every zoom.
///
/// The bug this suite pins down: a chosen size used to be nothing but the
/// FINEST rung of the ladder, so choosing four points drew fours, thirty twos
/// and two hundred and fifty sixes together, and at 100% drew no fours at all.
@Suite("A chosen grid size draws one grid")
struct GridChosenSizeTests {

    /// The whole range the canvas allows, walked finely enough that no zoom a
    /// pinch can reach is missed.
    private var zooms: [CGFloat] {
        (0...400).map { step in
            Viewport.minZoom * CGFloat(pow(Double(Viewport.maxZoom / Viewport.minZoom),
                                           Double(step) / 400))
        }
    }

    private func chosen(_ cell: CGFloat, spacing: CGFloat = 4,
                        majorEvery: Int = 8) -> CanvasGridSettings {
        CanvasGridSettings(isVisible: true, spacing: spacing,
                           majorEvery: majorEvery, minimumCell: cell)
    }

    // MARK: One grid, that spacing, every zoom

    @Test func aChosenSizeDrawsOnlyThatSpacingAndItsOwnEmphasis() {
        // Acceptance one and two together: every line position drawn is a whole
        // number of chosen cells from the zero point, and the only second entry
        // allowed is the bold every N, which sits ON lines the chosen grid is
        // already drawing rather than beside them.
        for cell in CanvasGridCellStops.all.dropFirst() {
            for majorEvery in [2, 4, 8, 10] {
                let g = chosen(cell, majorEvery: majorEvery)
                for zoom in zooms {
                    let drawn = g.levels(atZoom: zoom)
                    #expect(drawn.count <= 2,
                            "cell \(cell) every \(majorEvery) at zoom \(zoom) drew \(drawn.count)")
                    guard let finest = drawn.first else { continue }
                    #expect(finest.spacing == cell)
                    for level in drawn.dropFirst() {
                        let multiple = level.spacing / cell
                        #expect(abs(multiple - multiple.rounded()) < 1e-9)
                        #expect(level.spacing == cell * CGFloat(majorEvery))
                    }
                }
            }
        }
    }

    @Test func aFourPointGridDrawsFourPointLinesAtOneHundredPercent() {
        // The user's own report, as a test: set four, get four.
        let drawn = chosen(4).levels(atZoom: 1)
        #expect(drawn.first?.spacing == 4)
        #expect(drawn.first?.onScreenSpacing == 4)
        // And at full strength, because four screen points apart is a grid you
        // can read, not a wash.
        #expect(drawn.first!.opacity >= CanvasGridLevels.maximumOpacity - 1e-9)
    }

    @Test func theSpacingNeverChangesWithTheZoom() {
        // The one sentence of the task: one even grid, the same everywhere.
        for cell in CanvasGridCellStops.all.dropFirst() {
            let g = chosen(cell)
            let spacings = zooms.compactMap { g.levels(atZoom: $0).first?.spacing }
            #expect(!spacings.isEmpty)
            #expect(Set(spacings) == [cell], "cell \(cell) drew \(Set(spacings))")
        }
    }

    @Test func aChosenSizeCoarserThanTheSpacingStillDrawsExactlyOneGrid() {
        // The chosen size is a floor under the typed spacing, so what is drawn
        // is whichever is coarser — and it is still only ever that one.
        let g = chosen(16, spacing: 4)
        for zoom in zooms {
            for level in g.levels(atZoom: zoom).prefix(1) {
                #expect(level.spacing == 16)
            }
        }
    }

    // MARK: The emphasis is emphasis, not a second grid

    @Test func theBoldLineIsAlwaysOnALineTheChosenGridDraws() {
        let cell: CGFloat = 8
        let g = chosen(cell, majorEvery: 8)
        let origin: CGFloat = -13.5
        let drawn = g.levels(atZoom: 2)
        guard drawn.count == 2 else { return #expect(Bool(false), "no emphasis drawn") }
        let fine = CanvasGridLevels.lines(spacing: drawn[0].spacing,
                                          from: 0, to: 600, origin: origin)
        for line in CanvasGridLevels.lines(spacing: drawn[1].spacing,
                                           from: 0, to: 600, origin: origin) {
            #expect(fine.contains { abs($0 - line) < 1e-6 })
        }
    }

    @Test func theBoldLineNeverOutlivesTheGridItEmphasises() {
        // If the fine lines are gone, the bold ones go with them: otherwise the
        // only thing left on screen would be a density nobody chose.
        for cell in CanvasGridCellStops.all.dropFirst() {
            let g = chosen(cell)
            for zoom in zooms where g.levels(atZoom: zoom).isEmpty == false {
                let drawn = g.levels(atZoom: zoom)
                #expect(drawn.first?.spacing == cell)
            }
        }
    }

    @Test func aCoarserLineAlwaysComesOutStrongerThanAFinerOne() {
        for cell in CanvasGridCellStops.all.dropFirst() {
            for zoom in zooms {
                var seen: CGFloat = 0
                for level in chosen(cell).levels(atZoom: zoom) {
                    let composited = 1 - (1 - seen) * (1 - level.opacity)
                    #expect(composited > seen)
                    seen = composited
                }
            }
        }
    }

    // MARK: Too fine to draw is handled, not fudged

    @Test func aGridTooFineToReadFadesOutRatherThanTurningToMud() {
        // The deliberate answer to "what if the chosen cell is a solid wash at
        // this zoom": it thins to nothing and is not drawn, and nothing coarser
        // is put in its place. Below two screen points apart, lines land on the
        // same device pixels and stop being lines.
        let g = chosen(4)
        #expect(g.levels(atZoom: 0.25).isEmpty)  // one screen point apart
        #expect(g.levels(atZoom: 0.5).isEmpty)   // two screen points apart
        let faint = g.levels(atZoom: 0.75)       // three
        #expect(faint.first != nil)
        #expect(faint.first!.opacity < CanvasGridLevels.maximumOpacity)
    }

    @Test func fadingOutHasNoStepInIt() {
        // Whatever it does on the way out, it must not pop: sweep the zoom in
        // steps finer than a pinch and no strength may jump.
        for cell in CanvasGridCellStops.all.dropFirst() {
            let g = chosen(cell)
            var previous: [CGFloat: CGFloat] = [:]
            var first = true
            for step in 0...4000 {
                let t = Double(step) / 4000
                let zoom = Viewport.minZoom
                    * CGFloat(pow(Double(Viewport.maxZoom / Viewport.minZoom), t))
                var current: [CGFloat: CGFloat] = [:]
                for level in g.levels(atZoom: zoom) { current[level.spacing] = level.opacity }
                if !first {
                    for spacing in Set(previous.keys).union(current.keys) {
                        let before = previous[spacing] ?? 0
                        let after = current[spacing] ?? 0
                        #expect(abs(after - before) < 0.01,
                                "cell \(cell) level \(spacing) jumped \(before) to \(after) at \(zoom)")
                    }
                }
                previous = current
                first = false
            }
        }
    }

    @Test func onceTheLinesAreFarEnoughApartTheyStayFullyThereHoweverFarYouZoomIn() {
        // No fade at the top of the range: a chosen grid does not thin out
        // again just because you came closer.
        for cell in CanvasGridCellStops.all.dropFirst() {
            let g = chosen(cell)
            for zoom in zooms where cell * zoom >= CanvasGridLevels.chosenFullStrengthOnScreenSpacing {
                let strength = g.levels(atZoom: zoom).first?.opacity ?? 0
                #expect(strength >= CanvasGridLevels.maximumOpacity - 1e-9,
                        "cell \(cell) at zoom \(zoom)")
            }
        }
    }

    // MARK: Automatic is untouched

    @Test func automaticStillFollowsTheZoomOnTheLadder() {
        let auto = CanvasGridSettings(isVisible: true, spacing: 4,
                                      minimumCell: CanvasGridCellStops.automatic)
        for zoom in zooms {
            let ladder = CanvasGridLevels.levels(spacing: auto.drawnSpacing,
                                                 majorEvery: auto.majorEvery, zoom: zoom)
            #expect(auto.levels(atZoom: zoom) == ladder)
        }
        // And it is still the only setting whose density changes on its own.
        let spacings = Set(zooms.compactMap { auto.levels(atZoom: $0).first?.spacing })
        #expect(spacings.count > 1)
    }

    @Test func automaticNeverLeavesTheCanvasWithoutAGrid() {
        // The promise from "the grid never disappears at any zoom" still holds
        // where it was made: under automatic.
        let auto = CanvasGridSettings(isVisible: true, spacing: 4,
                                      minimumCell: CanvasGridCellStops.automatic)
        for zoom in zooms {
            let drawn = auto.levels(atZoom: zoom)
            #expect((drawn.map(\.opacity).max() ?? 0) >= CanvasGridLevels.maximumOpacity - 1e-9,
                    "zoom \(zoom)")
        }
    }

    // MARK: The pull follows the one grid drawn

    @Test func aChosenSizeIsWhatADragLandsOnAtEveryZoomItIsDrawn() {
        for cell in CanvasGridCellStops.all.dropFirst() {
            let g = chosen(cell)
            for zoom in zooms {
                let drawn = g.levels(atZoom: zoom)
                if drawn.isEmpty {
                    // Nothing drawn is nothing to pull to: an invisible grid
                    // must never catch a drag.
                    #expect(g.snapSpacing(atZoom: zoom) == nil, "cell \(cell) at zoom \(zoom)")
                } else {
                    #expect(g.snapSpacing(atZoom: zoom) == cell, "cell \(cell) at zoom \(zoom)")
                }
            }
        }
    }

    @Test func theReadoutSaysTheSizeThatWasChosen() {
        // Set and drawn are the same thing now, so there is no second number
        // to explain and no arrow on the chip.
        let g = chosen(16, spacing: 16)
        for zoom in zooms {
            #expect(g.liveSpacing(atZoom: zoom) == 16)
            #expect(g.liveSpacingNote(atZoom: zoom) == nil)
            #expect(g.spacingChipText(atZoom: zoom) == g.spacingText)
            #expect(!g.cellButtonHelp(atZoom: zoom).contains("Showing"))
        }
    }

    // MARK: Saying so, rather than just going quiet

    @Test func aSizeTooFineToDrawSaysSoRatherThanLeavingTheCanvasBlank() {
        // The one way this change can read as broken: the switch says the grid
        // is on, the button says 4 pt, and there is nothing on screen. So the
        // button admits it, and says what to do about it.
        let g = chosen(4)
        #expect(g.cellIsTooFineToDraw(atZoom: 0.5))
        #expect(g.cellButtonHelp(atZoom: 0.5).contains(CanvasGridCopy.cellTooFineHelp))
        // And at a zoom where it IS drawn, no such claim.
        #expect(!g.cellIsTooFineToDraw(atZoom: 1))
        #expect(!g.cellButtonHelp(atZoom: 1).contains(CanvasGridCopy.cellTooFineHelp))
    }

    @Test func automaticIsNeverTooFineToDraw() {
        // Automatic picks a rung it can draw, so it has nothing to admit to.
        let auto = CanvasGridSettings(isVisible: true, spacing: 4,
                                      minimumCell: CanvasGridCellStops.automatic)
        for zoom in zooms { #expect(!auto.cellIsTooFineToDraw(atZoom: zoom)) }
    }

    @Test func aHiddenGridIsNotCalledTooFine() {
        // Nothing is drawn because the grid is off, which is not the same
        // complaint and must not wear the same words.
        var g = chosen(4)
        g.isVisible = false
        #expect(!g.cellIsTooFineToDraw(atZoom: 0.5))
    }

    // MARK: Nonsense in, nothing drawn

    @Test func nonsenseInputsDrawNothingRatherThanCrashing() {
        #expect(chosen(8).levels(atZoom: 0).isEmpty)
        #expect(chosen(8).levels(atZoom: -1).isEmpty)
        #expect(chosen(8).levels(atZoom: .nan).isEmpty)
        #expect(chosen(8).levels(atZoom: .infinity).isEmpty)
    }
}
