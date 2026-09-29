import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Filming a segmented control's thumb as it moves, and reading where the
/// glass is drawn in each frame against its rail.
///
/// The user, 2026-09-29, of View | Edit in the title bar: "the segmented
/// control overshoots like CRAZY". The motion model was bounded to the row and
/// its tests were green, so the only honest check is the drawn window, frame by
/// frame, which is what `filmThumb` takes.
@Suite("Filming the segmented thumb")
struct PlaytestThumbFilmTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A filmThumb step names its rail, how long to film and a key that sets the thumb off")
    func parsesAKey() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmThumb", "name": "edit-to-view", "rail": ["View Mode", "Edit Mode"],
                       "seconds": 0.8, "key": "1", "modifiers": ["command"], "inside": true } ] }
        """)
        guard case .filmThumb(let film) = script.steps[0] else { Issue.record("filmThumb"); return }
        #expect(film.name == "edit-to-view")
        #expect(film.rail == ["View Mode", "Edit Mode"])
        #expect(film.pad == 0)
        #expect(film.seconds == 0.8)
        #expect(film.trigger == .key(try #require(PlaytestKey("1")), [.command]))
        #expect(film.inside == true)
        #expect(script.steps[0].name == "filmThumb")
        #expect(PlaytestStep.names.contains("filmThumb"))
    }

    @Test("It can press a control by its face instead, and films 0.7s unless it says")
    func parsesAPress() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmThumb", "name": "across", "rail": ["Left", "Right"], "pad": 2,
                       "press": "Center", "in": "Across" } ] }
        """)
        guard case .filmThumb(let film) = script.steps[0] else { Issue.record("filmThumb"); return }
        #expect(film.pad == 2)
        #expect(film.seconds == 0.7)
        #expect(film.trigger == .press(control: "Center", in: "Across"))
        #expect(film.inside == nil)
    }

    @Test("It needs exactly one thing to set the thumb off, a rail, and a sane length",
          arguments: [
              #"{ "do": "filmThumb", "name": "x", "rail": ["A"] }"#,
              #"{ "do": "filmThumb", "name": "x", "rail": ["A"], "key": "1", "press": "B" }"#,
              #"{ "do": "filmThumb", "name": "x", "key": "1" }"#,
              #"{ "do": "filmThumb", "name": "x", "rail": ["A"], "key": "1", "seconds": 9 }"#,
          ])
    func refusesWhatItCannotFilm(step: String) {
        #expect(throws: PlaytestScriptError.self) {
            try decode(#"{ "steps": [ "# + step + #" ] }"#)
        }
    }

    // MARK: Reading a frame

    /// A strip 60 columns wide with the rail at columns 20...39: the rail is
    /// dark (0.05), the title bar to its left middling (0.15), the window's
    /// dark corner to its right (0.02), and the thumb light (0.3) wherever
    /// `lit` says.
    private func strip(lit: ClosedRange<Int>?) -> [Double] {
        (0..<60).map { column in
            if let lit, lit.contains(column) { return 0.3 }
            if (20...39).contains(column) { return 0.05 }
            return column < 20 ? 0.15 : 0.02
        }
    }

    private let rail = 20...39

    @Test("The backdrop is the middle brightness beside the rail, off its hairline, with the thumb at rest")
    func readsTheBackdrop() {
        var columns = strip(lit: 22...29)
        columns[17] = 0.5 // the rail's own edge, lit
        columns[1] = 0.6  // something bright beside it, the panel toggle
        #expect(ThumbFootprint.backdrop(columns: columns, rail: rail) == 0.15)
    }

    @Test("The thumb is the run of columns clearly lighter than the backdrop")
    func findsTheThumb() {
        #expect(ThumbFootprint.read(columns: strip(lit: 22...29), rail: rail, backdrop: 0.1) == 22...29)
    }

    @Test("Something bright off the rail is never the thumb, however wide")
    func ignoresWhatIsOffTheRail() {
        var columns = strip(lit: 30...33)
        for column in 44...59 { columns[column] = 0.4 }
        #expect(ThumbFootprint.read(columns: columns, rail: rail, backdrop: 0.1) == 30...33)
    }

    @Test("A thumb past where it rests counts the columns beyond, either side",
          arguments: [(34...46, 7), (13...24, 7), (18...41, 4), (22...39, 0)])
    func countsWhatLeftTheRoom(lit: ClosedRange<Int>, outside: Int) {
        let thumb = ThumbFootprint.read(columns: strip(lit: lit), rail: rail, backdrop: 0.1)
        #expect(thumb == lit)
        #expect(thumb.map { ThumbFootprint.outside($0, of: 20...39) } == outside)
    }

    @Test("No light glass anywhere reads as no thumb")
    func noThumb() {
        #expect(ThumbFootprint.read(columns: strip(lit: nil), rail: rail, backdrop: 0.15) == nil)
    }

    @Test("A lone light column, a letter's stroke, is not a thumb")
    func ignoresSpecks() {
        var columns = strip(lit: nil)
        columns[30] = 0.9
        #expect(ThumbFootprint.read(columns: columns, rail: rail, backdrop: 0.15) == nil)
    }
}
