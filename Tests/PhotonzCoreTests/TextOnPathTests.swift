import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A title's words set along a drawn curve (`TextOnPath.swift`,
/// `docs/design/mocks/pages/video-motion.html`, "Text on a path").
@Suite("Text on a path")
struct TextOnPathTests {

    /// A quarter circle of radius `r` about (0, 0), from (r, 0) round to
    /// (0, r): one cubic with the usual 0.5523 handles.
    static func quarterCircle(_ r: CGFloat = 300, about centre: CGPoint = .zero) -> PathContent {
        let k: CGFloat = 0.5522847498
        let start = CGPoint(x: centre.x + r, y: centre.y)
        let end = CGPoint(x: centre.x, y: centre.y + r)
        return PathContent(anchors: [
            // Handles are stated from their own anchor.
            PathAnchor(point: start, handleOut: CGPoint(x: 0, y: k * r), kind: .smooth),
            PathAnchor(point: end, handleIn: CGPoint(x: k * r, y: 0), kind: .smooth),
        ], fill: nil)
    }

    static func line(from a: CGPoint, to b: CGPoint) -> PathContent {
        PathContent(anchors: [PathAnchor(point: a), PathAnchor(point: b)], fill: nil)
    }

    // MARK: - Walking along the curve

    @Test func aStraightLineIsAsLongAsItLooksAndPointsAlongItself() throws {
        let walk = PathWalk(Self.line(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 110, y: 20)))
        #expect(abs(walk.length - 100) < 0.001)
        let place = try #require(walk.place(atDistance: 25))
        #expect(abs(place.point.x - 35) < 0.001)
        #expect(abs(place.point.y - 20) < 0.001)
        #expect(abs(place.angle) < 0.0001)
    }

    @Test func aQuarterCircleIsAQuarterOfItsCircumference() {
        let walk = PathWalk(Self.quarterCircle(300))
        // The cubic is a hair long of a true arc (0.03 %); a percent is plenty.
        let quarter = CGFloat.pi * 300 / 2
        #expect(abs(walk.length - quarter) < 1)
    }

    @Test func halfWayRoundAQuarterCircleFacesDiagonallyDownAndLeft() throws {
        let walk = PathWalk(Self.quarterCircle(300))
        let place = try #require(walk.place(atDistance: walk.length / 2))
        // At 45 degrees round, on a circle that runs clockwise on screen from
        // the right-hand side down to the bottom, the way on is down and left.
        let diagonal: CGFloat = 300 * 0.7071067812
        #expect(abs(place.point.x - diagonal) < 1)
        #expect(abs(place.point.y - diagonal) < 1)
        let degrees = place.angle * 180 / CGFloat.pi
        #expect(abs(degrees - 135) < 0.5)
    }

    @Test func offTheEndOfAnOpenPathIsNowhere() {
        let walk = PathWalk(Self.line(from: .zero, to: CGPoint(x: 100, y: 0)))
        #expect(walk.place(atDistance: -1) == nil)
        #expect(walk.place(atDistance: 101) == nil)
    }

    @Test func aClosedPathGoesRoundAgain() throws {
        var square = PathContent(anchors: [
            PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 100, y: 0)),
            PathAnchor(point: CGPoint(x: 100, y: 100)), PathAnchor(point: CGPoint(x: 0, y: 100)),
        ], isClosed: true)
        square.fill = nil
        let walk = PathWalk(square)
        #expect(abs(walk.length - 400) < 0.001)
        let past = try #require(walk.place(atDistance: 450))
        #expect(abs(past.point.x - 50) < 0.001)
        #expect(abs(past.point.y) < 0.001)
        let before = try #require(walk.place(atDistance: -50))
        #expect(abs(before.point.x) < 0.001)
        #expect(abs(before.point.y - 50) < 0.001)
    }

    @Test func aPathOfOnePointHasNoLength() {
        let walk = PathWalk(PathContent(anchors: [PathAnchor(point: .zero)]))
        #expect(walk.length == 0)
        #expect(walk.place(atDistance: 0) == nil)
    }

    // MARK: - Setting the letters

    /// Ten letters, each 20 wide, set one after another.
    static let tenLetters: [TextOnPathLayout.Glyph] = (0..<10).map {
        TextOnPathLayout.Glyph(x: CGFloat($0) * 20, width: 20)
    }

    @Test func lettersOnAStraightLineSitInARowFromTheStart() throws {
        let walk = PathWalk(Self.line(from: CGPoint(x: 0, y: 50), to: CGPoint(x: 400, y: 50)))
        let letters = TextOnPathLayout.letters(Self.tenLetters, on: walk, startDistance: 40)
        #expect(letters.count == 10)
        let first = try #require(letters[0])
        #expect(abs(first.origin.x - 40) < 0.001)
        #expect(abs(first.origin.y - 50) < 0.001)
        let last = try #require(letters[9])
        #expect(abs(last.origin.x - 220) < 0.001)
        #expect(abs(last.angle) < 0.0001)
    }

    @Test func eachLetterTurnsWithTheCurveUnderIt() {
        let guide = Self.quarterCircle(300)
        let walk = PathWalk(guide)
        let letters = TextOnPathLayout.letters(Self.tenLetters, on: walk, startDistance: 30).compactMap { $0 }
        #expect(letters.count == 10)
        // Each turned further than the one before, the way round the arc runs.
        for (a, b) in zip(letters, letters.dropFirst()) { #expect(b.angle > a.angle) }
        let reading = TextOnPathReading(letters: letters, along: guide)
        #expect(reading.worstTurnDegrees < 1)
        #expect(reading.worstBaselineDistance < 0.5)
    }

    @Test func lettersPastTheEndOfAnOpenPathAreLeftOut() {
        let walk = PathWalk(Self.line(from: .zero, to: CGPoint(x: 100, y: 0)))
        let letters = TextOnPathLayout.letters(Self.tenLetters, on: walk, startDistance: 0)
        // Letter middles at 10, 30, 50, 70, 90 are on it; 110 onwards are not.
        #expect(letters.prefix(5).allSatisfy { $0 != nil })
        #expect(letters.dropFirst(5).allSatisfy { $0 == nil })
    }

    @Test func aStartBeforeTheLineHidesTheFirstLettersUntilTheyArrive() {
        let walk = PathWalk(Self.line(from: .zero, to: CGPoint(x: 400, y: 0)))
        let letters = TextOnPathLayout.letters(Self.tenLetters, on: walk, startDistance: -55)
        #expect(letters[0] == nil)
        #expect(letters[1] == nil)
        #expect(letters[2] == nil)
        #expect(letters[3] != nil)
    }

    // MARK: - The measured bar: flat words fail it

    @Test func wordsSetInAStraightRowAcrossTheArcFailTheReading() {
        let guide = Self.quarterCircle(300)
        // The flat version: every letter upright on a level baseline from
        // the path's first point.
        let flat = Self.tenLetters.map {
            PathLetter(origin: CGPoint(x: 300 + $0.x, y: 0), width: $0.width, angle: 0)
        }
        let reading = TextOnPathReading(letters: flat, along: guide)
        #expect(reading.worstTurnDegrees > 5 || reading.worstBaselineDistance > 2)
    }

    @Test func wordsAllTurnedByOneAngleFailTheReading() {
        let guide = Self.quarterCircle(300)
        let walk = PathWalk(guide)
        let placed = TextOnPathLayout.letters(Self.tenLetters, on: walk, startDistance: 100).compactMap { $0 }
        let oneAngle = placed.map { PathLetter(origin: $0.origin, width: $0.width, angle: placed[0].angle) }
        #expect(TextOnPathReading(letters: oneAngle, along: guide).worstTurnDegrees > 5)
    }

    // MARK: - On the text

    @Test func textOnAPathStartsWhereThePercentSays() {
        var text = TextContent(string: "Follow the curve")
        let guide = Self.line(from: .zero, to: CGPoint(x: 200, y: 0))
        text.onPath = TextOnPath(guide: guide, startPercent: 25)
        #expect(text.onPath?.startDistance(along: PathWalk(guide)) == 50)
    }

    @Test func textOnAPathIsKeptInTheDocument() throws {
        var text = TextContent(string: "Follow the curve")
        text.onPath = TextOnPath(guide: Self.quarterCircle(120), startPercent: 6)
        let back = try JSONDecoder().decode(TextContent.self, from: JSONEncoder().encode(text))
        #expect(back == text)
    }

    @Test func plainTextWritesNoPath() throws {
        let json = String(decoding: try JSONEncoder().encode(TextContent(string: "Hi")), as: UTF8.self)
        #expect(!json.contains("onPath"))
    }

    @Test func wordsOnAPathAreSetOnOneLine() {
        #expect(TextOnPath.lineOfWords("Ship it\nfaster") == "Ship it faster")
        #expect(TextOnPath.lineOfWords("a\r\n\nb") == "a b")
    }

    @Test func theLettersDrawAboveAndBelowTheCurveSoTheLayerReachesPastItsBox() {
        var layer = Layer(name: "Title", content: .text(TextContent(string: "Hi", fontSize: 40)),
                          frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        #expect(layer.contentOutset == 0)
        var text = TextContent(string: "Hi", fontSize: 40)
        text.onPath = TextOnPath(guide: Self.quarterCircle(300))
        layer.content = .text(text)
        #expect(layer.contentOutset >= 40)
    }
}
