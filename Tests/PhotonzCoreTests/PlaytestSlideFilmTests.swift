import Foundation
import Testing
@testable import PhotonzCore

/// Filming the whole window while something slides, and reading how often it
/// drew a new picture.
///
/// The slide into Edit mode on a long captioned recording drew a new picture
/// only every 40 to 90ms (2026-09-29), while the slide back to View drew one
/// about every 8. The main thread's busy time was the same both ways, so the
/// only honest check is the window itself: when it changed, and the longest it
/// sat still while it was moving, which is what `filmWindow` takes.
@Suite("Filming a slide")
struct PlaytestSlideFilmTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A filmWindow step names its film, the key that starts the slide, how long, and a ceiling")
    func parses() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmWindow", "name": "view-to-edit", "key": "2", "modifiers": ["command"],
                       "seconds": 0.6, "withinMS": 330, "longestStillUnderMS": 25 } ] }
        """)
        guard case .filmWindow(let film) = script.steps[0] else { Issue.record("filmWindow"); return }
        #expect(film.name == "view-to-edit")
        #expect(film.key == (try #require(PlaytestKey("2"))))
        #expect(film.modifiers == [.command])
        #expect(film.seconds == 0.6)
        #expect(film.withinMS == 330)
        #expect(film.longestStillUnderMS == 25)
        #expect(script.steps[0].name == "filmWindow")
        #expect(PlaytestStep.names.contains("filmWindow"))
    }

    @Test("It films 0.8s and claims nothing unless it says")
    func defaults() throws {
        let script = try decode(#"{ "steps": [ { "do": "filmWindow", "name": "x", "key": "1" } ] }"#)
        guard case .filmWindow(let film) = script.steps[0] else { Issue.record("filmWindow"); return }
        #expect(film.seconds == 0.8)
        #expect(film.modifiers == [])
        #expect(film.longestStillUnderMS == nil)
        #expect(film.withinMS == nil)
    }

    @Test("A filmWindow step can be set off by a press on a panel control instead of a key")
    func parsesAPress() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmWindow", "name": "time-opens", "press": "Time section", "in": "Time",
                       "seconds": 0.5 } ] }
        """)
        guard case .filmWindow(let film) = script.steps[0] else { Issue.record("filmWindow"); return }
        #expect(film.trigger == .press(control: "Time section", in: "Time"))
        #expect(film.key == nil)
        #expect(film.modifiers == [])
        #expect(film.seconds == 0.5)
    }

    @Test("It needs exactly one of a key or a press, a sane length and a ceiling above nothing",
          arguments: [
              #"{ "do": "filmWindow", "name": "x" }"#,
              #"{ "do": "filmWindow", "name": "x", "key": "1", "press": "Time section" }"#,
              #"{ "do": "filmWindow", "key": "1" }"#,
              #"{ "do": "filmWindow", "name": "x", "key": "not a key" }"#,
              #"{ "do": "filmWindow", "name": "x", "key": "1", "seconds": 9 }"#,
              #"{ "do": "filmWindow", "name": "x", "key": "1", "longestStillUnderMS": 0 }"#,
              #"{ "do": "filmWindow", "name": "x", "key": "1", "withinMS": 0 }"#,
          ])
    func refusesWhatItCannotFilm(step: String) {
        #expect(throws: PlaytestScriptError.self) {
            try decode(#"{ "steps": [ "# + step + #" ] }"#)
        }
    }

    // MARK: Reading the pictures

    @Test("The slide runs from the first new picture after the key to the last, and the longest wait is between two of them")
    func readsASlide() {
        // Two pictures before the key are the window at rest, not the slide.
        let cadence = SlideCadence.read(picturesAtMS: [-40, -12, 73, 81, 89, 106, 150, 158], keyAtMS: 0)
        #expect(cadence.firstMS == 73)
        #expect(cadence.lastMS == 158)
        #expect(cadence.pictures == 6)
        #expect(cadence.longestStillMS == 44)
    }

    @Test("Read within a stretch after the key, what the window drew after it is left out")
    func readsWithin() {
        // The slide, then the editor arriving onto a window that has stopped.
        let cadence = SlideCadence.read(picturesAtMS: [60, 70, 80, 95, 410, 520], keyAtMS: 0, withinMS: 330)
        #expect(cadence.lastMS == 95)
        #expect(cadence.pictures == 4)
        #expect(cadence.longestStillMS == 15)
    }

    @Test("A window that never changed after the key has no slide at all")
    func readsNothing() {
        let cadence = SlideCadence.read(picturesAtMS: [-30, -5], keyAtMS: 0)
        #expect(cadence.firstMS == nil)
        #expect(cadence.lastMS == nil)
        #expect(cadence.pictures == 0)
        #expect(cadence.longestStillMS == 0)
    }

    @Test("The pictures are read in the order they were drawn, whatever order they came in")
    func sortsFirst() {
        let cadence = SlideCadence.read(picturesAtMS: [20, 10, 50], keyAtMS: 5)
        #expect(cadence.firstMS == 5)
        #expect(cadence.longestStillMS == 30)
    }

    @Test("It says what it saw in one line")
    func summary() {
        let cadence = SlideCadence.read(picturesAtMS: [73, 81, 125], keyAtMS: 0)
        #expect(cadence.summary == "first new picture 73ms after the key, 3 pictures until it settled at 125ms, "
            + "longest still 44ms")
        #expect(SlideCadence.read(picturesAtMS: [], keyAtMS: 0).summary
            == "the window drew nothing new after the key")
    }
}
