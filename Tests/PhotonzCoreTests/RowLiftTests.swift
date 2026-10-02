import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The one lift every list's dragged row uses** (`RowLift.swift`): the
/// layers list and the timeline's track headers both draw their gap, their
/// moved-aside rows and their lifted row from it, so its geometry is tested
/// once here, rows of any height and rows riding along included.
@Suite("A row lifted out of a list")
struct RowLiftTests {

    typealias Row = RowLift.Row

    /// Rows of these heights, 4 apart, the first at y 4.
    static func rows(_ heights: [CGFloat]) -> [Row] {
        var top: CGFloat = 4
        return heights.map { height in
            defer { top += height + 4 }
            return Row(id: UUID(), top: top, height: height)
        }
    }

    @Test("Picked up, nothing moves and the gap is the lifted row's own slot and height")
    func pickUp() throws {
        let rows = Self.rows([30, 44, 30])
        let lift = try #require(RowLift(grabbing: rows[1].id, rows: rows, spacing: 4, pointerY: 50))
        #expect(lift.gap == 1 && lift.homeGap == 1)
        #expect(lift.gapTop == 38)
        #expect(lift.gapHeight == 44)
        #expect(lift.liftedTop == 38)
        for row in rows { #expect(lift.offset(of: row.id) == 0) }
        #expect(lift.trailingOffset == 0)
    }

    @Test("The pointer reads halves of rows as drawn, the gap reads as the gap, and the ends as the ends")
    func spots() throws {
        let rows = Self.rows([30, 30, 30])
        let lift = try #require(RowLift(grabbing: rows[0].id, rows: rows, spacing: 4, pointerY: 10))
        #expect(lift.spot(10) == .gap)
        #expect(lift.spot(-5) == .aboveAll)
        // The second row stands at 38 with the gap above it.
        #expect(lift.spot(40) == .row(0, upperHalf: true))
        #expect(lift.spot(60) == .row(0, upperHalf: false))
        #expect(lift.spot(500) == .pastAll)
    }

    @Test("Rows riding along are tucked away and the list closes up over them")
    func ridingRowsCloseUp() throws {
        let rows = Self.rows([30, 30, 30, 30])
        // The first row lifted with the second riding along.
        var lift = try #require(RowLift(grabbing: rows[0].id, riding: [rows[1].id], rows: rows,
                                        spacing: 4, pointerY: 10))
        #expect(lift.rest.map(\.id) == [rows[2].id, rows[3].id])
        // The gap is one row tall, so the third row moves up by one row.
        #expect(lift.offset(of: rows[2].id) == -34)
        #expect(lift.offset(of: rows[1].id) == 0)
        // And whatever sits under the list follows it up.
        #expect(lift.trailingOffset == -34)
        lift.gap = 2
        #expect(lift.offset(of: rows[2].id) == -68)
        #expect(lift.gapTop == 72)
    }

    @Test("Laid out again, the gap stays inside the rows standing")
    func relay() throws {
        let rows = Self.rows([30, 30, 30])
        var lift = try #require(RowLift(grabbing: rows[0].id, rows: rows, spacing: 4, pointerY: 10))
        lift.gap = 2
        lift.relay(rows: rows, riding: [rows[1].id, rows[2].id])
        #expect(lift.rest.isEmpty)
        #expect(lift.gap == 0)
    }

    @Test("Not in the list, or nothing to carry it past: no lift")
    func none() {
        let rows = Self.rows([30])
        #expect(RowLift(grabbing: rows[0].id, rows: rows, spacing: 4, pointerY: 10) == nil)
        #expect(RowLift(grabbing: UUID(), rows: rows, spacing: 4, pointerY: 10) == nil)
    }
}
