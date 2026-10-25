import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Filming a control while the pointer arrives on it, and reading whether a
/// band of light crossed it.
///
/// The user, 2026-10-24, of the Ask button: "when I hover over it the first
/// time it has a nice sheen animation, but subsequent hovers do not repeat
/// the sheen". A snapshot lands after the 0.66s sweep has ended and the reel
/// of the time was the drawing rendered offscreen, so only the drawn window,
/// frame by frame, can say whether a later hover sweeps.
@Suite("Filming a hover")
struct PlaytestHoverFilmTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A filmHover step names the control the pointer arrives on, how long to film and what it claims")
    func parses() throws {
        let script = try decode("""
        { "steps": [ { "do": "filmHover", "name": "third", "control": "Ask", "seconds": 1.2, "sweeps": true },
                     { "do": "filmHover", "name": "plain", "control": "Ask" } ] }
        """)
        guard case .filmHover(let claimed) = script.steps[0],
              case .filmHover(let plain) = script.steps[1] else { Issue.record("filmHover"); return }
        #expect(claimed == PlaytestHoverFilm(name: "third", control: "Ask", seconds: 1.2, sweeps: true))
        #expect(plain.seconds == PlaytestHoverFilm.defaultSeconds)
        #expect(plain.sweeps == nil)
        #expect(script.steps[0].name == "filmHover")
        #expect(PlaytestStep.names.contains("filmHover"))
    }

    @Test("It needs a control and a sane length",
          arguments: [
              #"{ "do": "filmHover", "name": "x" }"#,
              #"{ "do": "filmHover", "control": "Ask" }"#,
              #"{ "do": "filmHover", "name": "x", "control": "Ask", "seconds": 0.05 }"#,
              #"{ "do": "filmHover", "name": "x", "control": "Ask", "seconds": 9 }"#,
          ])
    func refusesWhatItCannotFilm(step: String) {
        #expect(throws: PlaytestScriptError.self) {
            try decode(#"{ "steps": [ "# + step + #" ] }"#)
        }
    }

    // MARK: Reading the frames

    /// A control 100 columns wide read as how light each column is, at rest:
    /// a pill whose lightness rises gently left to right.
    private func rest(_ column: Int) -> Double { 100 + Double(column) * 0.3 }
    /// The same control hovered and settled: its trailing end lighter, the
    /// way the hover's spectrum opens toward pink there.
    private func hovered(_ column: Int) -> Double { rest(column) + max(0, Double(column - 50)) * 0.6 }

    /// One frame: `opened` of the way from rest to hovered (the colour change
    /// is a cross fade), plus a white band `bandWidth` columns wide centred on
    /// `band` (nil: no band).
    private func frame(opened: Double, band: Int? = nil, bandWidth: Int = 50, strength: Double = 60) -> [Double] {
        (0..<100).map { column in
            var value = rest(column) + (hovered(column) - rest(column)) * opened
            if let band {
                let distance = abs(Double(column - band)) / (Double(bandWidth) / 2)
                if distance < 1 { value += strength * (1 - distance) }
            }
            return value
        }
    }

    /// Before the pointer arrives, the colour change, then held.
    private var noBand: [[Double]] {
        Array(repeating: frame(opened: 0), count: 5)
            + stride(from: 0.1, through: 1, by: 0.1).map { frame(opened: $0) }
            + Array(repeating: frame(opened: 1), count: 20)
    }

    @Test("A band carried from the leading edge past the trailing one reads as a sweep")
    func readsASweep() {
        var frames = Array(repeating: frame(opened: 0), count: 5)
        frames += stride(from: -10, through: 120, by: 10).enumerated().map { step, at in
            frame(opened: min(1, Double(step) / 5), band: at)
        }
        frames += Array(repeating: frame(opened: 1), count: 10)
        let reading = SheenSweep.read(frames)
        #expect(reading.swept)
        #expect(reading.lit >= 8)
        // Centres are shares of the width, leading to trailing.
        let centres = reading.centres.compactMap { $0 }
        #expect(centres.first.map { $0 < 0.3 } == true)
        #expect(centres.last.map { $0 > 0.7 } == true)
    }

    @Test("A hover that only changes colour, however unevenly, is no sweep")
    func colourAloneIsNoSweep() {
        // What the Ask button's second hover drew on 2026-10-24: its pink end
        // fading in, and no band.
        let reading = SheenSweep.read(noBand)
        #expect(!reading.swept)
        #expect(reading.lit == 0)
    }

    @Test("A band that sits still is no sweep, and neither is a faint one")
    func stillOrFaintIsNoSweep() {
        let still = [frame(opened: 0)] + Array(repeating: frame(opened: 1, band: 50), count: 10)
            + Array(repeating: frame(opened: 1), count: 10)
        #expect(!SheenSweep.read(still).swept)
        let faint = [frame(opened: 0)] + stride(from: -10, through: 120, by: 10).map { frame(opened: 1, band: $0, strength: 4) }
            + Array(repeating: frame(opened: 1), count: 10)
        #expect(!SheenSweep.read(faint).swept)
    }

    @Test("Too few frames to tell is no sweep")
    func tooFew() {
        #expect(!SheenSweep.read([]).swept)
        #expect(!SheenSweep.read([frame(opened: 0, band: 50)]).swept)
    }
}
