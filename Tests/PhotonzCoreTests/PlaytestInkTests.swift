import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// How thick the ink is through one point of a rendered picture, which is how
/// a walk proves a line got thicker on the CANVAS rather than in the panel's
/// number (`expectInk`). On 2026-10-19 the number said 26 and the picture
/// still drew 4.
@Suite("Playtest ink")
struct PlaytestInkTests {

    /// A white picture with a red band `rows` tall across it.
    private func picture(width: Int = 20, height: Int = 40, rows: Range<Int>) -> [UInt8] {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in rows {
            for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i + 1] = 59
                bytes[i + 2] = 48
            }
        }
        return bytes
    }

    @Test func itCountsTheBandThroughThePoint() {
        let bytes = picture(rows: 10..<26)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 5, y: 15) == 16)
    }

    @Test func aPointOnTheEdgeOfTheBandStillCountsAllOfIt() {
        let bytes = picture(rows: 10..<26)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 5, y: 10) == 16)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 5, y: 25) == 16)
    }

    @Test func aBandToTheEdgeOfThePictureStopsThere() {
        let bytes = picture(rows: 30..<40)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 5, y: 35) == 10)
    }

    @Test func aPointOutsideThePictureHasNoInk() {
        let bytes = picture(rows: 10..<26)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 25, y: 15) == nil)
        #expect(PlaytestInk.thickness(rgba: bytes, width: 20, height: 40, x: 5, y: -1) == nil)
    }

    @Test func aStepReadsWhereAndHowThick() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectInk", "at": [450, 300], "thickness": 40 } ] }
        """.utf8))
        guard case .expectInk(let at, let thickness, let within) = script.steps[0] else {
            Issue.record("expectInk"); return
        }
        #expect(at == CGPoint(x: 450, y: 300))
        #expect(thickness == 40)
        #expect(within == 1)
        #expect(script.steps[0].name == "expectInk")
    }

    @Test func aStepCanSayHowCloseIsCloseEnough() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectInk", "at": [1, 2], "thickness": 9, "within": 3 } ] }
        """.utf8))
        guard case .expectInk(_, _, let within) = script.steps[0] else {
            Issue.record("expectInk"); return
        }
        #expect(within == 3)
    }

    @Test func aStepWithoutAThicknessIsRefused() {
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectInk", "at": [1, 2] } ] }
            """.utf8))
        }
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectInk", "at": [1, 2], "thickness": -3 } ] }
            """.utf8))
        }
    }
}

/// A chip's words read off the rendered picture (`expectChipContrast`).
@Suite("A walk reads a chip's contrast off the picture")
struct PlaytestChipContrastStepTests {

    @Test func aStepAsksForTheBarItWasGiven() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectChipContrast", "min": 7 } ] }
        """.utf8))
        guard case .expectChipContrast(let min) = script.steps[0] else {
            Issue.record("expectChipContrast"); return
        }
        #expect(min == 7)
        #expect(script.steps[0].name == "expectChipContrast")
    }

    @Test func theBarIsFourAndAHalfUnlessSaid() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "expectChipContrast" } ] }
        """.utf8))
        guard case .expectChipContrast(let min) = script.steps[0] else {
            Issue.record("expectChipContrast"); return
        }
        #expect(min == 4.5)
    }

    @Test func aBarUnderOneIsRefused() {
        #expect(throws: (any Error).self) {
            try PlaytestScript.decode(Data("""
            { "steps": [ { "do": "expectChipContrast", "min": 0.5 } ] }
            """.utf8))
        }
    }

    @Test func itSurvivesALock() {
        #expect(PlaytestLockSafety.stepsThatSurviveALock.contains("expectChipContrast"))
    }
}
