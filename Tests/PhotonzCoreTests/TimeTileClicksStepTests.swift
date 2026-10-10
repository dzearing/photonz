import Foundation
import Testing
@testable import PhotonzCore

/// "A click on a Library tile shows it picked on the very next frame" has to be
/// TIMED: a picture of a picked tile looks the same whether it took one frame
/// or a third of a second. `timeTileClicks` clicks each named tile with real
/// mouse events, a number of times over, and reads how long each click took to
/// pick the tile and to put a frame on screen with the pick in it
/// (`library-tile-click-latency-walk`, 2026-10-10).
@Suite("timeTileClicks and what its readings say")
struct TimeTileClicksStepTests {

    @Test("A timeTileClicks step names the tiles, how many clicks, and the two budgets")
    func namesTilesTimesAndBudgets() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "timeTileClicks", "tiles": ["Sunrise", "Bar"], "times": 10,
                       "highlightUnderMS": 33, "settledUnderMS": 100 } ] }
        """.utf8))
        guard case .timeTileClicks(let tiles, let times, let switching, let highlight, let settled) = script.steps[0] else {
            Issue.record("timeTileClicks"); return
        }
        #expect(tiles == ["Sunrise", "Bar"])
        #expect(times == 10)
        #expect(!switching)
        #expect(highlight == 33)
        #expect(settled == 100)
        #expect(script.steps[0].name == "timeTileClicks")
        #expect(PlaytestStep.names.contains("timeTileClicks"))
    }

    @Test("Ten clicks a tile and no budget unless the walk sets one")
    func defaults() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "timeTileClicks", "tiles": ["Sunrise"] } ] }
        """.utf8))
        guard case .timeTileClicks(_, let times, let switching, let highlight, let settled) = script.steps[0] else {
            Issue.record("timeTileClicks"); return
        }
        #expect(times == 10)
        #expect(!switching)
        #expect(highlight == nil)
        #expect(settled == nil)
    }

    @Test("A timeTileClicks step needs a tile, a click, and budgets above zero")
    func refusesNonsense() {
        for body in [
            #"{ "do": "timeTileClicks" }"#,
            #"{ "do": "timeTileClicks", "tiles": [] }"#,
            #"{ "do": "timeTileClicks", "tiles": ["A"], "times": 0 }"#,
            #"{ "do": "timeTileClicks", "tiles": ["A"], "highlightUnderMS": 0 }"#,
            #"{ "do": "timeTileClicks", "tiles": ["A"], "settledUnderMS": -5 }"#,
            #"{ "do": "timeTileClicks", "tiles": ["A"], "switching": true }"#,
        ] {
            #expect(throws: (any Error).self, "\(body)") {
                try PlaytestScript.decode(Data(#"{ "steps": [ \#(body) ] }"#.utf8))
            }
        }
    }

    @Test("Switching moves the pick from tile to tile, and says so")
    func switching() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "timeTileClicks", "tiles": ["Sunrise", "Midnight"], "switching": true } ] }
        """.utf8))
        guard case .timeTileClicks(_, _, let switching, _, _) = script.steps[0] else {
            Issue.record("timeTileClicks"); return
        }
        #expect(switching)
    }

    @Test("The readings give the median and the worst of each measure")
    func medianAndWorst() {
        let readings = [12.0, 9, 40, 11, 10].map { TileClickTiming.Reading(highlightMS: $0, settledMS: $0 + 5) }
        let timing = TileClickTiming(tile: "Sunrise", readings: readings)
        #expect(timing.highlight.median == 11)
        #expect(timing.highlight.worst == 40)
        #expect(timing.settled.median == 16)
        #expect(timing.settled.worst == 45)
    }

    @Test("An even count takes the mean of the middle two")
    func evenMedian() {
        let readings = [10.0, 20, 30, 40].map { TileClickTiming.Reading(highlightMS: $0, settledMS: $0) }
        #expect(TileClickTiming(tile: "A", readings: readings).highlight.median == 25)
    }

    @Test("The worst click over the budget is the one named, and a budget met names nothing")
    func overBudget() {
        let readings = [8.0, 400, 9].map { TileClickTiming.Reading(highlightMS: $0, settledMS: $0 + 2) }
        let timing = TileClickTiming(tile: "Sunrise", readings: readings)
        #expect(timing.trouble(highlightUnderMS: 33, settledUnderMS: nil)?.contains("click 2") == true)
        #expect(timing.trouble(highlightUnderMS: 33, settledUnderMS: nil)?.contains("Sunrise") == true)
        #expect(timing.trouble(highlightUnderMS: 500, settledUnderMS: 500) == nil)
        #expect(timing.trouble(highlightUnderMS: nil, settledUnderMS: 100)?.contains("402") == true)
        #expect(timing.trouble(highlightUnderMS: nil, settledUnderMS: nil) == nil)
    }

    @Test("A click that never picked its tile is trouble whatever the budget")
    func neverPicked() {
        let timing = TileClickTiming(tile: "Bar", readings: [.init(highlightMS: nil, settledMS: nil)])
        #expect(timing.trouble(highlightUnderMS: nil, settledUnderMS: nil)?.contains("never") == true)
    }

    @Test("The summary line carries both measures, median and worst, in whole milliseconds")
    func summary() {
        let readings = [12.4, 9.6].map { TileClickTiming.Reading(highlightMS: $0, settledMS: $0 + 10) }
        let line = TileClickTiming(tile: "Sunrise", readings: readings).summary
        #expect(line.contains("Sunrise"))
        #expect(line.contains("2 clicks"))
        #expect(line.contains("median 11"))
        #expect(line.contains("worst 12"))
    }
}
