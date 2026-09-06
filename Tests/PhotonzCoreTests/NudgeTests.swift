import CoreGraphics
import Testing
@testable import PhotonzCore

/// Arrow-key nudge deltas (macOS convention: 1pt, ⇧ for 10pt).
@Suite("Nudge")
struct NudgeTests {

    @Test func arrowKeysMapToUnitDeltas() {
        #expect(Nudge.delta(keyCode: 123, large: false) == CGVector(dx: -1, dy: 0))  // ←
        #expect(Nudge.delta(keyCode: 124, large: false) == CGVector(dx: 1, dy: 0))   // →
        #expect(Nudge.delta(keyCode: 125, large: false) == CGVector(dx: 0, dy: 1))   // ↓ (model y grows down)
        #expect(Nudge.delta(keyCode: 126, large: false) == CGVector(dx: 0, dy: -1))  // ↑
    }

    @Test func shiftMakesTenPointNudges() {
        #expect(Nudge.delta(keyCode: 123, large: true) == CGVector(dx: -10, dy: 0))
        #expect(Nudge.delta(keyCode: 126, large: true) == CGVector(dx: 0, dy: -10))
    }

    @Test func otherKeysDoNotNudge() {
        #expect(Nudge.delta(keyCode: 53, large: false) == nil)  // Esc
        #expect(Nudge.delta(keyCode: 0, large: false) == nil)   // A
    }
}

/// Nudging while the canvas grid is pulling: the arrow keys step by the same
/// lines a drag lands on, so the two ways of moving something agree.
@Suite("Nudge on the grid")
struct GridNudgeTests {

    private func grid(_ spacing: CGFloat,
                      origin: CGPoint = .zero,
                      axes: CanvasGridAxes = .columnsAndRows) -> NudgeGrid {
        NudgeGrid(spacing: spacing, origin: origin, axes: axes)
    }

    @Test func onlyTheFourArrowsAreArrows() {
        #expect(Nudge.isArrow(keyCode: 123))
        #expect(Nudge.isArrow(keyCode: 124))
        #expect(Nudge.isArrow(keyCode: 125))
        #expect(Nudge.isArrow(keyCode: 126))
        #expect(!Nudge.isArrow(keyCode: 53))
        #expect(!Nudge.isArrow(keyCode: 36))
    }

    // MARK: Nothing pulling

    @Test func noGridLeavesTheKeysExactlyAsTheyWere() {
        #expect(Nudge.delta(keyCode: 124, large: false, grid: nil, from: .zero)
                == CGVector(dx: 1, dy: 0))
        #expect(Nudge.delta(keyCode: 126, large: true, grid: nil, from: CGPoint(x: 7, y: 7))
                == CGVector(dx: 0, dy: -10))
        #expect(Nudge.delta(keyCode: 53, large: false, grid: nil, from: .zero) == nil)
    }

    @Test func aGridWithNoRealSpacingIsNoGridAtAll() {
        for spacing: CGFloat in [0, -4, .nan, .infinity] {
            #expect(Nudge.delta(keyCode: 124, large: false, grid: grid(spacing), from: .zero)
                    == CGVector(dx: 1, dy: 0))
        }
        // A frame that is not a real point cannot be quantized either.
        #expect(Nudge.delta(keyCode: 124, large: false, grid: grid(32),
                            from: CGPoint(x: CGFloat.nan, y: 0)) == CGVector(dx: 1, dy: 0))
    }

    // MARK: One press, one cell

    @Test func onePressTravelsOneCell() {
        let from = CGPoint(x: 64, y: 64)
        #expect(Nudge.delta(keyCode: 124, large: false, grid: grid(32), from: from)
                == CGVector(dx: 32, dy: 0))
        #expect(Nudge.delta(keyCode: 123, large: false, grid: grid(32), from: from)
                == CGVector(dx: -32, dy: 0))
        #expect(Nudge.delta(keyCode: 125, large: false, grid: grid(32), from: from)
                == CGVector(dx: 0, dy: 32))
        #expect(Nudge.delta(keyCode: 126, large: false, grid: grid(32), from: from)
                == CGVector(dx: 0, dy: -32))
    }

    @Test func theGridIsCountedFromWhereItStarts() {
        let offset = grid(10, origin: CGPoint(x: 3, y: 3))
        // 13 is a line of this grid, so a press lands on the next one.
        #expect(Nudge.delta(keyCode: 124, large: false, grid: offset,
                            from: CGPoint(x: 13, y: 13)) == CGVector(dx: 10, dy: 0))
        // 10 is not, so the first press rejoins the grid rather than keeping
        // the layer three points off it forever.
        #expect(Nudge.delta(keyCode: 124, large: false, grid: offset,
                            from: CGPoint(x: 10, y: 10)) == CGVector(dx: 3, dy: 0))
    }

    // MARK: Shift

    @Test func shiftTravelsWholeCellsAndAlwaysMoreThanOnePress() {
        // The same ten points as before where the grid is fine enough for it,
        // and whole cells everywhere else, never fewer than two.
        #expect(Nudge.coarseCells(spacing: 1) == 10)
        #expect(Nudge.coarseCells(spacing: 2) == 5)
        #expect(Nudge.coarseCells(spacing: 4) == 3)
        #expect(Nudge.coarseCells(spacing: 8) == 2)
        #expect(Nudge.coarseCells(spacing: 32) == 2)
        for spacing: CGFloat in [1, 2, 4, 8, 16, 32, 64, 128] {
            #expect(Nudge.coarseCells(spacing: spacing) >= 2)
        }
    }

    @Test func shiftMovesByThatManyCells() {
        #expect(Nudge.delta(keyCode: 124, large: true, grid: grid(32),
                            from: CGPoint(x: 64, y: 64)) == CGVector(dx: 64, dy: 0))
        #expect(Nudge.delta(keyCode: 126, large: true, grid: grid(4),
                            from: CGPoint(x: 40, y: 40)) == CGVector(dx: 0, dy: -12))
        // A one point grid is the old behaviour, to the point.
        #expect(Nudge.delta(keyCode: 124, large: true, grid: grid(1),
                            from: CGPoint(x: 5, y: 5)) == CGVector(dx: 10, dy: 0))
    }

    // MARK: Coming back onto the grid

    @Test func aLayerOffTheGridRejoinsItOnTheFirstPress() {
        let from = CGPoint(x: 70, y: 70)
        // Right: the next line is 96, so it travels 26, not a whole 32.
        #expect(Nudge.delta(keyCode: 124, large: false, grid: grid(32), from: from)
                == CGVector(dx: 26, dy: 0))
        // Left: the line behind it is 64.
        #expect(Nudge.delta(keyCode: 123, large: false, grid: grid(32), from: from)
                == CGVector(dx: -6, dy: 0))
        // Down and up, on the other axis.
        #expect(Nudge.delta(keyCode: 125, large: false, grid: grid(32), from: from)
                == CGVector(dx: 0, dy: 26))
        #expect(Nudge.delta(keyCode: 126, large: false, grid: grid(32), from: from)
                == CGVector(dx: 0, dy: -6))
    }

    @Test func shiftFromOffTheGridAlsoLandsOnIt() {
        let from = CGPoint(x: 70, y: 0)
        guard let delta = Nudge.delta(keyCode: 124, large: true, grid: grid(32), from: from) else {
            Issue.record("no nudge")
            return
        }
        let landed = from.x + delta.dx
        #expect(landed == 128) // two whole cells past the line it rejoined
        #expect(landed.truncatingRemainder(dividingBy: 32) == 0)
    }

    @Test func everyPressAfterTheFirstIsAWholeCell() {
        // Holding the key walks the lines: 70 → 96 → 128 → 160.
        var x: CGFloat = 70
        var walked: [CGFloat] = []
        for _ in 0..<3 {
            guard let delta = Nudge.delta(keyCode: 124, large: false, grid: grid(32),
                                          from: CGPoint(x: x, y: 0)) else { break }
            x += delta.dx
            walked.append(x)
        }
        #expect(walked == [96, 128, 160])
    }

    // MARK: Which way the lines run

    @Test func aGridOfColumnsOnlyPullsSideways() {
        let columns = grid(32, axes: .columns)
        #expect(Nudge.delta(keyCode: 124, large: false, grid: columns, from: CGPoint(x: 64, y: 70))
                == CGVector(dx: 32, dy: 0))
        // No lines across, so up and down are the plain one point they always were.
        #expect(Nudge.delta(keyCode: 125, large: false, grid: columns, from: CGPoint(x: 64, y: 70))
                == CGVector(dx: 0, dy: 1))
        #expect(Nudge.delta(keyCode: 126, large: true, grid: columns, from: CGPoint(x: 64, y: 70))
                == CGVector(dx: 0, dy: -10))
    }
}
